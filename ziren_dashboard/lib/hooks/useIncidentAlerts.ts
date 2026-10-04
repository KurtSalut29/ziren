'use client';

/**
 * useIncidentAlerts — turns the agency's stored notification_rules into
 * actual dispatcher alerts, and holds the ones nobody has acknowledged yet.
 *
 * Before this hook, notification_rules was a settings screen that wrote a
 * JSON blob nobody read: the rubric computed a severity and then nothing
 * happened until a human happened to be looking at the queue. This closes
 * that loop.
 *
 * WHAT THIS HOOK OWNS AND WHAT IT DOES NOT
 *
 * It owns the PENDING set: incidents that arrived, matched the rules, and
 * have not been acknowledged. It does not own how they are shown — the
 * interrupt overlay reads `pending` and decides. Acknowledging an alert means
 * "I have seen that this exists"; it says nothing about the incident, which
 * stays in the queue until it is actually dispatched or closed.
 *
 * Behaviour:
 *   - Agency Admin      → uses their own agency's notification_rules, over
 *                         the queue the backend has already scoped to their
 *                         agency.
 *   - Provincial Admin  → has agency_type but no agency_id, and oversees
 *                         every station of that type — each with its own
 *                         notification_rules row — so there is still no
 *                         single row to read (the backend has no endpoint
 *                         that aggregates rules across an agency_type).
 *                         Falls back to DEFAULT_RULES (every severity).
 *   - A new tab's first poll is SEED-ONLY. Without this, opening the dashboard
 *     would fire one alert per incident already in the queue. A reload of the
 *     same tab resumes from the stored seen-set instead (see seenKey).
 *   - Alerts are de-duplicated by incident id for the life of the session.
 *
 * Delivery is deliberately layered, because each layer can fail
 * independently:
 *   1. The in-app interrupt (always works — no permission needed).
 *   2. A flashing tab title, for when the console is not the focused tab.
 *   3. A Web Notification (needs permission + a secure context).
 *   4. The alert sound (needs a prior user gesture on most browsers). It
 *      LOOPS until the dispatcher opens the report or dismisses the alert —
 *      see startAlarm.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { apiClient } from '@/lib/api/client';
import { fetchQueue, type QueueIncident } from '@/lib/api/dispatch';
import { alertPrefs } from '@/lib/prefs/definitions';
import { announceArrivals, useOpened } from '@/lib/incidents/arrivals';

/** localStorage flag: this browser has already been asked about desktop alerts. */
const PERMISSION_ASKED_KEY = 'ziren-desktop-alerts-asked';

export interface NotificationRules {
  critical: boolean;
  high: boolean;
  medium: boolean;
  low: boolean;
}

// Used when an agency has no stored rules, the rules cannot be fetched, or the
// caller is a Provincial Admin (who has no single agencies row to read).
//
// Every severity is ON. It used to be critical + high only, which silently made
// PNP the agency that never got alerted: its everyday reports - theft, a fight,
// a missing person, "tulong po" - score low or medium, while even a bare
// "sunog" scores high. An agency that wants fewer interruptions can switch
// severities off in Settings -> Alerts; the default must not do it for them.
// Mirrors migration 041 and DEFAULT_RULES in settings/panels/agency.tsx.
const DEFAULT_RULES: NotificationRules = {
  critical: true,
  high: true,
  medium: true,
  low: true,
};

/**
 * Report ids this tab has already considered, kept across a reload.
 *
 * The seen-set used to live only in memory, so a reload (or any full page
 * load) re-seeded it from the queue as it stood - and any report that had
 * arrived in the meantime was swallowed as "already known" without ever
 * alerting. sessionStorage is per tab and gone when the tab closes, so a fresh
 * tab still starts quietly instead of alerting on the whole backlog.
 */
// Per account, so signing in as another station in the same tab does not
// treat that station's whole queue as new.
const seenKey = () => `ziren-alert-seen:${sessionStorage.getItem('user_email') ?? ''}`;

function loadSeen(): Set<string> | null {
  try {
    const raw = sessionStorage.getItem(seenKey());
    return raw ? new Set(JSON.parse(raw) as string[]) : null;
  } catch {
    return null;
  }
}

function saveSeen(ids: Set<string>, current: string[]): void {
  // Only what is still in the queue - closed reports never come back, so
  // keeping them would grow the key forever.
  const keep = current.filter(id => ids.has(id));
  try { sessionStorage.setItem(seenKey(), JSON.stringify(keep)); } catch { /* storage blocked */ }
}

/**
 * Poll cadence — faster than the queue page's 15s.
 *
 * This is the path that decides how long a report can sit unseen before
 * anyone is told about it, so it is worth a tighter loop than a table a human
 * is already looking at. A province files a handful of reports an hour, not a
 * second, so the extra requests cost nothing.
 *
 * The cadence is now a per-browser setting (AlertPrefs.pollSeconds, default
 * 10s, Settings → Notifications); 5–30s are offered and nothing slower, since
 * this loop decides how long a report can sit unseen.
 */

/** How often the SYNTHESISED fallback re-fires. The file loops instead. */
const ESCALATE_MS = 12_000;

/**
 * The alert sound, served from public/.
 *
 * Replaceable by dropping a different file at this path — no code change, and
 * nothing else in the app refers to it. If it is missing or will not decode,
 * the synthesised chime below takes over rather than the console going silent.
 */
const ALERT_SOUND_URL = '/NotificationSound.mp3';

/**
 * An incident nobody has scored yet.
 *
 * NOT a severity — the absence of one. It happens when triage was unavailable
 * at filing time, or when the rubric could not determine an agency type, and
 * it is the case where a human is most needed. The previous version of this
 * hook dropped these reports silently: `rules[severity]` on an empty string is
 * undefined, so the alert was skipped.
 */
export type AlertSeverity = 'critical' | 'high' | 'medium' | 'low' | 'untriaged';

/**
 * Worst first, and an unscored report never sits below a scored MEDIUM.
 *
 * An untriaged incident could be anything, so ranking it under medium would
 * bury the one report whose severity is genuinely unknown. It stays under
 * `high`, though: a confirmed high is a confirmed emergency, and an unknown
 * is still only an unknown.
 */
const RANK: Record<AlertSeverity, number> = {
  critical: 0,
  high: 1,
  untriaged: 2,
  medium: 3,
  low: 4,
};

/**
 * Stand-ins used only when the live queue cannot supply enough real rows for a
 * demonstration. Written to read like Biliran reports actually read — Taglish,
 * partial addresses, one that says almost nothing — and every one is prefixed
 * so it can never be mistaken for a genuine report on screen.
 */
const SAMPLE_REPORTS: Omit<IncidentAlert, 'id' | 'filedAt'>[] = [
  {
    severity: 'critical',
    reportText: '[SAMPLE] Nasusunog ang bahay sa may palengke, may naiwan pang bata sa loob. Malakas na ang apoy.',
    address: 'Brgy. Sabang, Naval, Biliran',
    category: 'fire',
    agencyType: 'BFP',
    sosFlagged: true,
  },
  {
    severity: 'high',
    reportText: '[SAMPLE] May naaksidenteng motor sa highway, duguan ang driver, hindi makagalaw.',
    address: 'Brgy. Caraycaray, Naval, Biliran',
    category: 'vehicular',
    agencyType: 'PNP',
    sosFlagged: false,
  },
  {
    severity: 'untriaged',
    reportText: '[SAMPLE] tulong po dito sa amin',
    address: null,
    category: null,
    agencyType: null,
    sosFlagged: false,
  },
  {
    severity: 'high',
    reportText: '[SAMPLE] Bumagsak ang puno sa kalsada, may naipit na sasakyan sa ilalim.',
    address: 'Brgy. Larrazabal, Naval, Biliran',
    category: 'other',
    agencyType: 'MDRRMO',
    sosFlagged: false,
  },
  {
    severity: 'critical',
    reportText: '[SAMPLE] Sunog sa warehouse malapit sa pier, kumakalat na sa katabing bahay.',
    address: 'Brgy. Padre Inocentes Garcia, Naval, Biliran',
    category: 'fire',
    agencyType: 'BFP',
    sosFlagged: false,
  },
  {
    severity: 'medium',
    reportText: '[SAMPLE] Baha na sa may riverside, tumataas pa ang tubig.',
    address: 'Brgy. Villa Consuelo, Naval, Biliran',
    category: 'flood',
    agencyType: 'MDRRMO',
    sosFlagged: false,
  },
  {
    severity: 'untriaged',
    reportText: '[SAMPLE] emergency po dito sa amin bilis',
    address: 'Brgy. Calumpang, Naval, Biliran',
    category: null,
    agencyType: null,
    sosFlagged: false,
  },
];

export interface IncidentAlert {
  id: string;
  severity: AlertSeverity;
  reportText: string;
  address: string | null;
  category: string | null;
  agencyType: string | null;
  sosFlagged: boolean;
  /** When the RESIDENT filed it, not when this tab noticed. */
  filedAt: Date;
}

/**
 * Which reports in a queue poll are new to this console, and which of those
 * may interrupt the dispatcher. Pure apart from adding the new ids to `seen`.
 *
 * Kept out of the hook so the rule a dispatcher depends on — what sounds the
 * alarm — is unit-tested (evaluator finding #25), not only clicked through.
 */
export function decideAlerts(
  queue: QueueIncident[],
  seen: Set<string>,
  rules: NotificationRules,
): { fresh: IncidentAlert[]; arrived: string[] } {
  const fresh: IncidentAlert[] = [];
  // Every report new to this console, whether or not the agency's rules let
  // it interrupt. The lists behind the popup refresh on it: a low-severity
  // report that was (rightly) not announced must still show up.
  const arrived: string[] = [];
  for (const inc of queue) {
    if (seen.has(inc.id)) continue;
    seen.add(inc.id);
    arrived.push(inc.id);

    const scored = inc.suggested_severity ?? inc.severity ?? null;

    // An unscored report ALWAYS alerts, whatever the rules say. The rules
    // let an agency opt out of severities it has judged not worth an
    // interruption; nobody has judged this one, so there is nothing to
    // opt out of. Testing it against `rules[undefined]` is what used to
    // make exactly these reports vanish.
    const severity: AlertSeverity = scored ? (scored as AlertSeverity) : 'untriaged';
    if (severity !== 'untriaged' && !rules[severity as keyof NotificationRules]) continue;

    fresh.push({
      id: inc.id,
      severity,
      reportText: inc.report_text,
      address: inc.location_address,
      category: inc.incident_category,
      agencyType: inc.stations?.agencies?.agency_type ?? null,
      sosFlagged: Boolean(inc.sos_flagged),
      // The resident's clock, not ours. A report can already be a minute
      // old by the time a 10s poll and a slow upload have run their
      // course, and "filed 2m ago" is the number a dispatcher acts on.
      filedAt: new Date(inc.created_at),
    });
  }
  return { fresh, arrived };
}

export function useIncidentAlerts({
  token,
  isProvincialAdmin,
  enabled = true,
  viewingIncidentId = null,
}: {
  token: string | null;
  isProvincialAdmin: boolean;
  enabled?: boolean;
  /**
   * The incident the operator currently has open, if any. An alert for it is
   * acknowledged on sight rather than shown — interrupting someone to tell
   * them about the report already filling their screen is pure noise.
   */
  viewingIncidentId?: string | null;
}) {
  const [rules, setRules]     = useState<NotificationRules | null>(null);
  const [pending, setPending] = useState<IncidentAlert[]>([]);
  const [permission, setPermission] = useState<NotificationPermission | 'unsupported'>('default');
  /**
   * Whether the browser will let this page make a sound right now.
   *
   * `null` until the audio context has been looked at, so the sound bar never
   * flashes on first paint. It follows the context's own state, not a guess:
   * a page nobody has clicked is silent, but one the user has allowed sound for
   * (or that the browser already trusts) is running from the start, and the bar
   * must not claim otherwise.
   */
  const [audioReady, setAudioReady] = useState<boolean | null>(null);
  /** The sound file has been downloaded (decoding waits for the browser). */
  const [soundFileReady, setSoundFileReady] = useState(false);

  // How THIS BROWSER delivers what the agency's rules decided — see
  // AlertPrefs. Which severities interrupt is the agency's call (`rules`,
  // below); the sound, its level, the poll speed and the desktop and tab-title
  // layers are the operator's, per screen, and are edited under Settings →
  // Notifications.
  const { soundMode, volume, flashTitle, pollSeconds } = alertPrefs.use();
  // The alarm's callbacks are created once and read the level from a ref, so a
  // slider moved mid-alarm changes the loop that is already sounding instead
  // of waiting for the next one.
  const volumeRef = useRef(volume);
  volumeRef.current = volume;

  // Incident ids we've already considered. Seeded on the first poll so that
  // pre-existing incidents never alert.
  const seenRef  = useRef<Set<string> | null>(null);
  const rulesRef = useRef<NotificationRules | null>(null);
  const audioRef = useRef<AudioContext | null>(null);
  /** The file, decoded. Null until a context exists to decode it with. */
  const bufferRef = useRef<AudioBuffer | null>(null);
  /** The raw bytes, fetched before any user gesture has unlocked audio. */
  const encodedRef = useRef<ArrayBuffer | null>(null);
  /** A decode in flight, so however many callers ask, the file is decoded once. */
  const decodingRef = useRef<Promise<void> | null>(null);
  /**
   * The looping sound, while it is sounding.
   *
   * One node, held for as long as the alarm is up. Without this handle a busy
   * minute would start a fresh copy over every unfinished one — poll after
   * poll, stacking into noise at exactly the moment the room needs to hear
   * one clear alarm. It is also what lets the alarm be cut off the instant
   * the dispatcher answers it.
   */
  const soundRef = useRef<AudioBufferSourceNode | null>(null);
  /** Its volume, so a later critical can raise a loop already running. */
  const gainRef = useRef<GainNode | null>(null);
  /**
   * Whether an alarm SHOULD be sounding, whether or not one currently is.
   *
   * The two come apart constantly: a report can arrive before the browser has
   * seen the click that unlocks audio, or before the sound file has finished
   * downloading. Without this the alert would be lost in that gap — the alarm
   * would be skipped and never retried, on exactly the first report of a
   * shift. The unlock path reads it and starts the loop late.
   */
  const alarmRef = useRef(false);
  /** The level that alarm should sound at, for the same late start. */
  const urgentRef = useRef(false);

  // Keep a ref copy so the polling closure always reads current rules
  // without needing to be re-created (which would reset the interval).
  useEffect(() => { rulesRef.current = rules; }, [rules]);

  // ── Fetch the alert sound ───────────────────────────────────────────────
  //
  // Bytes now, decoding later. Fetching needs no AudioContext and no user
  // gesture, so the file is already in hand by the time someone clicks and
  // unlocks audio — the alternative is a first alert that arrives silent
  // while a 100KB download it could have done minutes ago finishes.
  useEffect(() => {
    if (!enabled) return;
    let cancelled = false;
    fetch(ALERT_SOUND_URL)
      .then(r => (r.ok ? r.arrayBuffer() : Promise.reject(new Error('404'))))
      .then(buf => {
        if (cancelled) return;
        encodedRef.current = buf;
        setSoundFileReady(true);
      })
      .catch(() => {
        // Left null on purpose: chime() falls through to the synthesised
        // tones. A missing sound file must never mean a silent console.
      });
    return () => { cancelled = true; };
  }, [enabled]);

  // ── Load the agency's notification rules ────────────────────────────────
  useEffect(() => {
    if (!token || !enabled) return;
    let cancelled = false;

    if (isProvincialAdmin) {
      // No agency_id, and no single agencies row to read — see the constant's
      // own comment above.
      setRules(DEFAULT_RULES);
      return;
    }

    (async () => {
      try {
        const me = await apiClient.get<{ agency_id: string | null }>('/users/me', token);
        if (cancelled || !me.agency_id) {
          if (!cancelled) setRules(DEFAULT_RULES);
          return;
        }
        const agency = await apiClient.get<{ notification_rules: NotificationRules | null }>(
          `/stations/agencies/${me.agency_id}`,
          token,
        );
        if (cancelled) return;
        setRules(agency.notification_rules ?? DEFAULT_RULES);
      } catch {
        // Never let a settings-fetch failure silence alerts.
        if (!cancelled) setRules(DEFAULT_RULES);
      }
    })();

    return () => { cancelled = true; };
  }, [token, isProvincialAdmin, enabled]);

  // ── Notification permission state ───────────────────────────────────────
  useEffect(() => {
    if (typeof window === 'undefined' || !('Notification' in window)) {
      setPermission('unsupported');
      return;
    }
    setPermission(Notification.permission);
  }, []);

  /**
   * Silence the alarm.
   *
   * Called when nothing is waiting to be seen any more — the dispatcher
   * opened the report, or dismissed the alert. Both mean the same thing to
   * the speaker: it has been heard.
   */
  const stopAlarm = useCallback(() => {
    alarmRef.current = false;
    try {
      soundRef.current?.stop();
    } catch {
      /* already ended */
    }
    soundRef.current = null;
    gainRef.current = null;
  }, []);

  /**
   * Sound the alarm, and KEEP sounding it.
   *
   * `loop = true` rather than a timer that replays the file. A repeat
   * scheduled every twelve seconds against a six-and-a-half-second file
   * leaves five and a half seconds of silence in the middle of an
   * unanswered emergency, and that silence reads exactly like the alarm
   * having stopped — which is the one thing it must never look like while a
   * report sits unopened. It is one node, started once, running until
   * something answers it.
   *
   * Safe to call repeatedly. A loop that is already running is left alone
   * and only its level is adjusted, so a second report arriving cannot
   * restart the file from the top or stack a copy over it.
   *
   * Returns silently when audio is not ready. That is not a failure to
   * swallow: alarmRef records the intent, and unlockAudio starts the loop as
   * soon as the browser allows it.
   */
  const startAlarm = useCallback((urgent: boolean) => {
    alarmRef.current = true;
    urgentRef.current = urgent;

    const ctx = audioRef.current;
    if (!ctx || ctx.state !== 'running' || !bufferRef.current) return;

    if (soundRef.current) {
      // Already sounding. A critical arriving behind a medium raises the
      // level of the alarm already in the room rather than starting a
      // second one over it.
      if (gainRef.current) gainRef.current.gain.value = (urgent ? 1 : 0.7) * volumeRef.current;
      return;
    }

    try {
      const src = ctx.createBufferSource();
      const gain = ctx.createGain();
      src.buffer = bufferRef.current;
      src.loop = true;
      src.connect(gain);
      gain.connect(ctx.destination);
      gain.gain.value = (urgent ? 1 : 0.7) * volumeRef.current;
      src.onended = () => {
        if (soundRef.current === src) {
          soundRef.current = null;
          gainRef.current = null;
        }
      };
      soundRef.current = src;
      gainRef.current = gain;
      src.start();
    } catch {
      /* the synthesised fallback covers it */
      soundRef.current = null;
      gainRef.current = null;
    }
  }, []);

  /**
   * The AudioContext, made on first need and watched from then on.
   *
   * `audioReady` follows the context's own state rather than a guess, because
   * "the page has been clicked" and "the browser will let this page make a
   * sound" are different things. A site the user has allowed sound for is
   * running the moment the context exists; a page nobody has clicked yet is
   * not. Reading the real state is what lets the console say the sound is off
   * only when it is.
   */
  const ensureContext = useCallback((): AudioContext | null => {
    if (audioRef.current) return audioRef.current;
    if (typeof window === 'undefined') return null;
    const Ctor = window.AudioContext ?? (window as unknown as {
      webkitAudioContext?: typeof AudioContext
    }).webkitAudioContext;
    if (!Ctor) return null;
    const ctx = new Ctor();
    audioRef.current = ctx;
    const sync = () => setAudioReady(ctx.state === 'running');
    ctx.onstatechange = sync;
    sync();
    return ctx;
  }, []);

  /** Decode the downloaded file into the context - once, however many callers ask. */
  const decodeSound = useCallback((ctx: AudioContext): Promise<void> => {
    if (bufferRef.current || !encodedRef.current) return Promise.resolve();
    if (!decodingRef.current) {
      // slice(0) because decodeAudioData DETACHES the ArrayBuffer it is
      // given. Handing it the original would leave encodedRef holding an
      // empty buffer, so a later retry - after a failed decode, or in a
      // second context - would silently decode nothing.
      decodingRef.current = ctx.decodeAudioData(encodedRef.current.slice(0))
        .then(buf => { bufferRef.current = buf; })
        .catch(() => { /* undecodable file - the synthesised chime covers it */ })
        .finally(() => { decodingRef.current = null; });
    }
    return decodingRef.current;
  }, []);

  /**
   * Resume the context so the alarm can be heard.
   *
   * Browsers refuse to play audio until the page has seen a real user gesture,
   * so this is only ever called from one: the first click, key press or tap
   * anywhere on the console (below), the Enable button, or the permission
   * click. The gesture listener matters more than it looks - a dispatcher who
   * never touches a button would otherwise have a console that never makes a
   * sound, and no way of knowing that from looking at it.
   */
  const unlockAudio = useCallback(async () => {
    const ctx = ensureContext();
    if (!ctx) return;
    await ctx.resume().catch(() => {});
    await decodeSound(ctx);

    // A report that arrived before this click is still unanswered, and its
    // alarm has been waiting for permission to be heard.
    if (alarmRef.current) startAlarm(urgentRef.current);
  }, [ensureContext, decodeSound, startAlarm]);

  // Look at the browser's answer as soon as this console is live, before anyone
  // has clicked anything. A site the user has allowed sound for is running
  // straight away and never needs a click; for the rest the state is
  // "suspended", and the bar in the layout says so until the first gesture.
  useEffect(() => {
    if (!enabled) return;
    ensureContext();
  }, [enabled, ensureContext]);

  // Once the browser is willing AND the file has arrived - in either order -
  // decode it, and start the alarm if a report is already waiting.
  useEffect(() => {
    if (!audioReady || !soundFileReady) return;
    const ctx = audioRef.current;
    if (!ctx) return;
    void decodeSound(ctx).then(() => {
      if (alarmRef.current) startAlarm(urgentRef.current);
    });
  }, [audioReady, soundFileReady, decodeSound, startAlarm]);

  // The first gesture anywhere turns the sound on. Every event a browser might
  // count as a gesture is listened for, and the listeners stay until the sound
  // really is running: on Chrome a finger's `pointerdown` is NOT an activation
  // (the tap's `pointerup` is), so a listener that fired once and removed
  // itself could be spent on a touch screen and leave the console silent for
  // good.
  useEffect(() => {
    if (!enabled || typeof window === 'undefined') return;
    const events = ['pointerdown', 'pointerup', 'click', 'touchend', 'keydown'] as const;
    const onGesture = () => {
      if (audioRef.current?.state === 'running') return;
      void unlockAudio();
    };
    events.forEach(t => window.addEventListener(t, onGesture, { capture: true, passive: true }));
    return () => events.forEach(t => window.removeEventListener(t, onGesture, { capture: true }));
  }, [enabled, unlockAudio]);

  /**
   * Ask for the desktop-alert permission, once per browser, from a real click.
   *
   * It used to wait for the operator to find a bar and press a button, which
   * is why the bar sat on the screen indefinitely. Now the first click anywhere
   * is enough: the browser shows its own Allow / Block prompt and remembers the
   * answer. Asked once - dismissing the prompt is a decision, and Settings →
   * Notifications keeps a button for changing your mind - and never when the
   * operator has switched desktop alerts off.
   */
  const askForDesktopAlerts = useCallback(() => {
    if (typeof window === 'undefined' || !('Notification' in window)) return;
    if (Notification.permission !== 'default') return;
    if (!alertPrefs.get().desktop) return;
    try {
      if (localStorage.getItem(PERMISSION_ASKED_KEY)) return;
      localStorage.setItem(PERMISSION_ASKED_KEY, String(Date.now()));
    } catch {
      /* storage blocked - ask anyway; the browser rate-limits repeat prompts itself */
    }
    void (async () => {
      try { setPermission(await Notification.requestPermission()); } catch { /* dismissed */ }
    })();
  }, []);

  // `click` and `keydown` are the two events every browser and input device
  // counts as a gesture for a permission prompt (a tap produces a click).
  useEffect(() => {
    if (!enabled || typeof window === 'undefined' || !('Notification' in window)) return;
    if (Notification.permission !== 'default') return;
    const on = () => { askForDesktopAlerts(); off(); };
    const off = () => {
      window.removeEventListener('click', on, true);
      window.removeEventListener('keydown', on, true);
    };
    window.addEventListener('click', on, true);
    window.addEventListener('keydown', on, true);
    return off;
  }, [enabled, askForDesktopAlerts]);

  const requestPermission = useCallback(async () => {
    if (typeof window === 'undefined' || !('Notification' in window)) return;
    try { localStorage.setItem(PERMISSION_ASKED_KEY, String(Date.now())); } catch { /* storage blocked */ }
    // The audio first, and without waiting: this runs inside the click, and the
    // permission prompt can take the operator several seconds to answer - long
    // enough for the gesture to expire, leaving a context born suspended.
    void unlockAudio();
    try {
      setPermission(await Notification.requestPermission());
    } catch {
      /* permission prompt dismissed - the in-app interrupt still works */
    }
  }, [unlockAudio]);

  /**
   * The alarm, synthesised, for when the sound file is not available.
   *
   * Reached when the file is missing, still downloading, or would not decode.
   * Deliberately kept: silence is the one alert behaviour a dispatch console
   * must never fall back to. Unlike the file it cannot loop, so the caller
   * re-fires it on a timer.
   */
  const synthChime = useCallback((urgent: boolean) => {
    const ctx = audioRef.current;
    if (!ctx || ctx.state !== 'running') return;
    if (bufferRef.current) return; // the real sound is looping; do not double up
    try {
      // Two rising notes for a normal alert; three, higher and tighter, for a
      // critical one. The pattern is the signal — a dispatcher should be able
      // to tell the two apart from across the room, without looking up.
      const notes = urgent ? [880, 1245, 1480] : [880, 1245];
      const step  = urgent ? 0.11 : 0.14;
      notes.forEach((freq, i) => {
        const osc  = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.type = 'sine';
        const t0 = ctx.currentTime + i * step;
        osc.frequency.setValueAtTime(freq, t0);
        gain.gain.setValueAtTime(0.0001, t0);
        gain.gain.exponentialRampToValueAtTime((urgent ? 0.3 : 0.22) * volumeRef.current, t0 + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + step + 0.12);
        osc.start(t0);
        osc.stop(t0 + step + 0.14);
      });
    } catch {
      /* audio is a nice-to-have, never a hard failure */
    }
  }, []);

  // Acknowledging is the dispatcher saying "I have seen it", so the alarm
  // has done its job and stops. It does not touch the incident, which stays
  // in the queue until it is actually dispatched or closed.
  const acknowledge = useCallback((id: string) => {
    setPending(a => a.filter(x => x.id !== id));
  }, []);

  const acknowledgeAll = useCallback(() => {
    setPending([]);
  }, []);

  /**
   * Raise alerts on demand, for demonstrating the interrupt without waiting
   * for a resident to file a real report.
   *
   * Replays incidents that are ACTUALLY in the queue rather than inventing
   * them, so every part of the alert is real — the text a resident wrote, the
   * severity the rubric gave it, and an "Open incident" that opens something
   * that exists. Only when the queue cannot supply enough rows does it fall
   * back to fabricated ones, and those are labelled as samples so nobody
   * mistakes a demo for a report.
   *
   * Bypasses both the seen-set and the notification rules on purpose: the
   * point is to show the overlay, not to re-run the filter that decides
   * whether a genuine report deserves it.
   */
  const simulate = useCallback(async (count: number) => {
    let replayed: IncidentAlert[] = [];
    if (token) {
      try {
        const queue = await fetchQueue(token);
        replayed = queue.slice(0, count).map(inc => {
          const scored = inc.suggested_severity ?? inc.severity ?? null;
          return {
            id: inc.id,
            severity: (scored ?? 'untriaged') as AlertSeverity,
            reportText: inc.report_text,
            address: inc.location_address,
            category: inc.incident_category,
            agencyType: inc.stations?.agencies?.agency_type ?? null,
            sosFlagged: Boolean(inc.sos_flagged),
            filedAt: new Date(inc.created_at),
          };
        });
      } catch {
        /* fall through to samples */
      }
    }

    const samples: IncidentAlert[] = SAMPLE_REPORTS
      .slice(0, Math.max(0, count - replayed.length))
      .map((sample, i) => ({
        ...sample,
        id: `demo-${Date.now()}-${i}`,
        // Staggered so the "oldest first within a severity" ordering is
        // actually visible in the demo instead of every card saying the same
        // thing.
        filedAt: new Date(Date.now() - (i + 1) * 97_000),
      }));

    setPending(prev => {
      const byId = new Map(prev.map(a => [a.id, a]));
      for (const a of [...replayed, ...samples]) byId.set(a.id, a);
      return [...byId.values()];
    });
    // No chime() here. The alarm follows the PENDING SET, not the event that
    // filled it — see the effect below. One rule, one place, and a demo that
    // sounds exactly like a real report because it is the same code path.
  }, [token]);

  // ── Poll and diff ───────────────────────────────────────────────────────
  useEffect(() => {
    if (!token || !enabled || !rules) return;

    let stopped = false;

    const tick = async () => {
      let queue: QueueIncident[];
      try {
        queue = await fetchQueue(token);
      } catch {
        return; // transient failure — try again next tick
      }
      if (stopped) return;

      const active = rulesRef.current ?? DEFAULT_RULES;

      // First run seeds the seen-set without alerting - unless this tab
      // already had one before a reload, in which case anything that arrived
      // in between is still new and must alert.
      if (seenRef.current === null) {
        const restored = loadSeen();
        if (!restored) {
          seenRef.current = new Set(queue.map(i => i.id));
          saveSeen(seenRef.current, queue.map(i => i.id));
          return;
        }
        seenRef.current = restored;
      }

      const { fresh, arrived } = decideAlerts(queue, seenRef.current, active);

      saveSeen(seenRef.current, queue.map(i => i.id));
      announceArrivals(arrived);

      if (fresh.length === 0) return;

      // No cap. The previous version kept only the newest five, which meant a
      // burst of a dozen reports silently discarded seven of them — exactly
      // the situation where losing one is least acceptable. Volume is the
      // overlay's problem to present, not this hook's to truncate.
      setPending(prev => [...prev, ...fresh]);

      // Desktop layer: needs the browser's permission AND the operator not
      // having switched it off for this screen. Read at the moment of use, so
      // flipping the switch takes effect on the very next report.
      if (
        typeof window !== 'undefined' && 'Notification' in window &&
        Notification.permission === 'granted' && alertPrefs.get().desktop
      ) {
        for (const a of fresh) {
          try {
            new Notification(
              a.severity === 'untriaged'
                ? 'New report — needs triage'
                : `${a.severity.toUpperCase()} incident`,
              {
                body: a.reportText.slice(0, 120),
                tag: a.id,               // collapse duplicates for the same incident
                requireInteraction: a.severity === 'critical',
              },
            );
          } catch {
            /* some browsers throw without a service worker — interrupt still shows */
          }
        }
      }
      // The alarm is not started here. It follows the pending set, so it
      // cannot get out of step with what is actually on screen.
    };

    tick();
    const id = setInterval(tick, pollSeconds * 1000);
    return () => { stopped = true; clearInterval(id); };
  }, [token, enabled, rules, pollSeconds]);

  // ── Acknowledge on sight ────────────────────────────────────────────────
  // Opening the incident IS acknowledgement. Without this, arriving at a
  // report from its own alert would leave the alert standing in front of the
  // page describing it.
  useEffect(() => {
    if (!viewingIncidentId) return;
    setPending(a => (a.some(x => x.id === viewingIncidentId)
      ? a.filter(x => x.id !== viewingIncidentId)
      : a));
    silenceAll();
  }, [viewingIncidentId]);

  // ── Heard ───────────────────────────────────────────────────────────────
  // Alerts the alarm has done its job for. Opening ANY report means the
  // dispatcher is at the console and working, so everything already waiting
  // stops sounding - it used to loop on over the very report being read,
  // because the alert-opened dialog deliberately keeps its alert in the tray
  // until close. Heard alerts stay on screen; only the sound stops. A report
  // that arrives AFTER this is not heard yet, and sounds.
  const [heard, setHeard] = useState<ReadonlySet<string>>(() => new Set());
  const pendingRef = useRef(pending);
  pendingRef.current = pending;

  function silenceAll() {
    setHeard(prev => {
      const next = new Set(prev);
      for (const a of pendingRef.current) next.add(a.id);
      return next;
    });
  }

  useOpened(({ id, fromAlert }) => {
    silenceAll();
    // Opened from a page's own table: that IS seeing it, exactly like the
    // incident route above. Opened from the alert itself: it leaves the tray
    // on close, not open (see incident-interrupt.tsx), so only the sound stops.
    if (!fromAlert) setPending(a => a.filter(x => x.id !== id));
  });

  // Worst first, then longest-waiting first — the same order the queue is
  // worked in, so the interrupt never disagrees with the page behind it.
  const ordered = useMemo(
    () => [...pending].sort(
      (a, b) => RANK[a.severity] - RANK[b.severity]
             || a.filedAt.getTime() - b.filedAt.getTime(),
    ),
    [pending],
  );

  // ── The alarm follows the unheard set ───────────────────────────────────
  //
  // Not the arrival event. A report that has been seen makes no sound and a
  // report that has not keeps making one, which is the whole of the rule and
  // is why it lives in one effect rather than at each of the three places
  // that can add an alert.
  //
  // It stops when nothing unheard is left: the dispatcher dismisses the alert,
  // acknowledges them all, or opens any report (from the alert, a page's
  // table, or the incident route). Every one of those is a person at the
  // console.
  // SOUND MODE is the operator's, per screen (Settings → Notifications): `all`
  // sounds for any pending alert, `critical` only while a critical one is
  // waiting, `off` never. A silenced console still shows the overlay, flashes
  // the tab and raises the desktop notification — silence here means the
  // ALARM, not the alert.
  // Only alerts nobody has heard yet ring - see `heard` above.
  const unheard = ordered.filter(a => !heard.has(a.id));
  const unheardCritical = unheard.some(a => a.severity === 'critical');
  const soundOn = soundMode === 'all' || (soundMode === 'critical' && unheardCritical);

  useEffect(() => {
    if (unheard.length === 0 || !soundOn) {
      stopAlarm();
      return;
    }
    startAlarm(unheardCritical);
  }, [unheard.length, unheardCritical, soundOn, startAlarm, stopAlarm]);

  // A level changed while the alarm is already sounding applies at once. The
  // loop is one long-lived node, so without this a slider would only affect
  // the NEXT alarm, and a dispatcher turning it down mid-emergency would hear
  // nothing change.
  useEffect(() => {
    if (gainRef.current) gainRef.current.gain.value = (urgentRef.current ? 1 : 0.7) * volume;
  }, [volume]);

  // The same rule for the synthesised fallback, which cannot loop on its own
  // and so has to be re-fired. It returns early once the real sound is
  // available, so the two can never sound at once.
  useEffect(() => {
    if (unheard.length === 0 || !soundOn) return;
    synthChime(unheardCritical);
    const id = setInterval(() => synthChime(unheardCritical), ESCALATE_MS);
    return () => clearInterval(id);
  }, [unheard.length, unheardCritical, soundOn, synthChime]);

  // Stop the sound if this console unmounts or alerting is switched off. A
  // looping alarm outliving the hook that owns it would be unstoppable.
  useEffect(() => stopAlarm, [stopAlarm]);

  // ── Flash the tab title ─────────────────────────────────────────────────
  // The one delivery layer that reaches a backgrounded tab without asking
  // permission first. Restores the original title on cleanup, so a denied
  // notification prompt never leaves a stuck "(3) NEW REPORTS" behind.
  useEffect(() => {
    if (typeof document === 'undefined' || ordered.length === 0 || !flashTitle) return;
    const original = document.title;
    let on = false;
    const id = setInterval(() => {
      on = !on;
      document.title = on
        ? `(${ordered.length}) ${ordered.length === 1 ? 'NEW REPORT' : 'NEW REPORTS'}`
        : original;
    }, 1_000);
    return () => { clearInterval(id); document.title = original; };
  }, [ordered.length, flashTitle]);

  return {
    /** Unacknowledged alerts, worst and oldest first. */
    pending: ordered,
    acknowledge,
    acknowledgeAll,
    simulate,
    permission,
    requestPermission,
    /** Whether the browser will let this page make a sound right now (null = not yet known). */
    audioReady,
    /** Turn the sound on. Must be called from a click or key press. */
    enableSound: unlockAudio,
    rules,
  };
}
