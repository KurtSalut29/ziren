'use client';

/**
 * Provincial Admin Overview
 *
 * The page answers one question: is anything slipping right now, and where.
 * Everything on it is derived from the existing /dispatch/queue endpoint
 * (already scoped to the Provincial Admin's own agency_type) — no new
 * endpoints.
 *
 * Ordering principle: an incident nobody has dispatched yet outranks a
 * dispatched critical one. The crew is already moving on the second; the
 * first is still sitting in a queue. That is why the table sorts by whether
 * anything has happened yet before it sorts by severity, and why the
 * headline figure is an elapsed time rather than another count.
 *
 * Visible to Provincial Admin only. Agency Admins land on /queue directly.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import {
  ArrowUpRight, CheckCircle, ChevronRight, ClipboardList, Inbox, LandPlot,
  Files, Radar, RefreshCw, ShieldAlert, ShieldCheck, TriangleAlert, UserPlus, Users, Building2,
} from 'lucide-react';
import {
  fetchQueue, fetchActivity, fetchHistory,
  type QueueIncident, type SeverityLevel, type ActivityIncident,
} from '@/lib/api/dispatch';
import { ApiError } from '@/lib/api/client';
import {
  volumePoints,
  severityDays,
  categoryMix,
  dispatchLatency,
  activeSeries,
  severitySeries,
  awaitingSeries,
  rosterSeries,
  standingSeries,
  stationsReportingSeries,
  timePatterns,
  stationTallies,
  deltaOf,
} from '@/lib/charts/queue-series';
import {
  countRoster,
  fetchAgencyResponders,
  fetchPlatformCounts,
  type PlatformCounts,
  type RosterCounts,
} from '@/lib/api/platform';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import {
  AG_COLOR as AGENCY_ACCENT, AG_BG as AGENCY_ACCENT_BG,
  CATEGORY_ICON, dueState, formatDue, DUE_COLOR,
} from '@/components/incidents/incident-vocabulary';
import { Alert } from '@/components/ui/alert';
import { Fig } from '@/components/ui/fig';
import { Skeleton } from '@/components/ui/panel';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/efferd/ui/card';
import { Button } from '@/components/efferd/ui/button';
import { GreetingHeader } from '@/components/shell/greeting-header';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { IncidentVolumeChart } from '@/components/charts/incident-volume-chart';
import { AgencyShareChart } from '@/components/charts/agency-share-chart';
import { SeverityTrendChart } from '@/components/charts/severity-trend-chart';
import { CategoryMixChart } from '@/components/charts/category-mix-chart';
import { DispatchLatencyChart } from '@/components/charts/dispatch-latency-chart';
import { WeekPatternCard } from '@/components/charts/week-pattern-card';

import { DemoTarget } from '@/components/help/demo-target';
const REFRESH_MS = 30_000;

/**
 * How far back every series on this page looks.
 *
 * Fourteen days, not seven. A week of a provincial queue is often two or three
 * incidents, and a sparkline over three points is a zigzag, not a trend. Two
 * weeks is long enough for a shape to mean something and short enough that an
 * admin still remembers the period.
 */
const TREND_DAYS = 14;

/**
 * How far back the Week pattern and the station tally look. Ninety days is the
 * most the activity endpoint returns, and the pattern needs it: a weekday
 * rhythm read off two weeks is two Mondays.
 */
const PATTERN_DAYS = 90;
const AGENCIES = ['BFP', 'PNP', 'MDRRMO'] as const;

/** Statuses where no responder has been committed yet. */
const WAITING_STATUSES = ['received', 'processing'];

const SEV_RANK: Record<string, number> = { critical: 4, high: 3, medium: 2, low: 1 };

const SEV_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};
/** Tint companion to SEV_COLOR, for the category-icon tile behind each row
 *  in "Needs attention" — the icon distinguishes the category, the tint
 *  reinforces the severity it was triaged at. */
const SEV_BG: Record<string, string> = {
  critical: 'var(--color-severity-critical-bg)',
  high:     'var(--color-severity-high-bg)',
  medium:   'var(--color-severity-medium-bg)',
  low:      'var(--color-severity-low-bg)',
};
const AG_COLOR: Record<string, string> = {
  BFP:    'var(--color-agency-bfp)',
  PNP:    'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};
const STATUS_STYLE: Record<string, { bg: string; text: string }> = {
  received:   { bg: 'var(--color-status-received-bg)',   text: 'var(--color-status-received)' },
  processing: { bg: 'var(--color-status-processing-bg)', text: 'var(--color-status-processing)' },
  dispatched: { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
  en_route:   { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
  arrived:    { bg: 'var(--color-system-success-bg)',    text: 'var(--color-system-success)' },
  resolved:   { bg: 'var(--color-status-resolved-bg)',   text: 'var(--color-status-resolved)' },
  cancelled:  { bg: 'var(--color-status-cancelled-bg)',  text: 'var(--color-status-cancelled)' },
};

const sevOf = (i: QueueIncident) => (i.suggested_severity ?? i.severity) as SeverityLevel | null;
const isWaiting = (i: QueueIncident) => WAITING_STATUSES.includes(i.status);
const agencyOf = (i: QueueIncident) => i.stations?.agencies?.agency_type ?? '—';

function minutesSince(iso: string): number {
  return Math.max(0, Math.floor((Date.now() - new Date(iso).getTime()) / 60000));
}

/** Compact elapsed time. Minutes matter most here, so they survive into hours. */
function formatDuration(mins: number): string {
  if (mins < 1) return '<1m';
  if (mins < 60) return `${mins}m`;
  const h = Math.floor(mins / 60);
  if (h < 24) {
    const rem = mins % 60;
    return rem ? `${h}h ${rem}m` : `${h}h`;
  }
  return `${Math.floor(h / 24)}d`;
}


export default function OverviewPage() {
  const { token, isProvincialAdmin, isAgencyAdmin, agencyType } = useAuth();
  // Provincial Admin's live figures are coloured by their own agency_type
  // instead of generic brand orange — the same fixed hue used for their
  // identity badge in GreetingHeader, so the two reinforce each other
  // instead of one carrying the identity and the numbers looking generic.
  // Agency Admin keeps brand orange: that color means "your actionable
  // queue" for them, which stays true regardless of which agency they're in.
  const liveAccent   = isProvincialAdmin && agencyType ? AGENCY_ACCENT[agencyType]   : 'var(--color-brand)';
  const liveAccentBg = isProvincialAdmin && agencyType ? AGENCY_ACCENT_BG[agencyType] : 'var(--color-brand-subtle)';
  const [incidents, setIncidents] = useState<QueueIncident[]>([]);
  // Separate from the queue on purpose — see lib/charts/queue-series.ts. The
  // queue is "what still needs doing" and cannot answer "what happened".
  const [activity, setActivity] = useState<ActivityIncident[]>([]);
  const [loading, setLoading]     = useState(true);
  const [error, setError]         = useState<string | null>(null);
  const [, setLastRefresh] = useState<Date | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  /**
   * Standing totals — people and infrastructure. Provincial Admin only, and
   * deliberately OUTSIDE the refresh loop below.
   *
   * These move when someone signs up or a station is added, not second to
   * second, so re-counting them every fifteen seconds alongside the queue
   * would be three database counts per tick for numbers that had not changed.
   * Loaded once per visit; the page is remounted on navigation anyway.
   */
  const [platform, setPlatform] = useState<PlatformCounts | null>(null);

  /**
   * Ninety days of activity, for the Week pattern and the station tally. Loaded
   * once per visit, outside the refresh loop, for the same reason as `platform`:
   * a rhythm over three months does not move on a thirty-second tick, and it is
   * the largest payload on the page. Allowed to fail on its own — the cards
   * simply do not appear.
   */
  const [longActivity, setLongActivity] = useState<ActivityIncident[] | null>(null);

  /**
   * The agency's responder roster — Agency Admin only.
   *
   * Refreshed with the queue rather than loaded once, unlike the Provincial
   * Admin totals below it. Those move when somebody signs up; "on duty right now"
   * moves when a shift starts, and a dispatcher deciding whether anyone is
   * available cannot be reading a number from twenty minutes ago.
   */
  const [roster, setRoster] = useState<RosterCounts | null>(null);

  /**
   * Every report this agency has ever received, and how many were resolved —
   * Agency Admin only. All time, where the first tile is the last 14 days.
   * One row is fetched: only the server's `total` and `counts` are read.
   */
  const [allTime, setAllTime] = useState<{ total: number; resolved: number } | null>(null);
  // When each roster account joined — the only history the roster has, and
  // what the Responders tile's trend line is built from.
  const [rosterJoined, setRosterJoined] = useState<string[]>([]);

  const load = useCallback(async () => {
    if (!token) return;
    setError(null);
    try {
      // The queue drives the live figures; activity drives every series.
      // Activity is allowed to fail on its own — a chart that cannot load
      // must not blank the numbers a dispatcher is actually working from.
      const data = await fetchQueue(token);
      setIncidents(data);
      setLastRefresh(new Date());
      try {
        setActivity(await fetchActivity(token, TREND_DAYS));
      } catch {
        setActivity([]);
      }
      if (isAgencyAdmin) {
        try {
          const rows = await fetchAgencyResponders(token);
          setRoster(countRoster(rows));
          setRosterJoined(rows.map(r => r.created_at));
        } catch {
          // The roster is context. A failure here must not blank the live
          // incident figures a dispatcher is working from.
          setRoster(null);
          setRosterJoined([]);
        }
        try {
          const page = await fetchHistory(token, { days: 0, limit: 1 });
          setAllTime({ total: page.total, resolved: page.counts.resolved });
        } catch {
          setAllTime(null);
        }
      }
    } catch (err: unknown) {
      // An expired or invalid session must send the operator back to sign
      // in, same as every other page on this console — without this check,
      // a stale token here didn't sign anyone out, it just left the
      // dashboard permanently stuck on a generic error with no way forward.
      if (err instanceof ApiError && err.status === 401) { signOut(); return; }
      setError(
        err instanceof ApiError ? err.message : 'Failed to load overview data.',
      );
    } finally {
      setLoading(false);
    }
  }, [token, isAgencyAdmin]);

  useEffect(() => {
    load();
    timerRef.current = setInterval(load, REFRESH_MS);
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [load]);

  useEffect(() => {
    // The endpoint is require_role("provincial_admin"); an Agency Admin
    // calling it would take a 403, so it is not called for them at all.
    if (!token || !isProvincialAdmin) return;
    let cancelled = false;
    fetchPlatformCounts(token)
      .then(c => { if (!cancelled) setPlatform(c); })
      // Swallowed on purpose. These tiles are context, not the live incident
      // figures — a failed count must not put an error banner over a queue a
      // dispatcher is working from, and the strip simply does not render.
      .catch(() => {});
    return () => { cancelled = true; };
  }, [token, isProvincialAdmin]);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    fetchActivity(token, PATTERN_DAYS)
      .then(rows => { if (!cancelled) setLongActivity(rows); })
      .catch(() => {});
    return () => { cancelled = true; };
  }, [token]);

  // ── Derived ────────────────────────────────────────────────
  const total = incidents.length;
  const counts = {
    critical: incidents.filter(i => sevOf(i) === 'critical').length,
    high:     incidents.filter(i => sevOf(i) === 'high').length,
    medium:   incidents.filter(i => sevOf(i) === 'medium').length,
    low:      incidents.filter(i => sevOf(i) === 'low').length,
  };

  const waiting    = incidents.filter(isWaiting);
  const dispatched = total - waiting.length;
  const pct = (n: number) => (total > 0 ? (n / total) * 100 : 0);

  // ── Series ─────────────────────────────────────────────────
  //
  // Feeds the chart deck below. Derived from `activity`, which includes
  // resolved and cancelled work — deriving it from `incidents` (the queue)
  // would undercount every past day and bend each line upward toward today,
  // see lib/charts/queue-series.ts.
  const hasTrend = activity.length > 0;

  // "Total Incidents" — every incident that touched the last 14 days,
  // any status, from the same `activity` feed the chart deck reads. This
  // can differ from `total` above: that is every incident open RIGHT NOW
  // regardless of when it arrived, while this is everything that arrived or
  // closed WITHIN the window. Both are honest; they answer different
  // questions, which is why the composition bar below is labelled against
  // its own window rather than compared to the live Active figure.
  const windowTotal     = activity.length;
  const windowResolved  = activity.filter(i => i.status === 'resolved').length;
  const windowCancelled = activity.filter(i => i.status === 'cancelled').length;
  const windowStillOpen = Math.max(0, windowTotal - windowResolved - windowCancelled);

  // Rows for the dashboard-3 chart cards. Same `activity` source as the
  // tiles above, so a figure and the chart under it can never disagree.
  const volumeRows   = hasTrend ? volumePoints(activity, TREND_DAYS) : [];
  const severityRows = hasTrend ? severityDays(activity, TREND_DAYS) : [];
  const latencyRows  = hasTrend ? dispatchLatency(activity, TREND_DAYS) : [];
  const categories   = categoryMix(activity, TREND_DAYS);
  // Stations that took a report in the window, busiest first (unmatched reports are not a station).
  const reportingStations = stationTallies(activity).filter(r => r.id !== null);

  // Same-shaped 14-day series behind the four live stat tiles above the
  // chart deck. Each is the tile's own figure walked back day by day — e.g.
  // activeSeriesRows' last point always equals `total` — so the trend line
  // and the number it sits beside can never disagree. Built from `activity`
  // for the same survivorship-bias reason the chart deck is: see the header
  // note in lib/charts/queue-series.ts.
  const activeSeriesRows     = hasTrend ? activeSeries(activity, TREND_DAYS) : [];
  const criticalSeriesRows   = hasTrend ? severitySeries(activity, 'critical', TREND_DAYS) : [];
  const awaitingSeriesRows   = hasTrend ? awaitingSeries(activity, TREND_DAYS) : [];
  // The roster's own series comes from account join dates, not from
  // `activity` — see rosterSeries in queue-series.ts for what it can and
  // cannot say.
  const rosterSeriesRows = rosterJoined.length ? rosterSeries(rosterJoined, TREND_DAYS) : [];

  // The values StatCell draws as its trend line. `undefined` when there is no
  // series to draw, which StatCell reads as "draw nothing" — never a made-up
  // shape.
  const sparkOf = (rows: { value: number }[]): number[] | undefined =>
    rows.length > 1 ? rows.map(r => r.value) : undefined;

  // The Provincial Admin's standing totals walked back from their creation
  // dates — see standingSeries. Empty when the backend predates `recent`.
  const platformSeries = (total: number, created?: string[]) =>
    created ? standingSeries(total, created, TREND_DAYS) : [];
  const residentsSeriesRows  = platform ? platformSeries(platform.residents,  platform.recent?.residents)  : [];
  const respondersSeriesRows = platform ? platformSeries(platform.responders, platform.recent?.responders) : [];
  const stationsSeriesRows   = platform ? platformSeries(platform.stations,   platform.recent?.stations)   : [];

  const agencyMap: Record<string, { active: number; critical: number }> = {};
  for (const inc of incidents) {
    const ag = agencyOf(inc);
    if (!agencyMap[ag]) agencyMap[ag] = { active: 0, critical: 0 };
    agencyMap[ag].active++;
    if (sevOf(inc) === 'critical') agencyMap[ag].critical++;
  }



  // Un-dispatched first, then by severity, then oldest first. Sorting by
  // recency instead put the newest low-severity report above a critical one
  // that had been sitting untouched for an hour.
  const needsAttention = [...incidents]
    .sort((a, b) => {
      const byWaiting = Number(isWaiting(b)) - Number(isWaiting(a));
      if (byWaiting) return byWaiting;
      const bySeverity = (SEV_RANK[sevOf(b) ?? ''] ?? 0) - (SEV_RANK[sevOf(a) ?? ''] ?? 0);
      if (bySeverity) return bySeverity;
      return new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
    })
    .slice(0, 6);

  // What the list card shows: the dispatch order for an Agency Admin, plain
  // recency for a Provincial Admin (who is reading, not triaging).
  const listRows = isAgencyAdmin
    ? needsAttention
    : [...incidents]
        .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
        .slice(0, 6);

  const isEmpty = loading && total === 0;

  return (
    <div className="min-h-full">
      <DemoTarget id="overview:greeting"><GreetingHeader /></DemoTarget>

      <div className="space-y-4 px-6 pb-5 pt-3 md:px-7">
        {error && (
          <div className="flex items-start gap-3">
            <div className="flex-1"><Alert variant="error" message={error} /></div>
            <Button onClick={() => load()} size="sm" variant="outline">
              <RefreshCw data-icon="inline-start" />
              Retry
            </Button>
          </div>
        )}

        {isEmpty ? (
          <Skeleton className="h-[157px]" />
        ) : (
          <DemoTarget id="overview:live"><StatStrip>
            {/* Window sum, not the live queue — see the comment on
                windowTotal above for why this can differ from Active. The
                trend line is arrivals per day across the same window, the
                same series the "Reports received per day" chart below
                draws. The one number from the old composition bar that is
                this admin's business — how many are still open — moved into
                the caption. */}
            <StatCell
              icon={<ClipboardList size={12} strokeWidth={2} />}
              // The window is in the label itself, not just the trend line
              // underneath — Incident History has its own "Total Incidents"
              // tile defaulted to a 30-day window, and the two numbers will
              // routinely disagree. Spelling out "14d" up top is what stops
              // that from reading as a bug.
              label={`Total incidents (${TREND_DAYS}d)`}
              value={windowTotal}
              trend={`${isProvincialAdmin ? 'Province-wide' : 'Your agency'} · ${
                windowTotal > 0 ? `${windowStillOpen} still open` : 'any status'
              }`}
              color="var(--color-brand)"
              bg="var(--color-brand-subtle)"
              spark={volumeRows.length > 1 ? volumeRows.map(r => r.received) : undefined}
            />
            <StatCell
              icon={<Radar size={12} strokeWidth={2} />}
              label="Active"
              value={total}
              trend={`${dispatched} dispatched · ${waiting.length} waiting`}
              color={liveAccent}
              bg={liveAccentBg}
              spark={sparkOf(activeSeriesRows)}
              delta={deltaOf(activeSeriesRows)}
            />
            <StatCell
              icon={<TriangleAlert size={12} strokeWidth={2} />}
              label="Critical"
              value={counts.critical}
              trend={`${Math.round(pct(counts.critical))}% of active queue`}
              color="var(--color-severity-critical)"
              bg="var(--color-severity-critical-bg)"
              spark={sparkOf(criticalSeriesRows)}
              delta={deltaOf(criticalSeriesRows)}
            />
            <StatCell
              icon={<Inbox size={12} strokeWidth={2} />}
              label="Awaiting triage"
              value={waiting.length}
              trend={`${Math.round(pct(waiting.length))}% not yet dispatched`}
              color="var(--color-status-processing)"
              bg="var(--color-status-processing-bg)"
              spark={sparkOf(awaitingSeriesRows)}
              delta={deltaOf(awaitingSeriesRows)}
            />
          </StatStrip></DemoTarget>
        )}

        {/* ── The agency's roster — Agency Admin only ────────
            The Provincial Admin strip below counts the whole agency_type
            province-wide, which is not a number an Agency Admin can act on.
            This is the one they can: who
            they have, who is available, and who is waiting on them.

            "Their agency", not "their station". Responders carry agency_id and
            no station_id, so a per-station roster is not something this schema
            can answer — and labelling it "station" would invent a grouping
            that does not exist. */}
        {isAgencyAdmin && roster && (
          <DemoTarget id="overview:roster"><StatStrip>
            {/* All time, where "Total incidents" above is the last 14 days.
                Sits with the roster strip purely to keep both strips at four
                cards apiece. No trend line: the tile has no day-by-day series
                of its own, and an invented shape would be worse than none. */}
            <StatCell
              icon={<Files size={12} strokeWidth={2} />}
              label="Total reports"
              // A failed fetch shows a dash, never a 0 that reads as "no reports".
              value={allTime?.total ?? '—'}
              trend={
                !allTime
                  ? 'All time · could not load'
                  : allTime.total === 0
                    ? 'No reports received yet'
                    : `All time · ${allTime.resolved} resolved`
              }
              color="var(--color-brand)"
              bg="var(--color-brand-subtle)"
            />
            {/* The only roster tile with a history to draw: every account has
                a join date. "On duty" is a live toggle and an approval leaves
                no timestamp, so those two tiles below draw no line rather
                than an invented one. */}
            <StatCell
              bg="var(--color-brand-subtle)"
              color="var(--color-brand)"
              icon={<Users size={12} strokeWidth={2} />}
              label="Responders"
              riseIsBad={false}
              trend={
                roster.total === 0
                  ? 'Nobody on the roster yet'
                  : `${roster.approved} approved to dispatch`
              }
              value={roster.total}
              spark={sparkOf(rosterSeriesRows)}
              delta={deltaOf(rosterSeriesRows)}
            />
            {/* Divided by APPROVED, not by the whole roster. A pending account
                cannot be sent anywhere, so counting it in the denominator
                would make availability look worse than it is — and counting
                it in the numerator would make it look better. */}
            <StatCell
              bg="var(--color-system-success-bg)"
              color="var(--color-system-success)"
              icon={<ShieldCheck size={12} strokeWidth={2} />}
              label="On duty now"
              riseIsBad={false}
              trend={
                roster.onDuty === 0
                  ? 'Nobody available to dispatch'
                  : 'Available to dispatch'
              }
              value={roster.onDuty}
              whole={roster.approved}
              wholeLabel="approved"
            />
            {/* Amber while someone is waiting on this admin, green once the
                roster is current — never grey, so the tile keeps its place in
                the row's colours either way. */}
            <StatCell
              bg={
                roster.pending > 0
                  ? 'var(--color-system-warning-bg)'
                  : 'var(--color-system-success-bg)'
              }
              color={
                roster.pending > 0
                  ? 'var(--color-system-warning)'
                  : 'var(--color-system-success)'
              }
              icon={<UserPlus size={12} strokeWidth={2} />}
              label="Awaiting approval"
              // The only tile here that is work for the person reading it.
              trend={
                roster.pending > 0
                  ? 'Waiting on you in Responders'
                  : 'Roster is current'
              }
              value={roster.pending}
              whole={roster.total}
              wholeLabel="on the roster"
            />
          </StatStrip></DemoTarget>
        )}

        {/* ── Standing totals — Provincial Admin only ────────
            A second strip rather than three more cards in the first one.
            The four above are the live incident state and change on every
            refresh; these are the size of the system and change when someone
            signs up. Mixing them would put a number that moves every fifteen
            seconds beside one that moves every few days, and invite the two to
            be read as the same kind of fact.

            None of the three carries a ring. A ring divides a part by its
            whole, and a total IS the whole — value and whole would be the same
            number and every gauge would sit at 100%. The sub-counts go on the
            context line, which is what it is for. */}
        {isProvincialAdmin && platform && (
          <DemoTarget id="overview:platform"><StatStrip>
            {/* Where the reports are landing. Counts the stations that took at
                least one report in the same window as the tiles above, and names
                the busiest, so a province of twenty-odd stations is readable at
                a glance. A report no station was matched to is not a station and
                is left out of the count; it still shows in Incident Records.
                (Agency Admins have one station, so their strip shows
                "Total reports" here instead.) */}
            <StatCell
              icon={<Building2 size={12} strokeWidth={2} />}
              label="Reports by station"
              value={reportingStations.length}
              trend={
                reportingStations.length === 0
                  ? `No station had a report in ${TREND_DAYS} days`
                  : `of ${platform.stations} stations · busiest ${reportingStations[0].name} (${reportingStations[0].reports})`
              }
              color="var(--color-brand)"
              bg="var(--color-brand-subtle)"
              riseIsBad={false}
              // Distinct stations per day. No delta: a day-to-day swing in how
              // many stations happened to get a call is noise, not a change.
              spark={sparkOf(hasTrend ? stationsReportingSeries(activity, TREND_DAYS) : [])}
            />
            <StatCell
              bg={liveAccentBg}
              color={liveAccent}
              icon={<Users size={12} strokeWidth={2} />}
              label="Residents"
              // riseIsBad false: more people able to report an emergency is
              // the direction this system exists to move in.
              riseIsBad={false}
              trend={
                platform.residents === 0
                  ? 'No accounts yet'
                  : `${platform.residents_verified} identity-verified`
              }
              value={platform.residents}
              spark={sparkOf(residentsSeriesRows)}
              delta={deltaOf(residentsSeriesRows)}
            />
            <StatCell
              bg="var(--color-system-success-bg)"
              color="var(--color-system-success)"
              icon={<ShieldCheck size={12} strokeWidth={2} />}
              label="Responders"
              riseIsBad={false}
              // Pending accounts come first when there are any: that is work
              // an Agency Admin still has to do, and it is the only part of
              // this tile anyone can act on.
              trend={
                platform.responders_pending > 0
                  ? `${platform.responders_pending} awaiting approval · ${platform.responders_on_duty} on duty`
                  : `${platform.responders_on_duty} on duty right now`
              }
              value={platform.responders}
              spark={sparkOf(respondersSeriesRows)}
              delta={deltaOf(respondersSeriesRows)}
            />
            {/* Amber when agencies outnumber the ones that have a station.
                An agency with no station cannot receive a dispatch — a report
                routed to it has nowhere to land — so the gap is a fault, not
                a statistic. Green when every agency is covered. */}
            <StatCell
              bg={
                platform.agencies_with_a_station < platform.agencies
                  ? 'var(--color-system-warning-bg)'
                  : 'var(--color-system-success-bg)'
              }
              color={
                platform.agencies_with_a_station < platform.agencies
                  ? 'var(--color-system-warning)'
                  : 'var(--color-system-success)'
              }
              icon={<LandPlot size={12} strokeWidth={2} />}
              label="Stations"
              riseIsBad={false}
              trend={
                platform.agencies_with_a_station < platform.agencies
                  ? `${platform.agencies - platform.agencies_with_a_station} of ${platform.agencies} agencies have none`
                  : `across all ${platform.agencies} agencies`
              }
              value={platform.stations}
              spark={sparkOf(stationsSeriesRows)}
              delta={deltaOf(stationsSeriesRows)}
            />
          </StatStrip></DemoTarget>
        )}

        {/* The chart deck, on the @efferd/dashboard-3 grid: a wide primary
            chart beside a narrow companion, then a full-width secondary row.
            The spans are what make the reference's rhythm — a 3/1 split reads
            as "one main story with a breakdown", which four equal cards does
            not. */}
        {isEmpty ? (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <Skeleton className="h-[320px] sm:col-span-2 lg:col-span-3" />
            <Skeleton className="h-[320px]" />
          </div>
        ) : (
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <DemoTarget id="overview:volume"><IncidentVolumeChart data={volumeRows} /></DemoTarget>
            <DemoTarget id="overview:agencies"><AgencyShareChart
              data={AGENCIES.map(ag => ({
                agency: ag,
                active: agencyMap[ag]?.active ?? 0,
              }))}
            /></DemoTarget>
            {/* Half-width pairs, side by side: Time to dispatch + What kind of
                emergency, then Severity mix + Week pattern. Severity is placed
                with the Week pattern, not ahead of Dispatch, so the pair that
                waits on the 90-day fetch is always the LAST one — when it
                arrives nothing above it moves. */}
            <DemoTarget id="overview:latency"><DispatchLatencyChart data={latencyRows} days={TREND_DAYS} /></DemoTarget>
            <DemoTarget id="overview:categories"><CategoryMixChart
              days={TREND_DAYS}
              ranked={categories.ranked}
              total={categories.total}
              unclassified={categories.unclassified}
            /></DemoTarget>
            <DemoTarget id="overview:severity"><SeverityTrendChart data={severityRows} /></DemoTarget>
            {/* Needs the long window, so it waits for it rather than drawing
                from the fourteen days above and quietly meaning something less. */}
            {longActivity && (
              <DemoTarget id="overview:week"><WeekPatternCard
                days={PATTERN_DAYS}
                isAgencyAdmin={isAgencyAdmin}
                patterns={timePatterns(longActivity)}
              /></DemoTarget>
            )}
          </div>
        )}

        {/* The list card — the same object for both admins, framed for what each
            does with it. Agency Admin gets "Needs attention": un-dispatched
            first, then by severity, then longest waiting, with a button
            straight into the Live Queue where the assign/resolve actions live.
            Provincial Admin gets "Latest reports": the same rows, newest
            first, read-only, and the button goes to Incident Records — they
            watch what arrived, they do not dispatch it (spec Section 1: "will
            not directly receive, dispatch, or operationally process emergency
            incidents"). Same card, same row, same rhythm, so the two
            dashboards read as one product; the framing is the difference, not
            the design. The System snapshot card that used to stand in here is
            gone — its four severity counts already sit in the stat strip and
            the severity chart below. */}
        {(
          <DemoTarget id="overview:list"><Card className="overflow-hidden">
            <CardHeader className="flex flex-col gap-3 border-b sm:flex-row sm:items-center sm:justify-between" style={{ borderColor: 'var(--color-surface-border)' }}>
              <div className="space-y-1">
                <div className="flex items-center gap-2">
                  <CardTitle>{isAgencyAdmin ? 'Needs attention' : 'Latest reports'}</CardTitle>
                  {!isEmpty && listRows.length > 0 && (
                    <span
                      className="inline-flex h-5 min-w-5 items-center justify-center rounded-full px-1.5 text-[11px] font-bold tabular-nums"
                      style={{ backgroundColor: liveAccentBg, color: liveAccent }}
                    >
                      {listRows.length}
                    </span>
                  )}
                </div>
                <CardDescription>
                  {isAgencyAdmin
                    ? 'Un-dispatched first, then by severity, then longest waiting'
                    : 'Newest first across your province — open one to read the full report'}
                </CardDescription>
              </div>
              <Button asChild size="sm" variant="outline">
                <Link href={isAgencyAdmin ? '/incidents' : '/incident-history'}>
                  {isAgencyAdmin ? 'Live queue' : 'Incident Records'}
                  <ArrowUpRight data-icon="inline-end" />
                </Link>
              </Button>
            </CardHeader>
            <CardContent className="px-2 py-2">
            {isEmpty ? (
              <div className="space-y-2 px-1 py-1">
                {Array.from({ length: 5 }).map((_, i) => (
                  <Skeleton key={i} className="h-16" rounded="var(--radius-control)" />
                ))}
              </div>
            ) : listRows.length === 0 ? (
              <_AllClear />
            ) : (
              <ul className="flex flex-col gap-1">
                {listRows.map(inc => (
                  <_IncidentRow incident={inc} key={inc.id} showDue={isAgencyAdmin} />
                ))}
              </ul>
            )}
            </CardContent>
          </Card></DemoTarget>
        )}
      </div>
    </div>
  );
}

// ── Status line ───────────────────────────────────────────────
//
// Two short sentences: where the load is, then what is outstanding.
//
// It stays true at every value — singular and plural agree, and the scope
// clause is derived from the agencies actually present rather than from the
// three that could be, which is what produced "across 0 agencies" while an
// incident was plainly sitting in the queue.
//
// A zero is only worth words when its absence is news. "None critical" was
// spending a clause to report nothing happening, on a line that is read every
// few minutes; the critical clause now appears only when there is a critical.

// ── Agency row ────────────────────────────────────────────────

// ── Incident row ──────────────────────────────────────────────
/**
 * A feed row, not a table row. The table this replaces read as a data grid
 * for four disjoint facts (report / agency / status / waiting); a
 * dispatcher scanning "what do I act on next" reads a list of CASES better
 * — one glance per row, the category icon and severity tint giving the eye
 * something to sort by before it even reads the text.
 */
function _IncidentRow({ incident, showDue }: { incident: QueueIncident; showDue: boolean }) {
  const sev       = sevOf(incident);
  const sevColor  = sev ? (SEV_COLOR[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
  const sevBg     = sev ? (SEV_BG[sev] ?? 'var(--color-surface-raised)') : 'var(--color-surface-raised)';
  const agType    = agencyOf(incident);
  const agColor   = AG_COLOR[agType] ?? 'var(--color-text-muted)';
  const sc        = STATUS_STYLE[incident.status] ?? STATUS_STYLE.received;
  const untouched = isWaiting(incident);
  const CategoryIcon = CATEGORY_ICON[incident.incident_category ?? ''] ?? ShieldAlert;

  // The due/late badge is a promise about DISPATCH, so it stops meaning
  // anything once a responder is already committed — urgencyTimeColor()
  // has the same status gate for the same reason. A dispatched row falls
  // back to a plain elapsed time instead, same as before this redesign.
  const due = showDue && untouched ? dueState(incident) : null;

  return (
    <li>
      <Link
        className="group flex items-center gap-3 rounded-[var(--radius-control)] px-2.5 py-2.5 transition-colors hover:bg-[var(--color-surface-hover)]"
        href={`/incidents/${incident.id}`}
      >
        <span
          aria-hidden="true"
          className="flex h-10 w-10 shrink-0 items-center justify-center rounded-[var(--radius-md)]"
          style={{ backgroundColor: sevBg, color: sevColor }}
        >
          <CategoryIcon size={17} strokeWidth={2} />
        </span>

        <div className="min-w-0 flex-1">
          <span className="sr-only">{sev ? `${sev} severity. ` : ''}</span>
          <span className="block truncate text-ui font-medium text-[var(--color-text-primary)]">
            {incident.report_text}
          </span>
          <div className="mt-0.5 flex items-center gap-1.5 text-meta" style={{ color: 'var(--color-text-muted)' }}>
            <span className="font-semibold" style={{ color: agColor }}>{agType}</span>
            <span aria-hidden="true">·</span>
            <span
              className="inline-flex whitespace-nowrap rounded-full px-1.5 py-0.5 text-[10.5px] font-semibold"
              style={{ backgroundColor: sc.bg, color: sc.text }}
            >
              {incident.status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
            </span>
            {sev && (
              <>
                <span aria-hidden="true" className="hidden sm:inline">·</span>
                <span className="hidden font-semibold sm:inline" style={{ color: sevColor }}>
                  {sev.charAt(0).toUpperCase() + sev.slice(1)}
                </span>
              </>
            )}
          </div>
        </div>

        {/* The one number this whole card exists to surface: is this report
            still inside its dispatch target, or already past it. Elapsed
            time reads at full strength while nobody has acted, and drops
            back to muted once a responder is committed — the number still
            matters then, but it is no longer anybody's outstanding
            decision. */}
        <div className="shrink-0 text-right">
          {due ? (
            <Fig className="text-[12.5px] font-semibold whitespace-nowrap" tone={DUE_COLOR[due.bucket]}>
              {formatDue(due)}
            </Fig>
          ) : (
            <Fig className="text-[12.5px] whitespace-nowrap" tone="var(--color-text-muted)">
              {formatDuration(minutesSince(incident.created_at))}
            </Fig>
          )}
        </div>

        <ChevronRight
          aria-hidden="true"
          className="shrink-0 opacity-0 transition-opacity group-hover:opacity-50"
          size={16}
          style={{ color: 'var(--color-text-muted)' }}
        />
      </Link>
    </li>
  );
}

// ── Empty state ───────────────────────────────────────────────
function _AllClear() {
  return (
    <div className="flex flex-col items-center justify-center py-12">
      <CheckCircle size={28} style={{ color: 'var(--color-system-success)' }} className="mb-3" />
      <p className="text-ui font-medium text-[var(--color-text-primary)]">All agencies clear</p>
      <p className="mt-1 text-meta text-[var(--color-text-muted)]">
        No active incidents system-wide.
      </p>
    </div>
  );
}
