/**
 * Daily series for the Overview, reconstructed from incident lifecycle stamps.
 *
 * Every figure on the Overview is a snapshot of *now*. A snapshot cannot say
 * whether the console is getting busier or quieter, which is the question an
 * admin actually opens this page with — so each headline number gets a series
 * behind it, rebuilt from the three timestamps an incident carries.
 *
 * WHY THIS READS /dispatch/activity AND NOT /dispatch/queue
 * ---------------------------------------------------------
 * The queue deliberately excludes resolved and cancelled incidents, because a
 * dispatcher is looking at what still needs doing. Counting that endpoint over
 * time is survivorship bias with a chart on top: an incident opened on Monday
 * and closed on Tuesday has vanished from it, so Monday and Tuesday are both
 * undercounted and the series slopes up toward today no matter what happened.
 * `/dispatch/activity` returns closed work too, which is what makes any of
 * this honest.
 *
 * THE ONE APPROXIMATION, STATED
 * -----------------------------
 * `severity` is the incident's severity *now*, not its severity on the day in
 * question. A dispatcher who overrides a rating today changes what the past
 * looks like in the critical series. The alternative is a severity history
 * table nobody has asked for; the effect is small because overrides are rare
 * and are usually made within minutes of arrival. It is recorded here rather
 * than hidden, because an admin comparing this chart against their memory of
 * last week deserves to know why the two might differ by one.
 */

import type { ActivityIncident, SeverityLevel } from '@/lib/api/dispatch';
import type { TimePatterns } from '@/lib/api/operational-area';

export interface DayPoint {
  /** Midnight at the start of the day, local time. */
  date: Date;
  /** Short weekday for the axis; "Today" for the last point. */
  label: string;
  value: number;
}

/** Midnight local, N days before today. */
function dayStart(offsetFromToday: number): Date {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + offsetFromToday);
  return d;
}

function labelFor(d: Date, isToday: boolean): string {
  if (isToday) return 'Today';
  return d.toLocaleDateString(undefined, { weekday: 'short' });
}

const ms = (iso: string | null): number | null =>
  iso ? new Date(iso).getTime() : null;

/**
 * Was this incident open at the given instant?
 *
 * Open means created and not yet closed. A resolution stamps `resolved_at`,
 * but a cancellation does NOT: the resident's withdraw, a dispatcher's cancel
 * and a verification reject all write `status = 'cancelled'` and leave
 * `resolved_at` null (the withdraw path stamps `withdrawn_at`, the reject path
 * `reviewed_at` — neither of which /dispatch/activity returns). Treating that
 * null as "still open" held a phantom +1 in the Active, Critical and Awaiting
 * series from the day of the cancellation to today, while the headline figure
 * above it — read from the live queue, which excludes cancelled work — said 0.
 *
 * So a terminal status with no stamp is closed, with the moment unknown. It is
 * counted as never open rather than open forever: an unanswered report that
 * was withdrawn or rejected was open for minutes to hours, which an end-of-day
 * snapshot almost never catches, whereas "open forever" is certainly wrong.
 */
function openAt(inc: ActivityIncident, at: number): boolean {
  const created = ms(inc.created_at);
  if (created === null || created > at) return false;
  const closed = ms(inc.resolved_at);
  if (closed !== null) return closed > at;
  return inc.status !== 'resolved' && inc.status !== 'cancelled';
}

/** Had a human dispatched it by this instant? */
function dispatchedBy(inc: ActivityIncident, at: number): boolean {
  const d = ms(inc.dispatched_at);
  return d !== null && d <= at;
}

/**
 * Walk back `days` days and evaluate `count` at the END of each one.
 *
 * End-of-day, not start: a day's figure should include everything that
 * happened during it, and an admin looking at "Tue" means "where did Tuesday
 * leave us". Today's point is evaluated at *now* rather than at midnight
 * tonight, so the last column matches the headline figure above it — a series
 * whose final point disagreed with the number it sits under would undermine
 * both.
 */
function seriesOf(
  incidents: ActivityIncident[],
  days: number,
  count: (open: ActivityIncident[], at: number) => number,
): DayPoint[] {
  const now = Date.now();
  const out: DayPoint[] = [];

  for (let i = days - 1; i >= 0; i--) {
    const date = dayStart(-i);
    const isToday = i === 0;
    const endOfDay = isToday
      ? now
      : dayStart(-i + 1).getTime() - 1;

    const open = incidents.filter(inc => openAt(inc, endOfDay));
    out.push({ date, label: labelFor(date, isToday), value: count(open, endOfDay) });
  }
  return out;
}

/** Incidents open at the end of each day. */
export function activeSeries(incidents: ActivityIncident[], days = 14): DayPoint[] {
  return seriesOf(incidents, days, open => open.length);
}

/** Open incidents rated `severity` at the end of each day. */
export function severitySeries(
  incidents: ActivityIncident[],
  severity: SeverityLevel,
  days = 14,
): DayPoint[] {
  return seriesOf(incidents, days, open =>
    open.filter(i => i.severity === severity).length,
  );
}

/** Open incidents nobody had dispatched yet at the end of each day. */
export function awaitingSeries(incidents: ActivityIncident[], days = 14): DayPoint[] {
  return seriesOf(incidents, days, (open, at) =>
    open.filter(i => !dispatchedBy(i, at)).length,
  );
}

/**
 * Age in hours of the oldest still-open incident at the end of each day.
 *
 * The metric a dispatcher actually fears: not how many are waiting, but how
 * long the worst one has. A queue of thirty an hour old is healthier than a
 * queue of two where one has sat for a week.
 */
export function longestWaitSeries(
  incidents: ActivityIncident[],
  days = 14,
): DayPoint[] {
  return seriesOf(incidents, days, (open, at) => {
    let oldest = 0;
    for (const i of open) {
      const created = ms(i.created_at);
      if (created === null) continue;
      oldest = Math.max(oldest, (at - created) / 3_600_000);
    }
    return Math.round(oldest);
  });
}

/**
 * Incidents *received* on each day — arrivals, not the standing queue.
 *
 * This is the one series that counts an event rather than a state, so it is
 * built by created_at alone and closed incidents count exactly as much as open
 * ones. That is the whole correction: the previous chart called itself
 * "Reports per day" while reading the queue, so it was really plotting
 * still-open reports by day created, and a busy day that got cleaned up
 * showed as a quiet one.
 */
export function receivedSeries(
  incidents: ActivityIncident[],
  days = 14,
): DayPoint[] {
  const out: DayPoint[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const start = dayStart(-i);
    const end = dayStart(-i + 1);
    const value = incidents.filter(inc => {
      const t = ms(inc.created_at);
      return t !== null && t >= start.getTime() && t < end.getTime();
    }).length;
    out.push({ date: start, label: labelFor(start, i === 0), value });
  }
  return out;
}

/**
 * How many different stations took at least one report, per day.
 *
 * The daily shape behind the dashboard's "Reports by station" tile, counted the
 * same way as its headline (distinct stations, reports no station was matched
 * to left out) so the line and the figure never describe different things. It
 * is a spread, not a volume: a day of forty reports at one station reads 1, and
 * the same forty spread over seven stations reads 7.
 */
export function stationsReportingSeries(
  incidents: ActivityIncident[],
  days = 14,
): DayPoint[] {
  const out: DayPoint[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const start = dayStart(-i);
    const end = dayStart(-i + 1);
    const seen = new Set<string>();
    for (const inc of incidents) {
      const t = ms(inc.created_at);
      if (inc.station_id && t !== null && t >= start.getTime() && t < end.getTime()) seen.add(inc.station_id);
    }
    out.push({ date: start, label: labelFor(start, i === 0), value: seen.size });
  }
  return out;
}

/**
 * Change between the first and last point, for a stat tile's delta.
 *
 * Returns null when there is nothing honest to say: no series, or a baseline
 * of zero, where "+3 (∞%)" is noise. A tile with no delta is correct and
 * common; a fabricated one is neither.
 */
export function deltaOf(series: DayPoint[]): { change: number; from: number } | null {
  if (series.length < 2) return null;
  const from = series[0].value;
  const to = series[series.length - 1].value;
  if (from === to) return null;
  return { change: to - from, from };
}

/* ── Series for the dashboard-3 chart cards ──────────────────────────────── */

/**
 * Arrivals per day, keyed by ISO date.
 *
 * Same counting rule as receivedSeries — this is a shape for recharts, which
 * wants a plain serialisable row, not a Date the axis formatter has to guess
 * at. Deliberately derived from receivedSeries rather than re-counting, so the
 * area chart and the stat tile can never disagree about what a day held.
 */
export function volumePoints(
  incidents: ActivityIncident[],
  days = 14,
): { date: string; received: number }[] {
  return receivedSeries(incidents, days).map(p => ({
    date: p.date.toISOString(),
    received: p.value,
  }));
}

/**
 * Arrivals per day split across the four severity tiers.
 *
 * Counts by the severity an incident currently carries, applied to the day it
 * ARRIVED. Triage can revise a severity after the fact, so a re-triaged report
 * moves between bands retroactively rather than appearing twice — which is the
 * honest reading, since the chart answers "what kind of week was that?" and
 * not "what did we believe at 3pm on Tuesday?".
 *
 * An untriaged incident has no tier and is counted in none of them; the totals
 * here can therefore sit below the arrivals line above, which is correct and
 * is why the two are separate cards rather than one.
 */
export function severityDays(
  incidents: ActivityIncident[],
  days = 14,
): { date: string; low: number; medium: number; high: number; critical: number }[] {
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const start = dayStart(-i).getTime();
    const end = dayStart(-i + 1).getTime();
    const onDay = incidents.filter(inc => {
      const t = ms(inc.created_at);
      return t !== null && t >= start && t < end;
    });
    const count = (tier: SeverityLevel) =>
      onDay.filter(inc => inc.severity === tier).length;
    out.push({
      date: new Date(start).toISOString(),
      low: count('low'),
      medium: count('medium'),
      high: count('high'),
      critical: count('critical'),
    });
  }
  return out;
}

/* ── Category mix and response time ──────────────────────────────────────── */

/** Display names for the wizard's categories. The enum values are snake_case
 *  machine identifiers and none of them belong on screen. */
export const CATEGORY_LABELS: Record<string, string> = {
  fire: 'Fire',
  medical_trauma: 'Medical / trauma',
  vehicular: 'Vehicular',
  flood_landslide_calamity: 'Flood / landslide',
  domestic_dispute_crime: 'Dispute / crime',
};

/** The five real categories, in the wizard's own order. */
export const REAL_CATEGORIES = [
  'fire',
  'medical_trauma',
  'vehicular',
  'flood_landslide_calamity',
  'domestic_dispute_crime',
] as const;

export interface CategoryCount {
  key: string;
  label: string;
  count: number;
}

/**
 * How many of each kind of emergency arrived in the window.
 *
 * Counts every incident regardless of status — a fire resolved yesterday is
 * still a fire this province had. Reading this off the queue instead would
 * answer "which kinds are open right now", which is a different and much less
 * useful question, and would undercount every past day.
 *
 * Returns the five real categories ranked by volume, and the unclassified
 * count separately. They are separated rather than ranked together because
 * `other` is an absence of an answer, not a kind of emergency: it holds both
 * "the resident skipped the category step" and the retired hazmat /
 * missing_person rows migration 019 rewrote. Ranked alongside the real five it
 * would routinely place near the top and read as a finding.
 */
export function categoryMix(
  incidents: ActivityIncident[],
  days = 14,
): { ranked: CategoryCount[]; unclassified: number; total: number } {
  const since = dayStart(-(days - 1)).getTime();
  const inWindow = incidents.filter(inc => {
    const t = ms(inc.created_at);
    return t !== null && t >= since;
  });

  const ranked = REAL_CATEGORIES.map(key => ({
    key,
    label: CATEGORY_LABELS[key],
    count: inWindow.filter(inc => inc.incident_category === key).length,
  })).sort((a, b) => b.count - a.count);

  // null covers rows filed before the field existed; 'other' is the wizard's
  // own "not chosen". Both mean the same thing to a reader.
  const unclassified = inWindow.filter(
    inc => inc.incident_category === 'other' || inc.incident_category === null,
  ).length;

  return { ranked, unclassified, total: inWindow.length };
}

/**
 * Median minutes from report to dispatch, per day.
 *
 * MEDIAN, not mean. One incident that sat for three days while everything else
 * moved in minutes drags a mean into uselessness, and on a queue this size
 * that happens most weeks. The median says what a typical report experienced.
 *
 * Dated by DISPATCH, not arrival: the question is "how fast were we on
 * Tuesday", and an incident that arrived Monday night and was dispatched
 * Tuesday morning is Tuesday's work. Dating it by arrival would credit the
 * delay to a day whose dispatchers had already gone home.
 *
 * A day with no dispatches yields null rather than zero — nothing happened,
 * which is not the same as "we responded instantly", and a zero would drag the
 * line to the floor and read as the best day on the chart.
 */
export function dispatchLatency(
  incidents: ActivityIncident[],
  days = 14,
): { date: string; minutes: number | null; dispatched: number }[] {
  const out = [];
  for (let i = days - 1; i >= 0; i--) {
    const start = dayStart(-i).getTime();
    const end = dayStart(-i + 1).getTime();

    const sameDay = incidents.filter(inc => {
      const d = ms(inc.dispatched_at);
      return d !== null && d >= start && d < end;
    });

    const gaps = sameDay
      .map(inc => {
        const c = ms(inc.created_at);
        const d = ms(inc.dispatched_at);
        return c !== null && d !== null ? (d - c) / 60000 : null;
      })
      .filter((n): n is number => n !== null && n >= 0)
      .sort((a, b) => a - b);

    let median: number | null = null;
    if (gaps.length) {
      const mid = Math.floor(gaps.length / 2);
      median =
        gaps.length % 2 === 0 ? (gaps[mid - 1] + gaps[mid]) / 2 : gaps[mid];
      median = Math.round(median);
    }

    out.push({
      date: new Date(start).toISOString(),
      minutes: median,
      dispatched: gaps.length,
    });
  }
  return out;
}

/**
 * Responders on an agency's roster at the end of each day, by join date.
 *
 * The one roster figure with a history to draw — every account carries a
 * created_at. "On duty" and "awaiting approval" do NOT: availability is a live
 * toggle and an approval leaves no timestamp, so there is nothing to walk back
 * and those tiles draw no line rather than an invented one.
 *
 * The one approximation: the roster endpoint returns the accounts that exist
 * today, so someone removed since is missing from the days they were on it and
 * earlier days can undercount by however many have left. Today's point counts
 * every row, so the last column always equals the headline figure.
 */
export function rosterSeries(
  joinedAt: string[],
  days = 14,
): DayPoint[] {
  const now = Date.now();
  const out: DayPoint[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const date = dayStart(-i);
    const isToday = i === 0;
    const endOfDay = isToday ? now : dayStart(-i + 1).getTime() - 1;
    const value = joinedAt.filter(iso => {
      const t = ms(iso);
      return t !== null && t <= endOfDay;
    }).length;
    out.push({ date, label: labelFor(date, isToday), value });
  }
  return out;
}

/**
 * A standing total at the end of each day, walked back from today's figure.
 *
 * `total` is what exists now; `createdAt` is when each of the rows created
 * inside the window was made. The value on any earlier day is today's total
 * minus everything created after that day ended, so the last point always
 * equals the headline number — the same guarantee every other tile series
 * here keeps. Rows deleted since are not counted back in, so earlier days can
 * read a little low; a line that is flat because nothing changed is the usual
 * case for a total this size.
 */
export function standingSeries(
  total: number,
  createdAt: string[],
  days = 14,
): DayPoint[] {
  const out: DayPoint[] = [];
  const times = createdAt.map(ms).filter((t): t is number => t !== null);
  for (let i = days - 1; i >= 0; i--) {
    const date = dayStart(-i);
    const isToday = i === 0;
    const endOfDay = isToday ? Number.POSITIVE_INFINITY : dayStart(-i + 1).getTime() - 1;
    const after = times.filter(t => t > endOfDay).length;
    out.push({ date, label: labelFor(date, isToday), value: Math.max(0, total - after) });
  }
  return out;
}

// ── Week pattern and per-station tallies ────────────────────────────────────

/** Philippine time is UTC+8 all year — there is no daylight saving to model. */
const PH_OFFSET_MS = 8 * 3_600_000;

/**
 * Weekday x hour of arrival, in Philippine time (0 = Monday), from the activity
 * feed. The same shape the Operational Area's Week pattern reads, so both draw
 * through one HeatGrid.
 *
 * Counted on arrival (`created_at`) and over every status: the question is when
 * reports come in, not what became of them.
 */
export function timePatterns(incidents: ActivityIncident[]): TimePatterns {
  const heatmap = Array.from({ length: 7 }, () => Array<number>(24).fill(0));
  let total = 0;
  for (const i of incidents) {
    const t = ms(i.created_at);
    if (t === null) continue;
    // Shifted by +8h, then read with the UTC getters: they now show Manila's clock.
    const local = new Date(t + PH_OFFSET_MS);
    heatmap[(local.getUTCDay() + 6) % 7][local.getUTCHours()] += 1;
    total += 1;
  }
  const byWeekday = heatmap.map(row => row.reduce((a, b) => a + b, 0));
  const byHour = Array.from({ length: 24 }, (_, h) => heatmap.reduce((a, row) => a + row[h], 0));
  const peak = (xs: number[]) => (total === 0 ? null : xs.indexOf(Math.max(...xs)));
  return { heatmap, by_hour: byHour, by_weekday: byWeekday, peak_hour: peak(byHour), peak_weekday: peak(byWeekday), total };
}

export interface StationTally {
  /** Null for reports routing found no station for. */
  id: string | null;
  name: string;
  reports: number;
  critical: number;
  /** Not yet resolved or cancelled. */
  open: number;
  lastAt: string | null;
}

/** Reports per station, busiest first. Reports with no station are kept, as their own row, never dropped. */
export function stationTallies(incidents: ActivityIncident[]): StationTally[] {
  const by = new Map<string, StationTally>();
  for (const i of incidents) {
    const key = i.station_id ?? '__none__';
    let row = by.get(key);
    if (!row) {
      row = { id: i.station_id ?? null, name: i.station_name ?? (i.station_id ? 'Unnamed station' : 'No station matched'), reports: 0, critical: 0, open: 0, lastAt: null };
      by.set(key, row);
    }
    row.reports += 1;
    if (i.severity === 'critical') row.critical += 1;
    if (i.status !== 'resolved' && i.status !== 'cancelled') row.open += 1;
    if (!row.lastAt || i.created_at > row.lastAt) row.lastAt = i.created_at;
  }
  return [...by.values()].sort((a, b) => b.reports - a.reports || a.name.localeCompare(b.name));
}
