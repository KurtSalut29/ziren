/**
 * Responder availability status (Agency Admin spec Section 7): who can
 * respond, right now, without cross-referencing the account-level on/off
 * duty flag against whichever incident happens to reference them.
 *
 * Extracted from responders/page.tsx so the Dispatch modal's responder
 * picker (incidents/[id]/page.tsx) can show the same status without a
 * second, drifting copy of the color/label map.
 */

export type CurrentStatus = 'offline' | 'available' | 'assigned' | 'en_route' | 'on_scene' | null;

/** Same status → color mapping incident badges already use (incident-vocabulary.ts)
 *  — Assigned/En Route/On Scene ARE dispatched/en_route/arrived, just read from
 *  the responder's side, so they carry the same colors for the same meaning. */
export const STATUS_META: Record<Exclude<CurrentStatus, null>, { label: string; color: string; bg: string }> = {
  available:  { label: 'Available',  color: 'var(--color-system-success)',    bg: 'var(--color-system-success-bg)' },
  assigned:   { label: 'Assigned',   color: 'var(--color-status-dispatched)', bg: 'var(--color-status-dispatched-bg)' },
  en_route:   { label: 'En Route',   color: 'var(--color-status-dispatched)', bg: 'var(--color-status-dispatched-bg)' },
  on_scene:   { label: 'On Scene',   color: 'var(--color-system-success)',    bg: 'var(--color-system-success-bg)' },
  offline:    { label: 'Offline',    color: 'var(--color-text-muted)',        bg: 'var(--color-surface-raised)' },
};

/**
 * A responder's current assignment, in the trimmed shape both callers
 * (responders/page.tsx's roster, the Dispatch modal's picker) already
 * receive from the backend.
 */
export interface CurrentIncidentRef {
  id: string;
  incident_category: string | null;
  location_address: string | null;
}

export function assignmentLabel(incident: CurrentIncidentRef | null): string | null {
  if (!incident) return null;
  return [incident.incident_category?.replace(/_/g, ' '), incident.location_address]
    .filter(Boolean).join(' — ') || 'Incident';
}

/** Renders nothing when status is null — a responder whose approval isn't
 *  'approved' has no current_status to show (see users.py's derivation). */
export function StatusPill({ status, currentIncident }: {
  status: CurrentStatus;
  currentIncident?: CurrentIncidentRef | null;
}) {
  if (!status) return null;
  const meta = STATUS_META[status];
  const label = assignmentLabel(currentIncident ?? null);

  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11.5px] font-semibold"
      style={{ backgroundColor: meta.bg, color: meta.color }}
      title={label ? `Current assignment: ${label}` : 'No current assignment'}
    >
      <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: meta.color }} />
      {meta.label}
    </span>
  );
}
