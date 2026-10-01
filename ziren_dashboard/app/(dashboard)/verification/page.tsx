'use client';

/**
 * Verification — Resident ID review for Agency Admin, plus a
 * Provincial-Admin-only Agency Admins tab for agency-type-wide identity
 * verification (see the extra tab gated on isProvincialAdmin below). Not
 * Agency-Admin-exclusive, despite the page's original name.
 *
 * The missing half of a feature that has existed, unusable, since migration
 * 012. Residents could submit a government ID and a selfie; nothing in this
 * dashboard could open either. That is the worst possible arrangement — the
 * privacy exposure of holding people's identity documents, with none of the
 * operational benefit of ever checking them.
 *
 * The reviewer's job on this page is one comparison: does the name and number
 * typed into the account match the card in the photograph, and is the face in
 * the selfie the face on the card. Everything here is arranged around making
 * that one comparison fast, and around the two rules that constrain it:
 *
 *   1. Verification is NOT permission. Approving raises a confidence signal a
 *      dispatcher reads. Rejecting takes it away again. Neither changes what
 *      the resident can do — an unverified person reports emergencies exactly
 *      like a verified one (migration 012).
 *
 *   2. The images are retained only to be checked once. Deciding purges them
 *      by default, per migration 015's retention rule. The ID type and number
 *      stay on the row as the audit trail of what was looked at.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  BadgeCheck, CalendarClock, Clock, Copy, ExternalLink, FileWarning, Gavel, Hash, IdCard,
  ImageOff, Info, MapPin, Phone, ScanFace, ShieldAlert, ShieldCheck, ShieldX, Siren,
  Trash2, UserRound, UserSearch, type LucideIcon,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import {
  BULK_DECIDE_MAX,
  ID_TYPE_LABELS,
  RESIDENCY_PROVING_IDS,
  verificationApi,
  type VerificationDetail,
  type VerificationMethod,
  type VerificationSummary,
} from '@/lib/api/verification';
import { Alert } from '@/components/ui/alert';
import { Fig } from '@/components/ui/fig';
import { Button } from '@/components/efferd/ui/button';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  Card,
} from '@/components/efferd/ui/card';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { OptionPicker } from '@/components/ui/option-picker';
import { SearchInput } from '@/components/ui/search-input';
import { AccessRequestsTab } from '@/components/accounts/access-requests-tab';
import { ResponderVerificationTab } from '@/components/verification/responder-verification-tab';
import { ResidentAccountsTab } from '@/components/verification/resident-accounts-tab';
import { ActionButton } from '@/components/incidents/incident-action-button';
import { Building2, UserCog, Users } from 'lucide-react';
import { NavTabs } from '@/components/ui/nav-tabs';
import {
  DataHead, DataRow, DataTableFrame, DataTd, DataTh, Initials,
} from '@/components/ui/data-table';
import { useNotice } from '@/lib/toast';

import { DemoTarget } from '@/components/help/demo-target';
type VerificationTab = 'residents' | 'accounts' | 'agency_admins' | 'responders';

/**
 * Verification — centralized account review.
 *
 * Residents is the original page (unchanged below, just re-hosted under a
 * tab) and is visible to both Agency Admin and Provincial Admin, matching
 * its existing nav gating. The other three tabs are the spec's system-wide
 * additions (Section 4) and are Provincial-Admin-only: Agency Admins reuses
 * the existing access-requests review flow verbatim (an Agency Admin's
 * access request already IS their verification — there is no second concept
 * to build), Responders is an agency-type-wide queue over the same approval
 * endpoint /responders already uses, and Agency Stations is an honest empty
 * state — stations are created directly active by a Provincial Admin (spec
 * Section 6), so there is no pending queue for them to review.
 */
export default function VerificationPage() {
  const { token, isProvincialAdmin } = useAuth();
  const [tab, setTab] = useState<VerificationTab>('residents');

  const tabs = [
    { key: 'residents', label: 'ID review', icon: IdCard, hint: 'Residents who submitted an ID and are waiting to be verified' },
    // Where a resident goes once they are verified, and where an account is
    // warned or suspended. Both admin roles, like the review queue beside it.
    { key: 'accounts', label: 'Resident accounts', icon: UserRound, hint: 'Verified residents, and how each account stands' },
    ...(isProvincialAdmin
      ? [
          { key: 'agency_admins', label: 'Agency Admins', icon: UserCog, hint: 'People asking to run an agency’s dashboard' },
          { key: 'responders', label: 'Responders', icon: Users, hint: 'Field responders waiting to be approved' },
        ]
      : []),
  ] as { key: VerificationTab; label: string; icon: typeof Users; hint: string }[];

  return (
    <div className="min-h-full">
      {tabs.length > 1 && (
        <div className="sticky top-0 z-30 bg-[var(--color-surface-card)]">
          <DemoTarget id="verify:tabs"><NavTabs
            activeKey={tab}
            ariaLabel="Verification views"
            idPrefix="verification-tab"
            onSelect={key => setTab(key as VerificationTab)}
            tabs={tabs}
          /></DemoTarget>
        </div>
      )}

      {/* What this view decides, who decides it, and what the decision changes.
          Verification is three different jobs under one name — an identity
          check, a request for dashboard access, and a field-crew approval — and
          the answers to "who can do this" and "what happens next" differ for
          each. Stating them here beats making a reviewer learn them by error. */}
      <div className="px-6 pt-5 md:px-7">
        <DemoTarget id="verify:purpose"><PurposeStrip tab={tab} /></DemoTarget>
      </div>

      {tab === 'residents' && <ResidentVerificationTab onSeeAccounts={() => setTab('accounts')} />}

      {tab === 'accounts' && token && (
        <div className="px-6 py-5 md:px-7">
          <ResidentAccountsTab token={token} />
        </div>
      )}

      {tab === 'agency_admins' && token && (
        <div className="px-6 py-5 md:px-7">
          <AccessRequestsTab token={token} />
        </div>
      )}

      {tab === 'responders' && token && (
        <div className="px-6 py-5 md:px-7">
          <ResponderVerificationTab token={token} />
        </div>
      )}

    </div>
  );
}

const PURPOSE: Record<VerificationTab, {
  title: string;
  what: string;
  who: () => string;
  effect: string;
}> = {
  residents: {
    title: 'Resident identity check',
    what: 'A resident submitted a government ID and a selfie. You compare the two and the name on the account.',
    who: () => 'Any admin — Agency or Provincial. Residents belong to no agency, so there is one shared queue.',
    effect: 'Adds a “verified” mark dispatchers can read. It never blocks anyone: an unverified resident can still report an emergency.',
  },
  accounts: {
    title: 'Resident accounts',
    what: 'Every resident who has been verified, with their details, their reports and any warnings. Warn or suspend an account that breaks the reporting rules.',
    who: () => 'Any admin. An Agency Admin sees their own municipality, and anyone who has reported to their agency.',
    effect: 'A warning notifies the resident; the third one suspends them. A suspended account cannot send reports until it ends or you lift it.',
  },
  agency_admins: {
    title: 'Agency admin access requests',
    what: 'Someone asked, through Request Access, to run one agency’s dashboard.',
    who: () => 'Provincial Admin only.',
    effect: 'Approving sends them an invite and creates their agency-admin account. Rejecting closes the request.',
  },
  responders: {
    title: 'Responder approval',
    what: 'A field responder registered under one of your agencies and is waiting to be let in.',
    who: () => 'You, or the Agency Admin of that responder’s own agency — either can approve or reject.',
    effect: 'Approving lets them sign in and receive dispatches. Rejecting keeps them out.',
  },
};

const PURPOSE_ICON: Record<VerificationTab, LucideIcon> = {
  residents: IdCard,
  accounts: UserRound,
  agency_admins: UserCog,
  responders: Users,
};

function PurposeStrip({ tab }: { tab: VerificationTab }) {
  const p = PURPOSE[tab];
  const Icon = PURPOSE_ICON[tab];
  return (
    <section
      aria-label="What this view is for"
      className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]"
    >
      <div className="flex items-center gap-3 border-b border-[var(--color-surface-border)] bg-[color-mix(in_srgb,var(--color-surface-raised)_45%,var(--color-surface-card))] px-5 py-3">
        <span
          aria-hidden="true"
          className="flex size-9 shrink-0 items-center justify-center rounded-[10px]"
          style={{ color: 'var(--color-brand)', backgroundColor: 'color-mix(in srgb, var(--color-brand) 12%, transparent)' }}
        >
          <Icon size={18} />
        </span>
        <h2 className="text-[15px] font-semibold text-foreground">{p.title}</h2>
      </div>
      <dl className="grid grid-cols-1 divide-y divide-[var(--color-surface-border)] md:grid-cols-3 md:divide-x md:divide-y-0">
        {([
          ['What it is', p.what, Info],
          ['Who decides', p.who(), Gavel],
          ['What it changes', p.effect, ShieldCheck],
        ] as const).map(([label, text, RowIcon]) => (
          <div className="px-5 py-3.5" key={label}>
            <dt className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--color-text-tertiary)]">
              <RowIcon aria-hidden="true" size={12} />
              {label}
            </dt>
            <dd className="mt-1.5 text-[13px] leading-relaxed text-[var(--color-text-secondary)]">{text}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

function ResidentVerificationTab({ onSeeAccounts }: { onSeeAccounts: () => void }) {
  const { token } = useAuth();

  const [queue, setQueue] = useState<VerificationSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const setNotice = useNotice();

  /**
   * Show only submissions carrying a review signal.
   *
   * The default. At a thousand waiting residents an exhaustive queue is eight
   * hours of looking at photographs, and most of that work changes nothing:
   * verification is metadata a dispatcher reads, never a permission, so an
   * unreviewed resident can still report an emergency exactly like a verified
   * one. The people worth a decision are the ones a duplicate ID, a filed
   * report or an SOS warning points at.
   */
  const [priorityOnly, setPriorityOnly] = useState(true);

  /**
   * Free-text filter over the loaded queue.
   *
   * Local, not a server query. The list is already bounded — the endpoint caps
   * at 200 and the priority filter usually leaves far fewer — so a round trip
   * per keystroke would buy nothing, and a server-side LIKE across name, email
   * and address would need an index this table does not have. The result line
   * says how many of how many are showing, so a narrow search can never be
   * mistaken for an empty queue.
   */
  const [q, setQ] = useState('');

  /**
   * Rows ticked for a bulk decision, by id.
   *
   * Held as a Set of ids rather than a flag on the row, so a refresh — the
   * 60-second poll — cannot silently drop a selection by replacing the array
   * it was stored in. Ids that vanish from the queue are pruned on submit.
   */
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [bulkMethod, setBulkMethod] = useState<VerificationMethod>('barangay_official');
  const [bulkBusy, setBulkBusy] = useState(false);
  // Same photo-deletion disclosure the single-decide ReviewModal already
  // gives before an irreversible decision — bulk was the one path that
  // skipped it.
  const [confirmBulk, setConfirmBulk] = useState<'approve' | 'reject' | null>(null);
  const [selected, setSelected] = useState<VerificationDetail | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [deciding, setDeciding] = useState(false);

  const load = useCallback(async () => {
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      setQueue(await verificationApi.list(token, { priorityOnly }));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof ApiError ? e.message : 'Could not load the queue.');
    } finally {
      setLoading(false);
    }
  }, [token, priorityOnly]);

  useEffect(() => {
    void load();
    // Refreshing by hand is gone with the toolbar, so the list has to keep
    // itself current — a reviewer who leaves the tab open would otherwise be
    // deciding against whatever was true when they opened it. A minute is
    // slow enough to be free on a list this size and fast enough that two
    // reviewers do not spend long working the same submission.
    const id = setInterval(() => void load(), 60_000);
    return () => clearInterval(id);
  }, [load]);

  async function open(userId: string) {
    if (!token) return;
    setLoadingDetail(true);
    setNotice(null);
    try {
      setSelected(await verificationApi.detail(token, userId));
    } catch (e) {
      setNotice({
        type: 'error',
        text: e instanceof ApiError ? e.message : 'Could not open that submission.',
      });
    } finally {
      setLoadingDetail(false);
    }
  }

  async function decide(approve: boolean, method?: VerificationMethod) {
    if (!token || !selected) return;
    setDeciding(true);
    try {
      await verificationApi.decide(token, selected.id, { approve, method });
      setNotice({
        type: 'success',
        text: approve
          ? `${selected.full_name} verified and moved to Resident accounts. Their ID and selfie have been deleted.`
          : `${selected.full_name} left unverified. Their submitted images have been deleted.`,
      });
      setSelected(null);
      await load();
    } catch (e) {
      setNotice({
        type: 'error',
        text: e instanceof ApiError ? e.message : 'Could not record the decision.',
      });
    } finally {
      setDeciding(false);
    }
  }

  // Oldest first is how the endpoint orders it, so the head of the list is the
  // longest wait. Derived rather than sorted again — re-sorting here would
  // quietly diverge the moment the endpoint's order changed.
  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    if (!needle) return queue;
    return queue.filter(r =>
      (r.full_name ?? '').toLowerCase().includes(needle) ||
      (r.email ?? '').toLowerCase().includes(needle) ||
      (r.phone_number ?? '').toLowerCase().includes(needle) ||
      (r.valid_id_number ?? '').toLowerCase().includes(needle) ||
      (r.barangay ?? '').toLowerCase().includes(needle) ||
      (r.municipality_address ?? '').toLowerCase().includes(needle),
    );
  }, [queue, q]);

  // Only ever selects what is VISIBLE. A select-all that quietly included rows
  // hidden by the search would approve people the reviewer never saw.
  const shownIds = shown.map(r => r.id);
  const pickedShown = shownIds.filter(id => picked.has(id));
  const allShownPicked = shownIds.length > 0 && pickedShown.length === shownIds.length;

  function toggleOne(id: string) {
    setPicked(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleAllShown() {
    setPicked(prev => {
      const next = new Set(prev);
      if (allShownPicked) shownIds.forEach(id => next.delete(id));
      else shownIds.forEach(id => next.add(id));
      return next;
    });
  }

  async function decideBulk(approve: boolean) {
    if (!token || pickedShown.length === 0) return;
    setConfirmBulk(null);
    setBulkBusy(true);
    setNotice(null);
    try {
      const res = await verificationApi.decideBulk(token, {
        user_ids: pickedShown.slice(0, BULK_DECIDE_MAX),
        approve,
        method: approve ? bulkMethod : undefined,
      });
      const verb = approve ? 'verified' : 'rejected';
      setNotice(
        res.failed.length === 0
          ? { type: 'success', text: `${res.decided} resident${res.decided === 1 ? '' : 's'} ${verb}${approve ? ' and moved to Resident accounts' : ''}. Their photographs were deleted.` }
          : { type: 'error', text: `${res.decided} ${verb}, ${res.failed.length} could not be: ${res.failed[0].reason}` },
      );
      setPicked(new Set());
      await load();
    } catch (e) {
      setNotice({
        type: 'error',
        text: e instanceof ApiError ? e.message : 'The batch could not be recorded.',
      });
    } finally {
      setBulkBusy(false);
    }
  }

  const oldest = queue[0] ?? null;
  const oldestDays = oldest
    ? Math.floor((Date.now() - new Date(oldest.created_at).getTime()) / 86_400_000)
    : null;

  const provesResidency = queue.filter(
    r => r.valid_id_type && RESIDENCY_PROVING_IDS.has(r.valid_id_type),
  ).length;

  // Either photograph missing means the one comparison this page exists for
  // cannot be made.
  const missingEvidence = queue.filter(
    r => !r.valid_id_image_path || !r.selfie_image_path,
  ).length;

  return (
    <div className="min-h-full">
      <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}

      {/* The four things a reviewer needs before opening anything: how much
          there is, whether anyone has been left too long, how much of it will
          also settle an address, and how much of it cannot be reviewed at all. */}
      <DemoTarget id="verify:stats"><StatStrip>
        <StatCell
          bg="var(--color-brand-subtle)"
          color="var(--color-brand)"
          icon={<UserSearch size={12} strokeWidth={2} />}
          label="Waiting"
          // No ring: this is the whole the other three divide by.
          trend={queue.length === 1 ? 'resident' : 'residents'}
          value={queue.length}
        />
        <StatCell
          bg="var(--color-system-warning-bg)"
          color="var(--color-system-warning)"
          icon={<Clock size={12} strokeWidth={2} />}
          label="Longest wait"
          // An elapsed time is not a share of anything, so no whole — the same
          // rule that keeps the queue's wait tile ringless.
          trend={oldest ? `since ${new Date(oldest.created_at).toLocaleDateString()}` : 'nothing waiting'}
          value={oldestDays === null ? '—' : `${oldestDays}d`}
        />
        <StatCell
          bg="var(--color-severity-low-bg)"
          color="var(--color-severity-low)"
          icon={<BadgeCheck size={12} strokeWidth={2} />}
          label="Proves residency"
          // riseIsBad false: an LGU-issued document settles the address as well
          // as the identity, so more of them is the easier queue to work.
          riseIsBad={false}
          trend="LGU-issued"
          value={provesResidency}
          whole={queue.length}
          wholeLabel="waiting"
        />
        <StatCell
          bg="var(--color-severity-critical-bg)"
          color="var(--color-severity-critical)"
          icon={<ImageOff size={12} strokeWidth={2} />}
          label="Missing evidence"
          // The failure state this page could not previously surface. A
          // submission with no ID photo or no selfie cannot be reviewed at
          // all, so it sits in the queue forever looking like ordinary work.
          trend={missingEvidence === 0 ? 'all reviewable' : 'cannot be checked'}
          value={missingEvidence}
          whole={queue.length}
          wholeLabel="waiting"
        />
      </StatStrip></DemoTarget>

      <Card className="gap-0 py-0">
        {/* The queue's own scale control, in the same tab style as every other
            switcher. Reviewing everyone does not scale and mostly changes
            nothing; reviewing the flagged ones is the work that does. */}
        <DemoTarget id="verify:priority"><NavTabs
          activeKey={priorityOnly ? 'priority' : 'all'}
          ariaLabel="Which submissions to show"
          idPrefix="verification-scope"
          onSelect={k => setPriorityOnly(k === 'priority')}
          tabs={[
            { key: 'priority', label: 'Needs a look', icon: ShieldAlert, hint: 'Submissions carrying a signal' },
            { key: 'all', label: 'Everyone waiting', icon: Users, hint: 'Every submission, oldest first' },
          ]}
        /></DemoTarget>

        <div className="flex flex-col gap-3 px-5 py-4">
          <p className="text-[13px] leading-relaxed text-muted-foreground">
            {priorityOnly
              ? 'Submissions carrying a signal — the face check disagreed, the ID photo is unclear, the ID number is shared with another account, a report has already been filed, or there is an SOS warning. Oldest first.'
              : 'Everyone who has submitted an ID and is waiting. Oldest first — nobody should wait behind a newer submission.'}
          </p>
          <DemoTarget id="verify:search"><SearchInput
            label="Search the waiting list"
            onValueChange={setQ}
            placeholder="Name, email, phone, ID number or barangay…"
            value={q}
          /></DemoTarget>
        </div>

        <div className="border-t border-[var(--color-surface-border)]">
        {loading ? (
          <p className="py-10 text-center text-meta text-muted-foreground">
            Loading…
          </p>
        ) : queue.length === 0 ? (
          <EmptyQueue onSeeAccounts={onSeeAccounts} />
        ) : (
          <div className="flex flex-col">
            {/* The running count. Always shown, so a search that matches two of
                forty can never be mistaken for a queue with two people in it. */}
            <div className="flex flex-wrap items-center gap-3 px-5 py-2.5">
              <span className="text-meta text-muted-foreground">
                <Fig className="text-[12px] font-semibold">{shown.length}</Fig>
                {q.trim() ? ` of ${queue.length} match` : ' waiting'}
                {pickedShown.length > 0 && (
                  <>
                    {' · '}
                    <Fig className="text-[12px] font-semibold">{pickedShown.length}</Fig>
                    {' selected'}
                  </>
                )}
              </span>
            </div>

            {pickedShown.length > 0 && (
              <div className="px-5 pb-3">
                <BulkBar
                  busy={bulkBusy}
                  count={pickedShown.length}
                  method={bulkMethod}
                  onApprove={() => setConfirmBulk('approve')}
                  onClear={() => setPicked(new Set())}
                  onMethod={setBulkMethod}
                  onReject={() => setConfirmBulk('reject')}
                />
              </div>
            )}

            {shown.length === 0 ? (
              <p className="py-8 text-center text-meta text-muted-foreground">
                No submission matches “{q.trim()}”. {queue.length} are waiting.
              </p>
            ) : (
              <DemoTarget id="verify:table"><DataTableFrame minWidth={1120}>
                <DataHead>
                  <DataTh width="48px">
                    <input
                      aria-label="Select every submission shown"
                      checked={allShownPicked}
                      className="size-4 accent-[var(--color-brand)]"
                      disabled={shown.length === 0}
                      onChange={toggleAllShown}
                      type="checkbox"
                    />
                  </DataTh>
                  <DataTh>Resident</DataTh>
                  <DataTh width="160px">ID submitted</DataTh>
                  <DataTh width="160px">Place</DataTh>
                  <DataTh width="330px">Signals</DataTh>
                  <DataTh width="112px">Submitted</DataTh>
                  <DataTh align="right" width="112px"><span className="sr-only">Review</span></DataTh>
                </DataHead>
                <tbody>
                  {shown.map(row => (
                    <QueueRow
                      busy={loadingDetail}
                      key={row.id}
                      onOpen={() => void open(row.id)}
                      onPick={() => toggleOne(row.id)}
                      picked={picked.has(row.id)}
                      row={row}
                    />
                  ))}
                </tbody>
              </DataTableFrame></DemoTarget>
            )}
          </div>
        )}
        </div>
      </Card>

      <ReviewModal
        detail={selected}
        deciding={deciding}
        onClose={() => setSelected(null)}
        onDecide={decide}
      />

      <AlertDialog open={confirmBulk !== null} onOpenChange={open => { if (!open) setConfirmBulk(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {confirmBulk === 'approve' ? 'Verify' : 'Reject'} {pickedShown.length} resident{pickedShown.length === 1 ? '' : 's'}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Their ID photographs will be deleted as part of this decision, per the retention
              policy. This cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={bulkBusy}>Back</AlertDialogCancel>
            <AlertDialogAction
              variant={confirmBulk === 'reject' ? 'destructive' : 'default'}
              disabled={bulkBusy}
              onClick={() => void decideBulk(confirmBulk === 'approve')}
            >
              {confirmBulk === 'approve' ? 'Verify' : 'Reject'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      </div>
    </div>
  );
}

function EmptyQueue({ onSeeAccounts }: { onSeeAccounts: () => void }) {
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-12 text-center">
      <span className="flex size-12 items-center justify-center rounded-full bg-[var(--color-system-success-bg)] text-[var(--color-system-success)]">
        <BadgeCheck className="size-6" />
      </span>
      <p className="mt-1 text-[15px] font-semibold text-foreground">
        Nothing waiting
      </p>
      <p className="max-w-sm text-[13px] leading-relaxed text-muted-foreground">
        Residents who skipped verification do not appear here — they have not
        asked for anything and are not blocked. Only submitted IDs queue up.
      </p>
      <Button className="mt-2" onClick={onSeeAccounts} size="sm" variant="outline">
        <UserRound data-icon="inline-start" />
        See verified residents
      </Button>
    </div>
  );
}

function QueueRow({
  row,
  busy,
  picked,
  onOpen,
  onPick,
}: {
  row: VerificationSummary;
  busy: boolean;
  picked: boolean;
  onOpen: () => void;
  onPick: () => void;
}) {
  const idLabel = row.valid_id_type
    ? (ID_TYPE_LABELS[row.valid_id_type] ?? row.valid_id_type)
    : 'No ID type recorded';
  const provesResidency = row.valid_id_type
    ? RESIDENCY_PROVING_IDS.has(row.valid_id_type)
    : false;
  const flags = row.review_flags;

  return (
    <DataRow selected={picked}>
      <DataTd>
        <input
          aria-label={`Select ${row.full_name || row.email}`}
          checked={picked}
          className="size-4 shrink-0 accent-[var(--color-brand)]"
          onChange={onPick}
          type="checkbox"
        />
      </DataTd>
      <DataTd>
        <div className="flex items-center gap-3">
          <Initials name={row.full_name || row.email} />
          <div className="min-w-0">
            <p className="truncate font-semibold text-foreground">{row.full_name || row.email}</p>
            {row.full_name && <p className="truncate text-meta text-muted-foreground">{row.email}</p>}
          </div>
        </div>
      </DataTd>
      <DataTd>
        <p className="inline-flex items-center gap-1.5 text-[13px] text-foreground">
          <IdCard aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          {idLabel}
        </p>
        <p
          className="mt-0.5 text-[11.5px] font-medium"
          style={{ color: provesResidency ? 'var(--color-severity-low)' : 'var(--color-text-muted)' }}
          title={
            provesResidency
              ? 'LGU-issued — also evidence of living in this municipality'
              : 'Proves identity, but not residency'
          }
        >
          {provesResidency ? 'Proves residency' : 'Identity only'}
        </p>
      </DataTd>
      <DataTd>
        <p className="inline-flex items-center gap-1.5 text-[13px] text-[var(--color-text-secondary)]">
          <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          <span className="truncate">
            {row.barangay ?? '—'}
            {row.municipality_address ? `, ${row.municipality_address}` : ''}
          </span>
        </p>
      </DataTd>
      <DataTd>
        {/* Why this row is in front of you. Ordered worst first: a shared ID
            number is the only one of these a reviewer could not work out for
            themselves from the two photographs. */}
        <div className="flex flex-wrap gap-1">
          {flags && flags.duplicate_id_count > 0 && (
            <FlagChip
              color="var(--color-severity-critical)"
              icon={<Copy className="size-3" />}
              label={`Same ID as ${flags.duplicate_id_count} other account${flags.duplicate_id_count === 1 ? '' : 's'}`}
            />
          )}
          {flags && flags.sos_warning_count > 0 && (
            <FlagChip
              color="var(--color-system-warning)"
              icon={<ShieldAlert className="size-3" />}
              label={`${flags.sos_warning_count} SOS warning${flags.sos_warning_count === 1 ? '' : 's'}`}
            />
          )}
          {flags && flags.report_count > 0 && (
            <FlagChip
              color="var(--color-brand)"
              icon={<Siren className="size-3" />}
              label={`${flags.report_count} report${flags.report_count === 1 ? '' : 's'} filed`}
            />
          )}
          {/* The automatic comparison. Deliberately worded as a prompt
              ("check the face") rather than a finding ("faces do not match"):
              the model has never been validated on Philippine ID cards
              re-photographed under a phone flash, its expected failure is a
              FALSE mismatch, and a chip that reads like a verdict is one a
              tired reviewer will act on without opening the row. */}
          {flags?.face_mismatch && (
            <FlagChip
              color="var(--color-severity-high)"
              icon={<ScanFace className="size-3" />}
              label="Check the face"
            />
          )}
          {flags?.id_unreadable && (
            <FlagChip
              color="var(--color-system-warning)"
              icon={<FileWarning className="size-3" />}
              label="ID photo unclear"
            />
          )}
          {flags?.missing_evidence && (
            <FlagChip
              color="var(--color-text-muted)"
              icon={<ImageOff className="size-3" />}
              label="Photo missing"
            />
          )}
          {!flags || (
            flags.duplicate_id_count === 0 && flags.sos_warning_count === 0 && flags.report_count === 0 &&
            !flags.face_mismatch && !flags.id_unreadable && !flags.missing_evidence
          ) ? <span className="text-muted-foreground">—</span> : null}
        </div>
      </DataTd>
      <DataTd className="whitespace-nowrap text-[var(--color-text-secondary)]">
        {new Date(row.created_at).toLocaleDateString()}
      </DataTd>
      <DataTd align="right">
        <Button disabled={busy} onClick={onOpen} size="sm" variant="outline">
          <UserSearch data-icon="inline-start" />
          Review
        </Button>
      </DataTd>
    </DataRow>
  );
}

function ReviewModal({
  detail,
  deciding,
  onClose,
  onDecide,
}: {
  detail: VerificationDetail | null;
  deciding: boolean;
  onClose: () => void;
  onDecide: (approve: boolean, method?: VerificationMethod) => void;
}) {
  if (!detail) return null;

  const idLabel = detail.valid_id_type
    ? (ID_TYPE_LABELS[detail.valid_id_type] ?? detail.valid_id_type)
    : null;
  const provesResidency = detail.valid_id_type
    ? RESIDENCY_PROVING_IDS.has(detail.valid_id_type)
    : false;
  // An LGU document corroborates the address; a national one does not, so the
  // method recorded against the decision differs.
  const method: VerificationMethod =
    detail.valid_id_type && RESIDENCY_PROVING_IDS.has(detail.valid_id_type)
      ? (detail.valid_id_type === 'pwd_id' ? 'pwd_id' : 'barangay_official')
      : 'government_id';
  const address = [detail.purok_sitio, detail.street_address, detail.barangay,
    detail.municipality_address].filter(Boolean).join(', ') || null;
  const warnings = detail.review_flags?.sos_warning_count ?? 0;
  // With a photograph missing the comparison cannot be made at all, so
  // Verify is not offered: it would record "a person compared a face to a
  // card" about a card nobody could see.
  const canCompare = Boolean(detail.id_image_url && detail.selfie_url);

  return (
    /* Radix, not the project's own Modal. That component's header states it
       implements no focus trap, and this dialog holds a person's identity
       documents behind an irreversible pair of buttons — the one place on this
       console where a keyboard user falling out of the dialog and hitting the
       page behind it would be worst. */
    <Dialog onOpenChange={o => { if (!o && !deciding) onClose(); }} open>
      <DialogContent
        className="flex max-h-[92vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[880px]"
        data-testid="review-modal"
      >
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] py-4 pr-14 pl-5 text-left sm:pl-6">
          <div className="flex items-center gap-3.5">
            <span
              aria-hidden="true"
              className="flex size-11 shrink-0 items-center justify-center rounded-[12px]"
              style={{ color: 'var(--color-brand)', backgroundColor: 'color-mix(in srgb, var(--color-brand) 12%, transparent)' }}
            >
              <UserSearch size={21} />
            </span>
            <div className="min-w-0 flex-1">
              <DialogTitle className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[18px]">
                <span className="truncate">{detail.full_name || detail.email}</span>
                {warnings > 0 && (
                  <FlagChip
                    color="var(--color-system-warning)"
                    icon={<ShieldAlert className="size-3" />}
                    label={`${warnings} warning${warnings === 1 ? '' : 's'} on record`}
                  />
                )}
              </DialogTitle>
              <DialogDescription className="mt-0.5">
                Does the name and number on the account match the card, and is the
                face in the selfie the face on the card?
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-y-auto bg-[var(--color-surface-raised)]/40 px-5 py-4 sm:px-6">
          <div className="flex flex-col gap-3.5">
            {/* Step 1: the two photographs, side by side and whole. They were
                cropped to fill their boxes, which cut the number off a card
                photographed at an angle - the one thing being compared. */}
            <ReviewCard icon={ScanFace} step="1" title="Compare the two photographs">
              <div className="grid gap-3 sm:grid-cols-2">
                <Evidence label="ID document" url={detail.id_image_url} />
                <Evidence label="Selfie" url={detail.selfie_url} />
              </div>

              {/* Directly under the two photographs, because it is about them. */}
              <div className="mt-3">
                <_FaceMatchSummary detail={detail} />
              </div>

              {detail.liveness_method === 'none' && (
                <p className="mt-2.5 text-meta text-[var(--color-text-muted)]">
                  This selfie was taken manually — the on-device face check did not
                  run. That is common and not suspicious in itself; it just means the
                  comparison is entirely yours to make.
                </p>
              )}
            </ReviewCard>

            {/* Step 2: what was TYPED, to read against the card above. */}
            <ReviewCard icon={IdCard} step="2" title="Check it against what was typed">
              <dl className="grid gap-2.5 sm:grid-cols-3" data-testid="review-compare">
                <CompareTile icon={UserRound} label="Name on account" value={detail.name_on_file} />
                <CompareTile icon={Hash} label="ID number" mono value={detail.valid_id_number} />
                <CompareTile icon={CalendarClock} label="Date of birth" value={detail.date_of_birth} />
              </dl>
              <dl className="mt-3.5 grid gap-x-6 gap-y-2.5 border-t border-[var(--color-surface-border)] pt-3.5 sm:grid-cols-2">
                <Field
                  hint={idLabel ? (provesResidency ? 'LGU-issued: also evidence of living here' : 'Proves identity, not residency') : undefined}
                  icon={IdCard}
                  label="ID type"
                  value={idLabel}
                />
                <Field icon={Phone} label="Mobile" value={detail.phone_number} />
                <Field icon={MapPin} label="Address" value={address} />
                {detail.is_pwd && <Field icon={BadgeCheck} label="PWD ID" value={detail.pwd_id_number} />}
              </dl>
            </ReviewCard>

            <p className="flex items-start gap-2.5 rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
              <Trash2 aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
              <span>
                Deciding either way <strong className="font-semibold text-foreground">deletes both photographs</strong>, which
                is the retention rule for identity documents. The ID type and number
                stay on the record. A verified resident moves to <strong className="font-semibold text-foreground">Resident accounts</strong>;
                neither decision changes what they can do in the app.
              </span>
            </p>
          </div>
        </div>

        <div
          className="grid shrink-0 grid-cols-2 gap-2 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 sm:flex sm:flex-wrap sm:items-center sm:gap-2.5 sm:px-6"
          data-testid="review-actions"
        >
          {canCompare ? (
            <ActionButton
              color="var(--color-system-success)"
              hint="The card, the face and the typed details all match"
              icon={ShieldCheck}
              label={deciding ? 'Saving…' : 'Verify resident'}
              onClick={() => { if (!deciding) onDecide(true, method); }}
              solidText="var(--color-on-success)"
            />
          ) : (
            <p className="col-span-2 flex items-center gap-2 text-[12.5px] text-[var(--color-text-secondary)] sm:col-span-1" data-testid="review-cannot-verify">
              <ImageOff aria-hidden="true" className="size-4 shrink-0" style={{ color: 'var(--color-system-warning)' }} />
              A photograph is missing, so this cannot be verified.
            </p>
          )}
          <ActionButton
            color="var(--color-severity-critical)"
            hint="Leave this resident unverified"
            icon={ShieldX}
            label="Does not match"
            onClick={() => { if (!deciding) onDecide(false); }}
          />
          <Button
            className="h-10 w-full rounded-[11px] px-4 text-[13px] font-semibold max-sm:col-span-2 sm:ml-auto sm:h-[38px] sm:w-auto"
            disabled={deciding}
            onClick={onClose}
            variant="outline"
          >
            Cancel
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/** One numbered step of the review: what to look at, in the order to do it. */
function ReviewCard({ step, title, icon: Icon, children }: {
  step: string; title: string; icon: LucideIcon; children: React.ReactNode;
}) {
  return (
    <section className="rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4">
      <header className="mb-3 flex items-center gap-2.5">
        <span
          aria-hidden="true"
          className="flex size-6 shrink-0 items-center justify-center rounded-full font-mono text-[12px] font-bold"
          style={{ color: 'var(--color-text-inverse)', backgroundColor: 'var(--color-brand)' }}
        >
          {step}
        </span>
        <h3 className="flex-1 text-[13.5px] font-semibold text-foreground">{title}</h3>
        <Icon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
      </header>
      {children}
    </section>
  );
}

function Evidence({ label, url }: { label: string; url: string | null }) {
  return (
    <figure className="overflow-hidden rounded-[12px] border border-[var(--color-surface-border)]" data-evidence={url ? 'present' : 'missing'}>
      <figcaption className="flex items-center justify-between gap-2 border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/60 px-3 py-1.5">
        <span className="text-[12px] font-semibold text-[var(--color-text-secondary)]">{label}</span>
        {url && (
          <a
            className="inline-flex items-center gap-1 text-[11.5px] font-semibold text-[var(--color-brand)] underline-offset-2 hover:underline"
            href={url}
            rel="noreferrer"
            target="_blank"
          >
            Full size <ExternalLink aria-hidden="true" className="size-3" />
          </a>
        )}
      </figcaption>
      {url ? (
        // Plain <img>: these are short-lived signed URLs from a private
        // bucket, so next/image's optimiser would cache a link that has
        // already expired and would need the host allow-listed for a URL that
        // is different on every request.
        // object-contain on a dark ground: the whole card, never a crop of it.
        <a className="block bg-[#111]" href={url} rel="noreferrer" target="_blank">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img alt={label} className="h-64 w-full object-contain" src={url} />
        </a>
      ) : (
        <div className="flex h-64 flex-col items-center justify-center gap-2 bg-[var(--color-surface-raised)]/40 text-meta text-[var(--color-text-muted)]">
          <ImageOff aria-hidden="true" className="size-6" />
          Not submitted
        </div>
      )}
    </figure>
  );
}

/** One of the three things read straight off the card: large, and alone. */
function CompareTile({ icon: Icon, label, value, mono = false }: {
  icon: LucideIcon; label: string; value: string | null; mono?: boolean;
}) {
  return (
    <div className="min-w-0 rounded-[11px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/60 px-3.5 py-2.5">
      <dt className="flex items-center gap-1.5 text-[11px] font-semibold text-[var(--color-text-tertiary)]">
        <Icon aria-hidden="true" className="size-3 shrink-0" />
        {label}
      </dt>
      <dd
        className={[
          'mt-1 text-[15px] leading-snug font-semibold break-words',
          mono ? 'font-mono tabular-nums' : '',
          value ? 'text-foreground' : 'text-muted-foreground',
        ].join(' ')}
      >
        {value || 'Not given'}
      </dd>
    </div>
  );
}

function Field({
  label,
  value,
  icon: Icon,
  hint,
}: {
  label: string;
  value: string | null;
  icon: LucideIcon;
  hint?: string;
}) {
  return (
    <div className="flex min-w-0 items-start gap-2.5">
      <Icon aria-hidden="true" className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <dt className="text-[11px] font-semibold text-[var(--color-text-tertiary)]">{label}</dt>
        <dd className="text-[13px] break-words text-foreground">
          {value || <span className="text-muted-foreground">Not given</span>}
        </dd>
        {hint && <p className="text-meta text-muted-foreground">{hint}</p>}
      </div>
    </div>
  );
}

// ── Small parts ───────────────────────────────────────────────

/** One reason this submission is worth opening. */
function FlagChip({
  label,
  color,
  icon,
}: {
  label: string;
  color: string;
  icon: React.ReactNode;
}) {
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={{
        backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`,
        color,
      }}
    >
      {icon}
      {label}
    </span>
  );
}


// ── Bulk decision bar ─────────────────────────────────────────

/**
 * What convinced the reviewer, for a whole batch.
 *
 * A method picker is the one thing standing between "verify all" and a field
 * that means nothing. verification_level is a claim a dispatcher reads as "a
 * person compared a face to a card"; approving four hundred rows nobody opened
 * and stamping government_id on every one writes that claim into four hundred
 * audit entries where it is false.
 *
 * So the method is chosen deliberately and defaults to the one that needs no
 * document. Some of these are honestly batchable — a list handed over by a
 * barangay official, a set of accounts that already passed phone OTP — and
 * those are exactly the cases this exists for.
 */
const BULK_METHODS: {
  value: VerificationMethod; label: string; hint: string; icon: typeof Building2; color: string;
}[] = [
  { value: 'barangay_official', label: 'Barangay official confirmed', hint: 'A named official vouched for this list', icon: Building2, color: 'var(--color-brand)' },
  { value: 'phone_otp',         label: 'Phone OTP passed',            hint: 'Already verified automatically — no document needed', icon: Phone, color: 'var(--color-system-success)' },
  { value: 'government_id',     label: 'Government ID examined',      hint: 'Only if you actually opened each one', icon: IdCard, color: 'var(--color-system-warning)' },
  { value: 'pwd_id',            label: 'PWD ID examined',             hint: 'Only if you actually opened each one', icon: BadgeCheck, color: 'var(--color-system-warning)' },
];

function BulkBar({
  count,
  method,
  busy,
  onMethod,
  onApprove,
  onReject,
  onClear,
}: {
  count: number;
  method: VerificationMethod;
  busy: boolean;
  onMethod: (m: VerificationMethod) => void;
  onApprove: () => void;
  onReject: () => void;
  onClear: () => void;
}) {
  const overCap = count > BULK_DECIDE_MAX;
  const hint = BULK_METHODS.find(m => m.value === method)?.hint;

  return (
    <div className="flex flex-col gap-2 rounded-[var(--radius-card)] border border-[var(--color-brand)] bg-[var(--color-brand-subtle)] px-4 py-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-[13px] font-semibold text-foreground">
          <Fig className="text-[13px] font-semibold">{count}</Fig> selected
        </span>

        <span className="text-meta text-[var(--color-text-secondary)]">
          Verified because
        </span>
        <OptionPicker
          className="w-[240px] bg-[var(--color-surface-card)]"
          label="Verified because"
          onChange={v => onMethod(v as VerificationMethod)}
          options={BULK_METHODS}
          placeholder="Choose a method"
          size="sm"
          value={method}
        />

        <div className="ml-auto flex items-center gap-2">
          <Button disabled={busy} onClick={onClear} size="sm" variant="ghost">
            Clear
          </Button>
          <Button
            className="text-[var(--color-severity-critical)]"
            disabled={busy}
            onClick={onReject}
            size="sm"
            variant="outline"
          >
            <ShieldX data-icon="inline-start" />
            Reject {count}
          </Button>
          <Button disabled={busy || overCap} onClick={onApprove} size="sm">
            <ShieldCheck data-icon="inline-start" />
            {busy ? 'Recording…' : `Verify ${count}`}
          </Button>
        </div>
      </div>

      <p className="text-meta text-[var(--color-text-secondary)]">
        {overCap ? (
          <span className="font-semibold text-[var(--color-system-error)]">
            {count} is over the {BULK_DECIDE_MAX} limit for one batch. Narrow the
            selection — the server refuses anything larger.
          </span>
        ) : (
          <>
            {hint} · Every photograph in the batch is deleted on decision, and
            each row is recorded against your account.
          </>
        )}
      </p>
    </div>
  );
}


/**
 * What the automatic checks found, for a reviewer who is about to decide.
 *
 * WHY IT IS WORDED THE WAY IT IS
 *
 * This panel sits directly above two irreversible buttons, so every sentence
 * in it is written to be read by somebody under time pressure who will act on
 * whatever it seems to say. Three rules follow from that:
 *
 *   1. It never uses the word "verified", and it never implies a decision has
 *      been made. verification_level is raised by the person reading this and
 *      by nothing else — migration 023 states that, and this is the screen
 *      where forgetting it would matter.
 *   2. A low score is phrased as "look closely", not as "different people".
 *      The model has not been validated on this domain — a laminated card
 *      photographed under a phone flash, often years old — and the failure it
 *      is expected to make is rejecting the right person. An ID photograph
 *      taken before an illness, or of someone wearing a hijab in one image and
 *      not the other, scores badly and is correct.
 *   3. "Not checked" is shown as its own state and not folded into a bad
 *      score. A deployment that has not installed the model, or a resident who
 *      registered before this existed, has no result — and rendering that as
 *      anything other than "no result" would invent evidence.
 *
 * The raw score is shown alongside the band. A reviewer who sees 0.34 next to
 * a 0.36 threshold learns something a chip reading "no match" would have
 * hidden from them entirely.
 */
function _FaceMatchSummary({ detail }: { detail: VerificationDetail }) {
  const verdict = detail.face_match_verdict ?? null;
  const checks = (detail.id_checks ?? null) as Record<string, unknown> | null;

  // Nothing was ever computed for this account. Not an error, and not a
  // finding — say so plainly and get out of the reviewer's way.
  if (!verdict && !checks) {
    return (
      <p className="text-meta text-[var(--color-text-muted)]">
        No automatic checks were run on this submission. Compare the two
        photographs yourself.
      </p>
    );
  }

  const READING: Record<string, { text: string; tone: string; bg: string }> = {
    match: {
      text: 'The two faces look like the same person.',
      tone: 'var(--color-system-success)',
      bg: 'var(--color-system-success-bg)',
    },
    uncertain: {
      text: 'Could not tell either way — look closely.',
      tone: 'var(--color-text-secondary)',
      bg: 'var(--color-surface-raised)',
    },
    no_match: {
      text: 'The two faces scored low against each other. Look closely — an old or worn ID photo scores low legitimately.',
      tone: 'var(--color-severity-high)',
      bg: 'var(--color-severity-high-bg)',
    },
    no_face_on_id: {
      text: 'No face was found on the ID photo — it may be the back of the card, or too blurred to read.',
      tone: 'var(--color-system-warning)',
      bg: 'var(--color-system-warning-bg)',
    },
    no_face_in_selfie: {
      text: 'No face was found in the selfie.',
      tone: 'var(--color-system-warning)',
      bg: 'var(--color-system-warning-bg)',
    },
    unavailable: {
      text: 'Automatic face checking is not switched on for this deployment. Compare the photographs yourself.',
      tone: 'var(--color-text-muted)',
      bg: 'var(--color-surface-raised)',
    },
  };

  const reading = verdict ? READING[verdict] : null;

  // Every ID check that has an opinion, as a short phrase. Keys absent on
  // older rows simply produce no line, which is correct — "we did not check"
  // and "the check passed" must never render the same way.
  const notes: string[] = [];
  if (checks) {
    if (checks.face_found === false) notes.push('no face on the card');
    if (checks.readable === false) notes.push('almost no readable text');
    if (checks.expired === true) notes.push('card expired');
    if (checks.number_format_ok === false) {
      notes.push('number does not fit the declared ID type');
    }
    if (checks.name_matched === false) {
      notes.push('typed surname not found on the card');
    }
    if (typeof checks.expiry_date === 'string' && checks.expired !== true) {
      notes.push(`valid until ${checks.expiry_date}`);
    }
  }

  const source = detail.id_number_source;

  return (
    <div
      className="rounded-[var(--radius-card)] px-4 py-3"
      style={{ backgroundColor: reading?.bg ?? 'var(--color-surface-raised)' }}
    >
      <p className="flex flex-wrap items-baseline gap-x-2 text-[13px] font-semibold"
         style={{ color: reading?.tone ?? 'var(--color-text-secondary)' }}>
        <span>Automatic check</span>
        {typeof detail.face_match_score === 'number' && (
          <span className="font-mono text-[12px] font-normal tabular-nums text-[var(--color-text-muted)]">
            score {detail.face_match_score.toFixed(2)}
          </span>
        )}
      </p>

      {reading && (
        <p className="mt-1 text-meta text-[var(--color-text-secondary)]">
          {reading.text}
        </p>
      )}

      {notes.length > 0 && (
        <p className="mt-1.5 text-meta text-[var(--color-text-secondary)]">
          <strong>ID photo:</strong> {notes.join(' · ')}.
        </p>
      )}

      {/* Where the number came from. An admin chasing a duplicate-ID flag
          needs to know whether it was read off the card by a machine or typed
          from memory before deciding whether a mismatch is fraud or a typo. */}
      {source && (
        <p className="mt-1.5 text-meta text-[var(--color-text-muted)]">
          ID number was{' '}
          {source === 'ocr'
            ? 'read off the card and left unchanged'
            : source === 'ocr_edited'
              ? 'read off the card, then corrected by hand'
              : 'typed by hand'}
          .
        </p>
      )}

      <p className="mt-2 text-meta text-[var(--color-text-muted)]">
        These are hints computed on the resident&rsquo;s phone. They decide
        nothing — your decision below is the only one that counts.
      </p>
    </div>
  );
}
