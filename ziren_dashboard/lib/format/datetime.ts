/**
 * Dates and times, written the way the operator asked for them.
 *
 * Every screen that shows a moment in time goes through here instead of calling
 * toLocaleString() ad hoc, so the Display settings (date style, 12/24 hour,
 * whose clock, month names) apply everywhere at once and nowhere can drift.
 *
 * Built from Intl's formatToParts rather than string surgery on a formatted
 * value, so the pieces are the pieces regardless of locale, and a chosen time
 * zone is honoured exactly — `new Date(iso).getHours()` is always the browser's
 * own zone and cannot be told otherwise.
 */

import { DISPLAY_DEFAULTS, type DisplayPrefs } from '@/lib/prefs/definitions';

function zone(prefs: DisplayPrefs): string | undefined {
  return prefs.timeZone === 'browser' ? undefined : prefs.timeZone;
}

function parts(
  d: Date,
  prefs: DisplayPrefs,
  opts: Intl.DateTimeFormatOptions,
  locale: string = prefs.locale,
): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of new Intl.DateTimeFormat(locale, { timeZone: zone(prefs), ...opts }).formatToParts(d)) {
    out[p.type] = p.value;
  }
  return out;
}

/** True for a Date that is a real instant. */
function valid(d: Date): boolean {
  return Number.isFinite(d.getTime());
}

/** 2026-09-19 · 19 Sep 2026 · 19/09/2026, per the chosen style. */
export function formatDate(iso: string | Date, prefs: DisplayPrefs = DISPLAY_DEFAULTS): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  if (!valid(d)) return '—';
  if (prefs.dateStyle === 'medium') {
    // Month NAME follows the chosen locale ("Set" in Filipino, "Sep" in English).
    const p = parts(d, prefs, { day: 'numeric', month: 'short', year: 'numeric' });
    return `${p.day} ${p.month.replace('.', '')} ${p.year}`;
  }
  // Numeric styles use a fixed locale so the ORDER is what was asked for, not
  // whatever the chosen locale's own convention happens to be.
  const p = parts(d, prefs, { year: 'numeric', month: '2-digit', day: '2-digit' }, 'en-CA');
  return prefs.dateStyle === 'dmy'
    ? `${p.day}/${p.month}/${p.year}`
    : `${p.year}-${p.month}-${p.day}`;
}

/** 03:48 or 3:48 AM. */
export function formatTime(iso: string | Date, prefs: DisplayPrefs = DISPLAY_DEFAULTS): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  if (!valid(d)) return '—';
  if (prefs.timeFormat === '12h') {
    const p = parts(d, prefs, { hour: 'numeric', minute: '2-digit', hour12: true }, 'en-US');
    return `${p.hour}:${p.minute} ${p.dayPeriod.toUpperCase()}`;
  }
  // hourCycle h23, not hour12:false — the latter renders midnight as "24:00" in
  // some engines.
  const p = parts(d, prefs, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }, 'en-GB');
  return `${p.hour}:${p.minute}`;
}

/** Both, for a timeline row: "2026-09-19 03:48" or "19 Sep 2026, 3:48 AM". */
export function formatDateTime(iso: string | Date, prefs: DisplayPrefs = DISPLAY_DEFAULTS): string {
  const d = typeof iso === 'string' ? new Date(iso) : iso;
  if (!valid(d)) return '—';
  return `${formatDate(d, prefs)}${prefs.dateStyle === 'medium' ? ',' : ''} ${formatTime(d, prefs)}`;
}

/** Whole-number grouping in the chosen locale: 1,234 (en) — used for counts. */
export function formatNumber(n: number, prefs: DisplayPrefs = DISPLAY_DEFAULTS): string {
  return new Intl.NumberFormat(prefs.locale).format(n);
}

/** Short name of the zone in effect, for a caption: "PHT" or the browser's. */
export function zoneLabel(prefs: DisplayPrefs = DISPLAY_DEFAULTS): string {
  if (prefs.timeZone === 'Asia/Manila') return 'Philippine Time (UTC+8)';
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'this device';
  } catch {
    return 'this device';
  }
}
