'use client';

/**
 * The small pieces every tab of the Operational Area is built from, so a figure
 * looks the same wherever it appears.
 *
 * Colour follows the console's standing rules (see globals.css): red is critical
 * severity and nothing else, brand orange is the primary action and the active
 * tab, the agency hues are fixed, and a severity or status is always a WORD as
 * well as a colour — a chip here is never a dot alone.
 */

import { ChevronDown, ChevronUp } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { DeltaBadge } from '@/components/charts/delta-badge';
import { AG_BG, AG_COLOR, SEV_COLOR, STATUS_STYLE, statusLabel } from '@/components/incidents/incident-vocabulary';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';

// ── Formatting ───────────────────────────────────────────────────────────

/** Minutes as a person says them: "45 s", "4.5 min", "2h 14m", "1d 3h". "—" when there is none. */
export function fmtMin(m: number | null | undefined): string {
  if (m === null || m === undefined || Number.isNaN(m)) return '—';
  if (m < 1) return `${Math.max(1, Math.round(m * 60))} s`;
  if (m < 10) return `${Number(m.toFixed(1))} min`;
  if (m < 60) return `${Math.round(m)} min`;
  const h = Math.floor(m / 60);
  const rest = Math.round(m - h * 60);
  if (h < 24) return rest ? `${h}h ${rest}m` : `${h}h`;
  const d = Math.floor(h / 24);
  const hh = h - d * 24;
  return hh ? `${d}d ${hh}h` : `${d}d`;
}

export const fmtInt = (n: number | null | undefined) => (n === null || n === undefined ? '—' : n.toLocaleString('en-PH'));
export const fmtPct = (n: number | null | undefined) => (n === null || n === undefined ? '—' : `${n}%`);

export function categoryLabel(key: string | null | undefined): string {
  if (!key) return 'Uncategorised';
  return CATEGORY_LABELS[key] ?? key.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());
}

export const OUTCOME_LABEL: Record<string, string> = {
  handled_on_scene: 'Handled on scene',
  transported: 'Casualties transported',
  turned_over: 'Turned over',
  false_alarm: 'False alarm',
  nobody_found: 'Nobody found',
  other: 'Other',
};
export const outcomeLabel = (k: string) => OUTCOME_LABEL[k] ?? k.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());

export const CHANNEL_LABEL: Record<string, string> = {
  internet: 'Mobile app',
  offline_sync: 'Offline sync',
};

export const SIGNAL_LABEL: Record<string, string> = {
  injuries: 'People injured',
  fire: 'Fire involved',
  flooding: 'Flooding',
  missing_person: 'Missing person',
  hazmat: 'Hazardous materials',
};

export const SEVERITY_WORD: Record<string, string> = {
  critical: 'Critical', high: 'High', medium: 'Medium', low: 'Low', untriaged: 'Unscored',
};

/** Time-ago in a few words, from an ISO string. */
export function ago(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return 'never';
  const t = new Date(iso).getTime();
  if (Number.isNaN(t)) return '—';
  const mins = Math.max(0, Math.round((now - t) / 60000));
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  const h = Math.round(mins / 60);
  if (h < 48) return `${h}h ago`;
  return `${Math.round(h / 24)}d ago`;
}

/**
 * "Better or worse than last period", as a badge. `riseIsBad` is stated by each
 * caller, as DeltaBadge requires: more reports and slower dispatches are worse,
 * a higher resolved share is better. Nothing is shown when either side is
 * missing — a change against nothing is not a change.
 */
export function Change({
  now,
  before,
  riseIsBad = true,
  unit = '',
  since,
}: {
  now: number | null | undefined;
  before: number | null | undefined;
  riseIsBad?: boolean;
  unit?: string;
  /** What the comparison is against, for the tooltip: "the 30 days before". */
  since: string;
}) {
  if (now === null || now === undefined || before === null || before === undefined) return undefined;
  const raw = now - before;
  const diff = Math.abs(raw) >= 10 ? Math.round(raw) : Math.round(raw * 10) / 10;
  return (
    <span title={`${diff === 0 ? 'No change' : diff > 0 ? 'Up' : 'Down'} from ${fmtNumber(before)}${unit} in ${since}`}>
      <DeltaBadge riseIsBad={riseIsBad} suffix={unit} value={diff} />
    </span>
  );
}

const fmtNumber = (n: number) => (Number.isInteger(n) ? String(n) : String(Number(n.toFixed(1))));

// ── Panel ────────────────────────────────────────────────────────────────

/** A titled card. The one container every block on the screen sits in. */
export function Panel({
  title,
  description,
  action,
  children,
  className,
  bodyClassName,
  flush = false,
  id,
}: {
  title?: React.ReactNode;
  description?: React.ReactNode;
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  bodyClassName?: string;
  /** No body padding — for a table that meets the card's edges. */
  flush?: boolean;
  id?: string;
}) {
  return (
    <section
      className={cn(
        'flex min-w-0 flex-col rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]',
        className,
      )}
      id={id}
    >
      {(title || action) && (
        <header className="flex flex-wrap items-start justify-between gap-x-4 gap-y-2 px-5 pb-1 pt-4">
          <div className="min-w-0">
            {title && <h2 className="text-[15px] font-semibold tracking-tight text-foreground">{title}</h2>}
            {description && <p className="mt-0.5 text-[12.5px] leading-relaxed text-muted-foreground">{description}</p>}
          </div>
          {action && <div className="shrink-0">{action}</div>}
        </header>
      )}
      <div className={cn(flush ? 'pt-3' : 'px-5 pb-5 pt-3', bodyClassName)}>{children}</div>
    </section>
  );
}

// ── KPI ──────────────────────────────────────────────────────────────────

export type Tone = 'brand' | 'critical' | 'warning' | 'success' | 'info' | 'neutral';

export const TONE: Record<Tone, { fg: string; bg: string }> = {
  brand:    { fg: 'var(--color-brand)',              bg: 'var(--color-brand-subtle)' },
  critical: { fg: 'var(--color-severity-critical)',  bg: 'var(--color-severity-critical-bg)' },
  warning:  { fg: 'var(--color-system-warning)',     bg: 'var(--color-system-warning-bg)' },
  success:  { fg: 'var(--color-system-success)',     bg: 'var(--color-system-success-bg)' },
  info:     { fg: 'var(--color-status-processing)',  bg: 'var(--color-status-processing-bg)' },
  neutral:  { fg: 'var(--color-text-secondary)',     bg: 'var(--color-surface-raised)' },
};

/** One headline figure: icon, label, the number, and one line that qualifies it. */
export function Kpi({
  icon: Icon,
  tone = 'neutral',
  label,
  value,
  unit,
  sub,
  delta,
  onClick,
  ariaLabel,
}: {
  icon: LucideIcon;
  tone?: Tone;
  label: string;
  value: React.ReactNode;
  unit?: string;
  sub?: React.ReactNode;
  delta?: React.ReactNode;
  onClick?: () => void;
  ariaLabel?: string;
}) {
  const t = TONE[tone];
  const body = (
    <>
      <div className="flex items-center gap-2.5">
        <span
          aria-hidden="true"
          className="flex size-8 shrink-0 items-center justify-center rounded-[10px]"
          style={{ backgroundColor: t.bg, color: t.fg }}
        >
          <Icon className="size-4" />
        </span>
        <span className="min-w-0 flex-1 truncate text-[13px] font-medium text-[var(--color-text-secondary)]">{label}</span>
        {delta}
      </div>
      <p className="mt-3 flex items-baseline gap-1.5 text-foreground">
        <span className="text-[28px] font-bold leading-none tracking-tight tabular-nums">{value}</span>
        {unit && <span className="text-[13px] font-medium text-muted-foreground">{unit}</span>}
      </p>
      {sub && <p className="mt-2 text-[12px] leading-snug text-muted-foreground">{sub}</p>}
    </>
  );
  const cls =
    'flex min-w-0 flex-col rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4 text-left shadow-[var(--shadow-card)]';
  return onClick ? (
    <button aria-label={ariaLabel} className={cn(cls, 'transition-colors hover:bg-[var(--color-surface-raised)]/50 focus-visible:outline-2 focus-visible:outline-[var(--color-brand)]')} data-kpi={label} onClick={onClick} type="button">
      {body}
    </button>
  ) : (
    <div className={cls} data-kpi={label}>{body}</div>
  );
}

// ── Chips ────────────────────────────────────────────────────────────────

export function SevChip({ severity, className }: { severity: string | null | undefined; className?: string }) {
  const key = severity ?? 'untriaged';
  const color = SEV_COLOR[key] ?? 'var(--color-text-muted)';
  return (
    <span
      className={cn('inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide', className)}
      style={{ color, backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)` }}
    >
      <span aria-hidden="true" className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
      {SEVERITY_WORD[key] ?? key}
    </span>
  );
}

export function StatusChip({ status }: { status: string | null | undefined }) {
  const s = STATUS_STYLE[status ?? ''] ?? { bg: 'var(--color-surface-raised)', text: 'var(--color-text-secondary)' };
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide" style={{ color: s.text, backgroundColor: s.bg }}>
      <span aria-hidden="true" className="size-1.5 rounded-full" style={{ backgroundColor: s.text }} />
      {statusLabel(status ?? 'received')}
    </span>
  );
}

export function AgencyChip({ type, className }: { type: string | null | undefined; className?: string }) {
  if (!type) return null;
  return (
    <span
      className={cn('inline-flex items-center rounded-md px-1.5 py-0.5 text-[11px] font-bold tracking-wide', className)}
      style={{ color: AG_COLOR[type] ?? 'var(--color-text-secondary)', backgroundColor: AG_BG[type] ?? 'var(--color-surface-raised)' }}
    >
      {type}
    </span>
  );
}

// ── Meter ────────────────────────────────────────────────────────────────

/** A horizontal bar showing `value` of `max`. The number is always beside it — never colour or length alone. */
export function Meter({
  value,
  max,
  color = 'var(--color-status-processing)',
  height = 8,
  ariaLabel,
}: {
  value: number;
  max: number;
  color?: string;
  height?: number;
  ariaLabel?: string;
}) {
  const pct = max > 0 ? Math.min(100, Math.max(0, (value / max) * 100)) : 0;
  return (
    <div
      aria-label={ariaLabel}
      aria-valuemax={max}
      aria-valuemin={0}
      aria-valuenow={value}
      className="w-full overflow-hidden rounded-full bg-[var(--color-surface-raised)]"
      role="meter"
      style={{ height }}
    >
      <div className="h-full rounded-full transition-[width] duration-300" style={{ width: `${pct}%`, backgroundColor: color }} />
    </div>
  );
}

/** A ranked list of label / bar / count rows — the workhorse for "how many of each". */
export function BarList({
  items,
  color = 'var(--color-status-processing)',
  empty = 'Nothing to show for this period.',
  icon,
}: {
  items: { key: string; label: string; count: number; color?: string; icon?: LucideIcon; hint?: string }[];
  color?: string;
  empty?: string;
  icon?: boolean;
}) {
  if (items.length === 0) return <p className="py-6 text-center text-[13px] text-muted-foreground">{empty}</p>;
  const max = Math.max(1, ...items.map(i => i.count));
  return (
    <ul className="flex flex-col gap-3">
      {items.map(i => {
        const Icon = i.icon;
        return (
          <li key={i.key}>
            <div className="mb-1 flex items-center justify-between gap-3 text-[13px]">
              <span className="flex min-w-0 items-center gap-2 text-foreground">
                {icon && Icon && <Icon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />}
                <span className="truncate">{i.label}</span>
              </span>
              <span className="shrink-0 font-semibold tabular-nums text-foreground">{fmtInt(i.count)}</span>
            </div>
            <Meter ariaLabel={`${i.label}: ${i.count}`} color={i.color ?? color} max={max} value={i.count} />
            {i.hint && <p className="mt-1 text-[11.5px] text-muted-foreground">{i.hint}</p>}
          </li>
        );
      })}
    </ul>
  );
}

// ── Empty / note ─────────────────────────────────────────────────────────

export function Empty({ icon: Icon, title, children }: { icon: LucideIcon; title: string; children?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-10 text-center">
      <span className="flex size-10 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-muted-foreground">
        <Icon aria-hidden="true" className="size-5" />
      </span>
      <p className="text-[14px] font-semibold text-foreground">{title}</p>
      {children && <p className="max-w-md text-[12.5px] leading-relaxed text-muted-foreground">{children}</p>}
    </div>
  );
}

/** A quiet explanation under a figure — what it counts, and what it does not. */
export function Note({
  children,
  tone = 'neutral',
  icon: Icon,
}: {
  children: React.ReactNode;
  tone?: 'neutral' | 'warning';
  icon?: LucideIcon;
}) {
  const warn = tone === 'warning';
  return (
    <p
      className="flex items-start gap-2 rounded-[10px] px-3 py-2 text-[12px] leading-relaxed text-[var(--color-text-secondary)]"
      style={{ backgroundColor: warn ? 'var(--color-system-warning-bg)' : 'var(--color-surface-raised)' }}
    >
      {Icon && (
        <Icon
          aria-hidden="true"
          className="mt-0.5 size-3.5 shrink-0"
          style={{ color: warn ? 'var(--color-system-warning)' : 'var(--color-text-tertiary)' }}
        />
      )}
      <span>{children}</span>
    </p>
  );
}

/** Sortable table header cell. */
export function SortTh({
  label,
  active,
  dir,
  onClick,
  align = 'left',
  className,
}: {
  label: string;
  active: boolean;
  dir: 'asc' | 'desc';
  onClick: () => void;
  align?: 'left' | 'center' | 'right';
  className?: string;
}) {
  return (
    <th
      aria-sort={active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'}
      className={cn(
        'whitespace-nowrap px-4 py-2.5 text-[11.5px] font-semibold uppercase tracking-wide text-muted-foreground',
        align === 'right' && 'text-right', align === 'center' && 'text-center',
        className,
      )}
      scope="col"
    >
      <button
        className={cn('inline-flex items-center gap-1 uppercase tracking-wide hover:text-foreground', active && 'text-foreground')}
        onClick={onClick}
        type="button"
      >
        {label}
        {dir === 'asc'
          ? <ChevronUp aria-hidden="true" className={cn('size-3.5 shrink-0', !active && 'opacity-0')} />
          : <ChevronDown aria-hidden="true" className={cn('size-3.5 shrink-0', !active && 'opacity-0')} />}
      </button>
    </th>
  );
}
