/**
 * The pieces the two incident tables share: the live queue (IncidentTable) and
 * Incident Records (IncidentRecordTable).
 *
 * They were drawn separately and had drifted: severity was an outlined word in
 * one and a filled chip in the other, status was sentence case here and bold
 * capitals there, and neither header looked like the console's other tables.
 * One report now looks the same in both places, which matters because a
 * dispatcher moves between them all shift.
 */

import { Siren, Tag } from 'lucide-react';
import type { QueueIncident } from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { cn } from '@/lib/utils';
import {
  AWAITING_STATUSES, CATEGORY_ICON, SEV_COLOR, SEV_ICON, STATUS_STYLE, statusLabel,
} from './incident-vocabulary';

/** The header band: the same tinted strip and quiet capitals as DataTable, so
 *  every table on the console reads as one family. Opaque, because the records
 *  table's header is sticky and rows scroll under it. */
export const TABLE_HEAD_CELL =
  'h-10 bg-[var(--color-surface-raised)] px-3 align-middle text-[11px] font-semibold ' +
  'uppercase tracking-[0.06em] whitespace-nowrap text-[var(--color-text-tertiary)]';

/** Severity as an icon AND a word in its colour. Never colour alone. */
export function SeverityChip({ severity }: { severity: string | null | undefined }) {
  const key = severity ?? 'untriaged';
  const color = SEV_COLOR[key] ?? 'var(--color-text-muted)';
  const Icon = SEV_ICON[key] ?? SEV_ICON.untriaged;
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-[6px] border px-1.5 py-[3px] text-[10.5px] leading-none font-bold tracking-wide whitespace-nowrap uppercase"
      style={{
        color,
        borderColor: `color-mix(in srgb, ${color} 40%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${color} 10%, transparent)`,
      }}
    >
      <Icon aria-hidden="true" size={11} strokeWidth={2.5} />
      {key}
    </span>
  );
}

/** Where the report is in the workflow: a dot and the words. */
export function StatusPill({ status, label }: { status: string; label?: string }) {
  const sc = STATUS_STYLE[status] ?? STATUS_STYLE.received;
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2 py-[3px] text-[11.5px] leading-tight font-semibold whitespace-nowrap"
      style={{ backgroundColor: sc.bg, color: sc.text }}
    >
      <span aria-hidden="true" className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: sc.text }} />
      {label ?? statusLabel(status)}
    </span>
  );
}

/**
 * What an open report is waiting FOR, in the words the detail dialog uses.
 *
 * The queue used to say "Received" on every row that had not been dispatched,
 * which is true and useless: a report nobody has looked at, one that was
 * accepted and needs a crew, and one waiting on the resident's answer are
 * three different jobs. The dialog already told them apart; the table did not.
 */
export function queueStateLabel(incident: QueueIncident): string {
  if (AWAITING_STATUSES.includes(incident.status)) {
    if (incident.review_status === 'pending') return 'Needs review';
    if (incident.review_status === 'clarification_requested') return 'Waiting for reporter';
    if (incident.review_status === 'accepted') return 'Awaiting dispatch';
  }
  return statusLabel(incident.status);
}

/** The category as an icon in a tinted tile, named on hover. */
export function CategoryTile({
  category,
  color,
  className,
}: {
  category: string | null | undefined;
  /** Tints the tile. The queue passes the severity colour; records stay neutral. */
  color?: string;
  className?: string;
}) {
  const Icon = category ? (CATEGORY_ICON[category] ?? Tag) : Tag;
  const label = category && category !== 'other' ? CATEGORY_LABELS[category] : null;
  const tone = color ?? 'var(--color-text-secondary)';
  return (
    <span
      className={cn('flex size-8 shrink-0 items-center justify-center rounded-[9px]', className)}
      style={{ color: tone, backgroundColor: `color-mix(in srgb, ${tone} 11%, transparent)` }}
      title={label ?? 'Category not chosen by the reporter'}
    >
      <Icon aria-hidden="true" size={16} />
    </span>
  );
}

/** An SOS is a different kind of report, not a severity — so its own mark. */
export function SosChip() {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full border px-1.5 py-[3px] text-[10px] leading-none font-bold tracking-wide uppercase"
      style={{
        color: 'var(--color-severity-critical)',
        borderColor: 'color-mix(in srgb, var(--color-severity-critical) 40%, transparent)',
        backgroundColor: 'color-mix(in srgb, var(--color-severity-critical) 8%, transparent)',
      }}
    >
      <Siren aria-hidden="true" size={10} />
      SOS
    </span>
  );
}
