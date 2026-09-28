/**
 * A period someone picked for a filtered screen, and how to say it in words.
 *
 * Shared by every "from date – to date" control in the dashboard (Operational
 * Area, Incident Records, Audit Logs, Reports & Export): a period is one of
 * two things — a rolling look-back ("the last 30 days", "all time") or a
 * range the reader chose, BOTH DAYS INCLUDED. Every day in this file is a
 * Philippine calendar day written 'YYYY-MM-DD', and all the arithmetic on it
 * goes through UTC on those strings. There is no `new Date(y, m, d)` in the
 * reader's own time zone: a reader whose device is not on Philippine time
 * would otherwise see "today" — and today's reports — on a different day from
 * the dispatch room, which is exactly the argument the backend makes by
 * counting in Philippine time everywhere else.
 *
 * Pure functions, no React and no imports that survive compilation, so the
 * whole file can be exercised outside a browser (see period.test conventions
 * used during development).
 */

export type Ymd = string;
export interface Range { from: Ymd; to: Ymd }

export const PERIODS: { days: number; label: string; short: string; long: string }[] = [
  { days: 7, label: '7 days', short: '7d', long: 'the last 7 days' },
  { days: 30, label: '30 days', short: '30d', long: 'the last 30 days' },
  { days: 90, label: '90 days', short: '90d', long: 'the last 90 days' },
  { days: 365, label: '1 year', short: '1y', long: 'the last year' },
  { days: 0, label: 'All time', short: 'All', long: 'all time' },
];

/** The longest range a picker will open a calendar to. Backends may accept less. */
export const MAX_RANGE_DAYS = 3650;

const PH_ZONE = 'Asia/Manila';
const DAY_MS = 86_400_000;

// ── Calendar days ────────────────────────────────────────────────────────

/** Today in the Philippines, whatever time zone the device is set to. */
export function phToday(now: number = Date.now()): Ymd {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: PH_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const get = (t: string) => parts.find(p => p.type === t)?.value ?? '';
  return `${get('year')}-${get('month')}-${get('day')}`;
}

export function parseYmd(s: string | null | undefined): { y: number; m: number; d: number } | null {
  const hit = s ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(s) : null;
  if (!hit) return null;
  const y = Number(hit[1]);
  const m = Number(hit[2]);
  const d = Number(hit[3]);
  const t = new Date(Date.UTC(y, m - 1, d));
  // 2026-02-31 rolls over to March in Date.UTC; a date that does not survive the round trip is not a date.
  if (t.getUTCFullYear() !== y || t.getUTCMonth() !== m - 1 || t.getUTCDate() !== d) return null;
  return { y, m, d };
}

export function toYmd(y: number, m: number, d: number): Ymd {
  return `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

const utcOf = (s: Ymd) => {
  const p = parseYmd(s);
  if (!p) throw new Error(`Not a calendar day: ${s}`);
  return Date.UTC(p.y, p.m - 1, p.d);
};

export function addDays(s: Ymd, n: number): Ymd {
  const t = new Date(utcOf(s) + n * DAY_MS);
  return toYmd(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

/** Whole days from `a` to `b` (negative when b is earlier). */
export function daysBetween(a: Ymd, b: Ymd): number {
  return Math.round((utcOf(b) - utcOf(a)) / DAY_MS);
}

/** Same day of the month `n` months on, or the last day of that month when it is shorter. */
export function addMonths(s: Ymd, n: number): Ymd {
  const p = parseYmd(s);
  if (!p) throw new Error(`Not a calendar day: ${s}`);
  const total = p.y * 12 + (p.m - 1) + n;
  const y = Math.floor(total / 12);
  const m = (total % 12) + 1;
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return toYmd(y, m, Math.min(p.d, daysInMonth));
}

export const startOfMonth = (s: Ymd): Ymd => { const p = parseYmd(s)!; return toYmd(p.y, p.m, 1); };
export const endOfMonth = (s: Ymd): Ymd => { const p = parseYmd(s)!; return toYmd(p.y, p.m, new Date(Date.UTC(p.y, p.m, 0)).getUTCDate()); };

/** ISO days sort as text, so clamping needs no parsing. */
export const clampYmd = (s: Ymd, min: Ymd, max: Ymd): Ymd => (s < min ? min : s > max ? max : s);

/** The 42 cells of a month laid out Sunday-first, six weeks tall so the calendar never changes height; null = not this month. */
export function monthGrid(y: number, m: number): (Ymd | null)[] {
  const lead = new Date(Date.UTC(y, m - 1, 1)).getUTCDay();
  const inMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  return Array.from({ length: 42 }, (_, i) => {
    const d = i - lead + 1;
    return d >= 1 && d <= inMonth ? toYmd(y, m, d) : null;
  });
}

export const WEEKDAYS = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
export const WEEKDAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/** 0 = Sunday … 6 = Saturday. */
export const weekdayOf = (s: Ymd): number => new Date(utcOf(s)).getUTCDay();

export const monthOf = (s: Ymd): { y: number; m: number } => { const p = parseYmd(s)!; return { y: p.y, m: p.m }; };

// ── Words ────────────────────────────────────────────────────────────────

const inUtc = (opts: Intl.DateTimeFormatOptions) => new Intl.DateTimeFormat('en-US', { ...opts, timeZone: 'UTC' });

/** "Mar 15" or "Mar 15, 2026". */
export function fmtDay(s: Ymd, withYear = false): string {
  return inUtc({ month: 'short', day: 'numeric', ...(withYear ? { year: 'numeric' } : {}) }).format(utcOf(s));
}

/** "Sun, Mar 1, 2026" — a day at a glance. */
export function fmtMedium(s: Ymd): string {
  return inUtc({ weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' }).format(utcOf(s));
}

/** "Sunday, March 1, 2026" — what a screen reader should say for a calendar cell. */
export function fmtLong(s: Ymd): string {
  return inUtc({ weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' }).format(utcOf(s));
}

export function monthLabel(y: number, m: number): string {
  return inUtc({ month: 'long', year: 'numeric' }).format(Date.UTC(y, m - 1, 1));
}

/** "Mar 1 – Mar 15, 2026"; a single day is just "Mar 15, 2026"; across a year both years are named. */
export function formatRange(from: Ymd, to: Ymd): string {
  if (from === to) return fmtDay(from, true);
  const sameYear = parseYmd(from)!.y === parseYmd(to)!.y;
  return `${fmtDay(from, !sameYear)} – ${fmtDay(to, true)}`;
}

// ── Ranges ───────────────────────────────────────────────────────────────

export const rangeLength = (r: Range): number => daysBetween(r.from, r.to) + 1;

/** The range of the same length that ends the day before this one starts — what the figures are compared with. */
export function previousRange(r: Range): Range {
  const to = addDays(r.from, -1);
  return { from: addDays(to, -(rangeLength(r) - 1)), to };
}

export const sameRange = (a: Range | null, b: Range | null): boolean =>
  !!a && !!b && a.from === b.from && a.to === b.to;

/** The calendar days that "the last N days" stand for, to start a picker somewhere sensible. */
export function presetRange(days: number, today: Ymd): Range {
  const n = days > 0 ? days : 30;                 // "all time" has no start to offer
  return { from: addDays(today, -(n - 1)), to: today };
}

/** One-click ranges for the picker. */
export function quickRanges(today: Ymd): { key: string; label: string; range: Range }[] {
  const lastMonth = addMonths(startOfMonth(today), -1);
  return [
    { key: 'today', label: 'Today', range: { from: today, to: today } },
    { key: 'yesterday', label: 'Yesterday', range: { from: addDays(today, -1), to: addDays(today, -1) } },
    { key: 'this-month', label: 'This month', range: { from: startOfMonth(today), to: today } },
    { key: 'last-month', label: 'Last month', range: { from: lastMonth, to: endOfMonth(lastMonth) } },
    { key: 'this-year', label: 'This year', range: { from: `${today.slice(0, 4)}-01-01`, to: today } },
  ];
}

// ── A picker's own (days, range) state ─────────────────────────────────────
//
// PeriodPicker (period-picker.tsx) hands a caller two pieces of state: a
// rolling preset in days (0 = all time) and a range that, when set,
// overrides it. These two helpers turn that pair into what it actually
// means, for a caller that keeps the pair as its own local state rather than
// reading it back from a server response (contrast Operational Area's own
// `periodLong`/`periodDates` in components/operational-area/period.ts, which
// describe what the SERVER applied to a request already sent).

/** What a picker's (days, range) selection resolves to as concrete calendar days, or null for all-time. */
export function resolvePeriod(days: number, range: Range | null, today: Ymd): Range | null {
  if (range) return range;
  if (days <= 0) return null;
  return presetRange(days, today);
}

/** How a picker's own (days, range) pair reads in a sentence: "the last 30 days", "all time", "Mar 1 – Mar 15, 2026". */
export function periodWords(days: number, range: Range | null): string {
  if (range) return formatRange(range.from, range.to);
  return PERIODS.find(p => p.days === days)?.long ?? `the last ${days} days`;
}
