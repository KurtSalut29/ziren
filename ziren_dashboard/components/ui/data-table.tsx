'use client';

/**
 * DataTable — the one table of the console's analysis screens.
 *
 * Used by Compare, Barangays and the Accounts directory, and meant for any
 * screen whose job is "read a column of figures". Three rules do all the work:
 *
 *   1. A column has ONE alignment, declared once. The header and every cell in
 *      it take it from the same place, so a header can never sit left of the
 *      figures under it — which is what made the old tables read as if the
 *      numbers had drifted. Text reads left, figures read right (so the digits
 *      line up by place value), and short status marks centre.
 *   2. Figures are tabular. Every digit has the same width, so 1,240 sits
 *      exactly under 9,875 and a column can be scanned top to bottom.
 *   3. No decoration in the cells. No bars, no sparklines, no gradients — the
 *      figure IS the content. Emphasis is weight and colour on the figure
 *      itself (a critical count turns red, a zero recedes), never a graphic.
 *
 * Rows are separated by a hairline, the header is a tinted band with quiet
 * uppercase labels, and every row has the same height, so the eye can travel
 * across a row without losing its line.
 *
 * Two levels are exported. `DataTable` is the declarative one — columns in,
 * table out — and covers most screens. The `Data*` primitives under it are for
 * the screen that needs something a column list cannot say (the directory's
 * place-group rows); they carry the same look, so it stays one family.
 */

import type { ReactNode } from 'react';
import { ChevronDown, ChevronRight, ChevronUp } from 'lucide-react';
import { cn } from '@/lib/utils';

export type DataAlign = 'left' | 'right' | 'center';

const ALIGN: Record<DataAlign, string> = {
  left: 'text-left',
  right: 'text-right tabular-nums',
  center: 'text-center',
};

// ── Primitives ────────────────────────────────────────────────────────────

/** The scrolling frame and the <table>. `minWidth` keeps the columns from being crushed on a narrow screen — the frame scrolls instead. */
export function DataTableFrame({
  children,
  minWidth = 720,
  className,
}: {
  children: ReactNode;
  minWidth?: number;
  className?: string;
}) {
  return (
    <div className={cn(
      'w-full overflow-hidden overflow-x-auto rounded-[var(--radius-card)] border border-[var(--color-surface-border)]',
      className,
    )}>
      <table className="w-full table-fixed border-collapse text-[13px]" style={{ minWidth }}>
        {children}
      </table>
    </div>
  );
}

export function DataHead({ children }: { children: ReactNode }) {
  return (
    <thead>
      <tr className="bg-[var(--color-surface-raised)]">{children}</tr>
    </thead>
  );
}

/** A header cell. Sortable when `onSort` is given; the arrow only shows on the sorted column, but its space is always kept so the label never shifts. */
export function DataTh({
  children,
  align = 'left',
  width,
  sort,
  onSort,
  className,
}: {
  children?: ReactNode;
  align?: DataAlign;
  width?: string;
  /** Present when this column is the sorted one. */
  sort?: 'asc' | 'desc';
  onSort?: () => void;
  className?: string;
}) {
  // The arrow goes on the side AWAY from the column's edge, so it never pushes the label
  // off the line the figures below it sit on: after the label in a left column, before it
  // in a right one. Its space is always kept, so the label does not shift when the sort moves.
  const arrow = onSort && (sort === 'asc'
    ? <ChevronUp aria-hidden="true" className="size-3.5 shrink-0" />
    : <ChevronDown aria-hidden="true" className={cn('size-3.5 shrink-0', !sort && 'opacity-0 group-hover/th:opacity-50')} />);
  const label = (
    <span
      className={cn(
        'inline-flex items-center gap-1 whitespace-nowrap text-[11.5px] font-semibold uppercase tracking-wide',
        sort ? 'text-foreground' : 'text-[var(--color-text-tertiary)]',
      )}
    >
      {align === 'right' && arrow}
      {children}
      {align !== 'right' && arrow}
    </span>
  );
  return (
    <th
      aria-sort={onSort ? (sort === 'asc' ? 'ascending' : sort === 'desc' ? 'descending' : 'none') : undefined}
      className={cn(
        'h-11 border-b border-[var(--color-border-strong)] px-4 align-middle',
        ALIGN[align],
        className,
      )}
      scope="col"
      style={width ? { width } : undefined}
    >
      {onSort ? (
        <button
          className={cn(
            'group/th -mx-1 inline-flex items-center rounded px-1 py-0.5 transition-colors hover:text-foreground',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)]/40',
          )}
          onClick={onSort}
          type="button"
        >
          {label}
        </button>
      ) : label}
    </th>
  );
}

export function DataRow({
  children,
  onClick,
  selected = false,
  muted = false,
  className,
}: {
  children: ReactNode;
  onClick?: () => void;
  selected?: boolean;
  /** A row with nothing to say recedes rather than competing with the rows that do. */
  muted?: boolean;
  className?: string;
}) {
  return (
    <tr
      className={cn(
        'transition-colors',
        onClick ? 'cursor-pointer hover:bg-[var(--color-surface-hover)]' : 'hover:bg-[var(--color-surface-hover)]/60',
        selected && 'bg-[var(--color-brand-subtle)] hover:bg-[var(--color-brand-subtle)]',
        muted && !selected && 'text-muted-foreground',
        className,
      )}
      onClick={onClick}
    >
      {children}
    </tr>
  );
}

export function DataTd({
  children,
  align = 'left',
  colSpan,
  className,
}: {
  children?: ReactNode;
  align?: DataAlign;
  colSpan?: number;
  className?: string;
}) {
  return (
    <td
      className={cn(
        'h-[52px] border-b border-[var(--color-surface-border)] px-4 py-2.5 align-middle',
        ALIGN[align],
        className,
      )}
      colSpan={colSpan}
    >
      {children}
    </td>
  );
}

/** A full-width row that names a group of rows — the directory's place headings. It lives inside the table so the table's own structure stays intact. */
export function DataGroupRow({ colSpan, children }: { colSpan: number; children: ReactNode }) {
  return (
    <tr className="border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/70">
      <td className="h-9 px-4 align-middle" colSpan={colSpan}>{children}</td>
    </tr>
  );
}

/**
 * A figure. Zero recedes to the muted tone — "nothing here" is information,
 * but it should not shout as loud as a real count — and `tone` colours a figure
 * that must be seen (a critical count is red, and only a critical count is).
 */
export function Figure({
  value,
  tone,
  bold = false,
  zeroAs,
}: {
  value: number | string;
  tone?: string;
  bold?: boolean;
  /** What to draw for zero — "—" where a zero would read as a measurement rather than an absence. */
  zeroAs?: string;
}) {
  const zero = value === 0 || value === '0';
  if (zero) {
    return <span className="text-muted-foreground">{zeroAs ?? '0'}</span>;
  }
  return (
    <span className={cn(bold && 'font-semibold')} style={{ color: tone ?? 'var(--color-text-primary)' }}>
      {value}
    </span>
  );
}

/** Two-letter avatar — the same mark for a person on every table of the console. */
export function Initials({ name, tone = 'neutral' }: { name: string; tone?: 'brand' | 'neutral' }) {
  return (
    <span
      aria-hidden="true"
      className={cn(
        'flex size-9 shrink-0 items-center justify-center rounded-[var(--radius-control)] text-[12px] font-semibold',
        tone === 'brand'
          ? 'bg-[var(--color-brand-subtle)] text-[var(--color-brand)]'
          : 'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]',
      )}
    >
      {name.split(' ').map(part => part[0]).join('').slice(0, 2).toUpperCase()}
    </span>
  );
}

/** A small filled state mark. The label always says the state — colour only reinforces it. */
export function StatusChip({ label, tone }: { label: string; tone: 'success' | 'neutral' | 'warning' }) {
  const palette = {
    success: ['var(--color-system-success-bg)', 'var(--color-system-success)'],
    warning: ['var(--color-system-warning-bg)', 'var(--color-system-warning)'],
    neutral: ['var(--color-surface-raised)', 'var(--color-text-muted)'],
  }[tone];
  return (
    <span
      className="inline-flex whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={{ backgroundColor: palette[0], color: palette[1] }}
    >
      {label}
    </span>
  );
}

// ── Declarative table ─────────────────────────────────────────────────────

export interface DataColumn<T> {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  align?: DataAlign;
  /** A CSS width (`'96px'`, `'12%'`). Leave one column — the identifying one — without it and it takes the rest. */
  width?: string;
  /** Adds a sort button to the header. The caller owns the sorting itself. */
  sortable?: boolean;
  /** The bottom "Total" row's figure for this column. Omit on every column to draw no total row. */
  total?: ReactNode;
  /** Extra classes for this column's cells (e.g. `whitespace-nowrap`). */
  className?: string;
}

export function DataTable<T>({
  columns,
  rows,
  rowKey,
  sort,
  onSort,
  onRowClick,
  isSelected,
  isMuted,
  totalLabel = 'Total',
  minWidth,
  caption,
  chevron = false,
}: {
  columns: DataColumn<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  sort?: { key: string; dir: 'asc' | 'desc' };
  onSort?: (key: string) => void;
  onRowClick?: (row: T) => void;
  isSelected?: (row: T) => boolean;
  isMuted?: (row: T) => boolean;
  totalLabel?: string;
  minWidth?: number;
  /** Read by screen readers; not drawn. */
  caption?: string;
  /** A trailing "›" on clickable rows — says the whole row opens something. */
  chevron?: boolean;
}) {
  const hasTotal = columns.some(c => c.total !== undefined);
  return (
    <DataTableFrame minWidth={minWidth}>
      {caption && <caption className="sr-only">{caption}</caption>}
      <DataHead>
        {columns.map(c => (
          <DataTh
            align={c.align}
            key={c.key}
            onSort={c.sortable && onSort ? () => onSort(c.key) : undefined}
            sort={sort?.key === c.key ? sort.dir : undefined}
            width={c.width}
          >
            {c.header}
          </DataTh>
        ))}
        {chevron && <DataTh width="40px"><span className="sr-only">Open</span></DataTh>}
      </DataHead>
      <tbody>
        {rows.map(r => (
          <DataRow
            muted={isMuted?.(r)}
            onClick={onRowClick ? () => onRowClick(r) : undefined}
            key={rowKey(r)}
            selected={isSelected?.(r)}
          >
            {columns.map(c => (
              <DataTd align={c.align} className={c.className} key={c.key}>{c.cell(r)}</DataTd>
            ))}
            {chevron && (
              <DataTd align="right" className="pl-0">
                <ChevronRight aria-hidden="true" className="ml-auto size-4 text-muted-foreground" />
              </DataTd>
            )}
          </DataRow>
        ))}
      </tbody>
      {hasTotal && (
        <tfoot>
          <tr className="border-t border-[var(--color-border-strong)] bg-[var(--color-surface-raised)]">
            {columns.map((c, i) => (
              <td className={cn('h-11 px-4 align-middle font-semibold', ALIGN[c.align ?? 'left'])} key={c.key}>
                {i === 0 ? totalLabel : c.total ?? ''}
              </td>
            ))}
            {chevron && <td />}
          </tr>
        </tfoot>
      )}
    </DataTableFrame>
  );
}
