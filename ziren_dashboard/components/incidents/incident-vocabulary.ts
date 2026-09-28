/**
 * The words, colours and clocks an incident is drawn with.
 *
 * Extracted from incident-row.tsx when the queue gained a table alongside the
 * card. That file's own header states the reason better than a new one could:
 * two hand-kept copies of this vocabulary "would have drifted within a week —
 * the severity palette, the agency hues and the role rule for the primary
 * action all have to agree across both pages or the same incident reads
 * differently depending on where you found it."
 *
 * A card and a table of the same queue are exactly that hazard, twice over.
 * So the palette and the clocks live here, and both renderers import them.
 *
 * Token names only, no literals — globals.css stays the one place a colour is
 * decided. The colour rules it documents are operational, not decorative: red
 * belongs to critical severity alone, brand orange to actions alone, and the
 * agency hues are fixed.
 */

import {
  AlertCircle, AlertOctagon, AlertTriangle, Building2, Car, CheckCircle2, CloudRain,
  Flame, HeartPulse, HelpCircle, Inbox, Info, MapPin, Navigation, RotateCw, Send,
  ShieldAlert, XCircle,
} from 'lucide-react';
import type { QueueIncident, SeverityLevel } from '@/lib/api/dispatch';

export const SEV_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

export const AG_COLOR: Record<string, string> = {
  BFP:    'var(--color-agency-bfp)',
  PNP:    'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

/** Tint companion to AG_COLOR, for a badge/card background behind the solid hue. */
export const AG_BG: Record<string, string> = {
  BFP:    'var(--color-agency-bfp-bg)',
  PNP:    'var(--color-agency-pnp-bg)',
  MDRRMO: 'var(--color-agency-mdrrmo-bg)',
};

export const STATUS_STYLE: Record<string, { bg: string; text: string }> = {
  received:   { bg: 'var(--color-status-received-bg)',   text: 'var(--color-status-received)' },
  processing: { bg: 'var(--color-status-processing-bg)', text: 'var(--color-status-processing)' },
  dispatched: { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
  en_route:   { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
  arrived:    { bg: 'var(--color-system-success-bg)',    text: 'var(--color-system-success)' },
  // History-only. The queue never shows these two, which is exactly why the
  // page that does had to stop reading /dispatch/queue.
  resolved:   { bg: 'var(--color-status-resolved-bg)',   text: 'var(--color-status-resolved)' },
  cancelled:  { bg: 'var(--color-status-cancelled-bg)',  text: 'var(--color-status-cancelled)' },
};

/** Icon per category. The wizard's set is closed, so this is exhaustive. */
export const CATEGORY_ICON: Record<string, typeof Flame> = {
  fire: Flame,
  medical_trauma: HeartPulse,
  vehicular: Car,
  flood_landslide_calamity: CloudRain,
  domestic_dispute_crime: ShieldAlert,
};

export const AGENCY_ICON: Record<string, typeof Flame> = {
  BFP: Flame,
  PNP: ShieldAlert,
  MDRRMO: Building2,
};

/**
 * Icon per severity, for the option dialogs (2026-09-19) — an escalating
 * shape, not a colour repeated as an icon: AlertOctagon (a stop-sign shape)
 * outranks AlertTriangle outranks AlertCircle outranks a plain Info circle.
 * `untriaged` is a queue-only fifth state (the rubric could not read the
 * report) — SEV_COLOR above has no entry for it, so callers pairing this
 * with a colour fall back to a muted token rather than indexing SEV_COLOR
 * with a key it does not have.
 */
export const SEV_ICON: Record<string, typeof Flame> = {
  critical: AlertOctagon,
  high: AlertTriangle,
  medium: AlertCircle,
  low: Info,
  untriaged: HelpCircle,
};

/**
 * Icon per workflow status, for the option dialogs — the lifecycle a report
 * moves through left to right: landed (Inbox), being read (RotateCw), sent
 * (Send), travelling (Navigation), on scene (MapPin), then one of two ways
 * closed (CheckCircle2 / XCircle). Colour still comes from STATUS_STYLE
 * above; this is only the shape half of "never colour alone".
 */
export const STATUS_ICON: Record<string, typeof Flame> = {
  received: Inbox,
  processing: RotateCw,
  dispatched: Send,
  en_route: Navigation,
  arrived: MapPin,
  resolved: CheckCircle2,
  cancelled: XCircle,
};

/** Statuses where nobody has been sent yet. This is the dispatcher's work. */
export const AWAITING_STATUSES = ['received', 'processing'];

/** Sent, and not yet on scene. */
export const EN_ROUTE_STATUSES = ['dispatched', 'en_route'];

/** The severity a row is filed under. Falls back to the model's suggestion. */
export const sevOf = (i: QueueIncident) =>
  (i.suggested_severity ?? i.severity) as SeverityLevel | null;

/** Worst first. Untriaged sorts last — it is unknown, not harmless. */
export const SEV_RANK: Record<string, number> = {
  critical: 0, high: 1, medium: 2, low: 3,
};

/** "en_route" → "En Route". */
export function statusLabel(status: string): string {
  return status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase());
}

/** The last six of the UUID — what gets read out over a radio. */
export function shortId(id: string): string {
  return id.replace(/-/g, '').toUpperCase().slice(-6);
}

/**
 * How long ago, without the word.
 *
 * The urgency column sets this in mono so digits line up down the list;
 * "3m ago" would align on the word rather than on the number, which is the
 * part being compared.
 */
export function timeShort(iso: string): string {
  const m = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (m < 1)  return 'now';
  if (m < 60) return m + 'm';
  const h = Math.floor(m / 60);
  return h < 24 ? h + 'h' : Math.floor(h / 24) + 'd';
}

/**
 * Elapsed time between two instants, as a span rather than an age.
 *
 * Separate from timeShort() on purpose: that one measures FROM a timestamp TO
 * now and answers "how long has this been waiting". This measures between two
 * fixed points and answers "how long did it take", which is the only question
 * a closed incident can still answer.
 */
export function durationBetween(fromIso: string, toIso: string): string {
  const ms = new Date(toIso).getTime() - new Date(fromIso).getTime();
  // Clock skew between the phone that filed the report and the server can put
  // dispatched_at a second before created_at. "-1m" would read as a data fault;
  // "under a minute" is both true and unremarkable.
  if (!Number.isFinite(ms) || ms < 60_000) return '<1m';
  const mins = Math.floor(ms / 60_000);
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  const rem = mins % 60;
  if (h < 24) return rem ? `${h}h ${rem}m` : `${h}h`;
  const d = Math.floor(h / 24);
  return d < 7 ? `${d}d ${h % 24}h` : `${d}d`;
}

export const CLOSED_STATUSES = ['resolved', 'cancelled'];

/** A report is "due" once it is inside the last quarter of its window. */
const DUE_SOON_FRACTION = 0.25;

/**
 * Colour by how long an unacknowledged incident has sat — against ITS OWN
 * target, not a single threshold for the whole console.
 *
 * The previous version escalated every report at fifteen minutes and again at
 * forty-five, whatever its severity. That is the wrong comparison in both
 * directions at once: a twenty-minute LOW went amber while it was still well
 * inside any sane target, and a ten-minute CRITICAL stayed grey at five times
 * past one. An age means nothing until you know what it is being measured
 * against, so the measure travels with it — see DISPATCH_TARGET_MINUTES.
 *
 * Still only escalates on statuses nobody has acted on. A resolved report that
 * took three days is history, not an alarm, and painting its age red would put
 * the loudest colour on the console's least urgent row.
 */
export function urgencyTimeColor(
  iso: string,
  status: string,
  severity?: string | null,
): string {
  if (!AWAITING_STATUSES.includes(status)) return 'var(--color-text-muted)';
  const target = targetMinutes(severity);
  const m = Math.floor((Date.now() - new Date(iso).getTime()) / 60000);
  if (m >= target) return 'var(--color-severity-critical)';
  if (m >= target * (1 - DUE_SOON_FRACTION)) return 'var(--color-severity-high)';
  return 'var(--color-text-muted)';
}

/**
 * The waiting line, in the order it will be worked.
 *
 * Severity first, then oldest first — the same two keys get_incident_queue
 * sorts on, restated here because the client re-sorts after filtering and the
 * position shown on each row has to survive that. If these two ever disagree,
 * the row labelled NEXT is not the one the server would hand over next, which
 * is worse than showing no number at all.
 */
export function queueOrder(a: QueueIncident, b: QueueIncident): number {
  const sa = SEV_RANK[sevOf(a) ?? ''] ?? 4;
  const sb = SEV_RANK[sevOf(b) ?? ''] ?? 4;
  if (sa !== sb) return sa - sb;
  return a.created_at.localeCompare(b.created_at);
}

/**
 * The longest anything in this set has been waiting, in words.
 *
 * Reads the OLDEST created_at rather than a mean, because the number a
 * dispatcher is answerable for is the worst one, not the typical one.
 */
export function longestWait(xs: QueueIncident[]): string | null {
  if (xs.length === 0) return null;
  const oldest = xs.reduce((a, b) => (a.created_at < b.created_at ? a : b));
  const mins = Math.floor((Date.now() - new Date(oldest.created_at).getTime()) / 60000);
  if (mins < 1) return 'under a minute';
  if (mins < 60) return `${mins}m`;
  return `${Math.floor(mins / 60)}h`;
}

// ── Dispatch targets ────────────────────────────────────────────────────────

/**
 * How long a report may sit UNDISPATCHED before it is late, per severity.
 *
 * The console already had the other half of this policy: responder_ack.py
 * scales the acceptance deadline by severity, so the board can say a crew is
 * slow to answer. Nothing measured the step before it — how long the report
 * waited on a dispatcher — so an incident's age was displayed against a single
 * threshold for every severity. A twenty-minute LOW went amber while a
 * ten-minute CRITICAL stayed grey, five times past anything defensible.
 *
 * WHY THIS EXISTS AT ALL, AND WHAT IT PROTECTS
 *
 * The working rule this console is asked to follow is first come, first
 * served — the dispatcher's own words. That rule is right almost all of the
 * time and it is the one everybody can check. It is wrong in exactly one
 * situation: when a fire with people inside arrives behind a noise complaint.
 *
 * A deadline expresses both at once. Sort by `created_at + target`, and:
 *
 *   - reports of the SAME severity come out in arrival order, always. Their
 *     targets are equal, so the deadline order IS the arrival order. This is
 *     the ordinary case and it is plain first-come-first-served.
 *   - a report only overtakes an older one when its deadline is genuinely
 *     sooner, and the row says so rather than leaving the reader to work out
 *     why #4 arrived after #5.
 *
 * PROVISIONAL NUMBERS. They are set here as one editable table rather than
 * scattered through the UI, and they are not yet agency policy — BFP, PNP and
 * MDRRMO should each confirm their own, at which point this belongs beside the
 * rubric configs as a per-agency setting rather than a constant.
 */
export const DISPATCH_TARGET_MINUTES: Record<string, number> = {
  critical: 5,
  high: 10,
  medium: 30,
  low: 60,
};

/**
 * Used when severity is absent. An untriaged report is not a low-priority
 * one — it is one the rubric could not read — so it gets the strictest
 * treatment rather than the most forgiving. Same rule, and the same reasoning,
 * as _DEFAULT_DEADLINE_SECONDS in responder_ack.py.
 */
export const DEFAULT_TARGET_MINUTES = 5;

export function targetMinutes(severity: string | null | undefined): number {
  if (!severity) return DEFAULT_TARGET_MINUTES;
  return DISPATCH_TARGET_MINUTES[severity] ?? DEFAULT_TARGET_MINUTES;
}

/** Late, nearly late, or fine — three words a reader can hold at once. */
export type DueBucket = 'late' | 'due' | 'ontime';

export interface DueState {
  /** When this report should have been dispatched, in epoch ms. */
  dueAt: number;
  /** Positive = minutes left. Negative = minutes past the target. */
  minutesLeft: number;
  bucket: DueBucket;
  targetMinutes: number;
}

export function dueState(incident: QueueIncident, now = Date.now()): DueState {
  const target = targetMinutes(sevOf(incident));
  const dueAt = new Date(incident.created_at).getTime() + target * 60_000;
  const minutesLeft = Math.round((dueAt - now) / 60_000);
  return {
    dueAt,
    minutesLeft,
    targetMinutes: target,
    bucket:
      minutesLeft < 0
        ? 'late'
        : minutesLeft <= Math.max(1, target * DUE_SOON_FRACTION)
          ? 'due'
          : 'ontime',
  };
}

export const DUE_COLOR: Record<DueBucket, string> = {
  // Red is reserved for critical severity on this console. A missed dispatch
  // target IS that class of fact — the report has waited longer than anyone
  // was willing to promise — so it is the one non-severity use of the token,
  // and it is paired with the word LATE rather than standing on colour alone.
  late: 'var(--color-severity-critical)',
  due: 'var(--color-severity-high)',
  ontime: 'var(--color-text-muted)',
};

/** "LATE by 12m" · "Due in 3m" · "Due in 1h". */
export function formatDue(d: DueState): string {
  const abs = Math.abs(d.minutesLeft);
  const span = abs < 60 ? `${abs}m` : `${Math.floor(abs / 60)}h ${abs % 60}m`;
  if (d.minutesLeft < 0) return `LATE by ${span}`;
  if (d.minutesLeft === 0) return 'Due now';
  return `Due in ${span}`;
}

