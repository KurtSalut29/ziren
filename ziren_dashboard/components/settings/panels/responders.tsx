'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { ArrowRight, Check, UserCheck, UserX, Users } from 'lucide-react';
import { ApiError, apiClient } from '@/lib/api/client';
import { fetchAgencyResponders, type AgencyResponder } from '@/lib/api/platform';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDate } from '@/lib/format/datetime';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, Segmented, Stat, StatGrid, StatusDot,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';

type Filter = 'all' | 'on_duty' | 'off_duty' | 'pending' | 'rejected';

/**
 * Responders, as an agency admin manages them from Settings.
 *
 * The full roster page (Responders) is where a responder is added, examined or
 * reassigned. This panel is the part of that job that is a SETTING of the
 * agency: who is allowed to be dispatched at all. That is one decision per
 * account — approve or reject — and it is the decision that gates everything
 * else, so it is done here, for real, on the same endpoint that page uses,
 * instead of pointing the reader at another screen to do it.
 */
export function RespondersPanel({ token }: { token: string }) {
  const display = displayPrefs.use();
  const [rows, setRows] = useState<AgencyResponder[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  const [busyId, setBusyId] = useState<string | null>(null);
  const setNotice = useNotice();

  const load = useCallback(async () => {
    try {
      setRows(await fetchAgencyResponders(token));
      setError(null);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Could not load the roster.');
    }
  }, [token]);

  useEffect(() => { void load(); }, [load]);

  async function decide(r: AgencyResponder, decision: 'approved' | 'rejected') {
    setBusyId(r.id);
    setNotice(null);
    try {
      await apiClient.patch(`/users/agency/responders/${r.id}/approval`, { approval_status: decision }, token);
      setNotice({
        tone: 'success',
        text: `${r.full_name ?? 'The responder'} was ${decision === 'approved' ? 'approved and can now be dispatched' : 'rejected'}.`,
      });
      await load();
    } catch (e) {
      setNotice({ tone: 'danger', text: e instanceof Error ? e.message : 'Could not save that decision.' });
    } finally {
      setBusyId(null);
    }
  }

  const counts = useMemo(() => {
    const r = rows ?? [];
    const approved = r.filter(x => x.approval_status === 'approved');
    return {
      total: r.length,
      approved: approved.length,
      onDuty: approved.filter(x => x.availability === 'on_duty').length,
      pending: r.filter(x => x.approval_status === 'pending').length,
    };
  }, [rows]);

  const pending = (rows ?? []).filter(x => x.approval_status === 'pending');

  const shown = useMemo(() => {
    const r = rows ?? [];
    const order = (x: AgencyResponder) =>
      x.approval_status === 'pending' ? 0
      : x.approval_status === 'approved' && x.availability === 'on_duty' ? 1
      : x.approval_status === 'approved' ? 2 : 3;
    return r
      .filter(x =>
        filter === 'all' ? true
        : filter === 'pending' ? x.approval_status === 'pending'
        : filter === 'rejected' ? x.approval_status === 'rejected'
        : x.approval_status === 'approved' && (filter === 'on_duty' ? x.availability === 'on_duty' : x.availability !== 'on_duty'))
      .sort((a, b) => order(a) - order(b) || (a.full_name ?? '').localeCompare(b.full_name ?? ''));
  }, [rows, filter]);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Who is allowed to be dispatched from your agency, and who is available right now. Approving an account is the decision everything else depends on."
        icon={Users}
        scope="agency"
        title="Responders"
      />

      {error && <Callout title="Could not load the roster" tone="danger">{error}</Callout>}

      {rows === null && !error ? (
        <Skeleton className="h-24 rounded-[var(--radius-card)]" />
      ) : rows && (
        <StatGrid>
          <Stat hint="Every account on the roster" label="On the roster" value={counts.total} />
          <Stat hint="Allowed to be dispatched" label="Approved" value={counts.approved} />
          <Stat
            hint={counts.approved ? `of ${counts.approved} approved` : 'None approved yet'}
            label="On duty now"
            tone={counts.approved > 0 && counts.onDuty === 0 ? 'warning' : 'success'}
            value={counts.onDuty}
          />
          <Stat
            hint={counts.pending ? 'Waiting on you' : 'Roster is current'}
            label="Awaiting approval"
            tone={counts.pending ? 'warning' : undefined}
            value={counts.pending}
          />
        </StatGrid>
      )}

      {rows && counts.approved > 0 && counts.onDuty === 0 && (
        <Callout title="Nobody is on duty" tone="warning">
          A report can only be assigned to an approved responder who is on duty, so right now
          none could be dispatched. Responders switch themselves on duty in the mobile app.
        </Callout>
      )}

      {pending.length > 0 && (
        <Card
          description="These accounts registered as responders for your agency and cannot be dispatched until you decide."
          flush
          title={`Awaiting your approval (${pending.length})`}
        >
          <ul className="divide-y divide-[var(--color-surface-border)]">
            {pending.map(r => (
              <li className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3.5" key={r.id}>
                <span className="min-w-0 flex-1">
                  <span className="block text-[13.5px] font-semibold text-foreground">{r.full_name ?? 'Unnamed account'}</span>
                  <span className="block text-[12px] text-muted-foreground">
                    Badge {r.badge_id ?? 'not given'} · registered {formatDate(r.created_at, display)}
                    {!r.is_verified && ' · identity not verified'}
                  </span>
                </span>
                <span className="flex items-center gap-2">
                  <Button
                    disabled={busyId !== null}
                    onClick={() => decide(r, 'rejected')}
                    size="sm"
                    variant="outline"
                  >
                    <UserX data-icon="inline-start" />
                    Reject
                  </Button>
                  <Button disabled={busyId !== null} onClick={() => decide(r, 'approved')} size="sm">
                    <UserCheck data-icon="inline-start" />
                    {busyId === r.id ? 'Saving…' : 'Approve'}
                  </Button>
                </span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Card
        action={
          <Link className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" href="/responders">
            Open Responders <ArrowRight className="size-3.5" />
          </Link>
        }
        description="Add a responder, look at one in detail or reassign them on the Responders page."
        flush
        title="Roster"
      >
        <div className="border-b border-[var(--color-surface-border)] px-5 py-3">
          <Segmented
            ariaLabel="Filter the roster"
            onChange={setFilter}
            options={[
              { value: 'all', label: 'All' },
              { value: 'on_duty', label: 'On duty' },
              { value: 'off_duty', label: 'Off duty' },
              { value: 'pending', label: 'Pending' },
              { value: 'rejected', label: 'Rejected' },
            ]}
            value={filter}
          />
        </div>
        {rows === null ? (
          <div className="flex flex-col gap-2 px-5 py-4"><Skeleton className="h-10 rounded-lg" /><Skeleton className="h-10 rounded-lg" /></div>
        ) : shown.length === 0 ? (
          <p className="px-5 py-8 text-center text-[13px] text-muted-foreground">
            {rows.length === 0 ? 'Nobody has registered on this agency’s roster yet.' : 'Nobody matches that filter.'}
          </p>
        ) : (
          <ul className="max-h-[420px] divide-y divide-[var(--color-surface-border)] overflow-y-auto">
            {shown.map(r => (
              <li className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-3" key={r.id}>
                <span className="min-w-0 flex-1">
                  <span className="block text-[13.5px] font-medium text-foreground">{r.full_name ?? 'Unnamed account'}</span>
                  <span className="block text-[12px] text-muted-foreground">
                    Badge {r.badge_id ?? '—'} · joined {formatDate(r.created_at, display)}
                  </span>
                </span>
                <span className="flex items-center gap-3">
                  {r.approval_status === 'approved' ? (
                    <StatusDot tone={r.availability === 'on_duty' ? 'success' : 'neutral'}>
                      {r.availability === 'on_duty' ? 'On duty' : 'Off duty'}
                    </StatusDot>
                  ) : r.approval_status === 'pending' ? (
                    <StatusDot tone="warning">Pending approval</StatusDot>
                  ) : (
                    <StatusDot tone="danger">Rejected</StatusDot>
                  )}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card
        description="What the console does with the roster when a report is being assigned — so nothing here is a surprise on a bad night."
        flush
        title="How dispatch uses your roster"
      >
        <RowList>
          <Row
            description="An incident can be assigned only to a responder of the same agency who is approved and on duty. Anyone else never appears in the list."
            icon={Check}
            label="Who can be assigned"
          />
          <Row
            description="As an Agency Admin you can also assign an incident to yourself, for when you are the one going. That does not make you a responder on the roster."
            icon={Check}
            label="Assigning yourself"
          />
          <Row
            description="A crew has 60 seconds (critical) up to 3 minutes (medium and low) to accept. A refusal is recorded with the reason the crew gave and shown on the board; an assignment nobody has answered in time is shown overdue. The exact table is under Alerts."
            icon={Check}
            label="Accepting and refusing"
          />
        </RowList>
      </Card>
    </div>
  );
}
