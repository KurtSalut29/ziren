'use client';

/**
 * useAssistInbox — every cross-agency assist request this station is part
 * of, kept fresh, plus the alert that tells a station it has been asked.
 *
 * WHY IT LIVES IN THE LAYOUT
 *
 * Stations testing the first version were asked for help and never knew: the
 * only signal was a bell entry, and a bell entry is something you find, not
 * something that finds you. So the request now interrupts the same way a new
 * report does, on whatever page the admin is on, with a sound that keeps
 * going until someone opens it or says "later". The report itself stays with
 * the station that asked — this only ALERTS the other one.
 *
 * WHAT IT ALERTS ON
 *
 *   request  — another station asked us for help. Loops the alarm until the
 *              card is opened or put off. Stays a sidebar badge until answered.
 *   response — a station we asked accepted or declined. One chime and a card
 *              that clears itself.
 *   message  — the other side wrote in a thread. One chime and a card.
 *
 * WHAT IS REMEMBERED, AND WHERE
 *
 * Per signed-in email, in localStorage, so it survives a reload and a new
 * tab: which requests have already alerted, which responses have been
 * announced, and — per request — the newest message this person has actually
 * read. "Unread" is always "the other side wrote after my read mark", never a
 * server-side flag, because the server has no per-person read state for this
 * feature and a database change is not needed to get one.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { alertPrefs } from '@/lib/prefs/definitions';
import {
  counterpart, lastMessageIsTheirs, listAssistRequests, type AssistRequestSummary,
} from '@/lib/api/assist-requests';

const POLL_MS = 10_000;
const SOUND_URL = '/NotificationSound.mp3';
/** How long a single chime (response / message) plays before it is cut. */
const CHIME_MS = 2_400;
/** How long a response/message card stays before clearing itself. */
const TOAST_MS = 12_000;
const READ_EVENT = 'ziren:assist-read';

export type AssistAlertKind = 'request' | 'response' | 'message';

export interface AssistAlert {
  key: string;
  kind: AssistAlertKind;
  request: AssistRequestSummary;
  at: number;
}

interface Memory {
  /** Incoming requests whose alert has been opened or put off. */
  alerted: string[];
  /** Outgoing requests whose accept/decline has been announced. */
  announced: string[];
  /** request id -> newest message timestamp this person has read. */
  read: Record<string, string>;
  /** request id -> newest message timestamp already chimed for. */
  chimed: Record<string, string>;
}

function memoryKey(): string | null {
  try {
    const email = sessionStorage.getItem('user_email');
    return email ? `ziren-assist-memory:${email}` : null;
  } catch {
    return null;
  }
}

function loadMemory(): Memory | null {
  const key = memoryKey();
  if (!key) return null;
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return null;
    const v = JSON.parse(raw) as Partial<Memory>;
    return {
      alerted: Array.isArray(v.alerted) ? v.alerted : [],
      announced: Array.isArray(v.announced) ? v.announced : [],
      read: v.read && typeof v.read === 'object' ? v.read : {},
      chimed: v.chimed && typeof v.chimed === 'object' ? v.chimed : {},
    };
  } catch {
    return null;
  }
}

function saveMemory(m: Memory): void {
  const key = memoryKey();
  if (!key) return;
  try {
    // Bounded: a station's whole history of requests is small, but an
    // unbounded array in localStorage is a slow leak all the same.
    localStorage.setItem(key, JSON.stringify({
      alerted: m.alerted.slice(-400),
      announced: m.announced.slice(-400),
      read: m.read,
      chimed: m.chimed,
    }));
  } catch {
    /* storage blocked — alerts still work for this page's life */
  }
}

/** Tell every mounted inbox (the layout's, a page's) that a thread was read. */
export function announceAssistRead(id: string, at: string | null | undefined): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(new CustomEvent(READ_EVENT, { detail: { id, at: at ?? new Date().toISOString() } }));
}

export interface AssistInbox {
  items: AssistRequestSummary[];
  loaded: boolean;
  error: string | null;
  refresh: () => void;
  alerts: AssistAlert[];
  dismissAlert: (key: string) => void;
  /** Mark one request's thread read up to its newest message, and silence its alert. */
  markRead: (id: string) => void;
  isUnread: (r: AssistRequestSummary) => boolean;
  /** Incoming requests still waiting for our answer. */
  pendingIncoming: number;
  /** Requests that need a look: waiting for our answer, or holding an unread reply. */
  attention: number;
}

export function useAssistInbox({
  token,
  enabled,
  isProvincialAdmin,
  alerting,
}: {
  token: string | null;
  enabled: boolean;
  isProvincialAdmin: boolean;
  /** Raise alerts and sound. Off for a Provincial Admin, who answers nothing. */
  alerting: boolean;
}): AssistInbox {
  const [items, setItems] = useState<AssistRequestSummary[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [alerts, setAlerts] = useState<AssistAlert[]>([]);
  const [memory, setMemory] = useState<Memory>({ alerted: [], announced: [], read: {}, chimed: {} });
  const memoryRef = useRef<Memory | null>(null);
  const itemsRef = useRef<AssistRequestSummary[]>([]);
  const { soundMode, volume } = alertPrefs.use();
  const soundOnRef = useRef(true);
  soundOnRef.current = soundMode !== 'off';
  const volumeRef = useRef(volume);
  volumeRef.current = volume;

  const commit = useCallback((m: Memory) => {
    memoryRef.current = m;
    setMemory(m);
    saveMemory(m);
  }, []);

  // ── Sound ──────────────────────────────────────────────────────────────
  // An <audio> element rather than the incident alarm's Web Audio graph: the
  // two alarms are independent on purpose (answering one must not silence the
  // other), and an element needs no decoding step. Browsers allow it once the
  // page has had any click or key press — the same gesture that unlocks the
  // incident alarm — and a refused play() is retried on the next gesture.
  const loopRef = useRef<HTMLAudioElement | null>(null);
  const wantLoopRef = useRef(false);

  const startLoop = useCallback(() => {
    wantLoopRef.current = true;
    if (!soundOnRef.current || typeof Audio === 'undefined') return;
    if (!loopRef.current) {
      loopRef.current = new Audio(SOUND_URL);
      loopRef.current.loop = true;
    }
    loopRef.current.volume = Math.min(1, 0.85 * volumeRef.current);
    if (loopRef.current.paused) void loopRef.current.play().catch(() => { /* retried on the next gesture */ });
  }, []);

  const stopLoop = useCallback(() => {
    wantLoopRef.current = false;
    if (loopRef.current) {
      loopRef.current.pause();
      loopRef.current.currentTime = 0;
    }
  }, []);

  const chime = useCallback(() => {
    if (!soundOnRef.current || typeof Audio === 'undefined') return;
    if (wantLoopRef.current) return; // the alarm is already sounding
    const a = new Audio(SOUND_URL);
    a.volume = Math.min(1, 0.6 * volumeRef.current);
    void a.play().catch(() => {});
    window.setTimeout(() => a.pause(), CHIME_MS);
  }, []);

  useEffect(() => {
    if (!alerting || typeof window === 'undefined') return;
    const retry = () => {
      if (wantLoopRef.current && loopRef.current?.paused) {
        void loopRef.current.play().catch(() => {});
      }
    };
    const events = ['pointerup', 'click', 'keydown', 'touchend'] as const;
    events.forEach(t => window.addEventListener(t, retry, { capture: true, passive: true }));
    return () => events.forEach(t => window.removeEventListener(t, retry, { capture: true }));
  }, [alerting]);

  useEffect(() => () => { loopRef.current?.pause(); }, []);

  // ── Diff one poll against memory ────────────────────────────────────────
  const absorb = useCallback((rows: AssistRequestSummary[]) => {
    itemsRef.current = rows;
    setItems(rows);
    setLoaded(true);
    setError(null);
    if (!alerting) return;

    const stored = memoryRef.current ?? loadMemory();
    // A browser that has never run this: everything that already happened is
    // history, not news — except an incoming request still waiting for an
    // answer, which is exactly what the alert exists for.
    const firstRun = !stored;
    const m: Memory = stored
      ? { ...stored, read: { ...stored.read }, chimed: { ...stored.chimed } }
      : { alerted: [], announced: [], read: {}, chimed: {} };
    const fresh: AssistAlert[] = [];
    const now = Date.now();

    for (const r of rows) {
      if (r.direction === 'incoming' && r.status === 'pending' && !m.alerted.includes(r.id)) {
        fresh.push({ key: `request:${r.id}`, kind: 'request', request: r, at: now });
      }
      if (r.direction === 'outgoing' && r.status !== 'pending' && !m.announced.includes(r.id)) {
        m.announced.push(r.id);
        if (!firstRun) fresh.push({ key: `response:${r.id}:${r.status}`, kind: 'response', request: r, at: now });
      }
      const last = r.last_message_at;
      // First run: a reply that was already sitting there before this browser
      // ever looked is history, not a "new message" — except on a request
      // still waiting for our answer, which stays marked until opened.
      if (firstRun && last && !(r.direction === 'incoming' && r.status === 'pending')) {
        m.read[r.id] = last;
      }
      if (last && lastMessageIsTheirs(r)) {
        const read = m.read[r.id];
        const chimed = m.chimed[r.id];
        const newer = (!read || last > read) && (!chimed || last > chimed);
        if (newer) {
          m.chimed[r.id] = last;
          // The opening message of a new incoming request is already the
          // request alert; do not announce it twice.
          const isOpening = r.direction === 'incoming' && (r.message_count ?? 1) <= 1;
          if (!firstRun && !isOpening) {
            fresh.push({ key: `message:${r.id}:${last}`, kind: 'message', request: r, at: now });
          }
        }
      }
    }
    commit(m);

    if (fresh.length) {
      setAlerts(prev => {
        const keys = new Set(prev.map(a => a.key));
        const next = [...prev];
        for (const a of fresh) if (!keys.has(a.key)) next.push(a);
        return next;
      });
      if (!fresh.some(a => a.kind === 'request')) chime();
    }
  }, [alerting, chime, commit]);

  const load = useCallback(async () => {
    if (!token || !enabled) return;
    try {
      const rows = await listAssistRequests(isProvincialAdmin ? null : 'all', token);
      absorb(rows);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Could not load assist requests.');
      setLoaded(true);
    }
  }, [token, enabled, isProvincialAdmin, absorb]);

  useEffect(() => {
    const m = loadMemory();
    if (m) { memoryRef.current = m; setMemory(m); }
  }, []);

  useEffect(() => {
    if (!token || !enabled) return;
    void load();
    const id = window.setInterval(() => { void load(); }, POLL_MS);
    const onFocus = () => { if (document.visibilityState === 'visible') void load(); };
    document.addEventListener('visibilitychange', onFocus);
    return () => {
      window.clearInterval(id);
      document.removeEventListener('visibilitychange', onFocus);
    };
  }, [token, enabled, load]);

  // The alarm follows the set of unanswered request cards, not the event
  // that raised them — the same rule the incident alarm keeps.
  const ringing = alerts.some(a => a.kind === 'request');
  useEffect(() => {
    if (ringing) startLoop(); else stopLoop();
  }, [ringing, startLoop, stopLoop]);

  // Response / message cards clear themselves.
  useEffect(() => {
    const soft = alerts.filter(a => a.kind !== 'request');
    if (!soft.length) return;
    const oldest = Math.min(...soft.map(a => a.at));
    const t = window.setTimeout(() => {
      const cutoff = Date.now() - TOAST_MS + 50;
      setAlerts(prev => prev.filter(a => a.kind === 'request' || a.at > cutoff));
    }, Math.max(0, oldest + TOAST_MS - Date.now()));
    return () => window.clearTimeout(t);
  }, [alerts]);

  const silence = useCallback((id: string) => {
    const base = memoryRef.current ?? { alerted: [], announced: [], read: {}, chimed: {} };
    if (!base.alerted.includes(id)) commit({ ...base, alerted: [...base.alerted, id] });
    setAlerts(prev => prev.filter(a => a.request.id !== id));
  }, [commit]);

  const dismissAlert = useCallback((key: string) => {
    const alert = alerts.find(a => a.key === key);
    if (alert?.kind === 'request') silence(alert.request.id);
    else setAlerts(prev => prev.filter(a => a.key !== key));
  }, [alerts, silence]);

  const applyRead = useCallback((id: string, at: string) => {
    const base = memoryRef.current ?? { alerted: [], announced: [], read: {}, chimed: {} };
    const prev = base.read[id];
    const alerted = base.alerted.includes(id) ? base.alerted : [...base.alerted, id];
    if (prev && prev >= at && alerted === base.alerted) return;
    commit({ ...base, alerted, read: { ...base.read, [id]: prev && prev > at ? prev : at } });
    setAlerts(p => p.filter(a => a.request.id !== id));
  }, [commit]);

  const markRead = useCallback((id: string) => {
    const r = itemsRef.current.find(x => x.id === id);
    const at = r?.last_message_at ?? new Date().toISOString();
    applyRead(id, at);
    announceAssistRead(id, at);
  }, [applyRead]);

  useEffect(() => {
    const on = (e: Event) => {
      const d = (e as CustomEvent<{ id: string; at: string }>).detail;
      if (d?.id) applyRead(d.id, d.at);
    };
    window.addEventListener(READ_EVENT, on);
    return () => window.removeEventListener(READ_EVENT, on);
  }, [applyRead]);

  const isUnread = useCallback((r: AssistRequestSummary) => {
    if (!r.last_message_at || !lastMessageIsTheirs(r)) return false;
    const read = memory.read[r.id];
    return !read || r.last_message_at > read;
  }, [memory]);

  const { pendingIncoming, attention } = useMemo(() => {
    let pending = 0;
    const need = new Set<string>();
    for (const r of items) {
      if (r.direction === 'incoming' && r.status === 'pending') { pending++; need.add(r.id); }
      if (isUnread(r)) need.add(r.id);
    }
    return { pendingIncoming: pending, attention: need.size };
  }, [items, isUnread]);

  return {
    items, loaded, error, refresh: () => { void load(); },
    alerts, dismissAlert, markRead, isUnread, pendingIncoming, attention,
  };
}

/** "PNP Naval Station" for the station on the other side, with a fallback. */
export function otherStationName(r: AssistRequestSummary): string {
  return counterpart(r).name ?? 'Another station';
}
