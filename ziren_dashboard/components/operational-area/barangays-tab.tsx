'use client';

import { useMemo, useState } from 'react';
import { SearchInput } from '@/components/ui/search-input';
import { AlertTriangle, CheckCircle2, Flame, HeartHandshake, Info, MapPinned, Search, Siren, Users } from 'lucide-react';
import type { BarangayRow, OperationalArea } from '@/lib/api/operational-area';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDate } from '@/lib/format/datetime';
import { CATEGORY_ICON } from '@/components/incidents/incident-vocabulary';
import { DataTable, Figure, type DataColumn } from '@/components/ui/data-table';
import { cn } from '@/lib/utils';
import { periodLong } from './period';
import { Empty, Kpi, Meter, Note, Panel, categoryLabel, fmtInt } from './kit';

type SortKey = 'name' | 'residents' | 'verified' | 'vulnerable' | 'incidents' | 'critical' | 'active' | 'last';
type Show = 'all' | 'empty' | 'reported';

const verifiedPct = (b: BarangayRow) => (b.residents ? Math.round((b.verified / b.residents) * 100) : -1);

export function BarangaysTab({
  data,
  focused,
  onFocus,
}: {
  data: OperationalArea;
  focused: string | null;
  onFocus: (name: string | null) => void;
}) {
  const display = displayPrefs.use();
  const [query, setQuery] = useState('');
  const [show, setShow] = useState<Show>('all');
  const [sort, setSort] = useState<{ key: SortKey; dir: 'asc' | 'desc' }>({ key: 'incidents', dir: 'desc' });

  const b = data.barangays;
  const items = b.items;
  const withResidents = items.filter(x => x.residents > 0).length;
  const totalIncidents = data.kpis.incidents;

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = items.filter(x =>
      (!q || x.name.toLowerCase().includes(q)) &&
      (show === 'all' || (show === 'empty' ? x.residents === 0 : x.incidents > 0)),
    );
    const val = (x: BarangayRow): number | string => {
      switch (sort.key) {
        case 'name': return x.name.toLowerCase();
        case 'residents': return x.residents;
        case 'verified': return verifiedPct(x);
        case 'vulnerable': return x.vulnerable;
        case 'incidents': return x.incidents;
        case 'critical': return x.critical;
        case 'active': return x.active;
        case 'last': return x.last_incident_at ? new Date(x.last_incident_at).getTime() : 0;
      }
    };
    return [...list].sort((a, c) => {
      const av = val(a), cv = val(c);
      const cmp = typeof av === 'string' ? av.localeCompare(cv as string) : (av as number) - (cv as number);
      // Ties fall back to the name so the order never shuffles between renders.
      return (sort.dir === 'asc' ? cmp : -cmp) || a.name.localeCompare(c.name);
    });
  }, [items, query, show, sort]);

  const onSort = (key: string) =>
    setSort(s => ({ key: key as SortKey, dir: s.key === key ? (s.dir === 'asc' ? 'desc' : 'asc') : key === 'name' ? 'asc' : 'desc' }));

  // Same rules as the Compare table: one alignment per column, the name reads
  // left, every figure reads right, and no bars — the number is the data.
  const columns: DataColumn<BarangayRow>[] = [
    {
      key: 'name', header: 'Barangay', sortable: true,
      cell: r => (
        <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span className="font-medium text-foreground">{r.name}</span>
          {r.residents === 0 && (
            <span className="shrink-0 whitespace-nowrap rounded-full bg-[var(--color-system-warning-bg)] px-1.5 py-0.5 text-[10.5px] font-semibold text-[var(--color-system-warning)]">No residents</span>
          )}
        </span>
      ),
    },
    { key: 'residents', header: 'Residents', align: 'right', width: '112px', sortable: true, cell: r => <Figure bold value={fmtInt(r.residents)} /> },
    {
      key: 'verified', header: 'Verified', align: 'right', width: '104px', sortable: true,
      cell: r => { const vp = verifiedPct(r); return vp < 0 ? <span className="text-muted-foreground">—</span> : <span className="text-[var(--color-text-secondary)]">{vp}%</span>; },
    },
    {
      key: 'vulnerable', header: 'Vulnerable', align: 'right', width: '112px', sortable: true,
      cell: r => (
        <span title={`${r.pwd} PWD · ${r.seniors} aged 60+ · ${r.children} under 12`}>
          <Figure value={fmtInt(r.vulnerable)} />
        </span>
      ),
    },
    { key: 'incidents', header: 'Reports', align: 'right', width: '104px', sortable: true, cell: r => <Figure bold value={fmtInt(r.incidents)} /> },
    { key: 'critical', header: 'Critical', align: 'right', width: '100px', sortable: true, cell: r => <Figure bold tone="var(--color-severity-critical)" value={r.critical} /> },
    { key: 'active', header: 'Active', align: 'right', width: '92px', sortable: true, cell: r => <Figure value={r.active} /> },
    {
      key: 'last', header: 'Last report', align: 'right', width: '132px', sortable: true,
      cell: r => (
        <span className="whitespace-nowrap text-[var(--color-text-secondary)]">
          {r.last_incident_at ? formatDate(r.last_incident_at, display) : '—'}
        </span>
      ),
    },
    {
      key: 'focus', header: <span className="sr-only">Actions</span>, align: 'right', width: '92px',
      cell: r => {
        const isFocus = focused === r.name;
        return (
          <button
            aria-label={isFocus ? `Stop focusing on ${r.name}` : `Focus the whole screen on ${r.name}`}
            className="rounded-md px-2 py-1 text-[12px] font-semibold text-[var(--color-brand)] hover:bg-[var(--color-brand-subtle)]"
            onClick={() => onFocus(isFocus ? null : r.name)}
            type="button"
          >
            {isFocus ? 'Clear' : 'Focus'}
          </button>
        );
      },
    },
  ];

  const emptyNames = items.filter(x => x.residents === 0).map(x => x.name);

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi
          icon={HeartHandshake}
          label="Vulnerable residents"
          sub={`${fmtInt(data.kpis.pwd_residents)} PWD · ${fmtInt(data.kpis.senior_residents)} aged 60+ · ${fmtInt(data.kpis.child_residents)} under 12`}
          tone="warning"
          value={fmtInt(data.kpis.vulnerable_residents)}
        />
        <Kpi
          icon={Users}
          label="With registered residents"
          sub={`${fmtInt(data.kpis.residents)} residents in total`}
          tone="brand"
          value={`${withResidents} of ${items.length}`}
        />
        <Kpi
          icon={CheckCircle2}
          label="With no residents yet"
          onClick={() => setShow(s => (s === 'empty' ? 'all' : 'empty'))}
          sub={b.empty_barangays ? 'Click to list them' : 'Every barangay has someone registered'}
          tone={b.empty_barangays ? 'warning' : 'success'}
          value={fmtInt(b.empty_barangays)}
        />
        <Kpi
          icon={Siren}
          label="Reports placed in a barangay"
          sub={`${fmtInt(b.matched_incidents)} of ${fmtInt(b.matched_incidents + b.unmatched_incidents + b.unlocated_incidents)} in ${periodLong(data.filters)}`}
          tone="info"
          value={`${b.matched_incidents + b.unmatched_incidents + b.unlocated_incidents ? Math.round((b.matched_incidents / (b.matched_incidents + b.unmatched_incidents + b.unlocated_incidents)) * 100) : 0}%`}
        />
      </div>

      <Panel
        action={
          <div className="flex flex-wrap items-center gap-2">
            <SearchInput
              className="w-[240px]"
              label="Search barangays"
              onValueChange={setQuery}
              placeholder="Search barangays…"
              size="sm"
              value={query}
            />
            <div aria-label="Show" className="inline-flex rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-0.5" role="radiogroup">
              {([['all', 'All'], ['reported', 'With reports'], ['empty', 'No residents']] as [Show, string][]).map(([k, label]) => (
                <button
                  aria-checked={show === k}
                  className={cn('rounded-md px-2.5 py-1 text-[12px] font-semibold transition-colors', show === k ? 'bg-[var(--color-surface-card)] text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground')}
                  key={k}
                  onClick={() => setShow(k)}
                  role="radio"
                  type="button"
                >
                  {label}
                </button>
              ))}
            </div>
            {(query || show !== 'all') && (
              <span className="whitespace-nowrap text-[12px] font-medium text-muted-foreground">
                {rows.length} of {items.length} shown
              </span>
            )}
          </div>
        }
        description="Every barangay of the municipality — including the ones with nothing registered, because an empty barangay is the finding."
        flush
        title="Barangay breakdown"
      >
        {rows.length === 0 ? (
          <Empty icon={Search} title="No barangay matches">Try a different word, or switch the filter back to All.</Empty>
        ) : (
          <DataTable
            caption="Barangay breakdown"
            columns={columns}
            isMuted={r => r.residents === 0 && r.incidents === 0 && focused !== r.name}
            isSelected={r => focused === r.name}
            minWidth={1000}
            onSort={onSort}
            rowKey={r => r.id}
            rows={rows}
            sort={sort}
          />
        )}
        <div className="flex flex-col gap-2 border-t border-[var(--color-surface-border)] px-5 py-3">
          <Note icon={Info}>
            <strong className="font-semibold">How reports are placed.</strong> A report has no barangay of its own — it has coordinates and an address the phone looked up. A report counts toward a barangay only when that address names one. {fmtInt(b.unmatched_incidents)} name none (a sitio or a landmark) and {fmtInt(b.unlocated_incidents)} have no address at all; both are still in the totals above, just not in a row here.
            {totalIncidents > 0 && b.matched_incidents === 0 && ' Nothing in this period could be placed.'}
          </Note>
          {emptyNames.length > 0 && show !== 'empty' && (
            <Note icon={AlertTriangle} tone="warning">
              <strong className="font-semibold">{emptyNames.length} barangay{emptyNames.length === 1 ? '' : 's'} with nobody registered:</strong>{' '}
              {emptyNames.slice(0, 12).join(', ')}{emptyNames.length > 12 ? `, and ${emptyNames.length - 12} more` : ''}. Residents there cannot file a report through the app.
            </Note>
          )}
        </div>
      </Panel>

      {/* ── Places that keep coming up ──────────────────────────────── */}
      <Panel
        description={`Addresses named by two or more reports in ${periodLong(data.filters)}. A barangay count says where to look; a repeat place says which street.`}
        title="Repeat locations"
      >
        {data.hotspots.length === 0 ? (
          <Empty icon={MapPinned} title="No place came up more than once">
            When two or more reports name the same address, it is listed here as a pattern worth a visit.
          </Empty>
        ) : (
          <ul className="flex flex-col divide-y divide-[var(--color-surface-border)]">
            {data.hotspots.map(h => {
              const Icon = CATEGORY_ICON[h.top_category] ?? Flame;
              return (
                <li className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-x-6 gap-y-1 py-3 first:pt-0 last:pb-0 sm:grid-cols-[minmax(0,1.4fr)_minmax(120px,1fr)_190px]" key={h.place}>
                  <div className="min-w-0">
                    <p className="truncate text-[13.5px] font-semibold text-foreground" title={h.place}>{h.place}</p>
                    <p className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[12px] text-muted-foreground">
                      {h.barangay ?? 'No barangay named'}
                      <span aria-hidden="true">·</span>
                      <span className="inline-flex items-center gap-1"><Icon aria-hidden="true" className="size-3" />mostly {categoryLabel(h.top_category).toLowerCase()}</span>
                      {h.last_at && <><span aria-hidden="true">·</span>last {formatDate(h.last_at, display)}</>}
                    </p>
                  </div>
                  <div className="hidden sm:block">
                    <Meter ariaLabel={`${h.place}: ${h.count} reports`} color="var(--color-status-processing)" max={data.hotspots[0].count} value={h.count} />
                  </div>
                  <p className="text-right tabular-nums">
                    <span className="text-[15px] font-bold text-foreground">{h.count}</span>
                    <span className="ml-1 text-[12px] text-muted-foreground">reports</span>
                    {h.critical > 0 && <span className="ml-2 text-[12px] font-semibold text-[var(--color-severity-critical)]">{h.critical} critical</span>}
                  </p>
                </li>
              );
            })}
          </ul>
        )}
        <div className="mt-4">
          <Note>These are matched from the address text the reporter’s phone looked up, so two spellings of one place count as two. A place reported once is an incident, not a pattern, and is not listed.</Note>
        </div>
      </Panel>
    </div>
  );
}
