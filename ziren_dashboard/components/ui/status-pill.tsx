/**
 * StatusPill — compact inline status indicator used in list rows and table cells.
 *
 * Compared to StatusBadge (badge.tsx), StatusPill is slightly larger and always
 * includes a leading color dot — designed for scan-heavy list views where the
 * dispatcher needs to triage status at a glance across many rows.
 *
 * The dot satisfies the "never color alone" accessibility rule when paired with
 * the text label (both present by default).
 *
 * For standalone severity display, use SeverityBadge from badge.tsx instead.
 */

type PillStatus =
  | 'critical'    // high-urgency emergency — maps to severity-critical red
  | 'pending'     // unacknowledged / unassigned — maps to severity-high amber
  | 'progress'    // in-progress / dispatched — maps to status-processing indigo
  | 'resolved'    // closed — maps to status-resolved green
  | 'cancelled'   // cancelled — maps to status-cancelled grey
  | 'online'      // connectivity — green
  | 'offline'     // connectivity — grey
  | 'syncing';    // connectivity — amber

interface StatusPillConfig {
  dot: string;    // Tailwind bg class for the dot color
  text: string;   // Tailwind text class for the label
  bg: string;     // Tailwind bg class for the pill background
  label: string;  // default display label
}

const PILL_CONFIG: Record<PillStatus, StatusPillConfig> = {
  critical: {
    dot: 'bg-[var(--color-severity-critical)]',
    text: 'text-[var(--color-severity-critical)]',
    bg: 'bg-[var(--color-severity-critical-bg)]',
    label: 'Critical',
  },
  pending: {
    dot: 'bg-[var(--color-severity-high)]',
    text: 'text-[var(--color-severity-high)]',
    bg: 'bg-[var(--color-severity-high-bg)]',
    label: 'Pending',
  },
  progress: {
    dot: 'bg-[var(--color-status-processing)]',
    text: 'text-[var(--color-status-processing)]',
    bg: 'bg-[var(--color-status-processing-bg)]',
    label: 'In Progress',
  },
  resolved: {
    dot: 'bg-[var(--color-status-resolved)]',
    text: 'text-[var(--color-status-resolved)]',
    bg: 'bg-[var(--color-status-resolved-bg)]',
    label: 'Resolved',
  },
  cancelled: {
    dot: 'bg-[var(--color-status-cancelled)]',
    text: 'text-[var(--color-status-cancelled)]',
    bg: 'bg-[var(--color-status-cancelled-bg)]',
    label: 'Cancelled',
  },
  online: {
    dot: 'bg-[var(--color-connectivity-online)]',
    text: 'text-[var(--color-connectivity-online)]',
    bg: 'bg-[var(--color-system-success-bg)]',
    label: 'Online',
  },
  offline: {
    dot: 'bg-[var(--color-connectivity-offline)]',
    text: 'text-[var(--color-connectivity-offline)]',
    bg: 'bg-[var(--color-status-cancelled-bg)]',
    label: 'Offline',
  },
  syncing: {
    dot: 'bg-[var(--color-connectivity-sms)]',
    text: 'text-[var(--color-connectivity-sms)]',
    bg: 'bg-[var(--color-system-warning-bg)]',
    label: 'Syncing',
  },
};

interface StatusPillProps {
  status: PillStatus;
  /** Override the default label — e.g. "En Route" instead of "In Progress" */
  label?: string;
  /** Animate the dot — useful for 'online' / 'syncing' live states */
  pulse?: boolean;
  className?: string;
}

export function StatusPill({
  status,
  label,
  pulse = false,
  className = '',
}: StatusPillProps) {
  const cfg = PILL_CONFIG[status];
  const displayLabel = label ?? cfg.label;

  return (
    <span
      className={[
        'inline-flex items-center gap-1.5 px-2.5 py-1',
        'rounded-[var(--radius-full)]',
        'text-[12px] font-semibold leading-none',
        cfg.bg,
        cfg.text,
        className,
      ].join(' ')}
    >
      {/* Dot — color indicator, paired with label text for a11y */}
      <span
        aria-hidden="true"
        className={[
          'w-1.5 h-1.5 rounded-full shrink-0',
          cfg.dot,
          pulse ? 'animate-pulse' : '',
        ].join(' ')}
      />
      {displayLabel}
    </span>
  );
}
