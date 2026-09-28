'use client';

/**
 * Active incidents — every OPEN report, as one numbered working line.
 *
 * One of the two views behind /incidents. It reads /dispatch/queue, which
 * excludes resolved and cancelled by design, so this view can only ever show
 * work that still needs doing. The History view beside it reads a different
 * endpoint for exactly that reason — see its header.
 *
 * WHY THIS IS A TABLE NOW, AND NOT A LIST OF CARDS
 *
 * The page used to draw each report as a three-pane card inside collapsible
 * severity bands. That was readable at six incidents. At sixty it stopped
 * answering the only question a dispatcher opens this page with — WHO IS
 * NEXT — because the answer was four scrolls away and the bands each restarted
 * the reader's sense of order. The dispatcher who works this console put it
 * plainly: pag marami na report, hindi na alam kung sino ang nauna.
 *
 * Three changes answer that, and everything else here follows from them:
 *
 *   1. ONE LINE, NUMBERED. The waiting incidents are one ordered list with a
 *      position column — worst severity first, then longest wait. Row 1 wears
 *      NEXT. The number is computed over the whole waiting set, so it does not
 *      change when the reader filters, re-sorts or turns the page.
 *
 *   2. A RAIL THAT KEEPS THE HEAD OF THE LINE IN VIEW. Whatever the table has
 *      been narrowed to, the two rows pinned in the overview are still the
 *      true next two. Filtering can no longer hide what you are working next.
 *
 *   3. PAGES INSTEAD OF CAPPED BANDS. The old "show 8 of 43" cap hid rows
 *      behind a button; paging hides nothing and says how much there is. In
 *      the default queue order the most dangerous reports are on page one by
 *      construction, which is the property the uncapped critical band existed
 *      to protect.
 *
 * DESIGNED FOR A BAD DAY, NOT A QUIET ONE
 *
 * The page a dispatcher uses at 3am during a typhoon holds a few hundred rows,
 * not the six on a demo screen. Hence the filter row, the truncation banner at
 * QUEUE_MAX, and the auto-refresh switch: a queue that reorders under someone
 * mid-decision is worse than one that is thirty seconds old, so the reader can
 * hold it still and is told plainly when they have.
 *
 * The row itself lives in components/incidents/incident-table.tsx. Incident
 * History still renders the card row — its rows are closed reports being read
 * one at a time, not a line being worked.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  CheckCircle, Circle, Clock, Eye, FilterX, HelpCircle,
  ListOrdered, MapPinned, Pause, Play, RefreshCw, Siren, Truck, X, Zap,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  fetchQueue, type QueueIncident,
} from '@/lib/api/dispatch';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { incidentPrefs } from '@/lib/prefs/definitions';
import { useArrivals } from '@/lib/incidents/arrivals';
import { Alert } from '@/components/ui/alert';
import { Pagination } from '@/components/ui/pagination';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { Button } from '@/components/efferd/ui/button';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import { IncidentDetailModal } from '@/components/incidents/incident-detail-modal';
import {
  GROUP_META, IncidentTable, groupOf, type GroupKey,
} from '@/components/incidents/incident-table';
import { QueueOverview, type QueueBand } from '@/components/incidents/queue-overview';
import { StationStrip } from '@/components/incidents/station-strip';
import {
  AG_COLOR, AGENCY_ICON, AWAITING_STATUSES, CATEGORY_ICON, EN_ROUTE_STATUSES,
  SEV_COLOR, SEV_ICON, STATUS_ICON, STATUS_STYLE, dueState, longestWait, sevOf, statusLabel,
} from '@/components/incidents/incident-vocabulary';
import { OptionPicker } from '@/components/ui/option-picker';
import { SearchInput } from '@/components/ui/search-input';
import type { OptionItem } from '@/components/ui/option-dialog';
import { CATEGORY_LABELS, REAL_CATEGORIES } from '@/lib/charts/queue-series';

/** Severity filter values — the real triage severities plus the untriaged bucket. */
const SEVERITY_FILTERS = ['critical', 'high', 'medium', 'low', 'untriaged'] as const;
const SEVERITY_LABEL: Record<string, string> = {
  critical: 'Critical', high: 'High', medium: 'Medium', low: 'Low', untriaged: 'Untriaged',
};

/** The tint every filter dialog's "no filter" row uses — see the option-list comment below. */
const NEUTRAL = 'var(--color-text-tertiary)';

/** The queue never carries resolved/cancelled rows (see this file's own header), so its Status filter — unlike Incident Records' — only ever offers the five open statuses. */
const QUEUE_STATUSES = ['received', 'processing', 'dispatched', 'en_route', 'arrived'] as const;

const SEVERITY_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any severity', icon: Circle, color: NEUTRAL },
  ...SEVERITY_FILTERS.map(s => ({ value: s, label: SEVERITY_LABEL[s], icon: SEV_ICON[s], color: SEV_COLOR[s] ?? NEUTRAL })),
];

const TYPE_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any type', icon: Circle, color: NEUTRAL },
  ...REAL_CATEGORIES.map(c => ({ value: c, label: CATEGORY_LABELS[c], icon: CATEGORY_ICON[c] })),
  { value: 'other', label: 'Other / unclassified', icon: HelpCircle },
];

const STATUS_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any status', icon: Circle, color: NEUTRAL },
  ...QUEUE_STATUSES.map(st => ({ value: st, label: statusLabel(st), icon: STATUS_ICON[st], color: STATUS_STYLE[st].text })),
];

// The live queue's refresh is the operator's choice (Settings → Incident
// Preferences → Live queue refresh); 15 seconds unless they changed it.


/** Must match QUEUE_MAX in dispatch_service.py. */
const QUEUE_MAX = 500;

/**
 * How long after being filed a report is "new".
 *
 * Measured from when the RESIDENT filed it, not from when this console noticed.
 * It used to be the latter, for ninety seconds, seeded silently on the first
 * load - so a dispatcher who opened the queue two minutes after the alert saw a
 * report with no marker at all, sitting at the far end of its severity group in
 * a long queue. The alert had said it exists and the list gave no way to find
 * it. Ten minutes from filing is long enough to still matter and short enough
 * that the marker keeps meaning something on a busy day.
 */
const RECENT_MS = 10 * 60_000;

const PAGE_SIZES = [25, 50, 100];

/** Which slice of the queue the table is showing. */
type BandKey =
  | 'awaiting' | 'critical' | 'high' | 'other' | 'en_route' | 'on_scene' | 'all';

/** Bands whose rows already have a responder — a status board, not a queue. */
const isCrewBand = (k: string) => k === 'en_route' || k === 'on_scene';

/** Rank of each group in the order the queue is worked. */
const GROUP_RANK: Record<GroupKey, number> = { critical: 0, high: 1, other: 2 };

/**
 * The working order: group first, then whoever arrived first.
 *
 * The second key is the whole point of the change. Within a group every report
 * shares a severity band, so nothing overtakes anything and the numbering can
 * be checked against the Received column by eye. Severity decides which GROUP
 * a report is in and nothing else — it no longer reaches inside a group to
 * reorder it, which is what made the old #1 disagree with the dispatcher's own
 * rule of first come, first served.
 */
function workingOrder(a: QueueIncident, b: QueueIncident): number {
  const ga = GROUP_RANK[groupOf(a)];
  const gb = GROUP_RANK[groupOf(b)];
  if (ga !== gb) return ga - gb;
  return a.created_at.localeCompare(b.created_at);
}

export function ActiveIncidentsView() {
  const { refreshSeconds } = incidentPrefs.use();
  const REFRESH_MS = refreshSeconds * 1000;
  const { token, isProvincialAdmin } = useAuth();
  // A Provincial Admin oversees every station of their agency_type and
  // dispatches for none of them, so "Assign" is an action they can never
  // take. Their useful next step is spatial — see where this sits relative
  // to everything else on the map.

  const [incidents, setIncidents] = useState<QueueIncident[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastSync, setLastSync] = useState<Date | null>(null);
  /** Resolved in the last 24h. Its own endpoint, its own clock — see below. */

  const [q, setQ] = useState('');
  const [agency, setAgency] = useState('all');
  // Provincial-Admin-only filters. Every incident an Agency Admin sees is
  // already their own one station, so these three would only ever have one
  // possible value for them — not worth the filter bar space. A Provincial
  // Admin's rows share one agency_type but span many stations, which is
  // exactly the dimension `agency` (BFP/PNP/MDRRMO) can no longer isolate
  // now that a login only ever has one agency_type to begin with.
  const [station, setStation] = useState('all');
  const [severity, setSeverity] = useState('all');
  const [incidentType, setIncidentType] = useState('all');
  const [status, setStatus] = useState('all');
  const [band, setBand] = useState<BandKey>('awaiting');
  const [sortMode, setSortMode] = useState<'queue' | 'newest'>('queue');
  const [page, setPage] = useState(1);
  const [perPage, setPerPage] = useState(25);
  /**
   * Whether the 15-second poll is running.
   *
   * On by default and switchable, because both states are dangerous in
   * different ways. A queue that re-sorts under someone halfway through
   * reading a report is how the wrong incident gets dispatched; a queue that
   * quietly stopped updating is how a new critical never gets seen. The switch
   * exists so the first is a choice, and the Connection card states which of
   * the two you are in.
   */
  const [autoRefresh, setAutoRefresh] = useState(true);

  // Which incident the detail dialog is showing. Held here rather than per
  // row so only one dialog ever exists, and so the poll replacing the row
  // array cannot unmount an open dialog mid-read.
  const [openId, setOpenId] = useState<string | null>(null);

  const searchRef = useRef<HTMLInputElement>(null);

  /**
   * Reports the dispatcher has been shown and has dealt with - opened, or
   * pointed at with "Show in list" - so they stop being announced as new.
   */
  const [seenNew, setSeenNew] = useState<Set<string>>(() => new Set());
  /** A row to scroll into view once the list has been rearranged around it. */
  const [focusId, setFocusId] = useState<string | null>(null);
  /** Re-evaluates "new" as time passes without waiting for the next poll. */
  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNowMs(Date.now()), 30_000);
    return () => clearInterval(id);
  }, []);

  const load = useCallback(async (showSpinner = false) => {
    if (!token) return;
    if (showSpinner) setLoading(true);
    try {
      const rows = await fetchQueue(token);
      setIncidents(rows);
      setLastSync(new Date());
      setError(null);
    } catch (err: unknown) {
      if (err instanceof ApiError) {
        if (err.status === 401) { signOut(); return; }
        if (err.status === 403) {
          setError('Your account does not have permission to view the dispatch queue.');
          return;
        }
        setError(err.message);
      } else {
        setError('Failed to load queue.');
      }
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    load(true);
  }, [load]);

  useEffect(() => {
    // Only an Agency Admin can pause the poll — see the bottom bar.
    if (!autoRefresh && !isProvincialAdmin) return;
    const id = setInterval(() => load(false), REFRESH_MS);
    return () => clearInterval(id);
  }, [autoRefresh, isProvincialAdmin, load, REFRESH_MS]);

  // The alert hook is the first to notice a new report (it polls every ten
  // seconds). Reading the queue at once means the row is on this page by the
  // time the dispatcher has read the popup, instead of up to a poll later - or,
  // with auto refresh switched off, never. Pausing the poll is about not
  // reordering under someone mid-decision; a report that has just arrived
  // changes nothing they are already looking at.
  useArrivals(() => { void load(false); });


  // Agencies present in the data, not a hardcoded three — an incident with no
  // station has no agency at all, and the filter must be able to isolate those.
  // Meaningful for Agency Admin only now (a single value for a Provincial
  // Admin, since every row already shares their own agency_type) — the
  // filter itself stays available to both, but see `stations` below for the
  // dimension that actually varies for a Provincial Admin.
  const agencies = useMemo(() => {
    const set = new Set<string>();
    for (const i of incidents) {
      const a = i.stations?.agencies?.agency_type;
      if (a) set.add(a);
    }
    return [...set].sort();
  }, [incidents]);

  // Stations present in the data — the dimension a Provincial Admin's queue
  // actually varies over. No station id on QueueIncident, only a name; that's
  // fine to key on directly, the same way `agencies` above keys on a bare
  // agency_type string with no id either.
  const stations = useMemo(() => {
    const set = new Set<string>();
    for (const i of incidents) {
      if (i.stations?.name) set.add(i.stations.name);
    }
    return [...set].sort();
  }, [incidents]);

  // Option lists for the filter dialogs below (2026-09-19) — reusing the same
  // colour/icon vocabulary a row is drawn with (incident-vocabulary.ts), so a
  // severity or an agency means the same thing in a filter as it does in the
  // table. `NEUTRAL` marks the "no filter" row of each list — every row needs
  // an icon or the list misaligns (see option-dialog.tsx's Row), and a plain
  // ring reads as "nothing chosen" without competing with the coloured ones.
  const stationOptions = useMemo<OptionItem[]>(() => [
    { value: 'all', label: 'All stations', icon: Circle, color: NEUTRAL },
    ...stations.map(s => ({ value: s, label: s, icon: MapPinned })),
  ], [stations]);

  const agencyOptions = useMemo<OptionItem[]>(() => [
    { value: 'all', label: 'All agencies', icon: Circle, color: NEUTRAL },
    ...agencies.map(a => ({ value: a, label: a, icon: AGENCY_ICON[a], color: AG_COLOR[a] })),
    // Always offered, even at zero: its absence would read as "no such thing",
    // and an unassigned incident is the one a dispatcher most needs to isolate.
    { value: 'unassigned', label: 'Unassigned', icon: HelpCircle, hint: 'No station recorded' },
  ], [agencies]);

  // The label of the first option depends on the role (see the Select it
  // replaces, below) — the only one of these lists that can't be a module-level constant.
  const orderOptions = useMemo<OptionItem[]>(() => [
    {
      value: 'queue', label: isProvincialAdmin ? 'Severity order' : 'Queue order', icon: ListOrdered,
      hint: 'Worst severity first, then longest wait',
    },
    { value: 'newest', label: 'Newest first', icon: Clock, hint: 'Most recently filed at the top' },
  ], [isProvincialAdmin]);

  const filtered = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return incidents.filter(i => {
      if (isProvincialAdmin) {
        if (station !== 'all' && i.stations?.name !== station) return false;
        if (severity !== 'all' && (sevOf(i) ?? 'untriaged') !== severity) return false;
        if (incidentType !== 'all' && (i.incident_category ?? 'other') !== incidentType) return false;
      } else {
        if (agency === 'unassigned') {
          if (i.stations?.agencies?.agency_type) return false;
        } else if (agency !== 'all' && i.stations?.agencies?.agency_type !== agency) {
          return false;
        }
      }
      if (status !== 'all' && i.status !== status) return false;
      if (!needle) return true;
      // Matched against what a dispatcher would actually type: the words in
      // the report, the place, the reporter, or the short ID off a radio call.
      return (
        i.report_text.toLowerCase().includes(needle) ||
        (i.location_address ?? '').toLowerCase().includes(needle) ||
        (i.users?.full_name ?? '').toLowerCase().includes(needle) ||
        i.id.replace(/-/g, '').toLowerCase().includes(needle)
      );
    });
  }, [incidents, q, agency, station, severity, incidentType, status, isProvincialAdmin]);

  /**
   * The waiting line: three groups, and inside each one, oldest first.
   *
   * THE NUMBER IS PER GROUP, NOT ACROSS THE WHOLE LINE. An earlier version
   * numbered every waiting report 1...n across all severities, so #1 was
   * frequently not the report that arrived first, and no column on the screen
   * explained the discrepancy. Numbering within a group makes the rule
   * checkable by eye: #1 is the oldest report in its group, always.
   *
   * Assigned BEFORE the band filter and the display sort, so a row's number
   * means the same thing on every screen it appears on.
   */
  const waiting = useMemo(() => {
    const rows = filtered
      .filter(i => AWAITING_STATUSES.includes(i.status))
      .sort(workingOrder);
    const position = new Map<string, number>();
    const seen: Record<string, number> = {};
    for (const r of rows) {
      const g = groupOf(r);
      seen[g] = (seen[g] ?? 0) + 1;
      position.set(r.id, seen[g]);
    }
    return { rows, position };
  }, [filtered]);

  /** Waiting reports already past the dispatch target for their severity. */
  const late = useMemo(
    () => waiting.rows.filter(i => dueState(i).bucket === 'late'),
    [waiting],
  );

  const enRoute = useMemo(
    () => filtered.filter(i => EN_ROUTE_STATUSES.includes(i.status)),
    [filtered],
  );
  const onScene = useMemo(
    () => filtered.filter(i => i.status === 'arrived'),
    [filtered],
  );
  const criticalWaiting = useMemo(
    () => waiting.rows.filter(i => sevOf(i) === 'critical'),
    [waiting],
  );
  const highWaiting = useMemo(
    () => waiting.rows.filter(i => sevOf(i) === 'high'),
    [waiting],
  );
  const otherWaiting = useMemo(
    () => waiting.rows.filter(i => groupOf(i) === 'other'),
    [waiting],
  );

  const bands: (QueueBand & { key: BandKey; rows: QueueIncident[] })[] = useMemo(
    () => [
      {
        key: 'awaiting',
        label: 'Awaiting dispatch',
        count: waiting.rows.length,
        color: 'var(--color-status-received)',
        rows: waiting.rows,
      },
      {
        key: 'critical',
        label: GROUP_META.critical.label,
        count: criticalWaiting.length,
        color: GROUP_META.critical.color,
        rows: criticalWaiting,
      },
      {
        key: 'high',
        label: GROUP_META.high.label,
        count: highWaiting.length,
        color: GROUP_META.high.color,
        rows: highWaiting,
      },
      {
        key: 'other',
        label: GROUP_META.other.label,
        count: otherWaiting.length,
        color: GROUP_META.other.color,
        rows: otherWaiting,
      },
      {
        key: 'en_route',
        label: 'Assigned / en route',
        count: enRoute.length,
        color: 'var(--color-status-dispatched)',
        rows: enRoute,
      },
      {
        key: 'on_scene',
        label: 'On scene',
        count: onScene.length,
        color: 'var(--color-system-success)',
        rows: onScene,
      },
      {
        key: 'all',
        label: 'All open',
        count: filtered.length,
        color: 'var(--color-text-muted)',
        rows: filtered,
      },
    ],
    [waiting, criticalWaiting, highWaiting, otherWaiting, enRoute, onScene, filtered],
  );

  /**
   * Reports filed in the last ten minutes that nobody has looked at yet and
   * that are still waiting - what the "just arrived" strip counts and what
   * wears the "New" marker in the table. Newest first.
   */
  const justIn = useMemo(
    () =>
      incidents
        .filter(i =>
          AWAITING_STATUSES.includes(i.status) &&
          !seenNew.has(i.id) &&
          nowMs - new Date(i.created_at).getTime() < RECENT_MS,
        )
        .sort((a, b) => b.created_at.localeCompare(a.created_at)),
    [incidents, seenNew, nowMs],
  );
  const newIds = useMemo(() => new Set(justIn.map(i => i.id)), [justIn]);

  const markSeen = useCallback((ids: string[]) => {
    setSeenNew(prev => {
      if (ids.every(id => prev.has(id))) return prev;
      const next = new Set(prev);
      for (const id of ids) next.add(id);
      return next;
    });
  }, []);

  /**
   * Take the dispatcher to what just came in.
   *
   * Everything that could be hiding it is undone in one move: the filters, the
   * band, and the working order that would put a new report at the far end of
   * its severity group. Newest first, page one, the row scrolled into view.
   */
  const showJustIn = () => {
    const first = justIn[0];
    if (!first) return;
    clearFilters();
    setBand('all');
    setSortMode('newest');
    setPage(1);
    setFocusId(first.id);
    markSeen(justIn.map(i => i.id));
  };

  const activeBand = bands.find(b => b.key === band) ?? bands[0];

  /**
   * The rows on screen, in the order the reader asked for.
   *
   * Queue order is the working order and the default. Newest first answers
   * "what has just come in", which correct triage order genuinely cannot: a
   * new report lands wherever its severity and age belong, which on a busy
   * screen is somewhere in the middle. Switching does NOT renumber anything —
   * the position column keeps meaning place-in-line in both modes.
   */
  const sorted = useMemo(() => {
    const rows = activeBand.rows.slice();
    if (sortMode === 'newest') {
      return rows.sort((a, b) => b.created_at.localeCompare(a.created_at));
    }
    // A band that is already with a crew has no working order to be in — its
    // rows are not waiting on anybody here. Sorting them by severity would
    // dress a status board up as a to-do list; most recent handoff first is
    // the order someone actually reads it in.
    if (isCrewBand(activeBand.key)) {
      return rows.sort((a, b) =>
        (b.dispatched_at ?? b.created_at).localeCompare(a.dispatched_at ?? a.created_at),
      );
    }
    return rows.sort(workingOrder);
  }, [activeBand, sortMode]);

  /** Headings only where they mean something: a list holding several groups. */
  const grouped =
    sortMode === 'queue' && (band === 'awaiting' || band === 'all');

  const pageCount = Math.max(1, Math.ceil(sorted.length / perPage));
  // A filter that shortens the list can strand the reader on a page that no
  // longer exists, which renders as an empty table over a "showing 76–100 of
  // 12" header. Clamp rather than reset: staying near where they were is
  // better than being thrown back to page one on every keystroke.
  const currentPage = Math.min(page, pageCount);
  const pageRows = sorted.slice((currentPage - 1) * perPage, currentPage * perPage);

  // "Show in list" rearranges the list around a row and then needs that row on
  // screen. It can only be found once the new arrangement has rendered, which is
  // why this waits on pageRows instead of scrolling from the click handler.
  useEffect(() => {
    if (!focusId) return;
    const el = document.querySelector<HTMLElement>(`[data-incident-id="${focusId}"]`);
    if (!el) return;
    el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    setFocusId(null);
  }, [focusId, pageRows]);

  /** Opening a report is looking at it: it stops being announced as new. */
  const openIncident = (id: string) => {
    markSeen([id]);
    setOpenId(id);
  };

  // Any change to what the list CONTAINS starts the reader at the top again.
  useEffect(() => {
    setPage(1);
  }, [q, agency, station, severity, incidentType, status, band, perPage]);

  const filtersOn = isProvincialAdmin
    ? q.trim() !== '' || station !== 'all' || severity !== 'all' || incidentType !== 'all' || status !== 'all'
    : q.trim() !== '' || agency !== 'all' || status !== 'all';
  const atCap = incidents.length >= QUEUE_MAX;
  const clearFilters = () => {
    setQ('');
    setAgency('all');
    setStation('all');
    setSeverity('all');
    setIncidentType('all');
    setStatus('all');
  };

  const nextUp = useMemo(
    () => waiting.rows.slice(0, 2).map((incident, i) => ({ incident, position: i + 1 })),
    [waiting],
  );

  return (
    <div className="min-h-full">
      {/* ── Filters ─────────────────────────────────────────── */}
      {/* Sticky: past thirty rows the controls you need are the ones that have
          scrolled off. Below the header's z-50 so it never covers the nav.
          top-0, not top-11: this page no longer sits under a tab shell —
          Incident History is its own sidebar route now, not a toggle here. */}
      <div className="sticky top-0 z-20 border-b border-[var(--color-surface-border)] bg-background/95 px-6 py-3 backdrop-blur md:px-7">
        <div className="flex flex-wrap items-center gap-2">
          <SearchInput
            className="min-w-[200px] flex-1"
            label="Filter the queue"
            onValueChange={setQ}
            placeholder="Report, place, reporter or ID…"
            ref={searchRef}
            value={q}
          />

          {isProvincialAdmin ? (
            <>
              {/* Station, not Agency — every row already shares this admin's
                  one agency_type, so the dimension worth isolating is which
                  of their agency's stations it came from. */}
              <OptionPicker
                className="w-[190px]"
                label="Choose a station"
                onChange={setStation}
                options={stationOptions}
                placeholder="Station"
                size="sm"
                value={station}
              />

              <OptionPicker
                className="w-[165px]"
                label="Choose a severity"
                onChange={setSeverity}
                options={SEVERITY_OPTIONS}
                placeholder="Severity"
                size="sm"
                value={severity}
              />

              <OptionPicker
                className="w-[190px]"
                label="Choose an incident type"
                onChange={setIncidentType}
                options={TYPE_OPTIONS}
                placeholder="Incident type"
                size="sm"
                value={incidentType}
              />
            </>
          ) : (
            <OptionPicker
              className="w-[170px]"
              label="Choose an agency"
              onChange={setAgency}
              options={agencyOptions}
              placeholder="Agency"
              size="sm"
              value={agency}
            />
          )}

          <OptionPicker
            className="w-[165px]"
            label="Choose a status"
            onChange={setStatus}
            options={STATUS_OPTIONS}
            placeholder="Status"
            size="sm"
            value={status}
          />

          {/* Order, beside the filters rather than hidden in a menu. This is
              the control that answers "what has just come in", and a
              dispatcher who cannot find it goes back to reading timestamps
              down a hundred rows. */}
          <OptionPicker
            className="w-[185px]"
            label="Choose the queue's order"
            onChange={v => setSortMode(v as 'queue' | 'newest')}
            options={orderOptions}
            placeholder="Order"
            size="sm"
            value={sortMode}
          />

          {filtersOn && (
            <Button onClick={clearFilters} size="sm" variant="ghost">
              Clear
            </Button>
          )}

          {/* The count is the filter's receipt. Without it a filter that
              matches nothing looks identical to an empty queue. */}
          <span className="text-meta ml-auto shrink-0 text-muted-foreground">
            {filtersOn
              ? `${filtered.length} of ${incidents.length} shown`
              : `${incidents.length} in queue`}
          </span>
        </div>
      </div>

      <div className="space-y-4 px-6 py-5 md:px-7">
        {error && <Alert variant="error" message={error} />}

        {atCap && (
          <Alert
            variant="warning"
            message={`Showing the first ${QUEUE_MAX} open incidents. There may be more than this view can load — resolve or reassign before relying on the totals.`}
          />
        )}

        {/* What has just come in. The alert popup says a report exists; this is
            what is still true after the popup is gone - how many, and a way to
            the list that skips every filter and the working order that can
            bury a new report at the far end of its severity group. */}
        {justIn.length > 0 && (
          <_JustInStrip
            onDismiss={() => markSeen(justIn.map(i => i.id))}
            onOpen={openIncident}
            onShow={showJustIn}
            rows={justIn}
          />
        )}

        {/* The lifecycle of a report, left to right, with the two severity
            tiers that must never be buried sitting where the eye lands first.
            Every figure counts the FILTERED set, so the band and the tile
            above it can never disagree. */}
        <StatStrip>
          <StatCell
            bg="var(--color-system-warning-bg)"
            color="var(--color-system-warning)"
            icon={<Siren size={14} />}
            label="Awaiting dispatch"
            trend={
              waiting.rows.length === 0
                ? 'Nothing waiting'
                : late.length > 0
                  ? `${late.length} past target`
                  : 'All inside target'
            }
            value={waiting.rows.length}
          />
          <StatCell
            bg="var(--color-severity-critical-bg)"
            color="var(--color-severity-critical)"
            icon={<Zap size={14} />}
            label="Critical waiting"
            trend={
              longestWait(criticalWaiting)
                ? `Longest wait ${longestWait(criticalWaiting)}`
                : 'None waiting'
            }
            value={criticalWaiting.length}
          />
          <StatCell
            bg="var(--color-status-dispatched-bg)"
            color="var(--color-status-dispatched)"
            icon={<Truck size={14} />}
            label="Assigned / en route"
            value={enRoute.length}
          />
          <StatCell
            bg="var(--color-system-success-bg)"
            color="var(--color-system-success)"
            icon={<CheckCircle size={14} />}
            label="On scene"
            value={onScene.length}
          />
        </StatStrip>

        {/* ── The queue ───────────────────────────────────────── */}
        {isProvincialAdmin && (
          <StationStrip active={station} incidents={incidents} onSelect={setStation} />
        )}

        {/* The same two-column working area for both admins — the rail of
            bands on the left, the table on the right — so the two consoles
            read as one product. What differs is what each role is given to
            work with: an Agency Admin's rail pins the next two reports and
            reports whether the poll is live (they can pause it); a Provincial
            Admin's rail has neither, because they hold no queue position and
            the page always refreshes on its own. */}
        <div className="flex flex-col gap-4 lg:flex-row">
          <QueueOverview
            active={band}
            bands={bands}
            connection={{
              live: autoRefresh,
              lastSync,
              stale: error !== null,
            }}
            next={isProvincialAdmin ? [] : nextUp}
            onOpen={openIncident}
            onSelect={k => setBand(k as BandKey)}
            showSync={!isProvincialAdmin}
          />

          {/* No overflow-hidden. It would make this card the scrollport for
              the table's sticky header, which then stops following the page.
              The corners give up a pixel of clipping on the last row's hover
              tint; a header that scrolls away on a 25-row table costs more. */}
          <div className="min-w-0 flex-1 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
            {/* Header: what you are looking at, and where in it you are. */}
            <div className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-[var(--color-surface-border)] px-4 py-2.5">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-baseline gap-x-3">
                  <span className="text-[13px] font-semibold text-foreground">
                    {activeBand.label}
                  </span>
                  <span className="text-meta text-muted-foreground">
                    {sorted.length === 0
                      ? 'Nothing in this band'
                      : `Showing ${(currentPage - 1) * perPage + 1}–${Math.min(currentPage * perPage, sorted.length)} of ${sorted.length}`}
                  </span>
                </div>
              </div>

              <div className="ml-auto flex items-center gap-2">
                <Pagination
                  onNext={() => setPage(currentPage + 1)}
                  onPrevious={() => setPage(currentPage - 1)}
                  page={currentPage}
                  pageCount={pageCount}
                />
                <Select
                  onValueChange={v => setPerPage(Number(v))}
                  value={String(perPage)}
                >
                  <SelectTrigger className="w-[104px]" size="sm">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {PAGE_SIZES.map(n => (
                      <SelectItem key={n} value={String(n)}>{n} / page</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            </div>

            {loading && incidents.length === 0 ? (
              <_QueueSkeleton />
            ) : incidents.length === 0 ? (
              <_EmptyState isProvincialAdmin={isProvincialAdmin} />
            ) : filtered.length === 0 ? (
              <_NoMatches onClear={clearFilters} />
            ) : pageRows.length === 0 ? (
              <_BandEmpty label={activeBand.label} onShowAll={() => setBand('all')} />
            ) : (
              <IncidentTable
                grouped={grouped}
                isProvincialAdmin={isProvincialAdmin}
                newIds={newIds}
                nextId={isProvincialAdmin ? null : waiting.rows[0]?.id ?? null}
                onOpen={openIncident}
                position={waiting.position}
                rows={pageRows}
              />
            )}
          </div>
        </div>
      </div>

      {/* ── Is this screen live? ────────────────────────────── */}
      {/* Sticky at the bottom, because the answer stops being reassuring the
          moment it needs scrolling to.

          Agency Admin only. A dispatcher may need to hold the queue still
          while they read a report, so they get the switch and the timestamp.
          A Provincial Admin dispatches nothing — nothing can be reordered
          under them mid-decision — so for them the page simply stays current
          and neither control is drawn. */}
      {!isProvincialAdmin && (
      <div className="sticky bottom-0 z-10 flex flex-wrap items-center gap-3 border-t border-[var(--color-surface-border)] bg-background/95 px-6 py-2 backdrop-blur md:px-7">
        <button
          aria-pressed={autoRefresh}
          className="inline-flex items-center gap-1.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] px-2.5 py-1 text-[12px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
          onClick={() => setAutoRefresh(v => !v)}
          type="button"
        >
          {autoRefresh ? <Pause size={12} /> : <Play size={12} />}
          Auto refresh
          <span
            style={{
              color: autoRefresh
                ? 'var(--color-system-success)'
                : 'var(--color-system-warning)',
            }}
          >
            {autoRefresh ? 'on' : 'off'}
          </span>
        </button>

        {!autoRefresh && (
          <Button onClick={() => load(false)} size="sm" variant="outline">
            <RefreshCw data-icon="inline-start" />
            Refresh now
          </Button>
        )}

        <span className="text-meta ml-auto text-muted-foreground">
          {lastSync
            ? `Last updated ${lastSync.toLocaleTimeString()}`
            : 'Never updated'}
        </span>
      </div>
      )}

      <IncidentDetailModal incidentId={openId} onClose={() => setOpenId(null)} />
    </div>
  );
}

/**
 * "1 new report just arrived" - the strip above the queue.
 *
 * Deliberately not the alert popup again. The popup interrupts once; this stays
 * for as long as the report is new and unseen, and it is where a dispatcher who
 * dismissed the popup, or was on another page when it fired, finds out that
 * something came in and gets to it in one press.
 */
function _JustInStrip({
  rows,
  onShow,
  onOpen,
  onDismiss,
}: {
  rows: QueueIncident[];
  onShow: () => void;
  onOpen: (id: string) => void;
  onDismiss: () => void;
}) {
  const newest = rows[0];
  const sev = sevOf(newest) ?? 'untriaged';
  const sevColor = SEV_COLOR[sev] ?? 'var(--color-text-muted)';
  const category = newest.incident_category && newest.incident_category !== 'other'
    ? (CATEGORY_LABELS[newest.incident_category] ?? null)
    : null;
  const place = newest.location_address?.trim() || 'No location given';
  const headline = rows.length === 1
    ? 'A new report just arrived'
    : `${rows.length} new reports arrived in the last 10 minutes`;

  return (
    <div
      className="flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border px-4 py-3"
      data-just-in={rows.length}
      role="status"
      style={{
        borderColor: 'color-mix(in srgb, var(--color-brand) 45%, transparent)',
        backgroundColor: 'color-mix(in srgb, var(--color-brand) 8%, transparent)',
      }}
    >
      <span
        aria-hidden="true"
        className="flex size-9 shrink-0 items-center justify-center rounded-full"
        style={{
          backgroundColor: 'color-mix(in srgb, var(--color-brand) 16%, transparent)',
          color: 'var(--color-brand)',
        }}
      >
        <Siren size={17} />
      </span>
      <div className="min-w-0 flex-1 basis-[220px]">
        <p className="text-[13.5px] font-semibold text-foreground">{headline}</p>
        <p className="mt-0.5 truncate text-[12.5px] text-muted-foreground">
          <span className="font-semibold" style={{ color: sevColor }}>
            {SEVERITY_LABEL[sev] ?? sev}
          </span>
          {category ? ` · ${category}` : ''}
          {` · ${place}`}
        </p>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        <Button onClick={onShow} size="sm">
          Show in list
        </Button>
        <Button onClick={() => onOpen(newest.id)} size="sm" variant="outline">
          Open
        </Button>
        <button
          aria-label="Dismiss this notice"
          className="flex size-7 items-center justify-center rounded-[var(--radius-sm)] text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
          onClick={onDismiss}
          type="button"
        >
          <X size={14} />
        </button>
      </div>
    </div>
  );
}

/**
 * Page controls.
 *
 * Numbered, not just prev/next: "page 4 of 9" is a position, and a dispatcher
 * who has walked three pages into a busy queue needs to be able to get back to
 * the top of the working order in one press rather than three.
 */

// ── Empty states ─────────────────────────────────────────────
/**
 * Worded per role, per the same distinction as everything else on this page:
 * an Agency Admin has nothing left TO DO; a Provincial Admin has nothing left
 * TO WATCH. Same fact, different relationship to it.
 */
function _EmptyState({ isProvincialAdmin }: { isProvincialAdmin: boolean }) {
  return (
    <div className="flex flex-col items-center justify-center gap-4 py-20">
      <div
        className="flex size-16 items-center justify-center rounded-full"
        style={{ backgroundColor: 'var(--color-system-success-bg)' }}
      >
        <CheckCircle className="size-8" style={{ color: 'var(--color-system-success)' }} />
      </div>
      <div className="text-center">
        <p className="text-[18px] font-bold text-foreground">
          {isProvincialAdmin ? 'No incidents to monitor' : 'No incidents to manage'}
        </p>
        <p className="mt-1 text-[14px] text-muted-foreground">
          {isProvincialAdmin
            ? 'There are currently no incidents reported across your agency’s stations.'
            : 'There are currently no incidents requiring action at your station.'}
          {' '}Refreshes every {incidentPrefs.get().refreshSeconds}s.
        </p>
      </div>
    </div>
  );
}

/**
 * Distinct from "All clear" on purpose.
 *
 * A filter that matches nothing and an empty queue look identical if they
 * share a screen, and telling a dispatcher "all clear" while thirty incidents
 * sit behind an unnoticed filter is the worst lie this page could tell.
 */
function _NoMatches({ onClear }: { onClear: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16">
      <p className="text-[15px] font-semibold text-foreground">
        No incidents match these filters
      </p>
      <p className="text-[13px] text-muted-foreground">
        The queue is not empty — the filters above are hiding everything in it.
      </p>
      <Button className="mt-1" onClick={onClear} size="sm" variant="outline">
        <FilterX data-icon="inline-start" />
        Clear filters
      </Button>
    </div>
  );
}

/**
 * This band is empty, but the console is not.
 *
 * Separate from both states above, because "nothing is waiting on you" is good
 * news and "the queue is empty" is different news — and a dispatcher looking
 * at an empty On scene band must not read it as either.
 */
function _BandEmpty({ label, onShowAll }: { label: string; onShowAll: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 py-16">
      <p className="text-[14px] font-semibold text-foreground">
        Nothing in {label.toLowerCase()}
      </p>
      <p className="text-[13px] text-muted-foreground">
        Other bands still hold open incidents.
      </p>
      <Button className="mt-1" onClick={onShowAll} size="sm" variant="outline">
        <Eye data-icon="inline-start" />
        Show all open
      </Button>
    </div>
  );
}

// ── Skeleton ─────────────────────────────────────────────────
function _QueueSkeleton() {
  return (
    <div className="flex flex-col">
      {Array.from({ length: 6 }).map((_, i) => (
        <div
          className="flex animate-pulse items-center gap-4 border-b border-[var(--color-surface-border)] px-4 py-4 last:border-b-0"
          key={i}
        >
          {/* bg-muted, not a literal grey. A hardcoded #f5f5f5 cannot be
              re-pointed by a theme, so the skeleton used to render as
              near-white blocks on a near-black card in dark mode. */}
          <div className="h-3 w-8 shrink-0 rounded bg-muted" />
          <div className="flex-1 space-y-2">
            <div className="h-3.5 rounded bg-muted" style={{ width: `${60 + i * 4}%` }} />
            <div className="h-3 w-1/3 rounded bg-muted" />
          </div>
          <div className="h-5 w-24 shrink-0 rounded-full bg-muted" />
          <div className="h-3 w-10 shrink-0 rounded bg-muted" />
        </div>
      ))}
    </div>
  );
}
