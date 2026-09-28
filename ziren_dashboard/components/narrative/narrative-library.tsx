'use client';

/**
 * NarrativeLibrary - every narrative report an agency has written, in one place.
 *
 * A narrative report used to be reachable only from the row of the incident it
 * was about, so the finished ones were scattered through Incident Records and
 * there was no way to look at them as a body of work. This is that: a filing
 * cabinet. Every report, newest first, and the drawer labels are the kinds of
 * incident - Fire, Medical / trauma, Vehicular, Flood / landslide, Dispute /
 * crime, Other - each with a count, so an agency can pull out every fire report it
 * has written, or every crime report from last quarter, without opening
 * anything.
 *
 * Two views:
 *
 *   Reports             What has been written: drafts and finalized ones, filtered
 *                       by incident type, status and when it was last saved.
 *   Awaiting a report   Resolved incidents nobody has written up yet - what
 *                       to do next. Agency Admin only: a Provincial Admin files
 *                       nothing on another station's behalf.
 *
 * The counts on the tabs come from the server and describe the OTHER filters
 * (see list_narrative_reports), so a tab never promises a report the list will
 * not show.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  CheckCircle2, Circle, Download, FilePenLine, FileText, HelpCircle, LayoutGrid,
  Loader2, RefreshCw, ShieldCheck,
} from 'lucide-react';
import {
  downloadNarrativeReportPdf, fetchHistory, fetchNarrativeReports,
  type HistoryIncident, type NarrativeLibrary as Library, type NarrativeListItem,
} from '@/lib/api/dispatch';
import { ApiError } from '@/lib/api/client';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { toast } from '@/lib/toast';
import { formatDate, formatTime } from '@/lib/format/datetime';
import { displayPrefs, type DisplayPrefs } from '@/lib/prefs/definitions';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import { FilterField } from '@/components/ui/filter-field';
import { NavTabs } from '@/components/ui/nav-tabs';
import { OptionPicker } from '@/components/ui/option-picker';
import { Pagination } from '@/components/ui/pagination';
import { PeriodPicker } from '@/components/ui/period-picker';
import { SearchInput } from '@/components/ui/search-input';
import { periodWords, phToday, type Range } from '@/components/ui/period';
import type { OptionItem } from '@/components/ui/option-dialog';
import {
  AGENCY_ICON, AG_COLOR, CATEGORY_ICON,
} from '@/components/incidents/incident-vocabulary';

const PAGE_SIZE = 25;

/** The drawer labels, in the wizard's own order, then the catch-all. */
const TYPES = [
  'fire', 'medical_trauma', 'vehicular', 'flood_landslide_calamity', 'domestic_dispute_crime', 'other',
] as const;
const TYPE_LABEL: Record<string, string> = { ...CATEGORY_LABELS, other: 'Other' };

type Mode = 'reports' | 'awaiting';
type StatusFilter = 'all' | 'finalized' | 'draft';

const NEUTRAL = 'var(--color-text-tertiary)';

function typeIcon(key: string) {
  return CATEGORY_ICON[key] ?? HelpCircle;
}

export function NarrativeLibrary() {
  const { token, isProvincialAdmin, hydrated } = useAuth();
  const display = displayPrefs.use();

  const [mode, setMode] = useState<Mode>('reports');
  const [category, setCategory] = useState<string>('all');
  const [status, setStatus] = useState<StatusFilter>('all');
  const [days, setDays] = useState(0);
  const [range, setRange] = useState<Range | null>(null);
  const [today] = useState(() => phToday());
  const [page, setPage] = useState(0);
  const [q, setQ] = useState('');

  const [data, setData] = useState<Library | null>(null);
  const [awaiting, setAwaiting] = useState<HistoryIncident[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [updatedAt, setUpdatedAt] = useState<Date | null>(null);
  const [downloading, setDownloading] = useState<string | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!token) return;
    if (!silent) { setLoading(true); setError(null); }
    try {
      const res = await fetchNarrativeReports(token, {
        category: category === 'all' ? undefined : category,
        status: status === 'all' ? undefined : status,
        days: range ? undefined : days,
        date_from: range?.from,
        date_to: range?.to,
        limit: PAGE_SIZE,
        offset: page * PAGE_SIZE,
      });
      setData(res);
      setUpdatedAt(new Date());
      setError(null);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      if (!silent) setError(e instanceof Error ? e.message : 'Could not load the narrative reports.');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [token, category, status, days, range, page]);

  useEffect(() => { void load(); }, [load]);

  // Any change to WHAT is listed starts the reader at the top again.
  useEffect(() => { setPage(0); }, [category, status, days, range]);

  // Coming back to the tab after writing a report elsewhere: it is already here.
  useEffect(() => {
    const onVisible = () => { if (document.visibilityState === 'visible') void load(true); };
    document.addEventListener('visibilitychange', onVisible);
    return () => document.removeEventListener('visibilitychange', onVisible);
  }, [load]);

  // Resolved incidents with no report - the work still to do. One read of the
  // last quarter of resolved incidents, filtered here to the ones with no report.
  const loadAwaiting = useCallback(async () => {
    if (!token || isProvincialAdmin) return;
    try {
      const res = await fetchHistory(token, { status: 'resolved', days: 90, limit: 100 });
      setAwaiting(res.items.filter(i => !i.narrative_report_status));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setAwaiting([]);
    }
  }, [token, isProvincialAdmin]);
  useEffect(() => { void loadAwaiting(); }, [loadAwaiting]);

  async function download(item: NarrativeListItem) {
    if (!token) return;
    setDownloading(item.incident_id);
    try {
      await downloadNarrativeReportPdf(item.incident_id, token);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Could not download the PDF.');
    } finally {
      setDownloading(null);
    }
  }

  // ── What is on screen ───────────────────────────────────────────────────
  const counts = data?.counts;
  const total = data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  const shown = useMemo(() => {
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    const items = data?.items ?? [];
    if (words.length === 0) return items;
    return items.filter(i => {
      const hay = [
        i.record_number, i.reference_no, i.reporting_person_name, i.place_of_incident, i.offense,
        i.prepared_by_name, i.investigator_name, i.station_name, i.agency_type, i.municipality,
        TYPE_LABEL[i.incident_category], i.status,
      ].filter(Boolean).join('\n').toLowerCase();
      return words.every(w => hay.includes(w));
    });
  }, [data, q]);

  const awaitingShown = useMemo(() => {
    const rows = (awaiting ?? []).filter(i => {
      if (category === 'all') return true;
      const cat = i.incident_category ?? 'other';
      return category === 'other' ? !CATEGORY_ICON[cat] : cat === category;
    });
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    if (words.length === 0) return rows;
    return rows.filter(i => {
      const hay = [i.record_number, i.location_address, i.users?.full_name, TYPE_LABEL[i.incident_category ?? 'other']]
        .filter(Boolean).join('\n').toLowerCase();
      return words.every(w => hay.includes(w));
    });
  }, [awaiting, category, q]);

  const statusOptions: OptionItem[] = [
    { value: 'all', label: `All statuses${counts ? ` (${counts.by_status.draft + counts.by_status.finalized})` : ''}`, icon: Circle, color: NEUTRAL },
    { value: 'finalized', label: `Finalized${counts ? ` (${counts.by_status.finalized})` : ''}`, icon: ShieldCheck, color: 'var(--color-system-success)' },
    { value: 'draft', label: `Drafts${counts ? ` (${counts.by_status.draft})` : ''}`, icon: FilePenLine, color: 'var(--color-system-warning)' },
  ];

  const filtersOn = category !== 'all' || status !== 'all' || range !== null || days !== 0 || q.trim() !== '';
  const clearAll = () => { setCategory('all'); setStatus('all'); setRange(null); setDays(0); setQ(''); };

  if (!hydrated) return null;

  return (
    <div className="min-h-full">
      {/* ── Filters ── */}
      <div className="sticky top-0 z-20 border-b border-[var(--color-surface-border)] bg-background/95 px-6 py-3.5 backdrop-blur md:px-7">
        <div className="flex flex-wrap items-end gap-x-5 gap-y-3.5">
          {mode === 'reports' && (
            <>
              <FilterField className="max-sm:w-full sm:flex-[2.2_1_400px]" label="Last saved">
                <PeriodPicker days={days} onDays={setDays} onRange={setRange} range={range} size="sm" today={today} />
              </FilterField>
              <FilterField className="max-sm:w-full sm:flex-[1_1_170px]" label="Status">
                <OptionPicker
                  label="Choose a status"
                  onChange={v => setStatus(v as StatusFilter)}
                  options={statusOptions}
                  placeholder="All statuses"
                  value={status}
                />
              </FilterField>
            </>
          )}
          <div className="flex flex-1 basis-[440px] flex-wrap items-center justify-end gap-3 self-end">
            {mode === 'reports' && (
              <button
                aria-label="Refresh the list"
                className="inline-flex shrink-0 items-center gap-1.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] px-2.5 py-1.5 text-[12px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
                onClick={() => void load(true)}
                type="button"
              >
                <RefreshCw size={12} />
                {updatedAt ? `Updated ${updatedAt.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}` : 'Refresh'}
              </button>
            )}
            <SearchInput
              className="min-w-[220px] max-w-[420px] flex-1"
              label="Search narrative reports"
              onValueChange={setQ}
              placeholder="Search reports…"
              title="Searches every column of the reports on this page"
              value={q}
            />
          </div>
        </div>
      </div>

      <div className="space-y-5 px-6 py-5 md:px-7">
        {/* ── Reports / Awaiting — the same NavTabs every multi-view screen on
            this console uses (Operational Area, Verification), so a tab reads
            the same way wherever it appears. */}
        {!isProvincialAdmin && (
          <NavTabs
            activeKey={mode}
            ariaLabel="Narrative report view"
            onSelect={key => setMode(key as Mode)}
            tabs={[
              { key: 'reports', label: 'Reports', icon: FileText, badge: data ? counts?.all ?? 0 : undefined },
              { key: 'awaiting', label: 'Awaiting a report', icon: FilePenLine, badge: awaiting ? awaiting.length : undefined },
            ]}
          />
        )}

        {/* ── The drawer labels: kinds of incident ── */}
        <div aria-label="Filter by type of incident" className="flex flex-wrap gap-2" data-type-tabs role="group">
          {[
            { key: 'all', label: 'All types', Icon: LayoutGrid, n: mode === 'reports' ? counts?.all : awaiting?.length },
            ...TYPES.map(k => ({
              key: k,
              label: TYPE_LABEL[k],
              Icon: typeIcon(k),
              n: mode === 'reports'
                ? counts?.by_category[k]
                : (awaiting ?? []).filter(i => {
                    const c = i.incident_category ?? 'other';
                    return k === 'other' ? !CATEGORY_ICON[c] : c === k;
                  }).length,
            })),
          ].map(({ key, label, Icon, n }) => {
            const on = category === key;
            return (
              <button
                aria-pressed={on}
                className={`inline-flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-[13px] font-semibold transition-colors ${
                  on
                    ? 'border-transparent bg-foreground text-background'
                    : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground'
                }`}
                data-type={key}
                key={key}
                onClick={() => setCategory(key)}
                type="button"
              >
                <Icon size={14} />
                {label}
                {n !== undefined && (
                  <span className={`tabular-nums text-[12px] ${on ? 'opacity-80' : n === 0 ? 'opacity-40' : 'text-muted-foreground'}`}>
                    {n}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {error && (
          <div className="flex items-start gap-3">
            <div className="flex-1"><Alert message={error} variant="error" /></div>
            <Button onClick={() => void load()} size="sm" variant="outline">Retry</Button>
          </div>
        )}

        {mode === 'reports' ? (
          <>
            <p className="text-[13px] text-muted-foreground" data-summary>
              <span className="font-semibold tabular-nums text-foreground">{total.toLocaleString()} report{total === 1 ? '' : 's'}</span>
              {' · '}{category === 'all' ? 'All types' : TYPE_LABEL[category]}
              {' · '}{status === 'all' ? 'Finalized and drafts' : status === 'finalized' ? 'Finalized' : 'Drafts'}
              {' · '}{isProvincialAdmin ? 'Province-wide' : 'Your agency'} · {periodWords(days, range)}
              {q.trim() && ` · ${shown.length} match${shown.length === 1 ? '' : 'es'} on this page`}
            </p>

            {loading && !data ? (
              <_Skeleton />
            ) : shown.length === 0 ? (
              <_Empty
                body={
                  filtersOn
                    ? 'Nothing matches these filters. Try another type, or clear them.'
                    : isProvincialAdmin
                      ? 'The agencies you oversee have not written a narrative report yet.'
                      : 'Once you finalize a narrative report it is kept here. Open a resolved incident in Incident Records to write your first.'
                }
                onClear={filtersOn ? clearAll : undefined}
                title={filtersOn ? 'No reports found' : 'No narrative reports yet'}
              />
            ) : (
              <div className="overflow-x-auto rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
                <table className="w-full min-w-[980px] border-collapse text-left" data-library-table>
                  <thead>
                    <tr className="[&>th]:border-b [&>th]:border-[var(--color-surface-border)] [&>th]:px-4 [&>th]:py-2.5 [&>th]:text-[11px] [&>th]:font-bold [&>th]:uppercase [&>th]:tracking-[0.06em] [&>th]:text-[var(--color-text-tertiary)]">
                      <th className="w-[150px]">Type</th>
                      <th className="w-[170px]">Record / entry no.</th>
                      <th>Reporting person &amp; place</th>
                      <th className="w-[130px]">Saved</th>
                      <th className="w-[150px]">Prepared by</th>
                      <th className="w-[110px]">Status</th>
                      <th className="w-[190px] text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {shown.map(item => (
                      <_ReportRow
                        display={display}
                        downloading={downloading === item.incident_id}
                        item={item}
                        key={item.id}
                        onDownload={() => void download(item)}
                        readOnly={isProvincialAdmin}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
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
          </>
        ) : (
          <>
            <p className="text-[13px] text-muted-foreground" data-summary>
              Resolved in the last 90 days, with no narrative report yet.
              {' '}<span className="font-semibold tabular-nums text-foreground">{awaitingShown.length}</span> shown.
            </p>
            {awaiting === null ? (
              <_Skeleton />
            ) : awaitingShown.length === 0 ? (
              <_Empty
                body={awaiting.length === 0
                  ? 'Every incident resolved in the last 90 days has a narrative report. Nothing is waiting.'
                  : 'No waiting incident matches these filters.'}
                onClear={awaiting.length > 0 && (category !== 'all' || q.trim()) ? () => { setCategory('all'); setQ(''); } : undefined}
                title={awaiting.length === 0 ? 'All caught up' : 'Nothing found'}
              />
            ) : (
              <ul className="flex flex-col gap-2" data-awaiting-list>
                {awaitingShown.map(i => {
                  const cat = i.incident_category && CATEGORY_ICON[i.incident_category] ? i.incident_category : 'other';
                  const Icon = typeIcon(cat);
                  return (
                    <li
                      className="flex flex-wrap items-center gap-x-4 gap-y-2 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3"
                      data-awaiting-row
                      key={i.id}
                    >
                      <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]">
                        <Icon size={16} />
                      </span>
                      <div className="min-w-0 flex-1 basis-[260px]">
                        <p className="flex flex-wrap items-baseline gap-x-2">
                          <span className="font-mono text-[13px] font-semibold text-foreground">{i.record_number ?? i.id.slice(0, 8)}</span>
                          <span className="text-[12.5px] text-muted-foreground">{TYPE_LABEL[cat]}</span>
                        </p>
                        <p className="truncate text-[12.5px] text-muted-foreground">
                          {i.location_address ?? 'No location given'}
                          {i.users?.full_name ? ` · ${i.users.full_name}` : ''}
                        </p>
                      </div>
                      <span className="shrink-0 text-[12px] text-muted-foreground">
                        Resolved {i.resolved_at ? formatDate(i.resolved_at, display) : ''}
                      </span>
                      <Button asChild size="sm">
                        <Link href={`/narrative-reports/${i.id}`}>
                          <FilePenLine data-icon="inline-start" size={14} /> Write report
                        </Link>
                      </Button>
                    </li>
                  );
                })}
              </ul>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// ── Pieces ────────────────────────────────────────────────────────────────

function _ReportRow({
  item, display, downloading, readOnly, onDownload,
}: {
  item: NarrativeListItem;
  display: DisplayPrefs;
  downloading: boolean;
  readOnly: boolean;
  onDownload: () => void;
}) {
  const Icon = typeIcon(item.incident_category);
  const finalized = item.status === 'finalized';
  const AgIcon = item.agency_type ? AGENCY_ICON[item.agency_type] : null;
  const savedIso = finalized && item.finalized_at ? item.finalized_at : item.updated_at;
  const href = `/narrative-reports/${item.incident_id}`;

  return (
    <tr
      className="border-b border-[var(--color-surface-border)] align-top transition-colors last:border-b-0 hover:bg-[var(--color-surface-hover)]"
      data-report-row={item.id}
      data-report-status={item.status}
      data-report-type={item.incident_category}
    >
      <td className="px-4 py-3">
        <span className="inline-flex items-center gap-2 text-[13px] font-medium text-foreground">
          <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]">
            <Icon size={14} />
          </span>
          {TYPE_LABEL[item.incident_category] ?? 'Other'}
        </span>
        {item.offense && (
          <p className="mt-1 max-w-[140px] truncate pl-9 text-[11.5px] text-muted-foreground" title={item.offense}>{item.offense}</p>
        )}
      </td>
      <td className="px-4 py-3">
        <Link className="font-mono text-[12.5px] font-semibold text-foreground underline-offset-2 hover:underline" href={href}>
          {item.record_number ?? item.incident_id.slice(0, 8)}
        </Link>
        <p className="mt-0.5 truncate text-[11.5px] text-muted-foreground" title={item.reference_no ?? undefined}>
          {item.reference_no ? `Entry ${item.reference_no}` : 'No entry number'}
        </p>
      </td>
      <td className="px-4 py-3">
        <p className="text-[13px] font-medium text-foreground">{item.reporting_person_name ?? 'Reporting person not named'}</p>
        <p className="mt-0.5 line-clamp-2 text-[12px] text-muted-foreground">{item.place_of_incident ?? 'No place given'}</p>
        {(item.station_name || item.agency_type) && (
          <p className="mt-1 inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
            {AgIcon && item.agency_type && <AgIcon size={11} style={{ color: AG_COLOR[item.agency_type] }} />}
            {item.station_name ?? item.agency_type}
          </p>
        )}
      </td>
      <td className="px-4 py-3 text-[12.5px] text-[var(--color-text-secondary)]">
        {formatDate(savedIso, display)}
        <p className="mt-0.5 text-[11.5px] text-muted-foreground">{formatTime(savedIso, display)}</p>
      </td>
      <td className="px-4 py-3 text-[12.5px] text-[var(--color-text-secondary)]">
        {item.prepared_by_name ?? <span className="text-muted-foreground">-</span>}
      </td>
      <td className="px-4 py-3">
        <span
          className="inline-flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide"
          style={finalized
            ? { color: 'var(--color-system-success)', borderColor: 'color-mix(in srgb, var(--color-system-success) 45%, transparent)', backgroundColor: 'color-mix(in srgb, var(--color-system-success) 10%, transparent)' }
            : { color: 'var(--color-system-warning)', borderColor: 'color-mix(in srgb, var(--color-system-warning) 45%, transparent)', backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 10%, transparent)' }}
        >
          {finalized ? <CheckCircle2 size={11} /> : <FilePenLine size={11} />}
          {finalized ? 'Finalized' : 'Draft'}
        </span>
      </td>
      <td className="px-4 py-3">
        <div className="flex justify-end gap-2">
          <Button asChild size="sm" variant="outline">
            <Link href={href}>
              <FileText data-icon="inline-start" size={14} />
              {readOnly ? 'View' : finalized ? 'Open' : 'Continue'}
            </Link>
          </Button>
          <Button aria-label={`Download the PDF for ${item.record_number ?? 'this report'}`} disabled={downloading} onClick={onDownload} size="sm" variant="outline">
            {downloading ? <Loader2 className="animate-spin" data-icon="inline-start" size={14} /> : <Download data-icon="inline-start" size={14} />}
            PDF
          </Button>
        </div>
      </td>
    </tr>
  );
}

function _Empty({ title, body, onClear }: { title: string; body: string; onClear?: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center gap-2 rounded-[var(--radius-card)] border border-dashed border-[var(--color-surface-border)] px-6 py-16 text-center" data-empty>
      <span className="flex size-12 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[var(--color-text-tertiary)]">
        <FileText size={22} />
      </span>
      <p className="mt-1 text-[15px] font-semibold text-foreground">{title}</p>
      <p className="max-w-[46ch] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
      {onClear && <Button className="mt-2" onClick={onClear} size="sm" variant="outline">Clear filters</Button>}
    </div>
  );
}

function _Skeleton() {
  return (
    <div className="animate-pulse overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)]">
      {Array.from({ length: 6 }).map((_, i) => (
        <div className="flex items-center gap-4 border-b border-[var(--color-surface-border)] px-4 py-4 last:border-b-0" key={i}>
          <div className="h-7 w-32 rounded bg-muted" />
          <div className="h-4 w-40 rounded bg-muted" />
          <div className="h-4 flex-1 rounded bg-muted" />
          <div className="h-5 w-20 rounded-full bg-muted" />
        </div>
      ))}
    </div>
  );
}
