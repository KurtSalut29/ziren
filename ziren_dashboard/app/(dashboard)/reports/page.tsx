'use client';

/**
 * Reports & Export — the two documents a station prints.
 *
 * Redesigned 2026-09-29 after station testing: of the ten report cards this
 * page used to hold, the stations only ever print two things — the incident
 * records for a period, and the narrative reports — and they wanted those
 * clean and formatted, not a spreadsheet dump. So the page is now two
 * documents, each with its options on the left and the real document on the
 * right, exactly as it will print:
 *
 *   Incident Records   — letterhead, period, summary, one row per incident,
 *                        signature block. Print, PDF, or Excel/CSV to work with.
 *   Narrative Reports  — pick reports from the period; they print as one PDF,
 *                        a cover page listing them, then each Incident Record Form.
 *
 * Both documents are built server-side (printable_reports.py) and scoped by
 * the same queries as Incident Records and Narrative Reports, so a printout
 * never shows what the screen would not.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle, AlertOctagon, AlertTriangle, Check, CheckCircle2, Download, FileSpreadsheet, FileText,
  Info, Loader2, NotebookText, Printer, RefreshCw, Search,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import {
  fetchIncidentRecords, fetchNarrativeBundle, printPdf, saveFile,
  type RecordsFormat, type RecordsSeverity, type RecordsStatus, type ReportFile,
} from '@/lib/api/reports';
import { fetchNarrativeReports, type NarrativeListItem } from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { SEV_COLOR } from '@/components/incidents/incident-vocabulary';
import { PeriodPicker } from '@/components/ui/period-picker';
import { phToday, periodWords, resolvePeriod, type Range } from '@/components/ui/period';
import { cn } from '@/lib/utils';

import { DemoTarget } from '@/components/help/demo-target';
type Doc = 'records' | 'narratives';

function useErrorText() {
  return (e: unknown, fallback: string): string | null => {
    if (e instanceof ApiError && e.status === 401) { signOut(); return null; }
    return e instanceof Error ? e.message : fallback;
  };
}

export default function ReportsPage() {
  const { token, isProvincialAdmin } = useAuth();
  const [doc, setDoc] = useState<Doc>('records');
  const [today] = useState(() => phToday());
  // One period for both documents — "September" is set once for a sitting of
  // printing, not per document.
  const [days, setDays] = useState(30);
  const [range, setRange] = useState<Range | null>(null);
  const resolved = resolvePeriod(days, range, today);
  const period = { startDate: resolved?.from, endDate: resolved?.to };
  const periodText = periodWords(days, range);

  return (
    <div className="flex flex-col gap-5 px-4 py-5 md:px-7">
      <div data-demo="rep:docs" className="grid grid-cols-1 gap-3 md:grid-cols-2" role="tablist" aria-label="Document to print">
        <DocTab
          active={doc === 'records'}
          description="Every incident in a period as one formatted table — with a summary and a signature block."
          formats="PDF · Excel · CSV"
          icon={FileText}
          onClick={() => setDoc('records')}
          title="Incident Records"
        />
        <DocTab
          active={doc === 'narratives'}
          description="Incident Record Forms, printed together with a cover page that lists them."
          formats="PDF"
          icon={NotebookText}
          onClick={() => setDoc('narratives')}
          title="Narrative Reports"
        />
      </div>

      {token && (
        doc === 'records' ? (
          <RecordsWorkspace
            days={days} isProvincialAdmin={isProvincialAdmin} period={period} periodText={periodText}
            range={range} setDays={d => { setDays(d); setRange(null); }} setRange={setRange} today={today} token={token}
          />
        ) : (
          <NarrativesWorkspace
            days={days} period={period} periodText={periodText}
            range={range} setDays={d => { setDays(d); setRange(null); }} setRange={setRange} today={today} token={token}
          />
        )
      )}
    </div>
  );
}

// ── Shared pieces ────────────────────────────────────────────────────────────

function DocTab({
  active, title, description, formats, icon: Icon, onClick,
}: {
  active: boolean; title: string; description: string; formats: string; icon: typeof FileText; onClick: () => void;
}) {
  return (
    <button
      aria-selected={active}
      className={cn(
        'group flex items-start gap-4 rounded-[var(--radius-card)] border p-4 text-left transition-[border-color,background-color,box-shadow]',
        active
          ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] shadow-[0_0_0_3px_color-mix(in_srgb,var(--color-brand)_14%,transparent)]'
          : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] hover:border-[color-mix(in_srgb,var(--color-brand)_40%,var(--color-surface-border))]',
      )}
      onClick={onClick}
      role="tab"
      type="button"
    >
      <span
        className={cn(
          'flex size-12 shrink-0 items-center justify-center rounded-xl transition-colors',
          active ? 'bg-[var(--color-brand)] text-white' : 'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]',
        )}
      >
        <Icon aria-hidden="true" className="size-6" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex flex-wrap items-center gap-2">
          <span className="text-[16px] font-bold text-foreground">{title}</span>
          <span className="rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">{formats}</span>
        </span>
        <span className="mt-1 block text-[13px] leading-relaxed text-[var(--color-text-secondary)]">{description}</span>
      </span>
    </button>
  );
}

function OptionBlock({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-2">
      <span className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">{label}</span>
      {children}
    </div>
  );
}

function Segmented<T extends string | null>({
  value, onChange, options,
}: {
  value: T;
  onChange: (v: T) => void;
  options: { value: T; label: string; icon?: typeof Info; color?: string }[];
}) {
  return (
    <div className="flex flex-wrap gap-1.5">
      {options.map(o => {
        const on = o.value === value;
        return (
          <button
            aria-pressed={on}
            className={cn(
              'inline-flex h-8 items-center gap-1.5 rounded-lg border px-3 text-[12.5px] font-semibold transition-colors',
              on
                ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] text-foreground'
                : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)]',
            )}
            key={String(o.value)}
            onClick={() => onChange(o.value)}
            type="button"
          >
            {o.icon && <o.icon aria-hidden="true" className="size-3.5" style={{ color: o.color }} />}
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function ActionButton({
  onClick, disabled, busy, icon: Icon, children, variant = 'outline',
}: {
  onClick: () => void; disabled?: boolean; busy?: boolean; icon: typeof Printer; children: React.ReactNode;
  variant?: 'primary' | 'outline';
}) {
  return (
    <button
      className={cn(
        'flex h-11 w-full items-center justify-center gap-2 rounded-xl px-4 text-[13.5px] font-bold transition-[filter,background-color] disabled:cursor-not-allowed disabled:opacity-50',
        variant === 'primary'
          ? 'bg-[var(--color-brand)] text-white shadow-[0_6px_16px_-8px_color-mix(in_srgb,var(--color-brand)_80%,transparent)] hover:brightness-110'
          : 'border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-foreground hover:bg-[var(--color-surface-hover)]',
      )}
      disabled={disabled || busy}
      onClick={onClick}
      type="button"
    >
      {busy ? <Loader2 aria-hidden="true" className="size-4 animate-spin" /> : <Icon aria-hidden="true" className="size-4" />}
      {children}
    </button>
  );
}

/** The document itself, in the browser's PDF viewer, exactly as it prints. */
function Preview({
  file, loading, error, empty, onRetry, title,
}: {
  file: ReportFile | null; loading: boolean; error: string | null; empty?: string; onRetry?: () => void; title: string;
}) {
  const url = useMemo(() => (file ? URL.createObjectURL(file.blob) : null), [file]);
  useEffect(() => () => { if (url) URL.revokeObjectURL(url); }, [url]);

  return (
    <section className="flex min-h-[560px] flex-col overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
      <div className="flex items-center gap-2 border-b border-[var(--color-surface-border)] px-4 py-3">
        <span className="text-[13px] font-bold text-foreground">Preview</span>
        <span className="text-[12px] text-muted-foreground">· {title} — exactly as it prints</span>
        {loading && <Loader2 aria-label="Updating" className="ml-auto size-4 animate-spin text-muted-foreground" />}
      </div>
      <div className="relative flex-1 bg-[var(--color-surface-raised)]">
        {error ? (
          <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
            <AlertCircle aria-hidden="true" className="size-8 text-[var(--color-system-error)]" />
            <p className="max-w-[360px] text-[13px] text-foreground">{error}</p>
            {onRetry && (
              <button className="inline-flex items-center gap-1.5 text-[13px] font-bold text-[var(--color-brand)] hover:underline" onClick={onRetry} type="button">
                <RefreshCw aria-hidden="true" className="size-3.5" /> Try again
              </button>
            )}
          </div>
        ) : url ? (
          <iframe className="absolute inset-0 size-full" src={`${url}#toolbar=0&navpanes=0&view=FitH`} title={`${title} preview`} />
        ) : loading ? (
          <div className="flex h-full items-center justify-center gap-2 text-[13px] text-muted-foreground">
            <Loader2 aria-hidden="true" className="size-4 animate-spin" /> Building the document from live data…
          </div>
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-3 p-8 text-center">
            <FileText aria-hidden="true" className="size-9 text-muted-foreground" />
            <p className="max-w-[340px] text-[13px] text-muted-foreground">{empty}</p>
          </div>
        )}
      </div>
    </section>
  );
}

interface PeriodProps {
  token: string;
  today: string;
  days: number;
  range: Range | null;
  setDays: (d: number) => void;
  setRange: (r: Range) => void;
  period: { startDate?: string; endDate?: string };
  periodText: string;
}

// ── Incident Records ────────────────────────────────────────────────────────

const STATUS_OPTIONS: { value: RecordsStatus | null; label: string }[] = [
  { value: null, label: 'All' },
  { value: 'open', label: 'Still open' },
  { value: 'resolved', label: 'Resolved' },
  { value: 'cancelled', label: 'Cancelled' },
];
const SEVERITY_OPTIONS: { value: RecordsSeverity | null; label: string; icon?: typeof Info; color?: string }[] = [
  { value: null, label: 'All' },
  { value: 'critical', label: 'Critical', icon: AlertOctagon, color: SEV_COLOR.critical },
  { value: 'high', label: 'High', icon: AlertTriangle, color: SEV_COLOR.high },
  { value: 'medium', label: 'Medium', icon: AlertCircle, color: SEV_COLOR.medium },
  { value: 'low', label: 'Low', icon: Info, color: SEV_COLOR.low },
];

function RecordsWorkspace({ token, today, days, range, setDays, setRange, period, periodText, isProvincialAdmin }: PeriodProps & { isProvincialAdmin: boolean }) {
  const [status, setStatus] = useState<RecordsStatus | null>(null);
  const [severity, setSeverity] = useState<RecordsSeverity | null>(null);
  const [file, setFile] = useState<ReportFile | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [exporting, setExporting] = useState<RecordsFormat | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);
  const ticket = useRef(0);
  const errorText = useErrorText();

  const filter = { ...period, status, severity };
  const key = JSON.stringify(filter);

  // The preview follows the options, a beat after the last change.
  useEffect(() => {
    const mine = ++ticket.current;
    setLoading(true);
    setError(null);
    const t = window.setTimeout(() => {
      fetchIncidentRecords(token, 'pdf', JSON.parse(key))
        .then(f => { if (mine === ticket.current) setFile(f); })
        .catch(e => { if (mine === ticket.current) { setFile(null); setError(errorText(e, 'Could not build the report.')); } })
        .finally(() => { if (mine === ticket.current) setLoading(false); });
    }, 350);
    return () => window.clearTimeout(t);
    // errorText is recreated each render and only formats; the key is the input.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, key, nonce]);

  async function exportAs(format: RecordsFormat) {
    setActionError(null);
    setExporting(format);
    try {
      saveFile(await fetchIncidentRecords(token, format, filter));
    } catch (e) {
      setActionError(errorText(e, 'Could not download the file.'));
    } finally {
      setExporting(null);
    }
  }

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[380px_1fr]">
      <aside data-demo="rep:options" className="flex flex-col gap-5 self-start rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-5">
        <div>
          <h2 className="text-[15px] font-bold text-foreground">Incident Records Report</h2>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            {isProvincialAdmin ? 'Every station of your agency in Biliran.' : 'Your station’s incidents only.'} Choose what it covers — the preview updates as you go.
          </p>
        </div>
        <OptionBlock label="Period">
          <PeriodPicker days={days} onDays={setDays} onRange={setRange} range={range} size="sm" today={today} />
          <span className="text-[12px] text-muted-foreground">Covers {periodText}.</span>
        </OptionBlock>
        <OptionBlock label="Status">
          <Segmented onChange={setStatus} options={STATUS_OPTIONS} value={status} />
        </OptionBlock>
        <OptionBlock label="Severity">
          <Segmented onChange={setSeverity} options={SEVERITY_OPTIONS} value={severity} />
        </OptionBlock>

        <div data-demo="rep:actions" className="flex flex-col gap-2 border-t border-[var(--color-surface-border)] pt-4">
          <ActionButton disabled={!file || loading} icon={Printer} onClick={() => file && printPdf(file.blob)} variant="primary">
            Print report
          </ActionButton>
          <ActionButton disabled={!file || loading} icon={Download} onClick={() => file && saveFile(file)}>
            Download PDF
          </ActionButton>
          <div className="grid grid-cols-2 gap-2">
            <ActionButton busy={exporting === 'xlsx'} icon={FileSpreadsheet} onClick={() => void exportAs('xlsx')}>Excel</ActionButton>
            <ActionButton busy={exporting === 'csv'} icon={FileSpreadsheet} onClick={() => void exportAs('csv')}>CSV</ActionButton>
          </div>
          {actionError && <p className="text-[12.5px] font-medium text-[var(--color-system-error)]">{actionError}</p>}
          <p className="flex items-start gap-1.5 text-[11.5px] leading-relaxed text-muted-foreground">
            <Info aria-hidden="true" className="mt-0.5 size-3.5 shrink-0" />
            Built from live data each time. Excel and CSV hold the same rows for spreadsheets.
          </p>
        </div>
      </aside>

      <DemoTarget id="rep:preview"><Preview
        error={error}
        file={file}
        loading={loading}
        onRetry={() => setNonce(n => n + 1)}
        title="Incident Records Report"
      /></DemoTarget>
    </div>
  );
}

// ── Narrative Reports ───────────────────────────────────────────────────────

const NARRATIVE_CATEGORIES = [...Object.keys(CATEGORY_LABELS), 'other'];

function NarrativesWorkspace({ token, today, days, range, setDays, setRange, period, periodText }: PeriodProps) {
  const [reportStatus, setReportStatus] = useState<'finalized' | 'draft' | null>('finalized');
  const [category, setCategory] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [items, setItems] = useState<NarrativeListItem[] | null>(null);
  const [total, setTotal] = useState(0);
  const [listError, setListError] = useState<string | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [file, setFile] = useState<ReportFile | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [nonce, setNonce] = useState(0);
  const ticket = useRef(0);
  const errorText = useErrorText();

  const listKey = JSON.stringify({ ...period, reportStatus, category });
  useEffect(() => {
    let live = true;
    setItems(null);
    setListError(null);
    const q = JSON.parse(listKey) as { startDate?: string; endDate?: string; reportStatus: 'finalized' | 'draft' | null; category: string | null };
    fetchNarrativeReports(token, {
      days: 0, date_from: q.startDate, date_to: q.endDate,
      status: q.reportStatus ?? undefined, category: q.category ?? undefined, limit: 50,
    })
      .then(lib => {
        if (!live) return;
        setItems(lib.items);
        setTotal(lib.total);
        // Everything in view is picked by default — the usual job is "print
        // this month's reports", not hand-picking one by one.
        setPicked(new Set(lib.items.map(i => i.incident_id)));
      })
      .catch(e => { if (live) { setItems([]); setListError(errorText(e, 'Could not load the narrative reports.')); } });
    return () => { live = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, listKey]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (items ?? []).filter(i => !q || [
      i.reference_no, i.record_number, i.offense, i.place_of_incident, i.reporting_person_name,
      CATEGORY_LABELS[i.incident_category],
    ].some(v => v?.toLowerCase().includes(q)));
  }, [items, query]);

  // The preview follows the selection, in list order.
  const pickedIds = (items ?? []).filter(i => picked.has(i.incident_id)).map(i => i.incident_id);
  const pickKey = pickedIds.join(',');
  useEffect(() => {
    const mine = ++ticket.current;
    if (!pickKey) { setFile(null); setLoading(false); setError(null); return; }
    setLoading(true);
    setError(null);
    const t = window.setTimeout(() => {
      fetchNarrativeBundle(token, pickKey.split(','))
        .then(f => { if (mine === ticket.current) setFile(f); })
        .catch(e => { if (mine === ticket.current) { setFile(null); setError(errorText(e, 'Could not build the document.')); } })
        .finally(() => { if (mine === ticket.current) setLoading(false); });
    }, 450);
    return () => window.clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, pickKey, nonce]);

  const allVisiblePicked = visible.length > 0 && visible.every(i => picked.has(i.incident_id));
  function toggleAll() {
    setPicked(prev => {
      const next = new Set(prev);
      for (const i of visible) {
        if (allVisiblePicked) next.delete(i.incident_id); else next.add(i.incident_id);
      }
      return next;
    });
  }

  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-[420px_1fr]">
      <aside className="flex min-h-0 flex-col gap-5 self-start rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-5">
        <div>
          <h2 className="text-[15px] font-bold text-foreground">Narrative Reports</h2>
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">
            Pick the reports to print. They come out as one document: a cover page listing them, then each Incident Record Form.
          </p>
        </div>
        <OptionBlock label="Period">
          <PeriodPicker days={days} onDays={setDays} onRange={setRange} range={range} size="sm" today={today} />
          <span className="text-[12px] text-muted-foreground">Reports written or updated in {periodText}.</span>
        </OptionBlock>
        <OptionBlock label="Report status">
          <Segmented
            onChange={setReportStatus}
            options={[
              { value: 'finalized', label: 'Finalized', icon: CheckCircle2 },
              { value: 'draft', label: 'Drafts' },
              { value: null, label: 'All' },
            ]}
            value={reportStatus}
          />
        </OptionBlock>
        <OptionBlock label="Type of incident">
          <Segmented
            onChange={setCategory}
            options={[{ value: null, label: 'All' }, ...NARRATIVE_CATEGORIES.map(c => ({ value: c, label: CATEGORY_LABELS[c] ?? 'Other' }))]}
            value={category}
          />
        </OptionBlock>

        <OptionBlock label={`Reports${items ? ` · ${picked.size} of ${items.length} selected` : ''}`}>
          <div className="flex items-center gap-2">
            <label className="relative flex-1">
              <Search aria-hidden="true" className="pointer-events-none absolute left-2.5 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground" />
              <input
                className="h-9 w-full rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] pl-8 pr-2 text-[12.5px] focus:border-[var(--color-brand)] focus:outline-none"
                onChange={e => setQuery(e.target.value)}
                placeholder="Search IRF no., record no., place"
                type="search"
                value={query}
              />
            </label>
            <button
              className="h-9 shrink-0 rounded-lg border border-[var(--color-surface-border)] px-3 text-[12px] font-semibold text-foreground hover:bg-[var(--color-surface-hover)] disabled:opacity-50"
              disabled={!visible.length}
              onClick={toggleAll}
              type="button"
            >
              {allVisiblePicked ? 'Clear' : 'Select all'}
            </button>
          </div>
          <div className="max-h-[340px] overflow-y-auto rounded-xl border border-[var(--color-surface-border)]">
            {items === null ? (
              <p className="flex items-center gap-2 p-4 text-[12.5px] text-muted-foreground"><Loader2 className="size-4 animate-spin" /> Loading…</p>
            ) : listError ? (
              <p className="p-4 text-[12.5px] text-[var(--color-system-error)]">{listError}</p>
            ) : visible.length === 0 ? (
              <p className="p-4 text-[12.5px] text-muted-foreground">
                {items.length ? 'Nothing matches that search.' : `No narrative report in ${periodText} with these filters.`}
              </p>
            ) : (
              <ul className="divide-y divide-[var(--color-surface-border)]">
                {visible.map(i => {
                  const on = picked.has(i.incident_id);
                  return (
                    <li key={i.id}>
                      <button
                        aria-checked={on}
                        className={cn('flex w-full items-start gap-3 px-3 py-2.5 text-left transition-colors', on ? 'bg-[var(--color-brand-subtle)]' : 'hover:bg-[var(--color-surface-hover)]')}
                        onClick={() => setPicked(prev => {
                          const next = new Set(prev);
                          if (next.has(i.incident_id)) next.delete(i.incident_id); else next.add(i.incident_id);
                          return next;
                        })}
                        role="checkbox"
                        type="button"
                      >
                        <span
                          aria-hidden="true"
                          className={cn(
                            'mt-0.5 flex size-[18px] shrink-0 items-center justify-center rounded-md border-2 text-white',
                            on ? 'border-[var(--color-brand)] bg-[var(--color-brand)]' : 'border-[var(--color-surface-border)]',
                          )}
                        >
                          {on && <Check className="size-3" strokeWidth={3.5} />}
                        </span>
                        <span className="min-w-0 flex-1">
                          <span className="flex items-center gap-2">
                            <span className="truncate text-[13px] font-bold text-foreground">{i.reference_no || i.record_number || 'Untitled report'}</span>
                            <span className={cn('ml-auto shrink-0 rounded-full px-1.5 py-px text-[10px] font-bold uppercase',
                              i.status === 'finalized' ? 'bg-[var(--color-system-success-bg)] text-[var(--color-system-success)]' : 'bg-[var(--color-surface-raised)] text-muted-foreground')}
                            >
                              {i.status === 'finalized' ? 'Final' : 'Draft'}
                            </span>
                          </span>
                          <span className="block truncate text-[12px] text-[var(--color-text-secondary)]">
                            {i.offense || CATEGORY_LABELS[i.incident_category] || 'Incident'}
                            {i.place_of_incident ? ` · ${i.place_of_incident}` : ''}
                          </span>
                          <span className="block text-[11px] text-muted-foreground">
                            {i.record_number ?? ''}{i.incident_created_at ? ` · ${new Date(i.incident_created_at).toLocaleDateString('en-PH', { month: 'short', day: 'numeric', year: 'numeric' })}` : ''}
                          </span>
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
          {items && total > items.length && (
            <span className="text-[11.5px] text-muted-foreground">Showing the newest {items.length} of {total}. Narrow the period to reach the rest.</span>
          )}
        </OptionBlock>

        <div className="flex flex-col gap-2 border-t border-[var(--color-surface-border)] pt-4">
          <ActionButton disabled={!file || loading} icon={Printer} onClick={() => file && printPdf(file.blob)} variant="primary">
            {pickedIds.length > 1 ? `Print ${pickedIds.length} reports` : 'Print report'}
          </ActionButton>
          <ActionButton disabled={!file || loading} icon={Download} onClick={() => file && saveFile(file)}>
            Download PDF
          </ActionButton>
        </div>
      </aside>

      <Preview
        empty="Select at least one narrative report to see it here."
        error={error}
        file={file}
        loading={loading}
        onRetry={() => setNonce(n => n + 1)}
        title="Narrative Reports"
      />
    </div>
  );
}
