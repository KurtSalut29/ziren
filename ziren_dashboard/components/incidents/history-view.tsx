'use client';

/**
 * Incident Records — every report, whatever became of it, as a record.
 *
 * This page used to be "Incident History": six monitoring tiles and a list of
 * cards with elapsed-time clocks and a View button. That is how you watch work
 * in progress, and this page is not that — the live queue is. This is the
 * archive: a flat table, one row per incident, one column per fact, each with a
 * citable record number, and a record panel behind every row holding the rest.
 * The tiles went with the monitoring; one summary line replaces them.
 *
 * The route stays /incident-history so existing links and bookmarks keep
 * working; only what the page is called and shows changed.
 *
 * WHAT WAS WRONG WITH THE DATA SOURCE (fixed earlier, still worth knowing)
 *
 * This page fetched /dispatch/queue, which excludes resolved and cancelled by
 * design. A history view built on the queue can only ever list what is still
 * open — under a heading promising the opposite. Its own status filter offered
 * "Resolved" and "Cancelled", and neither could ever match a single row.
 *
 * It now reads /dispatch/history, which returns every status.
 *
 * PAGED, NOT CAPPED
 *
 * Every other list on this console takes a ceiling because it is naturally
 * bounded — the queue by how many incidents are open, the charts by a 14-day
 * window. History is bounded by nothing: it is every report the province has
 * ever filed. A cap on it would silently hide the past rather than the excess,
 * so this pages instead, and states the unpaged total so "100 shown" can never
 * be mistaken for "100 exist".
 *
 * FILTERS RUN ON THE SERVER
 *
 * Status, severity and the date window are query parameters, not a client-side
 * pass over a fetched page. Filtering a page after fetching it returns a page
 * that is mostly empty whenever a filter is narrow, which reads as "nothing
 * matched" when it means "nothing matched ON THIS PAGE". Free-text search is
 * the exception and is deliberately local — see the note on it below.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Circle, HelpCircle, History, MapPinned, Radio, RefreshCw, X } from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  fetchHistory,
  type HistoryCounts,
  type HistoryIncident,
  type SeverityLevel,
} from '@/lib/api/dispatch';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import { FilterField } from '@/components/ui/filter-field';
import { OptionPicker } from '@/components/ui/option-picker';
import { Pagination } from '@/components/ui/pagination';
import { SearchInput } from '@/components/ui/search-input';
import type { OptionItem } from '@/components/ui/option-dialog';
import { PeriodPicker } from '@/components/ui/period-picker';
import { periodWords, phToday, type Range } from '@/components/ui/period';
import { IncidentRecordTable, recordSearchText } from '@/components/incidents/incident-record-table';
import {
  CATEGORY_ICON, SEV_COLOR, SEV_ICON, STATUS_ICON, STATUS_STYLE, statusLabel,
} from '@/components/incidents/incident-vocabulary';
import { displayPrefs, incidentPrefs } from '@/lib/prefs/definitions';
import { useArrivals } from '@/lib/incidents/arrivals';
import { IncidentDetailModal } from '@/components/incidents/incident-detail-modal';
import { CATEGORY_LABELS, REAL_CATEGORIES } from '@/lib/charts/queue-series';


import { DemoTarget } from '@/components/help/demo-target';
const STATUSES = [
  'received', 'processing', 'dispatched', 'en_route', 'arrived',
  'resolved', 'cancelled',
] as const;

const SEVERITIES: SeverityLevel[] = ['critical', 'high', 'medium', 'low'];

/** The tint every filter dialog's "no filter" row uses — a plain ring, so it reads as "nothing chosen" without competing with the coloured rows beneath it. */
const NEUTRAL = 'var(--color-text-tertiary)';

const STATUS_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any status', icon: Circle, color: NEUTRAL },
  // Not a status a row can have — everything still being worked. The server
  // reads it as "neither resolved nor cancelled".
  { value: 'open', label: 'Open now', icon: Radio, color: 'var(--color-brand)' },
  ...STATUSES.map(st => ({ value: st, label: statusLabel(st), icon: STATUS_ICON[st], color: STATUS_STYLE[st].text })),
];

const SEVERITY_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any severity', icon: Circle, color: NEUTRAL },
  ...SEVERITIES.map(sv => ({ value: sv, label: statusLabel(sv), icon: SEV_ICON[sv], color: SEV_COLOR[sv] })),
];

const TYPE_OPTIONS: OptionItem[] = [
  { value: 'all', label: 'Any type', icon: Circle, color: NEUTRAL },
  ...REAL_CATEGORIES.map(c => ({ value: c, label: CATEGORY_LABELS[c], icon: CATEGORY_ICON[c] })),
  { value: 'other', label: 'Uncategorised', icon: HelpCircle },
];

const EMPTY_COUNTS: HistoryCounts = {
  total: 0, critical: 0, resolved: 0, cancelled: 0, avg_response_minutes: null,
  stations_with_incidents: 0,
};

export function IncidentHistoryView({ initialStatus }: { initialStatus?: string | null }) {
  const { token, isProvincialAdmin } = useAuth();

  const [items, setItems]   = useState<HistoryIncident[]>([]);
  const [total, setTotal]   = useState(0);
  const [counts, setCounts] = useState<HistoryCounts>(EMPTY_COUNTS);
  const [loading, setLoading] = useState(true);
  const [error, setError]   = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  // The narrative report is a page of its own, not a dialog over this table -
  // the form it holds is the whole Incident Record Form. See NarrativeEditor.
  const router = useRouter();

  // Server-side filters.
  // Rows per page and the window this page opens on are the operator's own
  // (Settings → Incident Preferences). The server caps a page at 100.
  const { recordsPerPage: PAGE_SIZE, refreshSeconds } = incidentPrefs.use();
  const display = displayPrefs.use();
  // A link can arrive already narrowed to a status (?status=open — where a
  // Provincial Admin lands from the old Incident Monitoring address and the
  // alert's "open the queue"). It is handed in by the route, which reads the
  // address reactively: reading window.location here saw the PREVIOUS url during
  // a client-side redirect, so the first request went out unfiltered. Only values
  // the filter offers are honoured. Open reports are wanted whatever their age,
  // so that link also opens on All time instead of the operator's usual window.
  const linkedStatus =
    initialStatus === 'open' || (STATUSES as readonly string[]).includes(initialStatus ?? '')
      ? initialStatus
      : null;
  const [days, setDays]           = useState<number>(() => (linkedStatus === 'open' ? 0 : incidentPrefs.get().historyDays));
  const [status, setStatus]       = useState(linkedStatus ?? 'all');
  const [severity, setSeverity]   = useState('all');
  // Provincial Admin only — see the note beside the Select below for why
  // this replaced an agency-type filter rather than sitting next to it.
  const [stationId, setStationId] = useState('all');
  const [category, setCategory]   = useState('all');
  // An exact calendar range, e.g. picking one date twice for a specific day,
  // or a month/year's first and last date — chosen in the same Custom dialog
  // as Operational Area's own Period control. Wins over `days` on the server
  // — and is disabled below — the moment it is set, so the two can never
  // silently disagree about what window is actually showing.
  const [range, setRange]         = useState<Range | null>(null);
  const [page, setPage]           = useState(0);
  // "Today" for the picker's Custom dialog — computed once; this page has no
  // reason to re-tick it the way a page showing "updated Ns ago" would.
  const [today]                   = useState(() => phToday());

  const hasCustomRange = range !== null;

  // Local filter — see the note in load().
  const [q, setQ] = useState('');

  // `silent` is a re-read of what is already on screen - the poll, or a report
  // that has just arrived. It must not blank the table, disable the pager or
  // swap a failed refresh for an error banner over data that is still good.
  const load = useCallback(async (silent = false) => {
    if (!token) return;
    if (!silent) {
      setLoading(true);
      setError(null);
    }
    try {
      const res = await fetchHistory(token, {
        // Omit `days` once a custom range is in play — the server treats
        // either date bound as authoritative over it, but sending both would
        // misdescribe what was actually asked for if that precedence ever
        // changes on one side and not the other. `days` may be 0 (All time),
        // which the server now treats as "no window" the same way Operational
        // Area's own backend does.
        days: hasCustomRange ? undefined : days,
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
        status: status === 'all' ? undefined : status,
        severity: severity === 'all' ? undefined : severity,
        station_id: stationId === 'all' ? undefined : stationId,
        category: category === 'all' ? undefined : category,
        date_from: range?.from,
        date_to: range?.to,
      });
      setItems(res.items);
      setTotal(res.total);
      // Defensive default: an older backend that predates window counts would
      // omit the key, and the tiles reading `undefined` render as NaN.
      setCounts(res.counts ?? EMPTY_COUNTS);
      if (silent) setError(null);
    } catch (err: unknown) {
      if (err instanceof ApiError && err.status === 401) { signOut(); return; }
      if (silent) return;
      setError(
        err instanceof ApiError ? err.message : 'Failed to load incident history.',
      );
    } finally {
      if (!silent) setLoading(false);
    }
  }, [token, days, status, severity, stationId, category, range, page, hasCustomRange, PAGE_SIZE]);

  useEffect(() => { load(); }, [load]);

  // KEEPING THE RECORD CURRENT
  //
  // This page used to read the server once, when it opened, and never again. A
  // report filed while it was on screen simply did not exist here until the tab
  // was reloaded - so a dispatcher who was told "New report from a resident",
  // opened it, and came back to Incident Records found nothing, which reads as a
  // report that vanished. Two things fix it, and both only apply to the first
  // page, where newest-first puts a new report: a re-read on a timer, and an
  // immediate one the moment the alert hook sees something arrive. Deeper pages
  // are left alone - a list that shifts under a reader who is partway down it is
  // worse than one that is a minute old.
  useEffect(() => {
    if (page !== 0) return;
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') void load(true);
    }, Math.max(refreshSeconds, 15) * 1000);
    return () => clearInterval(id);
  }, [load, page, refreshSeconds]);

  useArrivals(() => { if (page === 0) void load(true); });

  // Changing a filter has to reset the page. Without this, narrowing while on
  // page 4 requests rows 400–499 of a result set that may now hold twelve, and
  // the page renders empty for a filter that plainly matched something.
  useEffect(() => {
    setPage(0);
  }, [days, status, severity, stationId, category, range, PAGE_SIZE]);

  /**
   * The Station dropdown's options — built from whatever page is currently
   * loaded, same as Incident Monitoring's own Station filter (see
   * active-view.tsx). Known limitation, inherited on purpose rather than
   * solved differently here: a station with nothing in the current window
   * won't appear until something of its is. Good enough for "narrow what
   * I'm already looking at"; a full roster belongs to /stations, not a
   * history filter.
   */
  const stations = useMemo(() => {
    const map = new Map<string, string>();
    for (const i of items) {
      if (i.station_id && i.stations?.name) map.set(i.station_id, i.stations.name);
    }
    return [...map.entries()]
      .map(([id, name]) => ({ id, name }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [items]);

  const stationOptions = useMemo<OptionItem[]>(() => [
    { value: 'all', label: 'All stations', icon: Circle, color: NEUTRAL },
    ...stations.map(s => ({ value: s.id, label: s.name, icon: MapPinned })),
  ], [stations]);

  /**
   * Free-text search stays LOCAL, unlike every filter in the bar above it.
   *
   * The server cannot answer it without a full-text index across report_text,
   * the reporter's name and the address, and a `LIKE '%…%'` over the whole
   * incidents table would degrade as the history grows — the exact thing this
   * page exists to accommodate. Searching within the loaded page is honest as
   * long as the UI says so, which the result line below does.
   */
  const shown = useMemo(() => {
    // Every word typed must match SOMEWHERE in the row, in any order, so
    // "fire naval" finds a fire at the Naval station without the reader
    // having to know which column each word lives in. What is searched is
    // everything the table shows — see recordSearchText.
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (words.length === 0) return items;
    return items.filter(i => {
      const haystack = recordSearchText(i, display);
      return words.every(w => haystack.includes(w));
    });
  }, [items, q, display]);

  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const firstRow = total === 0 ? 0 : page * PAGE_SIZE + 1;
  const lastRow = Math.min(total, (page + 1) * PAGE_SIZE);

  // The counts now come from the server and describe the whole filtered
  // window — see HistoryCounts. Deriving them from `items` meant four figures
  // about one page of a hundred, sitting under a heading that named a month.

  const scopeLine = `${isProvincialAdmin ? 'Province-wide' : 'Your agency'} · ${periodWords(days, range)}`;

  // The summary line above the table. First part is the headline count and is
  // set bolder; the rest are the disjoint facts the old tiles carried.
  const summary = [
    `${total.toLocaleString()} record${total === 1 ? '' : 's'}`,
    scopeLine,
    ...(total > 0
      ? [
          `${counts.critical.toLocaleString()} critical`,
          `${counts.resolved.toLocaleString()} resolved`,
          `${counts.cancelled.toLocaleString()} cancelled`,
          ...(counts.avg_response_minutes !== null
            ? [`avg. time to dispatch ${Math.round(counts.avg_response_minutes)}m`]
            : []),
        ]
      : []),
  ];

  const filtersOn =
    status !== 'all' || severity !== 'all' || stationId !== 'all' ||
    category !== 'all' || q.trim() !== '' || hasCustomRange;

  return (
    <div className="min-h-full">
      {/* ── Filters ─────────────────────────────────────────── */}
      {/* top-0, not top-11: this is its own sidebar route now (Incident
          History), not a tab under a shell that reserved the first 44px. */}
      <div data-demo="records:filters" className="sticky top-0 z-20 border-b border-[var(--color-surface-border)] bg-background/95 px-6 py-3.5 backdrop-blur md:px-7">
        <div className="flex flex-wrap items-end gap-x-5 gap-y-3.5">
          {/* Captioned fields that fill the row, the same pattern as Operational
              Area's own filter tier — each control says what it is before it is
              read, and the row shares its width instead of a cluster of bare
              controls huddled left with room going unused on the right. The
              lookup-by-record-number box that used to live here is gone: the
              free-text search below already reaches every loaded row, and a
              second, server-side way to find one record added a control this
              bar did not need. */}
          <DemoTarget id="records:period"><FilterField className="max-sm:w-full sm:flex-[2.2_1_400px]" label="Period">
            <PeriodPicker days={days} onDays={setDays} onRange={setRange} range={range} size="sm" today={today} />
          </FilterField></DemoTarget>

          <FilterField className="max-sm:w-[calc(50%-10px)] sm:flex-[1_1_150px]" label="Status">
            <OptionPicker
              label="Choose a status"
              onChange={setStatus}
              options={STATUS_OPTIONS}
              placeholder="Any status"
              value={status}
            />
          </FilterField>

          <FilterField className="max-sm:w-[calc(50%-10px)] sm:flex-[1_1_150px]" label="Severity">
            <OptionPicker
              label="Choose a severity"
              onChange={setSeverity}
              options={SEVERITY_OPTIONS}
              placeholder="Any severity"
              value={severity}
            />
          </FilterField>

          {/* Agency Admin has exactly one station — this filter would always
              be a no-op for them. Provincial Admin's own agency_type is
              already pinned server-side (see get_incident_history's role
              check), so an agency-type filter here could only ever narrow
              to "my own type" or "nothing" — it used to offer the other two
              types and silently return zero rows if picked. Station is the
              axis that's actually meaningful once several are in scope. */}
          {isProvincialAdmin && (
            <FilterField className="max-sm:w-[calc(50%-10px)] sm:flex-[1_1_160px]" label="Station">
              <OptionPicker
                label="Choose a station"
                onChange={setStationId}
                options={stationOptions}
                placeholder="All stations"
                value={stationId}
              />
            </FilterField>
          )}

          <FilterField className="max-sm:w-[calc(50%-10px)] sm:flex-[1_1_150px]" label="Type">
            <OptionPicker
              label="Choose an incident type"
              onChange={setCategory}
              options={TYPE_OPTIONS}
              placeholder="Any type"
              value={category}
            />
          </FilterField>

          {filtersOn && (
            <Button
              className="self-end"
              onClick={() => {
                setStatus('all'); setSeverity('all');
                setStationId('all'); setCategory('all'); setQ('');
                setRange(null);
              }}
              variant="ghost"
            >
              Clear
            </Button>
          )}

          {/* The unpaged total, always. "100 shown" without it cannot be told
              apart from "100 exist". */}
          <span className="ml-auto shrink-0 self-end pb-1.5 text-meta text-muted-foreground">
            {total === 0
              ? 'No records in this window'
              : q.trim()
                ? `${shown.length} matching on this page · ${firstRow}–${lastRow} of ${total}`
                : `${firstRow}–${lastRow} of ${total}`}
          </span>
        </div>
      </div>

      <div className="space-y-5 px-6 py-5 md:px-7">
        {error && (
          <div className="flex items-start gap-3">
            <div className="flex-1"><Alert message={error} variant="error" /></div>
            <Button onClick={() => load()} size="sm" variant="outline">
              <RefreshCw data-icon="inline-start" />
              Retry
            </Button>
          </div>
        )}

        {/* One line, where six monitoring tiles were. The tiles answered "how
            is the response going" — a live-operations question. This page is
            the record, so the summary just says what is in the table: how many
            records, over what scope, and the same disjoint facts the tiles
            carried (critical is a severity; resolved and cancelled are the two
            ways a status closes; none overlap). They come from the server and
            describe the WHOLE filtered window, not the page shown, and they go
            through the same filters as the rows, so this line can never
            disagree with the table beneath it. */}
        {/* The search sits at the right end of this line, not up in the filter
            bar: it searches the rows this line describes, so it reads best
            beside them. It wraps under the summary on a narrow screen rather
            than squeezing it. */}
        <div data-demo="records:summary" className="flex flex-wrap items-center justify-between gap-x-6 gap-y-3">
          <p className="flex min-w-0 flex-wrap items-baseline gap-x-2 gap-y-1 text-[13px] text-muted-foreground">
            {summary.map((part, i) => (
              <span className="flex items-baseline gap-2" key={i}>
                {i > 0 && <span aria-hidden="true">·</span>}
                <span className={i === 0 ? 'font-semibold tabular-nums text-foreground' : 'tabular-nums'}>
                  {part}
                </span>
              </span>
            ))}
          </p>

          <div className="flex min-w-0 flex-wrap items-center gap-3 sm:ml-auto sm:flex-1 sm:basis-[340px] sm:justify-end">
            {/* Takes the room the summary leaves (at least 240px, at most 460px)
                instead of a fixed width, so it is as wide as the row allows and
                still ends at the right edge of the table. */}
            <DemoTarget id="records:search"><SearchInput
              className="min-w-[240px] max-w-[460px] flex-1"
              label="Search these records"
              onValueChange={setQ}
              placeholder="Search records…"
              title="Searches every column of the records loaded on this page"
              value={q}
            /></DemoTarget>
          </div>
        </div>

        {loading && items.length === 0 ? (
          <_HistorySkeleton />
        ) : total === 0 ? (
          <_Empty
            days={days}
            filtered={
              status !== 'all' || severity !== 'all' ||
              stationId !== 'all' || category !== 'all' ||
              hasCustomRange
            }
            isProvincialAdmin={isProvincialAdmin}
          />
        ) : shown.length === 0 ? (
          <_NoMatches onClear={() => setQ('')} pageSize={PAGE_SIZE} />
        ) : (
          <DemoTarget id="records:table"><IncidentRecordTable
            display={display}
            isProvincialAdmin={isProvincialAdmin}
            onNarrative={id => router.push(`/narrative-reports/${id}`)}
            onOpen={setOpenId}
            // The page's own bottom padding, and the pager under the table when
            // there is more than one page of records.
            reserveBottom={pages > 1 ? 84 : 32}
            rows={shown}
          /></DemoTarget>
        )}

        {pages > 1 && (
          <Pagination
            className="border-t border-[var(--color-surface-border)] pt-4"
            disabled={loading}
            onNext={() => setPage(p => p + 1)}
            onPrevious={() => setPage(p => Math.max(0, p - 1))}
            page={page + 1}
            pageCount={pages}
          />
        )}
      </div>

      <IncidentDetailModal incidentId={openId} isHistory onClose={() => setOpenId(null)} />
    </div>
  );
}

function _HistorySkeleton() {
  // Rows of the same rhythm as the table that replaces it, in one frame, so
  // the page does not jump from a stack of cards to a grid when data lands.
  return (
    <div
      className="animate-pulse overflow-hidden rounded-[var(--radius-card)] border bg-card"
      style={{ borderColor: 'var(--color-surface-border)' }}
    >
      {Array.from({ length: 8 }).map((_, i) => (
        <div
          className="flex items-center gap-4 border-b border-[var(--color-surface-border)] px-3 py-4 last:border-b-0"
          key={i}
        >
          <div className="h-3 w-28 rounded bg-muted" />
          <div className="h-3 w-24 rounded bg-muted" />
          <div className="h-3 flex-1 rounded bg-muted" style={{ maxWidth: `${55 + (i % 4) * 8}%` }} />
          <div className="h-3 w-20 rounded bg-muted" />
        </div>
      ))}
    </div>
  );
}

/**
 * Two different nothings.
 *
 * "No incidents in the last 30 days" and "no incidents match these filters"
 * look identical if they share a screen, and only one of them means the
 * province had a quiet month. The supporting line also names the SCOPE —
 * "your station" vs. "your agency's stations" — so it can't be misread as
 * "there is no history anywhere" from a view that only ever showed one
 * slice of it.
 */
function _Empty({
  days, filtered, isProvincialAdmin,
}: { days: number; filtered: boolean; isProvincialAdmin: boolean }) {
  const scope = isProvincialAdmin ? "your agency's stations" : 'your station';
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-20">
      <div
        className="flex size-14 items-center justify-center rounded-full"
        style={{ backgroundColor: 'var(--color-surface-raised)' }}
      >
        <History className="size-7 text-muted-foreground" />
      </div>
      <p className="text-[15px] font-semibold text-foreground">
        {filtered
          ? 'Nothing matches these filters'
          : days > 0
            ? `No records from ${scope} in the last ${days} days`
            : `No records from ${scope} yet`}
      </p>
      <p className="text-[13px] text-muted-foreground">
        {filtered
          ? `Widen the status, severity or date window above, or try a wider search across ${scope}.`
          : days > 0
            ? 'Try a longer window — history only reaches back as far as it is asked to.'
            : 'Once a report comes in, it will show up here.'}
      </p>
    </div>
  );
}

function _NoMatches({ onClear, pageSize }: { onClear: () => void; pageSize: number }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-16">
      <p className="text-[15px] font-semibold text-foreground">
        No match on this page
      </p>
      {/* Says exactly what it searched. A reader who assumes this covered the
          whole history would conclude a report does not exist when it is two
          pages away. */}
      <p className="max-w-md text-center text-[13px] text-muted-foreground">
        Search looks at the {pageSize} rows currently loaded, not the whole
        window. Try the next page, or narrow with the status and severity
        filters, which do run across everything.
      </p>
      <Button className="mt-1" onClick={onClear} size="sm" variant="outline">
        <X data-icon="inline-start" />
        Clear search
      </Button>
    </div>
  );
}
