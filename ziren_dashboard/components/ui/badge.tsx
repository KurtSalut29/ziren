/**
 * Badge — small inline label used for severity, agency, status, and role display.
 *
 * Variants:
 *   severity   — uses the 4-tier severity color system (critical/high/medium/low)
 *   agency     — BFP / PNP / MDRRMO locked agency colors
 *   status     — workflow status lifecycle colors
 *   role       — user role labels (neutral tint)
 *   ai         — purple, machine-output ONLY (mirrors .badge-ai in globals.css)
 *   neutral    — grey tint, for tags/labels with no semantic color meaning
 *
 * Accessibility: Badge is display-only. When used for severity, always pair with
 * an icon or label text — never rely on color alone (globals.css color rules).
 */

import { ReactNode } from 'react';

// ── Severity ──────────────────────────────────────────────────────────────────
type SeverityLevel = 'critical' | 'high' | 'medium' | 'low';

const SEVERITY_STYLES: Record<SeverityLevel, string> = {
  critical:
    'bg-[var(--color-severity-critical-bg)] text-[var(--color-severity-critical)] border border-[var(--color-severity-critical-border)]',
  high: 'bg-[var(--color-severity-high-bg)] text-[var(--color-severity-high)] border border-[var(--color-severity-high-border)]',
  medium:
    'bg-[var(--color-severity-medium-bg)] text-[var(--color-severity-medium)] border border-[var(--color-severity-medium-border)]',
  low: 'bg-[var(--color-severity-low-bg)] text-[var(--color-severity-low)] border border-[var(--color-severity-low-border)]',
};

export function SeverityBadge({ level }: { level: SeverityLevel }) {
  return (
    <span
      className={[
        'inline-flex items-center gap-1 px-2 py-0.5 rounded-[var(--radius-full)]',
        'text-[11px] font-bold tracking-wide uppercase',
        SEVERITY_STYLES[level],
      ].join(' ')}
    >
      {/* Color-blind-safe shape indicator — filled square dot */}
      <span aria-hidden="true" className="w-1.5 h-1.5 rounded-sm bg-current" />
      {level}
    </span>
  );
}

// ── Agency ────────────────────────────────────────────────────────────────────
type AgencyType = 'BFP' | 'PNP' | 'MDRRMO';

const AGENCY_STYLES: Record<AgencyType, string> = {
  BFP: 'bg-[var(--color-agency-bfp-bg)] text-[var(--color-agency-bfp)]',
  PNP: 'bg-[var(--color-agency-pnp-bg)] text-[var(--color-agency-pnp)]',
  MDRRMO: 'bg-[var(--color-agency-mdrrmo-bg)] text-[var(--color-agency-mdrrmo)]',
};

export function AgencyBadge({ agency }: { agency: AgencyType | string }) {
  const style =
    AGENCY_STYLES[agency as AgencyType] ??
    'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]';

  return (
    <span
      className={[
        'inline-flex items-center px-2 py-0.5 rounded-[var(--radius-full)]',
        'text-[11px] font-bold tracking-wide',
        style,
      ].join(' ')}
    >
      {agency}
    </span>
  );
}

// ── Status (workflow lifecycle) ───────────────────────────────────────────────
type WorkflowStatus =
  | 'received'
  | 'processing'
  | 'dispatched'
  | 'en_route'
  | 'arrived'
  | 'resolved'
  | 'cancelled';

const STATUS_STYLES: Record<WorkflowStatus, string> = {
  received:
    'bg-[var(--color-status-received-bg)] text-[var(--color-status-received)]',
  processing:
    'bg-[var(--color-status-processing-bg)] text-[var(--color-status-processing)]',
  dispatched:
    'bg-[var(--color-status-dispatched-bg)] text-[var(--color-status-dispatched)]',
  en_route:
    'bg-[var(--color-status-dispatched-bg)] text-[var(--color-status-dispatched)]',
  arrived:
    'bg-[var(--color-system-success-bg)] text-[var(--color-system-success)]',
  resolved:
    'bg-[var(--color-status-resolved-bg)] text-[var(--color-status-resolved)]',
  cancelled:
    'bg-[var(--color-status-cancelled-bg)] text-[var(--color-status-cancelled)]',
};

const STATUS_LABELS: Record<WorkflowStatus, string> = {
  received: 'Received',
  processing: 'Processing',
  dispatched: 'Dispatched',
  en_route: 'En Route',
  arrived: 'Arrived',
  resolved: 'Resolved',
  cancelled: 'Cancelled',
};

export function StatusBadge({ status }: { status: WorkflowStatus | string }) {
  const style =
    STATUS_STYLES[status as WorkflowStatus] ??
    'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]';
  const label =
    STATUS_LABELS[status as WorkflowStatus] ??
    status.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase());

  return (
    <span
      className={[
        'inline-flex items-center px-2.5 py-0.5 rounded-[var(--radius-full)]',
        'text-[11px] font-bold',
        style,
      ].join(' ')}
    >
      {label}
    </span>
  );
}

// ── Role ──────────────────────────────────────────────────────────────────────
type UserRole = 'resident' | 'responder' | 'agency_admin' | 'provincial_admin';

const ROLE_LABELS: Record<UserRole, string> = {
  resident: 'Resident',
  responder: 'Responder',
  agency_admin: 'Agency Admin',
  provincial_admin: 'Provincial Admin',
};

export function RoleBadge({ role }: { role: UserRole | string }) {
  const label =
    ROLE_LABELS[role as UserRole] ??
    role.replace('_', ' ').replace(/\b\w/g, (l) => l.toUpperCase());

  return (
    <span
      className={[
        'inline-flex items-center px-2.5 py-0.5 rounded-[var(--radius-full)]',
        'text-[11px] font-bold',
        'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]',
      ].join(' ')}
    >
      {label}
    </span>
  );
}

// ── AI-suggested ──────────────────────────────────────────────────────────────
export function AiBadge({ label = 'AI suggested' }: { label?: string }) {
  return (
    <span className="badge-ai">{label}</span>
  );
}

// ── Generic / neutral ─────────────────────────────────────────────────────────
export function Badge({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={[
        'inline-flex items-center px-2.5 py-0.5 rounded-[var(--radius-full)]',
        'text-[11px] font-semibold',
        'bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]',
        className,
      ].join(' ')}
    >
      {children}
    </span>
  );
}
