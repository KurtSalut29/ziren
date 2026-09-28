'use client';

/**
 * Agency Admin — Responders
 *
 * The agency's field roster: who is on duty, and who is waiting on an
 * approval decision. Approvals are the work this page exists for, so they
 * lead the status line and sort to the top of the list.
 */

import { Children, useCallback, useEffect, useState } from 'react';
import { motion } from 'framer-motion';
import {
  Check, Hourglass, RefreshCw, UserCheck, UserX, X, Users,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Fig } from '@/components/ui/fig';
import { PageHeader } from '@/components/shell/page-header';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import {
  assignmentLabel, StatusPill, type CurrentStatus, type CurrentIncidentRef,
} from '@/components/responders/status-pill';
import { useNotice } from '@/lib/toast';

interface ResponderUser {
  id: string;
  email: string;
  full_name: string;
  badge_id: string | null;
  approval_status: 'pending' | 'approved' | 'rejected' | 'not_required';
  availability: 'on_duty' | 'off_duty';
  is_verified: boolean;
  created_at: string;
  /**
   * Agency Admin spec Section 7 (Responder Availability): who can respond,
   * right now, without cross-referencing the duty flag against whichever
   * incident happens to reference them. "Unavailable" (the spec's sixth
   * state — e.g. on break) never appears: this schema has no signal for it
   * distinct from off_duty, so it is never fabricated.
   */
  current_status: CurrentStatus;
  current_incident: CurrentIncidentRef | null;
}

export default function RespondersPage() {
  const { token, isProvincialAdmin } = useAuth();
  const [responders, setResponders] = useState<ResponderUser[]>([]);
  const [loading, setLoading]       = useState(true);
  const [error, setError]           = useState<string | null>(null);
  const setActionMsg = useNotice();
  const [acting, setActing]         = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    setLoading(true); setError(null);
    try {
      const data = await apiClient.get<ResponderUser[]>('/users/agency/responders', token);
      setResponders(data);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load responders.');
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  async function updateApproval(id: string, approval_status: 'approved' | 'rejected') {
    if (!token) return;
    setActing(id); setActionMsg(null);
    try {
      await apiClient.patch(`/users/agency/responders/${id}/approval`, { approval_status }, token);
      setActionMsg({
        type: 'success',
        text: `Responder ${approval_status === 'approved' ? 'approved' : 'rejected'}.`,
      });
      await load();
    } catch (e: unknown) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Action failed.' });
    } finally {
      setActing(null);
    }
  }

  const pending  = responders.filter(r => r.approval_status === 'pending');
  const approved = responders.filter(r => r.approval_status === 'approved');
  const rejected = responders.filter(r => r.approval_status === 'rejected');
  const onDuty   = approved.filter(r => r.availability === 'on_duty');

  const total = responders.length;
  const share = (n: number) => (total > 0 ? (n / total) * 100 : 0);

  return (
    <div className="min-h-full">
      <PageHeader
        meta={`${isProvincialAdmin ? 'Province-wide' : 'Your agency'} · roster updates when a responder registers in the mobile app`}
      >
        Who can respond to incidents, and who is waiting on your decision.
      </PageHeader>

      <div className="space-y-5 px-6 py-5 md:px-7">
        <StatStrip>
          <StatCell
            icon={<Users size={12} strokeWidth={2} />}
            label="Roster"
            value={total}
            trend="All registered responders"
            color="var(--color-brand)"
            bg="var(--color-brand-subtle)"
          />
          <StatCell
            icon={<UserCheck size={12} strokeWidth={2} />}
            label="On duty"
            value={onDuty.length}
            trend={`${Math.round(share(onDuty.length))}% of the roster`}
            color="var(--color-system-success)"
            bg="var(--color-system-success-bg)"
          />
          {/* Hourglass, not Shield. A shield says "protected"; what this cell
              counts is people held in a queue waiting on a human decision —
              the same idea as Longest wait on the overview, so it takes the
              same icon. */}
          <StatCell
            icon={<Hourglass size={12} strokeWidth={2} />}
            label="Awaiting approval"
            value={pending.length}
            trend={pending.length > 0 ? 'Needs a decision' : 'Nothing waiting'}
            color="var(--color-system-warning)"
            bg="var(--color-system-warning-bg)"
          />
          <StatCell
            icon={<UserX size={12} strokeWidth={2} />}
            label="Rejected"
            value={rejected.length}
            trend={`${Math.round(share(rejected.length))}% of the roster`}
            color="var(--color-status-processing)"
            bg="var(--color-status-processing-bg)"
          />
        </StatStrip>

        {error && <Alert variant="error" message={error} />}

        {loading && total === 0 ? (
          <div className="flex items-center justify-center py-24">
            <RefreshCw className="h-6 w-6 animate-spin text-[var(--color-text-muted)]" />
          </div>
        ) : (
          <div className="space-y-7">
            {pending.length > 0 && (
              <Section title="Awaiting approval" count={pending.length} color="var(--color-system-warning)">
                {pending.map(r => (
                  <ResponderCard key={r.id} responder={r} acting={acting === r.id}
                    actions={
                      <div className="flex gap-2">
                        <Button variant="success" size="sm" onClick={() => updateApproval(r.id, 'approved')} disabled={acting === r.id} isLoading={acting === r.id}>
                          <UserCheck className="mr-1.5 h-3.5 w-3.5" /> Approve
                        </Button>
                        <Button variant="danger" size="sm" onClick={() => updateApproval(r.id, 'rejected')} disabled={acting === r.id} isLoading={acting === r.id}>
                          <UserX className="mr-1.5 h-3.5 w-3.5" /> Reject
                        </Button>
                      </div>
                    }
                  />
                ))}
              </Section>
            )}

            {approved.length > 0 && (
              <Section title="Approved" count={approved.length} color="var(--color-system-success)">
                {approved.map(r => (
                  <ResponderCard key={r.id} responder={r} acting={acting === r.id}
                    actions={
                      <Button variant="ghost" size="sm" onClick={() => updateApproval(r.id, 'rejected')} disabled={acting === r.id} isLoading={acting === r.id}>
                        <X className="mr-1.5 h-3.5 w-3.5" /> Revoke
                      </Button>
                    }
                  />
                ))}
              </Section>
            )}

            {rejected.length > 0 && (
              <Section title="Rejected" count={rejected.length} color="var(--color-text-muted)">
                {rejected.map(r => (
                  <ResponderCard key={r.id} responder={r} acting={acting === r.id}
                    actions={
                      <Button variant="outline" size="sm" onClick={() => updateApproval(r.id, 'approved')} disabled={acting === r.id} isLoading={acting === r.id}>
                        <Check className="mr-1.5 h-3.5 w-3.5" /> Re-approve
                      </Button>
                    }
                  />
                ))}
              </Section>
            )}

            {total === 0 && (
              <div className="flex flex-col items-center justify-center gap-3 py-24">
                <span
                  aria-hidden="true"
                  className="flex h-14 w-14 items-center justify-center rounded-full bg-[var(--color-surface-raised)]"
                >
                  <Users className="h-7 w-7 text-[var(--color-text-muted)]" />
                </span>
                <div className="text-center">
                  <p className="text-ui font-medium text-[var(--color-text-primary)]">No responders yet</p>
                  <p className="mt-1 text-meta text-[var(--color-text-muted)]">
                    Responders appear here once they register in the mobile app.
                  </p>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function Section({ title, count, color, children }: {
  title: string; count: number; color: string; children: React.ReactNode;
}) {
  return (
    <section>
      <div className="mb-3 flex items-center gap-2.5">
        <span aria-hidden="true" className="h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: color }} />
        <span className="text-section-label" style={{ color: 'var(--color-text-tertiary)' }}>{title}</span>
        <Fig className="text-[11px] text-[var(--color-text-muted)]">{count}</Fig>
        <div className="h-px flex-1 bg-[var(--color-surface-border)]" />
      </div>
      <div className="space-y-2">
        {Children.map(children, (child, i) => (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.22, delay: Math.min(i, 6) * 0.03, ease: [0.16, 1, 0.3, 1] }}
          >
            {child}
          </motion.div>
        ))}
      </div>
    </section>
  );
}

function ResponderCard({ responder, actions, acting }: {
  responder: ResponderUser; actions: React.ReactNode; acting: boolean;
}) {
  const initials = responder.full_name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
  const label = assignmentLabel(responder.current_incident);

  return (
    <div className="flex flex-wrap items-center justify-between gap-4 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4 transition-colors hover:border-[var(--color-border-strong)]">
      <div className="flex items-center gap-3.5">
        <span className="relative inline-flex shrink-0">
          <span
            aria-hidden="true"
            className="flex h-11 w-11 items-center justify-center rounded-full bg-[var(--color-brand-subtle)] text-[13px] font-semibold text-[var(--color-brand)]"
          >
            {initials}
          </span>
          {/* Supplementary only — the StatusPill beside the name is the
              accessible, labelled statement of duty; this dot is the
              at-a-glance reinforcement TailAdmin's avatar pattern adds. */}
          <span
            aria-hidden="true"
            className="absolute right-0 bottom-0 size-3 rounded-full ring-2 ring-[var(--color-surface-card)]"
            style={{
              backgroundColor: responder.availability === 'on_duty'
                ? 'var(--color-system-success)'
                : 'var(--color-connectivity-offline)',
            }}
          />
        </span>
        <div className="min-w-0">
          <p className="text-ui font-medium text-[var(--color-text-primary)]">{responder.full_name}</p>
          <p className="mt-0.5 text-meta text-[var(--color-text-muted)]">
            {responder.email}
            {responder.badge_id && (
              <Fig className="ml-2 text-[var(--color-text-secondary)]">#{responder.badge_id}</Fig>
            )}
          </p>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-3">
        <StatusPill status={responder.current_status} currentIncident={responder.current_incident} />
        {label && (
          <span className="max-w-[220px] truncate text-meta text-[var(--color-text-secondary)]">
            {label}
          </span>
        )}
        <span className="text-meta text-[var(--color-text-muted)]">
          Joined <Fig>{new Date(responder.created_at).toLocaleDateString()}</Fig>
        </span>
        <div className={acting ? 'pointer-events-none opacity-50' : ''}>
          {actions}
        </div>
      </div>
    </div>
  );
}
