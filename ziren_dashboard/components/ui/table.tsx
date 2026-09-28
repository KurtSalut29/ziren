/**
 * Table — reusable data table for list/history screens (accounts, responders,
 * incident history, audit logs).
 *
 * Usage pattern:
 *
 *   <Table>
 *     <TableHead>
 *       <TableRow>
 *         <TableHeader>Name</TableHeader>
 *         <TableHeader>Status</TableHeader>
 *       </TableRow>
 *     </TableHead>
 *     <TableBody>
 *       {rows.map(row => (
 *         <TableRow key={row.id}>
 *           <TableCell>{row.name}</TableCell>
 *           <TableCell><StatusBadge status={row.status} /></TableCell>
 *         </TableRow>
 *       ))}
 *     </TableBody>
 *   </Table>
 *
 * For empty states, wrap the table in a container and render <TableEmptyState>
 * below it — don't render an empty <TableBody>.
 *
 * Accessibility: <table> semantics are preserved. Column headers use <th scope="col">.
 */

import { ReactNode } from 'react';

// ── Container ─────────────────────────────────────────────────────────────────

export function Table({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={[
        'w-full overflow-x-auto rounded-[20px]',
        'border border-[var(--color-surface-border)]',
        'bg-[var(--color-surface-card)]',
        className,
      ].join(' ')}
    >
      <table className="w-full text-left border-collapse">{children}</table>
    </div>
  );
}

// ── Head ──────────────────────────────────────────────────────────────────────

export function TableHead({ children }: { children: ReactNode }) {
  return (
    <thead className="bg-[var(--color-surface-raised)] border-b border-[var(--color-surface-border)]">
      {children}
    </thead>
  );
}

// ── Body ──────────────────────────────────────────────────────────────────────

export function TableBody({ children }: { children: ReactNode }) {
  return (
    <tbody className="divide-y divide-[var(--color-surface-border)]">
      {children}
    </tbody>
  );
}

// ── Row ───────────────────────────────────────────────────────────────────────

export function TableRow({
  children,
  onClick,
  className = '',
}: {
  children: ReactNode;
  onClick?: () => void;
  className?: string;
}) {
  return (
    <tr
      className={[
        'transition-colors',
        onClick
          ? 'cursor-pointer hover:bg-[var(--color-surface-raised)]'
          : 'hover:bg-[var(--color-surface-raised)]/50',
        className,
      ].join(' ')}
      onClick={onClick}
    >
      {children}
    </tr>
  );
}

// ── Header cell ───────────────────────────────────────────────────────────────

export function TableHeader({
  children,
  className = '',
  width,
}: {
  children: ReactNode;
  className?: string;
  width?: string;
}) {
  return (
    <th
      scope="col"
      style={width ? { width } : undefined}
      className={[
        'px-4 py-3.5',
        'text-[11px] font-bold uppercase tracking-wider',
        'text-[var(--color-text-muted)]',
        'whitespace-nowrap',
        className,
      ].join(' ')}
    >
      {children}
    </th>
  );
}

// ── Avatar cell ───────────────────────────────────────────────────────────────

/**
 * TableAvatarCell — leading initials-avatar + label/sublabel, matching the
 * reference design's "Recent Orders" row pattern (avatar + name + order id).
 */
export function TableAvatarCell({
  label,
  sublabel,
  initials,
  color = 'var(--color-text-secondary)',
  bg = 'var(--color-surface-raised)',
  className = '',
}: {
  label: ReactNode;
  sublabel?: ReactNode;
  initials: string;
  color?: string;
  bg?: string;
  className?: string;
}) {
  return (
    <TableCell className={className}>
      <div className="flex items-center gap-2.5">
        <div
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-[11px] font-bold"
          style={{ backgroundColor: bg, color }}
        >
          {initials}
        </div>
        <div className="min-w-0">
          <p className="truncate text-[13px] font-semibold text-[var(--color-text-primary)]">{label}</p>
          {sublabel && <p className="truncate text-[11px] text-[var(--color-text-muted)]">{sublabel}</p>}
        </div>
      </div>
    </TableCell>
  );
}

// ── Data cell ─────────────────────────────────────────────────────────────────

export function TableCell({
  children,
  className = '',
  muted = false,
  colSpan,
}: {
  children: ReactNode;
  className?: string;
  /** Render text in muted color — for secondary/supporting data */
  muted?: boolean;
  /** For a row that spans every column — a group header, an inline expanded
   *  panel — rather than one more per-row data point. */
  colSpan?: number;
}) {
  return (
    <td
      colSpan={colSpan}
      className={[
        'px-4 py-3 text-[13px]',
        muted
          ? 'text-[var(--color-text-muted)]'
          : 'text-[var(--color-text-primary)]',
        className,
      ].join(' ')}
    >
      {children}
    </td>
  );
}

// ── Empty state ───────────────────────────────────────────────────────────────

/**
 * TableEmptyState — shown when a table has no rows.
 * Render this instead of an empty <TableBody> — a blank table reads as broken.
 */
export function TableEmptyState({
  icon,
  message,
  description,
  action,
}: {
  icon?: ReactNode;
  message: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-6 gap-3 text-center">
      {icon && (
        <div className="text-[var(--color-text-muted)] opacity-60">{icon}</div>
      )}
      <p className="text-h3 text-[var(--color-text-muted)]">{message}</p>
      {description && (
        <p className="text-body-sm text-[var(--color-text-muted)] max-w-xs">
          {description}
        </p>
      )}
      {action && <div className="mt-2">{action}</div>}
    </div>
  );
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

/**
 * TableSkeleton — skeleton rows while data loads.
 * Avoids spinner flash on fast connections.
 */
export function TableSkeleton({
  rows = 5,
  cols = 4,
}: {
  rows?: number;
  cols?: number;
}) {
  return (
    <TableBody>
      {Array.from({ length: rows }).map((_, ri) => (
        <TableRow key={ri}>
          {Array.from({ length: cols }).map((_, ci) => (
            <TableCell key={ci}>
              <div
                className="h-4 rounded-[var(--radius-sm)] bg-neutral-100 animate-pulse"
                style={{ width: ci === 0 ? '60%' : '40%' }}
              />
            </TableCell>
          ))}
        </TableRow>
      ))}
    </TableBody>
  );
}
