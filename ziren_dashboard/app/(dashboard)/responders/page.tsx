'use client';

/**
 * Agency Admin — Responders
 *
 * The agency's field roster: who is on duty, and who is waiting on an
 * approval decision. Approvals are the work this page exists for, so they
 * lead the status line and sort to the top of the list.
 *
 * REDESIGNED 2026-10-01. The roster used to be three stacks of cards
 * (Awaiting approval, Approved, Rejected), one card per responder, each with
 * its facts scattered along a wrapping row. Past a dozen people it could not
 * be scanned, there was no way to find one by name, and Reject / Revoke fired
 * the moment they were pressed. It is now one table - a row per responder, a
 * column per fact - with a view switcher, a search box, and a confirmation
 * before anything that takes access away.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Check, Hourglass, Inbox, RotateCcw, ShieldCheck, UserCheck, UserX, Users, X,
  type LucideIcon,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { SearchInput } from '@/components/ui/search-input';
import {
  DataHead, DataRow, DataTableFrame, DataTd, DataTh,
} from '@/components/ui/data-table';
import { AgencyChip } from '@/components/operational-area/kit';
import {
  assignmentLabel, StatusPill, type CurrentStatus, type CurrentIncidentRef,
} from '@/components/responders/status-pill';
import { formatDate } from '@/lib/format/datetime';
import { displayPrefs } from '@/lib/prefs/definitions';
import { useNotice } from '@/lib/toast';
import { cn } from '@/lib/utils';

import { DemoTarget } from '@/components/help/demo-target';
type Approval = 'pending' | 'approved' | 'rejected' | 'not_required';

interface ResponderUser {
  id: string;
  email: string;
  full_name: string;
  badge_id: string | null;
  approval_status: Approval;
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
  /** Present for a Provincial Admin, whose roster spans every station. */
  agencies?: { name: string; agency_type: string; municipality: string } | null;
}

type View = 'all' | 'pending' | 'approved' | 'rejected';

const WARN = 'var(--color-system-warning)';
const GOOD = 'var(--color-system-success)';
const STOP = 'var(--color-severity-critical)';

const APPROVAL: Record<Approval, { label: string; color: string; icon: LucideIcon }> = {
  pending: { label: 'Awaiting approval', color: WARN, icon: Hourglass },
  approved: { label: 'Approved', color: GOOD, icon: ShieldCheck },
  rejected: { label: 'Rejected', color: 'var(--color-text-muted)', icon: UserX },
  not_required: { label: 'Approved', color: GOOD, icon: ShieldCheck },
};

/** What is about to happen to whom - held while the confirmation is open. */
interface Pending {
  responder: ResponderUser;
  to: 'approved' | 'rejected';
}

export default function RespondersPage() {
  const { token, isProvincialAdmin } = useAuth();
  const display = displayPrefs.use();
  const [responders, setResponders] = useState<ResponderUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const setActionMsg = useNotice();
  const [acting, setActing] = useState<string | null>(null);
  const [view, setView] = useState<View>('all');
  const [q, setQ] = useState('');
  const [confirm, setConfirm] = useState<Pending | null>(null);

  const load = useCallback(async (silent = false) => {
    if (!token) return;
    if (!silent) { setLoading(true); setError(null); }
    try {
      setResponders(await apiClient.get<ResponderUser[]>('/users/agency/responders', token));
      setError(null);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      if (!silent) setError(e instanceof Error ? e.message : 'Failed to load responders.');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    void load();
    // Who is on duty and who is on a call changes by the minute; a roster
    // read once at page load goes stale while it is being looked at.
    const id = setInterval(() => void load(true), 30_000);
    return () => clearInterval(id);
  }, [load]);

  async function updateApproval(r: ResponderUser, approval_status: 'approved' | 'rejected') {
    if (!token) return;
    setActing(r.id); setActionMsg(null);
    try {
      await apiClient.patch(`/users/agency/responders/${r.id}/approval`, { approval_status }, token);
      setActionMsg({
        type: 'success',
        text: approval_status === 'approved'
          ? `${r.full_name} is approved and can sign in to receive dispatches.`
          : r.approval_status === 'approved'
            ? `${r.full_name}'s access was revoked.`
            : `${r.full_name} was rejected.`,
      });
      await load(true);
    } catch (e: unknown) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Action failed.' });
    } finally {
      setActing(null);
    }
  }

  const counts = useMemo(() => ({
    all: responders.length,
    pending: responders.filter(r => r.approval_status === 'pending').length,
    approved: responders.filter(r => r.approval_status === 'approved').length,
    rejected: responders.filter(r => r.approval_status === 'rejected').length,
  }), [responders]);
  const onDuty = responders.filter(r => r.approval_status === 'approved' && r.availability === 'on_duty').length;
  const onCall = responders.filter(r => r.current_incident).length;
  const total = counts.all;

  const shown = useMemo(() => {
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    // Whoever is waiting on a decision first, then the people on duty, then
    // the rest by name: the rows somebody has to act on are never below the fold.
    const rank = (r: ResponderUser) =>
      r.approval_status === 'pending' ? 0
        : r.approval_status === 'rejected' ? 3
          : r.availability === 'on_duty' ? 1 : 2;
    return responders
      .filter(r => view === 'all' || r.approval_status === view)
      .filter(r => {
        if (words.length === 0) return true;
        const hay = [r.full_name, r.email, r.badge_id, r.agencies?.name, r.agencies?.municipality]
          .filter(Boolean).join('\n').toLowerCase();
        return words.every(w => hay.includes(w));
      })
      .sort((a, b) => rank(a) - rank(b) || a.full_name.localeCompare(b.full_name));
  }, [responders, view, q]);

  const VIEWS: { key: View; label: string; icon: LucideIcon }[] = [
    { key: 'all', label: 'Everyone', icon: Users },
    { key: 'pending', label: 'Awaiting approval', icon: Hourglass },
    { key: 'approved', label: 'Approved', icon: ShieldCheck },
    { key: 'rejected', label: 'Rejected', icon: UserX },
  ];

  return (
    <div className="min-h-full">
      <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
        <DemoTarget id="resp:stats"><StatStrip>
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
            value={onDuty}
            trend={onCall > 0 ? `${onCall} on a call right now` : 'None on a call'}
            color={GOOD}
            bg="var(--color-system-success-bg)"
          />
          {/* Hourglass, not Shield. A shield says "protected"; what this cell
              counts is people held in a queue waiting on a human decision. */}
          <StatCell
            icon={<Hourglass size={12} strokeWidth={2} />}
            label="Awaiting approval"
            value={counts.pending}
            trend={counts.pending > 0 ? 'Needs a decision' : 'Nothing waiting'}
            color={WARN}
            bg="var(--color-system-warning-bg)"
          />
          <StatCell
            icon={<UserX size={12} strokeWidth={2} />}
            label="Rejected"
            value={counts.rejected}
            trend={counts.rejected > 0 ? 'Cannot sign in' : 'Nobody rejected'}
            color="var(--color-status-processing)"
            bg="var(--color-status-processing-bg)"
          />
        </StatStrip></DemoTarget>

        {error && <Alert variant="error" message={error} />}

        <div
          className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]"
          data-testid="responder-roster"
        >
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2.5 border-b border-[var(--color-surface-border)] px-4 py-3">
            <div data-demo="resp:filters" aria-label="Which responders to show" className="flex flex-wrap gap-1.5" role="group">
              {VIEWS.map(v => {
                const on = view === v.key;
                const n = counts[v.key];
                // The one count that is a job to do is drawn as a job to do.
                const urgent = v.key === 'pending' && n > 0 && !on;
                return (
                  <button
                    aria-pressed={on}
                    className={cn(
                      'inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-[12.5px] font-semibold transition-colors',
                      on
                        ? 'border-transparent bg-foreground text-background'
                        : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
                    )}
                    data-view={v.key}
                    key={v.key}
                    onClick={() => setView(v.key)}
                    type="button"
                  >
                    <v.icon aria-hidden="true" size={14} />
                    {v.label}
                    <span
                      className={cn(
                        'tabular-nums text-[11.5px]',
                        urgent ? 'rounded-full px-1.5 font-bold' : on ? 'opacity-80' : n === 0 ? 'opacity-40' : 'text-muted-foreground',
                      )}
                      style={urgent ? { color: WARN, backgroundColor: `color-mix(in srgb, ${WARN} 16%, transparent)` } : undefined}
                    >
                      {n}
                    </span>
                  </button>
                );
              })}
            </div>
            <DemoTarget id="resp:search"><SearchInput
              className="ml-auto min-w-[220px] max-w-[340px] flex-1"
              label="Search responders"
              onValueChange={setQ}
              placeholder="Name, email or badge…"
              value={q}
            /></DemoTarget>
          </div>

          {loading && total === 0 ? (
            <p className="py-16 text-center text-meta text-muted-foreground">Loading the roster…</p>
          ) : total === 0 ? (
            <_Empty
              body="Responders appear here once they register in the mobile app."
              icon={Users}
              title="No responders yet"
            />
          ) : shown.length === 0 ? (
            <_Empty
              body={q.trim() ? 'Try a name, an email or a badge number.' : 'Nobody is in this group right now.'}
              icon={Inbox}
              title={q.trim() ? 'No responder matches that search' : `No responders ${view === 'pending' ? 'awaiting approval' : view}`}
            />
          ) : (
            <DemoTarget id="resp:table"><DataTableFrame className="rounded-none border-0" minWidth={isProvincialAdmin ? 1120 : 960}>
              <DataHead>
                <DataTh>Responder</DataTh>
                {isProvincialAdmin && <DataTh width="200px">Station</DataTh>}
                <DataTh width="220px">Right now</DataTh>
                <DataTh width="164px">Access</DataTh>
                <DataTh width="104px">Joined</DataTh>
                <DataTh align="right" width="200px"><span className="sr-only">Actions</span></DataTh>
              </DataHead>
              <tbody>
                {shown.map(r => (
                  <_Row
                    acting={acting === r.id}
                    joined={formatDate(r.created_at, display)}
                    key={r.id}
                    onApprove={() => void updateApproval(r, 'approved')}
                    onReject={() => setConfirm({ responder: r, to: 'rejected' })}
                    responder={r}
                    showStation={isProvincialAdmin}
                  />
                ))}
              </tbody>
            </DataTableFrame></DemoTarget>
          )}
        </div>
      </div>

      {/* Taking access away asks first. Both used to fire on the press, and a
          revoked responder is signed out of a phone they may be holding on a
          call. Approving is not confirmed: it is the safe direction, and easily
          undone. */}
      <AlertDialog onOpenChange={o => { if (!o) setConfirm(null); }} open={confirm !== null}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirm?.responder.approval_status === 'approved' ? 'Revoke access for' : 'Reject'} {confirm?.responder.full_name}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              {confirm?.responder.approval_status === 'approved'
                ? 'They will no longer be able to sign in or receive dispatches.'
                : 'They will not be able to sign in as a responder.'}
              {confirm?.responder.current_incident && ' They are assigned to an incident right now.'}
              {' '}You can approve them again later.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Back</AlertDialogCancel>
            <AlertDialogAction
              onClick={() => {
                const c = confirm;
                setConfirm(null);
                if (c) void updateApproval(c.responder, c.to);
              }}
              variant="destructive"
            >
              {confirm?.responder.approval_status === 'approved' ? 'Revoke access' : 'Reject'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

function _Empty({ icon: Icon, title, body }: { icon: LucideIcon; title: string; body: string }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-16 text-center" data-empty>
      <span className="flex size-12 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[var(--color-text-tertiary)]">
        <Icon size={22} />
      </span>
      <p className="mt-1 text-[15px] font-semibold text-foreground">{title}</p>
      <p className="max-w-[44ch] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

function _Row({ responder: r, acting, joined, showStation, onApprove, onReject }: {
  responder: ResponderUser;
  acting: boolean;
  joined: string;
  showStation: boolean;
  onApprove: () => void;
  onReject: () => void;
}) {
  const initials = r.full_name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase();
  const label = assignmentLabel(r.current_incident);
  const approval = APPROVAL[r.approval_status] ?? APPROVAL.pending;
  const pending = r.approval_status === 'pending';
  const approved = r.approval_status === 'approved';

  return (
    <DataRow
      className={pending ? 'bg-[color-mix(in_srgb,var(--color-system-warning)_6%,transparent)]' : undefined}
      muted={r.approval_status === 'rejected'}
    >
      <DataTd className="relative">
        {/* The accent sits on the first cell: a border on a <tr> is not painted
            by every engine under border-collapse. */}
        {pending && <span aria-hidden="true" className="absolute top-0 bottom-0 left-0 w-[3px]" style={{ backgroundColor: WARN }} />}
        <div className="flex items-center gap-3">
          <span className="relative inline-flex shrink-0">
            <span
              aria-hidden="true"
              className="flex size-10 items-center justify-center rounded-full bg-[var(--color-brand-subtle)] text-[12.5px] font-semibold text-[var(--color-brand)]"
            >
              {initials}
            </span>
            {/* Supplementary only — the pill in "Right now" is the labelled
                statement of duty; this dot is the at-a-glance reinforcement. */}
            {approved && (
              <span
                aria-hidden="true"
                className="absolute right-0 bottom-0 size-3 rounded-full ring-2 ring-[var(--color-surface-card)]"
                style={{ backgroundColor: r.availability === 'on_duty' ? GOOD : 'var(--color-connectivity-offline)' }}
              />
            )}
          </span>
          <div className="min-w-0">
            <p className="truncate font-semibold text-foreground">{r.full_name}</p>
            <p className="truncate text-meta text-muted-foreground">
              {r.email}
              {r.badge_id && <span className="ml-2 font-mono text-[var(--color-text-secondary)]">#{r.badge_id}</span>}
            </p>
          </div>
        </div>
      </DataTd>

      {showStation && (
        <DataTd>
          {r.agencies ? (
            <div className="min-w-0">
              <p className="flex items-center gap-2">
                <AgencyChip type={r.agencies.agency_type} />
                <span className="truncate text-foreground">{r.agencies.name}</span>
              </p>
              <p className="mt-0.5 truncate text-meta text-muted-foreground">{r.agencies.municipality}</p>
            </div>
          ) : (
            <span className="text-muted-foreground">No station</span>
          )}
        </DataTd>
      )}

      <DataTd>
        {r.current_status ? (
          <div className="flex min-w-0 flex-col items-start gap-1">
            <StatusPill currentIncident={r.current_incident} status={r.current_status} />
            {label && <span className="max-w-full truncate text-meta text-[var(--color-text-secondary)]" title={label}>{label}</span>}
          </div>
        ) : (
          <span className="text-muted-foreground" title="Only an approved responder has a duty status.">—</span>
        )}
      </DataTd>

      <DataTd>
        <span
          className="inline-flex items-center gap-1.5 rounded-full px-2 py-[3px] text-[11.5px] leading-tight font-semibold whitespace-nowrap"
          data-approval={r.approval_status}
          style={{ color: approval.color, backgroundColor: `color-mix(in srgb, ${approval.color} 12%, transparent)` }}
        >
          <approval.icon aria-hidden="true" size={12} strokeWidth={2.4} />
          {approval.label}
        </span>
      </DataTd>

      <DataTd className="whitespace-nowrap font-mono text-[12.5px] tabular-nums text-[var(--color-text-secondary)]">
        {joined}
      </DataTd>

      <DataTd align="right">
        <div className={cn('flex justify-end gap-2', acting && 'pointer-events-none opacity-50')}>
          {pending && (
            <>
              <Button
                aria-label={`Reject ${r.full_name}`}
                onClick={onReject}
                size="sm"
                style={{ color: STOP, borderColor: `color-mix(in srgb, ${STOP} 40%, transparent)` }}
                variant="outline"
              >
                <X data-icon="inline-start" /> Reject
              </Button>
              <Button
                aria-label={`Approve ${r.full_name}`}
                onClick={onApprove}
                size="sm"
                style={{ backgroundColor: GOOD, color: 'var(--color-on-success)' }}
              >
                <Check data-icon="inline-start" /> {acting ? 'Saving…' : 'Approve'}
              </Button>
            </>
          )}
          {approved && (
            <Button aria-label={`Revoke access for ${r.full_name}`} onClick={onReject} size="sm" variant="outline">
              <UserX data-icon="inline-start" /> Revoke
            </Button>
          )}
          {r.approval_status === 'rejected' && (
            <Button aria-label={`Approve ${r.full_name} again`} onClick={onApprove} size="sm" variant="outline">
              <RotateCcw data-icon="inline-start" /> Approve again
            </Button>
          )}
        </div>
      </DataTd>
    </DataRow>
  );
}
