'use client';

import { useMemo, useState } from 'react';
import { Building2, MapPinned, Siren, Users } from 'lucide-react';
import type { AreaFilters, ComparisonRow } from '@/lib/api/operational-area';
import { DataTable, Figure, type DataColumn } from '@/components/ui/data-table';
import { periodLong } from './period';
import { Kpi, Note, Panel, fmtInt } from './kit';

type Key = 'municipality' | 'barangays' | 'residents' | 'stations' | 'responders' | 'incidents' | 'critical' | 'active';

/**
 * Provincial Admin only: every municipality side by side. Where the residents
 * are, where the stations are, where the reports are — and where one of those is
 * missing. Incident columns are scoped to the admin's own agency type, as
 * everywhere else on this screen.
 */
export function CompareTab({
  rows,
  filters,
  selected,
  onSelect,
}: {
  rows: ComparisonRow[];
  filters: AreaFilters;
  selected: string;
  onSelect: (m: string) => void;
}) {
  const [sort, setSort] = useState<{ key: Key; dir: 'asc' | 'desc' }>({ key: 'incidents', dir: 'desc' });

  const totals = useMemo(() => rows.reduce((t, r) => ({
    barangays: t.barangays + r.barangays, residents: t.residents + r.residents, stations: t.stations + r.stations,
    responders: t.responders + r.responders, on_duty: t.on_duty + r.on_duty, incidents: t.incidents + r.incidents,
    critical: t.critical + r.critical, active: t.active + r.active,
  }), { barangays: 0, residents: 0, stations: 0, responders: 0, on_duty: 0, incidents: 0, critical: 0, active: 0 }), [rows]);

  const sorted = useMemo(() => [...rows].sort((a, b) => {
    const av = a[sort.key], bv = b[sort.key];
    const cmp = typeof av === 'string' ? av.localeCompare(bv as string) : (av as number) - (bv as number);
    return (sort.dir === 'asc' ? cmp : -cmp) || a.municipality.localeCompare(b.municipality);
  }), [rows, sort]);

  const onSort = (key: string) =>
    setSort(s => ({ key: key as Key, dir: s.key === key ? (s.dir === 'asc' ? 'desc' : 'asc') : key === 'municipality' ? 'asc' : 'desc' }));

  // One alignment per column, declared once: the name reads left, every figure
  // reads right so the digits stack by place value. No bars — the figure is the data.
  const columns: DataColumn<ComparisonRow>[] = [
    {
      key: 'municipality', header: 'Municipality', sortable: true,
      cell: r => (
        <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
          <span className="font-semibold text-foreground">{r.municipality}</span>
          {r.stations === 0 && (
            <span className="rounded-full bg-[var(--color-system-warning-bg)] px-1.5 py-0.5 text-[10.5px] font-semibold text-[var(--color-system-warning)]">No station</span>
          )}
        </span>
      ),
    },
    { key: 'barangays', header: 'Barangays', align: 'right', width: '104px', sortable: true, cell: r => <Figure value={r.barangays} />, total: fmtInt(totals.barangays) },
    { key: 'residents', header: 'Residents', align: 'right', width: '112px', sortable: true, cell: r => <Figure bold value={fmtInt(r.residents)} zeroAs="0" />, total: fmtInt(totals.residents) },
    { key: 'stations', header: 'Stations', align: 'right', width: '96px', sortable: true, cell: r => <Figure value={r.stations} />, total: fmtInt(totals.stations) },
    {
      key: 'responders', header: 'On duty / approved', align: 'right', width: '164px', sortable: true,
      cell: r => (
        <span>
          <span className="font-medium text-foreground">{r.on_duty}</span>
          <span className="text-muted-foreground"> / {r.responders}</span>
        </span>
      ),
      total: `${fmtInt(totals.on_duty)} / ${fmtInt(totals.responders)}`,
    },
    { key: 'incidents', header: 'Reports', align: 'right', width: '104px', sortable: true, cell: r => <Figure bold value={fmtInt(r.incidents)} />, total: fmtInt(totals.incidents) },
    { key: 'critical', header: 'Critical', align: 'right', width: '100px', sortable: true, cell: r => <Figure bold tone="var(--color-severity-critical)" value={r.critical} />, total: fmtInt(totals.critical) },
    { key: 'active', header: 'Active', align: 'right', width: '92px', sortable: true, cell: r => <Figure value={r.active} />, total: fmtInt(totals.active) },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi icon={MapPinned} label="Municipalities" sub={`${fmtInt(totals.barangays)} barangays`} tone="neutral" value={fmtInt(rows.length)} />
        <Kpi icon={Users} label="Registered residents" sub="Across the province" tone="brand" value={fmtInt(totals.residents)} />
        <Kpi icon={Building2} label="Stations" sub={`${fmtInt(totals.on_duty)} of ${fmtInt(totals.responders)} responders on duty`} tone="info" value={fmtInt(totals.stations)} />
        <Kpi icon={Siren} label="Reports" sub={`${fmtInt(totals.critical)} critical · ${fmtInt(totals.active)} active · ${periodLong(filters)}`} tone="warning" value={fmtInt(totals.incidents)} />
      </div>

      <Panel
        description="Click a municipality to open its full operational area."
        flush
        title="Municipalities compared"
      >
        <DataTable
          caption="Municipalities compared"
          chevron
          columns={columns}
          isSelected={r => r.municipality === selected}
          minWidth={920}
          onRowClick={r => onSelect(r.municipality)}
          onSort={onSort}
          rowKey={r => r.municipality}
          rows={sorted}
          sort={sort}
          totalLabel="Province total"
        />
        <div className="border-t border-[var(--color-surface-border)] px-5 py-3">
          <Note>“Responders” reads on duty / approved, for your agency type. Report columns are your agency type’s reports only.</Note>
        </div>
      </Panel>
    </div>
  );
}
