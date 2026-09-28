'use client';

/**
 * Access Requests — the review half of the Request Access flow.
 *
 * The dashboard's public "Request Access" page writes to access_requests, but
 * nothing surfaced those rows, so submissions piled up invisibly and
 * applicants waited on a decision no Provincial Admin could see was pending.
 *
 * Approving here calls the same provisioning endpoint as the manual "Create
 * Agency Admin" form, so there is exactly one path that mints an agency_admin
 * account — the applicant receives a Supabase invite and sets their own
 * password on /accept-invite.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Check, Inbox, ListChecks, UserCheck, UserX, X } from 'lucide-react';

import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { NavTabs } from '@/components/ui/nav-tabs';
import {
  DataHead, DataRow, DataTableFrame, DataTd, DataTh, Initials, StatusChip,
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

export interface AccessRequest {
  id: string;
  full_name: string;
  email: string;
  position: string | null;
  agency_id: string;
  status: 'pending' | 'approved' | 'rejected';
  created_at: string;
  reviewed_at: string | null;
  review_note: string | null;
  agencies: AgencyInfo | null;
}

export function AccessRequestsTab({
  token,
  onCountChange,
}: {
  token: string;
  onCountChange?: (pending: number) => void;
}) {
  const [requests, setRequests] = useState<AccessRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [acting, setActing] = useState<string | null>(null);
  const setMsg = useNotice();
  const [showAll, setShowAll] = useState(false);
  // Both directions are confirmed: Approve mints a real account and sends an
  // invite email immediately, Reject is a one-way decision on an applicant.
  const [confirmAction, setConfirmAction] = useState<
    { request: AccessRequest; action: 'approve' | 'reject' } | null
  >(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await apiClient.get<AccessRequest[]>(
        `/users/provincial/access-requests?status_filter=${showAll ? 'all' : 'pending'}`,
        token,
      );
      setRequests(data);
      onCountChange?.(data.filter(r => r.status === 'pending').length);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Could not load access requests.');
    } finally {
      setLoading(false);
    }
  }, [token, showAll, onCountChange]);

  useEffect(() => { void load(); }, [load]);

  // Approved/Rejected only count what is actually loaded — in "pending only"
  // scope (the default) the server never sends decided rows, so those two
  // cells would misreport as zero. They read "—" there instead, per the
  // console's rule against a fabricated ratio.
  const counts = useMemo(() => ({
    pending: requests.filter(r => r.status === 'pending').length,
    approved: requests.filter(r => r.status === 'approved').length,
    rejected: requests.filter(r => r.status === 'rejected').length,
  }), [requests]);

  async function review(id: string, action: 'approve' | 'reject') {
    setActing(id);
    setMsg(null);
    try {
      await apiClient.patch(`/users/provincial/access-requests/${id}`, { action }, token);
      setMsg({
        type: 'success',
        text:
          action === 'approve'
            ? 'Approved. An invite email has been sent so they can set a password.'
            : 'Request rejected.',
      });
      await load();
    } catch (e) {
      setMsg({
        type: 'error',
        text: e instanceof Error ? e.message : describeApiError(500, null),
      });
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
          label="Pending"
          trend="waiting for a decision"
          value={counts.pending}
        />
        <StatCell
          bg="var(--color-system-success-bg)"
          color="var(--color-system-success)"
          icon={<UserCheck size={12} strokeWidth={2} />}
          label="Approved"
          riseIsBad={false}
          trend={showAll ? 'in this view' : 'switch to "Show all" to see'}
          value={showAll ? counts.approved : '—'}
        />
        <StatCell
          bg="var(--color-surface-raised)"
          color="var(--color-text-muted)"
          icon={<UserX size={12} strokeWidth={2} />}
          label="Rejected"
          trend={showAll ? 'in this view' : 'switch to "Show all" to see'}
          value={showAll ? counts.rejected : '—'}
        />
      </StatStrip>

      <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]">
        <NavTabs
          activeKey={showAll ? 'all' : 'pending'}
          ariaLabel="Which requests to show"
          idPrefix="access-scope"
          onSelect={k => setShowAll(k === 'all')}
          tabs={[
            { key: 'pending', label: 'Pending', icon: Inbox, hint: 'Requests waiting on a decision' },
            { key: 'all', label: 'All requests', icon: ListChecks, hint: 'Including approved and rejected' },
          ]}
        />

        {loading && requests.length === 0 ? (
          <div className="flex items-center justify-center py-16">
            <Inbox className="h-6 w-6 animate-pulse text-[var(--color-text-muted)]" />
          </div>
        ) : requests.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-12">
            <Inbox className="h-6 w-6 text-[var(--color-text-muted)]" />
            <p className="text-[14px] font-semibold text-[var(--color-text-primary)]">
              No access requests
            </p>
            <p className="max-w-[380px] text-center text-[12.5px] text-[var(--color-text-muted)]">
              Requests submitted from the public Request Access page appear here for approval.
            </p>
          </div>
        ) : (
          <DataTableFrame minWidth={860}>
            <DataHead>
              <DataTh>Applicant</DataTh>
              <DataTh width="240px">Agency</DataTh>
              <DataTh width="150px">Requested</DataTh>
              <DataTh align="right" width="250px">Decision</DataTh>
            </DataHead>
            <tbody>
              {requests.map(r => (
                <DataRow key={r.id}>
                  <DataTd>
                    <div className="flex items-center gap-3">
                      <Initials name={r.full_name} tone="brand" />
                      <div className="min-w-0">
                        <p className="truncate font-semibold text-[var(--color-text-primary)]">{r.full_name}</p>
                        <p className="truncate text-meta text-[var(--color-text-muted)]">
                          {r.email}{r.position ? ` · ${r.position}` : ''}
                        </p>
                      </div>
                    </div>
                  </DataTd>
                  <DataTd>
                    {r.agencies ? (
                      <div className="min-w-0">
                        <AgencyChip type={r.agencies.agency_type} />
                        <p className="mt-0.5 truncate text-meta text-[var(--color-text-muted)]">{r.agencies.municipality}</p>
                      </div>
                    ) : (
                      <span className="text-[var(--color-text-muted)]">Unknown agency</span>
                    )}
                  </DataTd>
                  <DataTd className="whitespace-nowrap text-[var(--color-text-secondary)]">
                    {new Date(r.created_at).toLocaleDateString(undefined, {
                      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
                    })}
                  </DataTd>
                  <DataTd align="right">
                    {r.status === 'pending' ? (
                      <div className="flex justify-end gap-2">
                        <Button
                          variant="outline"
                          size="sm"
                          disabled={acting === r.id}
                          onClick={() => setConfirmAction({ request: r, action: 'reject' })}
                        >
                          <X className="h-3.5 w-3.5" />
                          Reject
                        </Button>
                        <Button
                          size="sm"
                          isLoading={acting === r.id}
                          onClick={() => setConfirmAction({ request: r, action: 'approve' })}
                        >
                          <Check className="h-3.5 w-3.5" />
                          Approve &amp; invite
                        </Button>
                      </div>
                    ) : (
                      <StatusChip
                        label={r.status === 'approved' ? 'Approved' : 'Rejected'}
                        tone={r.status === 'approved' ? 'success' : 'neutral'}
                      />
                    )}
                  </DataTd>
                </DataRow>
              ))}
            </tbody>
          </DataTableFrame>
        )}
      </div>

      <AlertDialog
        open={confirmAction !== null}
        onOpenChange={open => { if (!open) setConfirmAction(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmAction?.action === 'approve'
                ? `Approve ${confirmAction.request.email} and send an invite?`
                : `Reject ${confirmAction?.request.full_name}'s request?`}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirmAction?.action === 'approve'
                ? 'An invite email is sent immediately so they can set a password and sign in as an agency admin.'
                : 'This decision is final — they would need to submit a new request to be reconsidered.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={acting !== null}>Back</AlertDialogCancel>
            <AlertDialogAction
              variant={confirmAction?.action === 'approve' ? 'default' : 'destructive'}
              disabled={acting !== null}
              onClick={() => {
                const target = confirmAction;
                setConfirmAction(null);
                if (target) void review(target.request.id, target.action);
              }}
            >
              {confirmAction?.action === 'approve' ? 'Approve & invite' : 'Reject'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
