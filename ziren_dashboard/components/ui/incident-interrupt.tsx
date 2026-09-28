'use client';

/**
 * IncidentInterrupt — spotlight the most urgent unread report, keep the rest
 * visibly waiting in a tray, open either one in the same detail dialog the
 * queue table uses.
 *
 * WHY THIS CHANGED FROM ONE CARD AT A TIME
 *
 * The previous version showed exactly one report with "1 of 4" in the
 * footer — worst-first, but the other three were text nobody could read.
 * Live testing with real multi-report bursts found dispatchers who could not
 * tell whether four reports were four DIFFERENT incidents or the same one
 * counted four times, and who had to click through blind to find out which
 * of the four was actually critical. So the count is no longer a number to
 * trust — it is a column of real cards, worst first, sitting in view the
 * whole time.
 *
 * "OPEN INCIDENT" OPENS A DIALOG, NOT A PAGE
 *
 * It used to `router.push('/incidents/{id}')`, which left whatever the
 * dispatcher was doing (a filtered table, a map, a scroll position) to load a
 * full page for one report. Both the spotlight's button and every tray row
 * now report an id upward; the layout owns exactly one <IncidentDetailModal>
 * for this purpose and opens it in place, on top of whatever page is
 * showing — the same dialog the live queue table opens on a row click.
 *
 * A REPORT LEAVES THE TRAY WHEN ITS DIALOG CLOSES, NOT WHEN IT OPENS
 *
 * Opening a report is not the same as being done with it — the dispatcher
 * may spend a minute on the phone with the resident before touching a
 * button. If opening removed it immediately, the tray's count would already
 * be wrong while they were still reading it. So the layout keeps it in
 * `pending` for as long as its dialog is open (this component simply hides
 * its own spotlight card for that one id, since the real dialog already
 * shows everything) and only acknowledges it on close — which is also the
 * moment the next-worst report in the tray is promoted into the spotlight,
 * automatically, with nothing to click.
 *
 * BRIEF BLOCK, THEN A PERSISTENT DOCK
 *
 * A report that nobody has any reason to expect — the first one after a
 * quiet stretch, or a critical breaking in while something else is being
 * worked — still takes the whole screen for a few seconds, exactly as
 * before: an emergency must interrupt, not wait to be noticed in a corner.
 * Once that beat has passed, the same spotlight card settles into a docked
 * panel at the top right, backdrop and focus trap both gone, so the
 * dispatcher can keep working the rest of the console (open a different
 * page, use the table, answer a call) while it keeps waiting in view — the
 * same relationship the responder-distress banner already has with the rest
 * of the shell.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'framer-motion';
import {
  ArrowRight, Check, Clock, Layers, MapPin, Siren, TriangleAlert, CircleHelp,
} from 'lucide-react';
import type { AlertSeverity, IncidentAlert } from '@/lib/hooks/useIncidentAlerts';

/**
 * How long a genuinely new arrival takes the whole screen before settling
 * into the docked panel. Long enough to actually register a critical
 * incident just came in; short enough that it never becomes the thing
 * standing between a dispatcher and the rest of the console.
 */
const ANNOUNCE_MS = 2_600;

/**
 * How long the buttons ignore input after a card the person did not expect
 * appears under their hands — a fresh announce, or a promotion that just put
 * a new report where an old one used to be. Without this, a click already
 * travelling toward the page lands on whatever button happens to be there
 * and dismisses a report nobody actually read.
 */
const ARM_MS = 600;

/**
 * How long a report that joined the tray without retaking the whole screen
 * (see the file comment — only a fresh critical or the first-after-empty
 * gets the takeover) keeps its "just landed" highlight. Long enough to catch
 * a glance that wasn't aimed at the tray the instant it happened; short
 * enough that the tray goes back to reading as a calm, static list.
 */
const JUST_LANDED_MS = 2_200;

const SEV: Record<AlertSeverity, { label: string; color: string; bg: string }> = {
  critical:  { label: 'Critical',     color: 'var(--color-severity-critical)', bg: 'var(--color-severity-critical-bg)' },
  high:      { label: 'High',         color: 'var(--color-severity-high)',     bg: 'var(--color-severity-high-bg)' },
  medium:    { label: 'Medium',       color: 'var(--color-severity-medium)',   bg: 'var(--color-severity-medium-bg)' },
  low:       { label: 'Low',          color: 'var(--color-severity-low)',      bg: 'var(--color-severity-low-bg)' },
  // No severity colour, because there is no severity. Borrowing the amber of
  // `high` would state a score the rubric never produced, and severity colour
  // in this console is an operational claim, not decoration.
  untriaged: { label: 'Needs triage', color: 'var(--color-text-muted)',        bg: 'var(--color-surface-raised)' },
};

const RANK: Record<AlertSeverity, number> = { critical: 0, high: 1, medium: 2, untriaged: 3, low: 4 };

/** Worst first — shared by the tray and its modal-open strip so the two never disagree on what "worst" means. */
const SEV_ORDER: AlertSeverity[] = ['critical', 'high', 'untriaged', 'medium', 'low'];
function severityTally(items: IncidentAlert[]) {
  return SEV_ORDER
    .map(s => [s, items.filter(a => a.severity === s).length] as const)
    .filter(([, n]) => n > 0);
}

/**
 * Critical reports get a tinted border, so the card's own silhouette says
 * "this one is critical" before anyone reads the label — every other
 * severity keeps the plain neutral border. Shared by every card the alert
 * flow draws: the takeover, the docked spotlight, and each tray card.
 */
function criticalBorder(severity: AlertSeverity): string {
  return severity === 'critical'
    ? `color-mix(in srgb, ${SEV.critical.color} 35%, var(--color-surface-border))`
    : 'var(--color-surface-border)';
}

/** The takeover and docked spotlight — the two places a WHOLE card (not a
 * compact tray row) renders — also get a soft colour-matched glow on top of
 * the tinted border when critical. */
function spotlightChrome(severity: AlertSeverity): React.CSSProperties {
  if (severity !== 'critical') {
    return { backgroundColor: 'var(--color-surface-card)', borderColor: 'var(--color-surface-border)' };
  }
  return {
    backgroundColor: 'var(--color-surface-card)',
    borderColor: criticalBorder(severity),
    boxShadow: `0 0 0 1px color-mix(in srgb, ${SEV.critical.color} 14%, transparent), var(--shadow-lg)`,
  };
}

function SevIcon({ severity, size = 15 }: { severity: AlertSeverity; size?: number }) {
  if (severity === 'untriaged') return <CircleHelp size={size} />;
  if (severity === 'critical')  return <Siren size={size} />;
  return <TriangleAlert size={size} />;
}

/** Coarse on purpose — an exact second is noise on a card read at a glance. */
function ago(from: Date, now: number): string {
  const s = Math.max(0, Math.round((now - from.getTime()) / 1000));
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60);
  return `${h}h ${m % 60}m ago`;
}

export function IncidentInterrupt({
  pending,
  openIncidentId,
  onAcknowledge,
  onAcknowledgeAll,
  onOpen,
}: {
  /** Worst and oldest first — see useIncidentAlerts. */
  pending: IncidentAlert[];
  /** The id currently open in the layout's <IncidentDetailModal>, or null. */
  openIncidentId: string | null;
  /** Dismiss one without opening it — "I've seen it, not acting on it here." */
  onAcknowledge: (id: string) => void;
  onAcknowledgeAll: () => void;
  /** Ask the layout to open this id in the shared detail dialog. */
  onOpen: (id: string) => void;
}) {
  // ── Live relative times ─────────────────────────────────────────────────
  const anyVisible = pending.length > 0;
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!anyVisible) return;
    const id = setInterval(() => setNow(Date.now()), 1_000);
    return () => clearInterval(id);
  }, [anyVisible]);

  // ── Which report is spotlighted, and whether it is still being announced ─
  //
  // Only a genuinely new arrival announces: the first one after the queue
  // was empty, or any new report that is itself critical. A new low or
  // medium arriving while something else is already the spotlight just takes
  // its place in the tray without retaking the screen — see the file
  // comment.
  const seenIdsRef = useRef<Set<string>>(new Set());
  const previousCountRef = useRef(0);
  const [announceId, setAnnounceId] = useState<string | null>(null);
  const announceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Reports that joined the tray silently (not worth the full takeover) still
  // get a brief highlight where they actually landed — otherwise the only
  // sign a new one arrived is a number changing, which is exactly what the
  // user reported: "diko agad napapansin". Cleared per-id on its own timer.
  const [justLandedIds, setJustLandedIds] = useState<Set<string>>(new Set());

  useEffect(() => {
    const wasEmpty = previousCountRef.current === 0;
    previousCountRef.current = pending.length;

    const freshlyArrived = pending.filter(a => !seenIdsRef.current.has(a.id));
    for (const a of pending) seenIdsRef.current.add(a.id);
    if (freshlyArrived.length === 0) return;

    const worthAnnouncing = wasEmpty
      ? freshlyArrived[0] // the whole batch just broke a quiet stretch
      : freshlyArrived.find(a => a.severity === 'critical');

    const landedQuietly = freshlyArrived.filter(a => a.id !== worthAnnouncing?.id);
    if (landedQuietly.length > 0) {
      setJustLandedIds(prev => {
        const next = new Set(prev);
        for (const a of landedQuietly) next.add(a.id);
        return next;
      });
      for (const a of landedQuietly) {
        setTimeout(() => {
          setJustLandedIds(prev => {
            if (!prev.has(a.id)) return prev;
            const next = new Set(prev);
            next.delete(a.id);
            return next;
          });
        }, JUST_LANDED_MS);
      }
    }

    if (!worthAnnouncing) return;

    setAnnounceId(worthAnnouncing.id);
    if (announceTimerRef.current) clearTimeout(announceTimerRef.current);
    announceTimerRef.current = setTimeout(() => setAnnounceId(null), ANNOUNCE_MS);
    // pending changes on every poll tick; only react to membership, not identity.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pending.map(a => a.id).join(',')]);

  useEffect(() => () => { if (announceTimerRef.current) clearTimeout(announceTimerRef.current); }, []);

  // A dialog already open for this id ends the announce immediately — the
  // dispatcher's attention is plainly on it already.
  useEffect(() => {
    if (openIncidentId) setAnnounceId(null);
  }, [openIncidentId]);

  // Nothing to spotlight while its own dialog is open — that dialog already
  // shows everything this card would.
  const spotlight = openIncidentId ? null : pending[0] ?? null;
  const trayItems = openIncidentId
    ? pending.filter(a => a.id !== openIncidentId)
    : pending.slice(1);

  const blocking = !openIncidentId && spotlight !== null && spotlight.id === announceId;

  // ── Arming ──────────────────────────────────────────────────────────────
  // Re-arms whenever the spotlighted id changes — a fresh announce AND a
  // silent promotion both put a new report where an old one used to sit.
  const [armed, setArmed] = useState(false);
  useEffect(() => {
    if (!spotlight) { setArmed(false); return; }
    setArmed(false);
    const id = setTimeout(() => setArmed(true), ARM_MS);
    return () => clearTimeout(id);
    // Keyed on the id on purpose, not the object — `pending` gets a new array
    // (new object references) on every poll tick even when nothing changed,
    // and re-arming on every tick would mean the buttons practically never
    // finish arming during a long poll run.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spotlight?.id]);

  // ── Hand-off cue ────────────────────────────────────────────────────────
  // A promoted report was already sitting in the tray — it never earns the
  // takeover (see the announce effect), so without this the docked card's
  // content would just silently swap, and closing one report would look
  // exactly like nothing happened. The card itself is keyed by id below
  // (AnimatePresence), which gives the swap a real exit/enter transition;
  // this adds the explicit "Next incident" tag on top of it, because a
  // slide/fade alone still reads as ambiguous motion, not as "you're now
  // looking at a different report."
  const prevSpotlightIdRef = useRef<string | null>(null);
  const [justPromoted, setJustPromoted] = useState(false);
  useEffect(() => {
    // Only update the "last real spotlight" memory when there IS one.
    // `spotlight` goes null the instant a dialog opens (see above), and if
    // that null were allowed to overwrite the ref, closing the dialog would
    // always look like the very first report ever shown (nothing to compare
    // against) — exactly the silent case this effect exists to catch.
    if (!spotlight) return;
    const previousId = prevSpotlightIdRef.current;
    prevSpotlightIdRef.current = spotlight.id;
    if (!previousId || previousId === spotlight.id) return;
    setJustPromoted(true);
    const id = setTimeout(() => setJustPromoted(false), JUST_LANDED_MS);
    return () => clearTimeout(id);
    // Keyed on the id, same reasoning as the arm effect above — `spotlight`
    // itself is a new object every poll tick.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spotlight?.id]);

  const dismissSpotlight = useCallback(() => {
    if (!armed || !spotlight) return;
    onAcknowledge(spotlight.id);
  }, [armed, spotlight, onAcknowledge]);

  const openSpotlight = useCallback(() => {
    if (!armed || !spotlight) return;
    onOpen(spotlight.id);
  }, [armed, spotlight, onOpen]);

  // ── Keyboard — only while actually blocking. A docked panel traps nothing. ─
  const panelRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!blocking) return;
    const previous = document.activeElement as HTMLElement | null;
    panelRef.current?.focus();
    const { overflow } = document.body.style;
    document.body.style.overflow = 'hidden';

    const onKey = (e: KeyboardEvent) => {
      // Escape dismisses ordinary alerts, but never a critical one: a reflex
      // Escape is exactly how the most serious report in the system would
      // get waved away without being read.
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        if (spotlight?.severity === 'critical' || !armed) return;
        dismissSpotlight();
        return;
      }
      if (e.key === 'Tab' && panelRef.current) {
        const focusables = panelRef.current.querySelectorAll<HTMLElement>(
          'button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])',
        );
        if (focusables.length === 0) return;
        const first = focusables[0];
        const last  = focusables[focusables.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => {
      window.removeEventListener('keydown', onKey, true);
      document.body.style.overflow = overflow;
      previous?.focus?.();
    };
  }, [blocking, spotlight?.severity, armed, dismissSpotlight]);

  if (!anyVisible && trayItems.length === 0) return null;

  return (
    <>
      {/* ── Persistent background blur, for as long as anything is waiting ─
          Requested 2026-09-23: the takeover's own blur used to disappear
          the moment it docked (~2.6s), which read as the alert being
          "handled" when nothing had actually happened yet — the user wanted
          the blur to stay for as long as a report is genuinely unread.
          Deliberately separate from the takeover below and from `blocking`:
          this one is `pointer-events-none` and z-[1050] — UNDER the incident
          detail dialog's own overlay (z-[1100]) and every alert card
          (z-[2000]) — so it blurs the ordinary page behind everything, but
          never the dialog or the cards themselves, and never blocks a
          click. That is what keeps this an ADDITION to the round-1 "not
          blocking" decision rather than a reversal of it: the visual cue
          persists, the ability to keep working through it does not change. */}
      <AnimatePresence>
        {anyVisible && (
          <motion.div
            animate={{ opacity: 1 }}
            className="pointer-events-none fixed inset-0 z-[1050]"
            exit={{ opacity: 0 }}
            initial={{ opacity: 0 }}
            style={{ backdropFilter: 'blur(2px)', backgroundColor: 'rgba(9, 11, 16, 0.1)' }}
            transition={{ duration: 0.3 }}
          />
        )}
      </AnimatePresence>

      {/* ── The brief, unmissable takeover ─────────────────────────────── */}
      <AnimatePresence>
        {blocking && spotlight && (
          <motion.div
            animate={{ opacity: 1 }}
            className="fixed inset-0 z-[2000] flex items-center justify-center p-4"
            data-incident-interrupt=""
            exit={{ opacity: 0 }}
            initial={{ opacity: 0 }}
            transition={{ duration: 0.15 }}
            style={{
              backgroundColor: 'rgba(9, 11, 16, 0.62)',
              backdropFilter: 'blur(3px)',
              pointerEvents: 'auto',
            }}
          >
            <motion.div
              animate={{ opacity: 1, scale: 1, y: 0 }}
              aria-labelledby="incident-interrupt-title"
              aria-modal="true"
              className="w-full max-w-[520px] overflow-hidden rounded-[16px] border shadow-[var(--shadow-lg)] outline-none"
              // Explicit exit, not left to default to `initial` — and
              // deliberately just a fade+shrink with NO y movement. This used
              // to drift toward the dock position when the dock lived
              // elsewhere (top-of-screen); now the docked card renders at
              // this SAME centred spot (see below), so the two are already
              // in the same place and don't need to travel toward each other
              // at all — the backdrop dissolving away is the only real change.
              exit={{ opacity: 0, scale: 0.96 }}
              initial={{ opacity: 0, scale: 0.96, y: 8 }}
              ref={panelRef}
              role="alertdialog"
              style={spotlightChrome(spotlight.severity)}
              tabIndex={-1}
              transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
            >
              <div style={{ height: 4, backgroundColor: SEV[spotlight.severity].color }} />
              <SpotlightBody alert={spotlight} now={now} />
              <SpotlightFooter
                armed={armed}
                hint={spotlight.severity === 'critical' ? 'Critical — read before dismissing' : 'Esc to dismiss'}
                onDismiss={dismissSpotlight}
                onOpen={openSpotlight}
              />
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── The docked spotlight: dead centre, same spot as the takeover ──
          Used to dock at top-centre once past the takeover, which put a
          repositioning jump between the two ("bigla siyang pumunta sa
          taas" — reported 2026-09-23, twice). Fixed by not moving it at
          all: the docked card renders at the EXACT same centred position
          and EXACT same full (non-compact) size as the takeover card, so
          there is nothing to travel between — losing the backdrop and focus
          trap is the only thing that actually changes when `blocking` ends.
          Hidden entirely while its own dialog is open (`spotlight` is null
          then; that dialog already shows everything this card would).
          Keyed by id so a silent promotion (the previous report's dialog
          just closed) gets a real transition instead of its content
          swapping in place — see the `justPromoted` effect above. */}
      <div
        className="pointer-events-none fixed left-1/2 top-1/2 z-[2000] w-[520px] max-w-[calc(100vw-2rem)] -translate-x-1/2 -translate-y-1/2"
        data-incident-interrupt=""
      >
        <AnimatePresence>
          {spotlight && !blocking && (
            <motion.div
              animate={{ opacity: 1, scale: 1 }}
              className="pointer-events-auto relative"
              exit={{ opacity: 0, scale: 0.96 }}
              initial={{ opacity: 0, scale: 0.96 }}
              key={spotlight.id}
              transition={{ duration: 0.25, ease: [0.16, 1, 0.3, 1] }}
            >
              <AnimatePresence>
                {justPromoted && (
                  <motion.span
                    animate={{ opacity: 1, y: 0 }}
                    className="absolute -top-2.5 left-4 z-10 rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide shadow-[var(--shadow-sm)]"
                    exit={{ opacity: 0 }}
                    initial={{ opacity: 0, y: -4 }}
                    key="next-tag"
                    style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
                  >
                    Next incident
                  </motion.span>
                )}
              </AnimatePresence>
              <div
                className="overflow-hidden rounded-[16px] border shadow-[var(--shadow-lg)]"
                style={spotlightChrome(spotlight.severity)}
              >
                <div style={{ height: 4, backgroundColor: SEV[spotlight.severity].color }} />
                <SpotlightBody alert={spotlight} now={now} />
                <SpotlightFooter armed={armed} onDismiss={dismissSpotlight} onOpen={openSpotlight} />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* ── The tray: everything else, worst first, always visible ────────
          Stays docked on the right AT ALL TIMES, including while a report's
          dialog is open — IncidentDetailModal now reserves this column
          itself (left-4, capped width — see that file), so the two sit side
          by side instead of the tray sitting on top of it. */}
      {trayItems.length > 0 && (
        <div
          aria-live="polite"
          className="pointer-events-none fixed right-4 top-[76px] z-[2000] w-[364px] max-w-[calc(100vw-2rem)]"
          data-incident-interrupt=""
        >
          <Tray
            heading={openIncidentId ? 'more waiting to be dispatched' : 'more waiting'}
            items={trayItems}
            justLandedIds={justLandedIds}
            now={now}
            onDismissAll={onAcknowledgeAll}
            onOpen={onOpen}
            showDismissAll={pending.length >= 3}
          />
        </div>
      )}
    </>
  );
}

// ── The spotlighted report's content ────────────────────────────────────────
//
// Redesigned 2026-09-23, round 5 ("mas professional, clean look, and easy to
// notice"). The takeover and docked cards render identically now (round 4),
// so the old `compact` variant is dead code — removed rather than kept
// unused. Changes: the icon badge gets a soft colour-matched ring instead of
// a flat fill only, so it reads as an accent rather than a coloured circle
// stamped on the card; the severity label and heading are visually tied
// together on one baseline instead of stacked; a critical report also tints
// the card's own border, so "this one is critical" is legible from the
// card's silhouette alone, not only its text.

function SpotlightBody({ alert, now }: { alert: IncidentAlert; now: number }) {
  const sev = SEV[alert.severity];

  return (
    <div className="px-6 pb-5 pt-5">
      <div className="flex items-start gap-3.5">
        <div
          className="flex shrink-0 items-center justify-center rounded-full"
          style={{
            backgroundColor: sev.bg,
            color: sev.color,
            width: 44,
            height: 44,
            boxShadow: `0 0 0 4px color-mix(in srgb, ${sev.color} 10%, transparent)`,
          }}
        >
          <SevIcon severity={alert.severity} size={21} />
        </div>

        <div className="min-w-0 flex-1">
          <span
            className="text-[12px] font-bold uppercase tracking-wide"
            style={{ color: sev.color }}
          >
            {sev.label}
          </span>
          <h2
            className="mt-0.5 text-[16px] font-semibold leading-snug tracking-tight"
            id="incident-interrupt-title"
            style={{ color: 'var(--color-text-primary)' }}
          >
            New report from a resident
          </h2>
          <div className="mt-1.5 flex flex-wrap items-center gap-1.5">
            {alert.agencyType && <Chip>{alert.agencyType}</Chip>}
            {alert.category && <Chip>{alert.category.replace(/_/g, ' ')}</Chip>}
            {alert.sosFlagged && (
              <span
                className="rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide"
                style={{ backgroundColor: 'var(--color-severity-critical-bg)', color: 'var(--color-severity-critical)' }}
              >
                SOS
              </span>
            )}
          </div>
        </div>
      </div>

      <p
        className="mt-3.5 line-clamp-4 whitespace-pre-wrap text-[13.5px] leading-relaxed"
        style={{ color: 'var(--color-text-secondary)' }}
      >
        {alert.reportText}
      </p>

      <div
        className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 border-t pt-2.5 text-[11.5px]"
        style={{ color: 'var(--color-text-muted)', borderColor: 'var(--color-surface-border)' }}
      >
        <span className="flex items-center gap-1.5">
          <Clock size={12} />
          Filed {ago(alert.filedAt, now)}
        </span>
        {alert.address && (
          <span className="flex min-w-0 items-center gap-1.5">
            <MapPin className="shrink-0" size={12} />
            <span className="truncate">{alert.address}</span>
          </span>
        )}
      </div>

      {alert.severity === 'untriaged' && (
        <p
          className="mt-3 rounded-[10px] px-3 py-2 text-[12px] leading-snug"
          style={{ backgroundColor: 'var(--color-surface-raised)', color: 'var(--color-text-secondary)' }}
        >
          The rubric produced no score for this report, so it is being shown to
          you regardless of your alert settings. Someone has to read it.
        </p>
      )}
    </div>
  );
}

function SpotlightFooter({
  armed, onDismiss, onOpen, hint,
}: {
  armed: boolean;
  onDismiss: () => void;
  onOpen: () => void;
  hint?: string;
}) {
  return (
    <div
      className="flex flex-wrap items-center justify-between gap-2.5 border-t px-4 py-3"
      style={{ borderColor: 'var(--color-surface-border)', backgroundColor: 'var(--color-surface-raised)' }}
    >
      {hint ? (
        <span className="text-[11.5px]" style={{ color: 'var(--color-text-muted)' }}>{hint}</span>
      ) : <span />}

      <div className="flex items-center gap-2">
        <button
          className="flex items-center gap-1.5 rounded-full border px-3.5 py-2 text-[12.5px] font-semibold transition-colors hover:bg-[var(--color-surface-hover)] disabled:pointer-events-none disabled:opacity-40"
          disabled={!armed}
          onClick={onDismiss}
          style={{ borderColor: 'var(--color-surface-border)', color: 'var(--color-text-secondary)', backgroundColor: 'var(--color-surface-card)' }}
          type="button"
        >
          <Check size={13} />
          Dismiss
        </button>
        {/* Deliberately NOT autoFocused — see the file comment on arming. */}
        <button
          className="flex items-center gap-1.5 rounded-full px-3.5 py-2 text-[12.5px] font-semibold shadow-[var(--shadow-sm)] transition-all hover:brightness-105 hover:shadow-[var(--shadow-md)] disabled:pointer-events-none disabled:opacity-40"
          disabled={!armed}
          onClick={onOpen}
          style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
          type="button"
        >
          Open incident
          <ArrowRight size={13} />
        </button>
      </div>
    </div>
  );
}

// ── The tray: everything else, worst first, always visible ─────────────────
//
// Redesigned 2026-09-23, twice the same day after live feedback. First pass:
// the original version read as same-weight chrome as everything else on the
// console, so a report landing in it did not register — fixed with a bold
// coloured count, tally chips, and a brief highlight on whichever report
// just arrived (`justLandedIds`, from the parent). Second pass: reports were
// all rows inside ONE shared card, which read as a single list rather than
// as separate incidents — each one is now its own card (own border, own
// severity accent, own shadow), stacked with a real gap between them, the
// same visual language the spotlight card already uses. The heading + tally
// sit in their own small pill ABOVE the stack rather than inside it, so nothing
// visually binds the individual reports into one box.

function Tray({
  items, now, onOpen, heading, onDismissAll, showDismissAll, justLandedIds,
}: {
  items: IncidentAlert[];
  now: number;
  onOpen: (id: string) => void;
  heading: string;
  onDismissAll: () => void;
  showDismissAll: boolean;
  justLandedIds: Set<string>;
}) {
  const tally = severityTally(items);
  const worst = tally[0]?.[0] ?? 'low';

  return (
    <div className="flex flex-col gap-2">
      <div
        className="pointer-events-auto flex items-center justify-between gap-2 rounded-full border px-3.5 py-1.5 shadow-[var(--shadow-lg)]"
        style={{ backgroundColor: 'var(--color-surface-card)', borderColor: 'var(--color-surface-border)' }}
      >
        <span className="flex items-center gap-1.5">
          <Layers size={13} style={{ color: SEV[worst].color }} />
          <span className="text-[12.5px] font-bold" style={{ color: 'var(--color-text-primary)' }}>
            <span style={{ color: SEV[worst].color }}>{items.length}</span>
            {' '}
            {heading}
          </span>
        </span>
        {showDismissAll && (
          <button
            className="shrink-0 text-[11px] font-medium underline-offset-2 hover:underline"
            onClick={onDismissAll}
            style={{ color: 'var(--color-text-muted)' }}
            type="button"
          >
            Dismiss all
          </button>
        )}
      </div>

      {tally.length > 1 && (
        <div className="flex flex-wrap gap-1 px-1">
          {tally.map(([s, n]) => (
            <span
              className="pointer-events-auto flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold shadow-[var(--shadow-sm)]"
              key={s}
              style={{ backgroundColor: SEV[s].bg, color: SEV[s].color }}
            >
              <SevIcon severity={s} size={10} />
              {n}
            </span>
          ))}
        </div>
      )}

      <div className="relative">
        <ul className="flex max-h-[calc(100vh-220px)] flex-col gap-2 overflow-y-auto px-0.5 pb-1.5">
          <AnimatePresence initial={false}>
            {items
              .slice()
              .sort((a, b) => RANK[a.severity] - RANK[b.severity] || a.filedAt.getTime() - b.filedAt.getTime())
              .map(a => {
                const justLanded = justLandedIds.has(a.id);
                return (
                  <motion.li
                    animate={{ opacity: 1, x: 0 }}
                    className="pointer-events-auto"
                    exit={{ opacity: 0 }}
                    initial={{ opacity: 0, x: 10 }}
                    key={a.id}
                    layout
                    transition={{ duration: 0.2 }}
                  >
                    {/* Its own card — border, radius, shadow, severity accent
                        — not a row inside a shared one. The background is a
                        plain CSS transition, not framer-motion: the target
                        colour is a CSS custom property (see SEV), and letting
                        the browser transition the computed colour directly is
                        simpler than asking framer-motion to interpolate a
                        var() reference. The inline style is only present
                        WHILE just-landed, so the card falls back to its
                        ordinary resting background (and :hover) the rest of
                        the time — an inline value present permanently, even
                        one that matches the resting colour, would otherwise
                        outrank :hover forever. */}
                    <button
                      className="flex w-full items-center gap-3 overflow-hidden rounded-[14px] border bg-[var(--color-surface-card)] py-2.5 pl-0 pr-3.5 text-left shadow-[var(--shadow-md)] duration-700 ease-out hover:bg-[var(--color-surface-raised)]"
                      onClick={() => onOpen(a.id)}
                      style={{
                        borderColor: criticalBorder(a.severity),
                        backgroundColor: justLanded ? SEV[a.severity].bg : undefined,
                      }}
                      type="button"
                    >
                      <span
                        aria-hidden="true"
                        className="h-11 w-[4px] shrink-0 self-stretch rounded-full"
                        style={{ backgroundColor: SEV[a.severity].color }}
                      />
                      {/* Same icon-badge language the spotlight card uses,
                          scaled down — so a tray card reads as a smaller
                          member of the same family, not a different kind of
                          element entirely. */}
                      <span
                        className="flex shrink-0 items-center justify-center rounded-full"
                        style={{
                          backgroundColor: SEV[a.severity].bg,
                          color: SEV[a.severity].color,
                          width: 30,
                          height: 30,
                        }}
                      >
                        <SevIcon severity={a.severity} size={15} />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="block truncate text-[13px] font-medium" style={{ color: 'var(--color-text-primary)' }}>
                          {a.reportText}
                        </span>
                        <span className="block truncate text-[11.5px]" style={{ color: 'var(--color-text-muted)' }}>
                          {SEV[a.severity].label} · {ago(a.filedAt, now)}
                          {justLanded && (
                            <>
                              {' · '}
                              <span style={{ color: SEV[a.severity].color, fontWeight: 700 }}>just in</span>
                            </>
                          )}
                        </span>
                      </span>
                      <ArrowRight className="shrink-0" size={14} style={{ color: 'var(--color-text-muted)' }} />
                    </button>
                  </motion.li>
                );
              })}
          </AnimatePresence>
        </ul>
      </div>
    </div>
  );
}

function Chip({ children }: { children: React.ReactNode }) {
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide"
      style={{ backgroundColor: 'var(--color-surface-raised)', color: 'var(--color-text-secondary)' }}
    >
      {children}
    </span>
  );
}
