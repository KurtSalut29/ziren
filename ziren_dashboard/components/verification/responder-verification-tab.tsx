'use client';

/**
 * Responders — the Provincial Admin's agency-type-wide slice of Verification.
 *
 * Agency Admin already has a full responder roster at /responders (their own
 * agency only, with approve/reject/on-duty/etc.). This tab is not a second
 * copy of that page — it is the part the spec's Verification module actually
 * asks for: a queue of accounts still waiting on a decision, system-wide,
 * addressed from the same review-and-decide surface as Residents and Agency
 * Admins. It reuses the SAME approval endpoint the /responders page calls;
 * there is exactly one place a responder actually gets approved.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Building2, Check, Inbox, X } from 'lucide-react';

import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import {
  DataHead, DataRow, DataTableFrame, DataTd, DataTh, Initials,
} from '@/components/ui/data-table';
import { AgencyChip } from '@/components/operational-area/kit';
import { ApiError, apiClient } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { describeApiError } from '@/lib/utils/validators';
import { useNotice } from '@/lib/toast';

interface AgencyInfo {
  name: string;
  agency_type: string;
  municipality: string;
}

interface PendingResponder {
  id: string;
  full_name: string;
  email: string;
  badge_id: string | null;
  approval_status: 'pending' | 'approved' | 'rejected' | 'not_required';
  created_at: string;
  agencies: AgencyInfo | null;
}

export function ResponderVerificationTab({ token }: { token: string }) {
  const [responders, setResponders] = useState<PendingResponder[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [acting, setActing] = useState<string | null>(null);
  const setMsg = useNotice();

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Unfiltered by design — for a provincial_admin this endpoint already
      // spans every station of their agency_type (no agency_id query param
      // needed); the pending filter
      // happens client-side below, same as the existing /responders page.
      const data = await apiClient.get<PendingResponder[]>('/users/agency/responders', token);
      setResponders(data.filter(r => r.approval_status === 'pending'));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Could not load responders.');
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  const agencyCount = useMemo(
    () => new Set(responders.map(r => r.agencies?.name).filter(Boolean)).size,
    [responders],
  );

  async function decide(id: string, approval_status: 'approved' | 'rejected') {
    setActing(id);
    setMsg(null);
    try {
      await apiClient.patch(`/users/agency/responders/${id}/approval`, { approval_status }, token);
      setMsg({
        type: 'success',
        text: `Responder ${approval_status === 'approved' ? 'approved' : 'rejected'}.`,
      });
      await load();
    } catch (e) {
      setMsg({ type: 'error', text: e instanceof Error ? e.message : describeApiError(500, null) });
    } finally {
      setActing(null);
    }
  }

  if (error) return <Alert variant="error" message={error} />;

  return (
    <div className="flex flex-col gap-4">

      <StatStrip>
        <StatCell
          bg="var(--color-brand-subtle)"
          color="var(--color-brand)"
          icon={<Inbox size={12} strokeWidth={2} />}
          label="Waiting"
          trend={responders.length === 1 ? 'responder pending approval' : 'responders pending approval'}
          value={responders.length}
        />
        <StatCell
          bg="var(--color-system-success-bg)"
          color="var(--color-system-success)"
          icon={<Building2 size={12} strokeWidth={2} />}
          label="Agencies"
          trend="represented in the queue"
          value={agencyCount}
        />
      </StatStrip>

      {loading && responders.length === 0 ? (
        <div className="flex items-center justify-center py-16">
          <Inbox className="h-6 w-6 animate-pulse text-[var(--color-text-muted)]" />
        </div>
      ) : responders.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] py-12">
          <Inbox className="h-6 w-6 text-[var(--color-text-muted)]" />
          <p className="text-[14px] font-semibold text-[var(--color-text-primary)]">
            No responders waiting
          </p>
          <p className="max-w-[380px] text-center text-[12.5px] text-[var(--color-text-muted)]">
            New responder accounts appear here as soon as they register against a station.
          </p>
        </div>
      ) : (
        <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]">
          <DataTableFrame minWidth={820}>
            <DataHead>
              <DataTh>Responder</DataTh>
              <DataTh width="260px">Agency</DataTh>
              <DataTh width="170px">Registered</DataTh>
              <DataTh align="right" width="210px">Decision</DataTh>
            </DataHead>
            <tbody>
              {responders.map(r => (
                <DataRow key={r.id}>
                  <DataTd>
                    <div className="flex items-center gap-3">
                      <Initials name={r.full_name} tone="brand" />
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-[var(--color-text-primary)]">
                          {r.full_name}
                          {r.badge_id && (
                            <span className="ml-2 text-[12px] font-normal text-[var(--color-text-muted)]">
                              Badge {r.badge_id}
                            </span>
                          )}
                        </p>
                        <p className="truncate text-meta text-[var(--color-text-muted)]">{r.email}</p>
                      </div>
                    </div>
                  </DataTd>
                  <DataTd>
                    {r.agencies ? (
                      <div className="min-w-0">
                        <p className="flex items-center gap-2">
                          <AgencyChip type={r.agencies.agency_type} />
                          <span className="truncate text-[var(--color-text-primary)]">{r.agencies.name}</span>
                        </p>
                        <p className="mt-0.5 truncate text-meta text-[var(--color-text-muted)]">{r.agencies.municipality}</p>
                      </div>
                    ) : (
                      <span className="text-[var(--color-text-muted)]">Unassigned agency</span>
                    )}
                  </DataTd>
                  <DataTd className="whitespace-nowrap text-[var(--color-text-secondary)]">
                    {new Date(r.created_at).toLocaleDateString(undefined, {
                      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
                    })}
                  </DataTd>
                  <DataTd align="right">
                    <div className="flex justify-end gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={acting === r.id}
                        onClick={() => decide(r.id, 'rejected')}
                      >
                        <X className="h-3.5 w-3.5" />
                        Reject
                      </Button>
                      <Button
                        variant="success"
                        size="sm"
                        disabled={acting === r.id}
                        isLoading={acting === r.id}
                        onClick={() => decide(r.id, 'approved')}
                      >
                        <Check className="h-3.5 w-3.5" />
                        Approve
                      </Button>
                    </div>
                  </DataTd>
                </DataRow>
              ))}
            </tbody>
          </DataTableFrame>
        </div>
      )}
    </div>
  );
}
