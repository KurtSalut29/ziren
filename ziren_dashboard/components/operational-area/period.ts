/**
 * The period the Operational Area is asked about, and how to say it in words.
 *
 * The calendar-day arithmetic and the picker's own (days, range) helpers
 * live in components/ui/period.ts, shared with every other date-range
 * filter in the dashboard — re-exported here so existing imports
 * (`from './period'`) throughout this folder keep working unchanged.
 *
 * What stays local to this file is Operational-Area-specific: `periodLong`,
 * `previousLabel`, `periodDates` and `isCustom` all read an `AreaFilters`
 * object — what the SERVER echoed back for a request already sent — which
 * is a different question from components/ui/period.ts's `periodWords`,
 * which describes what a picker currently shows before any request
 * completes. A page with no server-echoed filters (Incident Records, Audit
 * Logs, Reports & Export) has no use for these four; it uses `periodWords`
 * and `resolvePeriod` directly.
 */

import type { AreaFilters } from '@/lib/api/operational-area';
import { PERIODS, formatRange, fmtDay, phToday } from '@/components/ui/period';

export * from '@/components/ui/period';

// ── A period as the screen reports it ────────────────────────────────────

type Period = Pick<AreaFilters, 'days' | 'date_from' | 'date_to'>;

export const isCustom = (f: Pick<AreaFilters, 'date_from' | 'date_to'>): boolean => !!(f.date_from && f.date_to);

/** "the last 30 days", "all time", or "Mar 1 – Mar 15, 2026" — fits "in …", "from …" and "How … measured up". */
export function periodLong(f: Period): string {
  if (f.date_from && f.date_to) return formatRange(f.date_from, f.date_to);
  return PERIODS.find(p => p.days === f.days)?.long ?? `the last ${f.days} days`;
}

/** What the figures are compared with, for a tooltip or a caption: "the 30 days before", "the 15 days before Mar 1". */
export function previousLabel(f: Period): string {
  if (f.date_from && f.date_to) {
    return f.days === 1 ? `the day before ${fmtDay(f.date_from)}` : `the ${f.days} days before ${fmtDay(f.date_from)}`;
  }
  return `the ${f.days} days before`;
}

/**
 * The dates a period covers, for the header: a chosen range as it was chosen; a
 * rolling window from its start to the moment the figures were made. Null when
 * there is no start (all time). Philippine time, like every other time here.
 */
export function periodDates(f: Pick<AreaFilters, 'since' | 'date_from' | 'date_to'>, generatedAt: string): string | null {
  if (f.date_from && f.date_to) return formatRange(f.date_from, f.date_to);
  if (!f.since) return null;
  const a = new Date(f.since).getTime();
  const b = new Date(generatedAt).getTime();
  if (Number.isNaN(a) || Number.isNaN(b)) return null;
  const from = phToday(a);
  const to = phToday(b);
  return formatRange(from, to);
}
