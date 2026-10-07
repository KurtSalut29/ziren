'use client';

/**
 * IncidentDetailModal — the whole report, without leaving the queue.
 *
 * A dispatcher triaging a busy queue reads a dozen reports for every one they
 * act on. Sending them to a full page for each means losing their scroll
 * position, their filters, and their place in the band every single time — and
 * the back button is a poor answer when the queue has re-polled underneath
 * them and reordered.
 *
 * So this opens over the queue and closes back to exactly where they were.
 *
 * IT FETCHES ON OPEN, NOT ON RENDER. The queue row already holds a summary,
 * but the fields that decide a dispatch — the reporter's phone number, the
 * emergency contact, the coordinates, the dispatch log — are detail-only.
 * Fetching them for every visible row on the off-chance one gets opened would
 * multiply the queue's traffic by its own length.
 *
 * Built on the Radix dialog rather than the project's own Modal, whose header
 * states outright that it implements no focus trap. A dialog holding a phone
 * number and a dispatch action is one a keyboard user has to be able to work
 * without falling out of it into the page behind.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { AcceptReportDialog } from '@/components/incidents/accept-report-dialog';
import { toast } from '@/lib/toast';
import { announceOpened } from '@/lib/incidents/arrivals';
import {
  AlertTriangle, Ban, CalendarClock, Check, CheckCheck, ClipboardCheck, Clock,
  Flag, Handshake, Landmark, ListTree, MapPin, MessageSquare, Phone, PhoneCall,
  ShieldCheck, ShieldX, Siren, Sparkles, Star, UserCheck, UserRound, Users, X,
  KeyRound, Crosshair, ExternalLink, Contact,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  acceptReport,
  fetchIncidentDetail,
  OUTCOME_LABEL,
  resolveIncident,
  type IncidentDetail,
  type SeverityLevel,
} from '@/lib/api/dispatch';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Button } from '@/components/efferd/ui/button';
import {
  AWAITING_STATUSES, CATEGORY_ICON, CLOSED_STATUSES, DUE_COLOR, SEV_ICON,
  STATUS_ICON, STATUS_STYLE, dueState, durationBetween, formatDue, statusLabel,
  timeShort,
} from '@/components/incidents/incident-vocabulary';
import { Alert } from '@/components/ui/alert';
import { SeverityRationale } from '@/components/ui/severity-rationale';
import { IncidentFeedbackPanel } from '@/components/incidents/incident-feedback-panel';
import { IncidentVoiceNote } from '@/components/incidents/incident-voice-note';
import { IncidentAttachments } from '@/components/incidents/incident-attachments';
import { IncidentLocationPanel } from '@/components/incidents/incident-location-panel';
import { NearbyResponders } from '@/components/incidents/nearby-responders';
import { ReportedFromElsewhere } from '@/components/incidents/reported-from-elsewhere';
import { geoPoint } from '@/lib/incidents/response-route';
import { severityKey } from '@/components/map/map-legend';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { recordReportText, withoutVoicePlaceholder } from '@/lib/incidents/report-text';
import { formatDate, formatDateTime } from '@/lib/format/datetime';
import { formatCoordinates } from '@/lib/format/geo';
import { displayPrefs, incidentPrefs, mapPrefs, privacyPrefs } from '@/lib/prefs/definitions';
import {
  groupWizardAnswers, OVERLAP_LABELS, VICTIM_RELATIONSHIP,
} from '@/lib/incidents/wizard-catalog';
// Reused rather than duplicated — see that module's docstring. Assign used
// to be a Link out to the full page purely to reach DispatchModal; now this
// dialog renders the same component directly.
import {
  CancelModal, DispatchModal, FlagSosModal, RejectReportModal,
} from '@/components/incidents/dispatch-action-modals';
import { AssistRequestDialog } from '@/components/incidents/assist-request-dialog';
import { IncidentAssistList } from '@/components/assist/incident-assist-list';
import { IncidentChatModal } from '@/components/incidents/incident-chat-modal';
import { ActionButton } from '@/components/incidents/incident-action-button';
import { ChatButtonBadge } from '@/components/incidents/chat-button-badge';
import { useIncidentThread } from '@/lib/hooks/useIncidentThread';
import {
  Answers, DetailSkeleton, Fact, Flag as FlagChip, InfoTile, MaskedContact, Milestones,
  Normalisation, Row, Section, type Milestone,
} from '@/components/incidents/incident-detail-parts';
import { HotlineLinks } from '@/components/ui/hotline-links';

const SEV_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

/**
 * The action bar's colours. Colour carries the decision at a glance: green
 * moves the report forward, brand orange is "send help now" (Dispatch is this
 * panel's one primary CTA, so it gets the colour every other CTA on the
 * console has), amber asks the reporter something, red stops or refuses.
 */
const ACT_GO = 'var(--color-system-success)';
const ACT_SEND = 'var(--color-brand)';
const ACT_ASK = 'var(--color-system-warning)';
const ACT_STOP = 'var(--color-severity-critical)';

/** A wash of [color] with a matching border and text, for a secondary button
 * that should read as a deliberate choice, not neutral chrome. */
function tintedOutline(color: string): React.CSSProperties {
  return {
    color,
    borderColor: `color-mix(in srgb, ${color} 45%, transparent)`,
    backgroundColor: `color-mix(in srgb, ${color} 10%, transparent)`,
  };
}

export function IncidentDetailModal({
  incidentId,
  onClose,
  isHistory = false,
  otherPendingCount = 0,
  fromAlert = false,
  preview = false,
}: {
  /** Null closes the dialog. Passing the id IS the open signal. */
  incidentId: string | null;
  onClose: () => void;
  /**
   * Opened from Incident History rather than the live queue. History has no
   * live poll behind it (see history-view.tsx), so acting on a still-open
   * incident from here means dispatching off a snapshot that may already be
   * stale — Assign always gives way to the read-only "More" menu here,
   * whatever the incident's status. The live queue (active-view.tsx) never
   * passes this, so its own behaviour — Assign on open work — is unchanged.
   */
  isHistory?: boolean;
  /**
   * How many OTHER reports are still waiting in the alert tray, when this
   * dialog was opened from there (see layout.tsx) — 0/omitted everywhere
   * else (Incident Records, History, Map), which has no tray and keeps the
   * old close-immediately behaviour. Requested 2026-09-23: closing with
   * others still waiting, on a report that isn't finished yet, now confirms
   * first rather than silently dropping back to the queue.
   */
  otherPendingCount?: number;
  /** The layout's alert-owned instance. Only it keeps the alert in the tray until close. */
  fromAlert?: boolean;
  /**
   * Opened by a Ziren demo to show what is in a report. Not announced as
   * opened, so it neither silences an alarm nor clears an alert.
   */
  preview?: boolean;
}) {
  const { token, isProvincialAdmin } = useAuth();

  useEffect(() => {
    if (incidentId && !preview) announceOpened({ id: incidentId, fromAlert });
  }, [incidentId, fromAlert, preview]);
  // A Provincial Admin oversees every station of their agency_type and
  // dispatches for none of them — assignment belongs to the agency that
  // owns the incident. Their useful next step is spatial: see where this
  // sits relative to everything else.
  const [detail, setDetail] = useState<IncidentDetail | null>(null);
  const [loading, setLoading] = useState(false);
  // The header's "Waiting 4m" is an age, so it has to keep moving while the
  // dialog sits open on a report nobody has been sent to.
  const [, setClockTick] = useState(0);
  useEffect(() => {
    if (!incidentId) return;
    const timer = setInterval(() => setClockTick(t => t + 1), 30_000);
    return () => clearInterval(timer);
  }, [incidentId]);
  const [error, setError] = useState<string | null>(null);

  // The conversation with the resident is its own window, opened by the Chat
  // button — not a card in the middle of the report. The thread itself is owned
  // HERE, not by the window, so it keeps loading (and can badge the button)
  // while the window is closed. See IncidentChatModal.
  const [chatOpen, setChatOpen] = useState(false);
  const thread = useIncidentThread({ incidentId, token, chatOpen });
  useEffect(() => { setChatOpen(false); }, [incidentId]);

  // ── Dispatch actions, done here instead of on a separate page ──────────
  //
  // Assign used to be a Link to /incidents/{id}#assign — the one action a
  // dispatcher actually takes on most reports, sending them straight back
  // out of the "without leaving the queue" dialog this file exists for.
  // Accept/Reject/Clarify/Resolve/Cancel/Flag had the same problem in the
  // other direction: they were never here at all, only on the full page,
  // so ANY decision beyond looking meant leaving. All seven now run from
  // this dialog, reusing the exact modal components the full page uses
  // (see the import above) rather than a second implementation of each.
  // Raised as toasts, not drawn in the page: an <Alert> at the top of a scrolling
  // panel is out of sight when the button that caused it is at the bottom.
  const setActionError = useCallback((msg: string | null) => { if (msg) toast.error(msg); }, []);
  const [actionLoading, setActionLoading] = useState(false);
  const setSuccessMsg = useCallback((msg: string | null) => { if (msg) toast.success(msg); }, []);
  const [showDispatchModal, setShowDispatchModal] = useState(false);
  // A responder chosen from the 'near this incident' panel, so the dialog opens with them ticked.
  const [dispatchPreselect, setDispatchPreselect] = useState<string | null>(null);
  const [showCancelModal, setShowCancelModal] = useState(false);
  const [showFlagModal, setShowFlagModal] = useState(false);
  const [showRejectModal, setShowRejectModal] = useState(false);
  const [showAssistDialog, setShowAssistDialog] = useState(false);
  // Bumped after a request goes out so the "stations we asked" list re-reads.
  const [assistVersion, setAssistVersion] = useState(0);
  const assistTriggerRef = useRef<HTMLButtonElement>(null);
  const [showAcceptConfirm, setShowAcceptConfirm] = useState(false);
  const [showResolveConfirm, setShowResolveConfirm] = useState(false);
  const [showCloseConfirm, setShowCloseConfirm] = useState(false);

  const reload = useCallback(async () => {
    if (!incidentId || !token) return;
    try {
      const d = await fetchIncidentDetail(incidentId, token);
      setDetail(d);
    } catch (err: unknown) {
      if (err instanceof ApiError && err.status === 401) { signOut(); return; }
      setError(
        err instanceof ApiError ? err.message : 'Could not load this incident.',
      );
    }
  }, [incidentId, token]);

  useEffect(() => {
    if (!incidentId || !token) return;
    let cancelled = false;

    // Clear before fetching. Without this the dialog shows the PREVIOUS
    // incident's detail for as long as the new request takes — the most
    // dangerous stale read on this console, because it looks like data.
    setDetail(null);
    setError(null);
    setLoading(true);

    fetchIncidentDetail(incidentId, token)
      .then(d => { if (!cancelled) setDetail(d); })
      .catch((err: unknown) => {
        if (cancelled) return;
        if (err instanceof ApiError && err.status === 401) { signOut(); return; }
        setError(
          err instanceof ApiError ? err.message : 'Could not load this incident.',
        );
      })
      .finally(() => { if (!cancelled) setLoading(false); });

    return () => { cancelled = true; };
  }, [incidentId, token]);

  // Closing on a report that isn't finished yet, while others are still
  // waiting, used to drop straight back to the queue with no warning — easy
  // to do by accident (Escape, a stray click outside) mid-triage. Only asks
  // when it actually matters: nothing to confirm once the incident is
  // resolved/cancelled, or when nothing else is waiting on this admin.
  const attemptClose = useCallback(() => {
    const unfinished = !!detail && !CLOSED_STATUSES.includes(detail.status);
    if (otherPendingCount > 0 && unfinished) { setShowCloseConfirm(true); return; }
    onClose();
  }, [detail, otherPendingCount, onClose]);

  const handleOpenChange = useCallback(
    (open: boolean) => { if (!open && !actionLoading) attemptClose(); },
    [attemptClose, actionLoading],
  );

  async function handleAccept() {
    if (!token || !detail) return;
    setShowAcceptConfirm(false);
    setActionLoading(true); setActionError(null);
    try {
      await acceptReport(detail.id, token);
      setSuccessMsg('Report accepted — ready to assign a responder.');
      await reload();
    } catch (e: unknown) {
      setActionError(e instanceof Error ? e.message : 'Action failed.');
    } finally { setActionLoading(false); }
  }

  async function handleResolve() {
    if (!token || !detail) return;
    setShowResolveConfirm(false);
    setActionLoading(true); setActionError(null);
    try {
      await resolveIncident(detail.id, null, token);
      setSuccessMsg('Incident resolved.');
      await reload();
    } catch (e: unknown) {
      setActionError(e instanceof Error ? e.message : 'Action failed.');
    } finally { setActionLoading(false); }
  }

  // Same derivation as page.tsx's, gated by `!isHistory` on top — the two
  // consoles must agree on what a dispatcher is allowed to do with the same
  // incident, or an action visible in one and missing from the other reads
  // as a bug rather than as the two-page-vs-one-dialog difference it
  // actually is. isHistory has no equivalent on the full page because the
  // full page is never opened from History — see this component's own
  // isHistory doc comment: History has no live poll behind it, so acting on
  // an incident from here means acting on a snapshot that may already be
  // stale. That was true before this dialog grew its own action bar and
  // stays true now — every flag below is false whenever isHistory is true,
  // whatever the snapshot's status claims.
  const reviewStatus = detail?.review_status ?? 'pending';
  const reviewUndecided = reviewStatus === 'pending' || reviewStatus === 'clarification_requested';
  const dispatchable = detail?.status === 'received' || detail?.status === 'processing';
  // Accept's own success message has always promised "ready to assign a
  // responder" — but until this reviewStatus check was added, Dispatch's
  // only gate was the incident's dispatch `status`, which is 'received' from
  // the moment a report is filed, same as review_status. The two conditions
  // were both already true on every brand-new report, so Dispatch sat right
  // next to Accept/Reject before either had been pressed — asked about
  // 2026-09-15 ("why show all the options if dispatch shows once you
  // accept?"). Cancel deliberately keeps no such gate: a dispatcher cancelling
  // an obvious duplicate should not have to Accept it first.
  const canDispatch = !isHistory && !!detail && !isProvincialAdmin && dispatchable && reviewStatus === 'accepted';
  const canResolve  = !isHistory && !!detail && !isProvincialAdmin && ['dispatched', 'en_route', 'arrived'].includes(detail.status);
  const incidentOpen = !!detail && !['resolved', 'cancelled'].includes(detail.status);
  const canCancel   = !isHistory && incidentOpen && !isProvincialAdmin;
  const canFlagSos  = !isHistory && incidentOpen && !!detail?.sos_flagged;
  const canReview = !isHistory && incidentOpen && !isProvincialAdmin && reviewUndecided;

  const sev = detail
    ? ((detail.suggested_severity ?? detail.severity) as SeverityLevel | null)
    : null;
  const sevColor = sev ? (SEV_COLOR[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
  const shortId = incidentId
    ? incidentId.replace(/-/g, '').toUpperCase().slice(-6)
    : '';

  // What the report says, without the mobile app's voice-report scaffolding —
  // the corrected reading where the spelling pass changed something. Used for
  // the heading; the stored text itself is never altered.
  // The operator's own display choices (Settings → Appearance, Map & Location,
  // Incident Preferences, Privacy). They change what THIS screen draws — never
  // what is stored, scored or sent to a crew.
  const display = displayPrefs.use();
  const view = incidentPrefs.use();
  const geo = mapPrefs.use();
  const privacy = privacyPrefs.use();

  const voiceText = recordReportText(detail?.report_text ?? '', detail?.signals);

  // The wizard's answers, split across the facets they answer. Anything the
  // catalog does not recognise still appears, under How.
  const facets = groupWizardAnswers(detail?.wizard_answers);

  // Chat is for the agency handling the report. A Provincial Admin, or anyone
  // reading from Incident Records, gets the same window read-only - and only
  // when there is something in it to read.
  const chatCanCompose = !isProvincialAdmin && !isHistory;
  const actionBarVisible = !!detail && (canReview || canDispatch || canResolve || canCancel || canFlagSos);
  const hasThread =
    (thread.notes?.length ?? 0) > 0 || Boolean(detail?.clarification_requested_at);
  const chatButton = (
    <ActionButton
      color={ACT_ASK}
      hint={chatCanCompose ? 'Ask the reporter' : 'Read the conversation'}
      icon={MessageSquare}
      label={chatCanCompose ? 'Chat' : 'Messages'}
      onClick={() => setChatOpen(true)}
      title={
        thread.unread > 0
          ? `${thread.unread} new ${thread.unread === 1 ? 'reply' : 'replies'} from the resident`
          : chatCanCompose ? 'Message the resident' : 'Read the messages on this report'
      }
    >
      <ChatButtonBadge count={thread.unread} />
    </ActionButton>
  );

  // ── What the header and the cards say, worked out once ──────────────────
  const category = detail?.incident_category ?? null;
  const categoryLabel = detail
    ? category && category !== 'other'
      ? CATEGORY_LABELS[category] ?? category
      : 'Uncategorised report'
    : loading ? 'Loading incident…' : 'Incident';
  const CategoryIcon = (category && CATEGORY_ICON[category]) || Siren;
  const SeverityIcon = SEV_ICON[sev ?? 'untriaged'] ?? SEV_ICON.untriaged;
  const recordNo = detail?.record_number ?? `INC-${shortId}`;
  const closed = !!detail && CLOSED_STATUSES.includes(detail.status);
  const awaiting = !!detail && AWAITING_STATUSES.includes(detail.status);

  // The status pill says where the report is in ITS OWN words: a report that
  // is "received" but not yet reviewed needs a person, and that is the state.
  const statusPill = (() => {
    if (!detail) return null;
    const style = STATUS_STYLE[detail.status] ?? STATUS_STYLE.received;
    const Icon = STATUS_ICON[detail.status] ?? STATUS_ICON.received;
    let label = statusLabel(detail.status);
    if (detail.status === 'cancelled' && reviewStatus === 'rejected') label = 'Rejected';
    else if (awaiting && reviewStatus === 'clarification_requested') label = 'Waiting for the reporter';
    else if (awaiting && reviewStatus === 'pending') label = 'Needs review';
    else if (awaiting && reviewStatus === 'accepted') label = 'Accepted · awaiting dispatch';
    return { style, Icon, label };
  })();

  // The clock: how long it has waited while nobody is sent, how long dispatch
  // took once somebody is, how long the whole thing took once it is closed.
  const clock = (() => {
    if (!detail) return null;
    if (closed) {
      return detail.resolved_at
        ? {
          label: detail.status === 'cancelled' ? 'Cancelled after' : 'Resolved in',
          value: durationBetween(detail.created_at, detail.resolved_at),
          note: null as string | null,
          tone: 'var(--color-text-secondary)',
        }
        : null;
    }
    if (awaiting) {
      const due = dueState(detail);
      return {
        label: 'Waiting',
        value: timeShort(detail.created_at),
        note: formatDue(due),
        tone: due.bucket === 'ontime' ? 'var(--color-text-primary)' : DUE_COLOR[due.bucket],
      };
    }
    return detail.dispatched_at
      ? {
        label: 'Dispatched after',
        value: durationBetween(detail.created_at, detail.dispatched_at),
        note: `${timeShort(detail.created_at)} since the report`,
        tone: 'var(--color-text-primary)',
      }
      : null;
  })();

  const reporter = detail?.users ?? null;
  // Verified = an administrator approved the resident's ID (verification_level
  // 2). Not `is_verified`, which doubles as the account's active flag and was
  // true or false regardless of the ID (user report 2026-10-08: a verified
  // resident shown as "Unverified").
  const reporterVerified = (reporter?.verification_level ?? 0) >= 2;
  const reporterInitials = (reporter?.full_name ?? '')
    .split(/\s+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('') || '?';
  const answerCount = facets.what.length + facets.who.length + facets.how.length;
  const showAnswers = view.showWizardAnswers;
  const hasFacts = !!detail && (
    (showAnswers && answerCount > 0)
    || !!detail.victim_relationship
    || (detail.overlap_agencies?.length ?? 0) > 0
  );

  // Dispatched, then the crew's own acceptance, then the close. A step that
  // cannot happen any more (a report cancelled before anyone was sent) is left
  // out instead of being shown as "not yet".
  const milestones: Milestone[] = detail ? [
    { label: 'Reported', at: formatDateTime(detail.created_at, display) },
    ...(detail.dispatched_at || !closed ? [{
      label: 'Dispatched',
      at: detail.dispatched_at ? formatDateTime(detail.dispatched_at, display) : null,
      note: detail.dispatched_at ? `after ${durationBetween(detail.created_at, detail.dispatched_at)}` : null,
      pending: 'Not yet dispatched',
      tone: 'var(--color-brand)',
    }] : []),
    // Only when the crew actually answered, or still can. Absent, not "Not
    // accepted", on an incident closed before acceptance was recorded.
    ...(detail.accepted_at || !closed ? [{
      label: 'Accepted by crew',
      at: detail.accepted_at ? formatDateTime(detail.accepted_at, display) : null,
      pending: 'Not yet',
    }] : []),
    {
      label: detail.status === 'cancelled' ? 'Cancelled' : 'Resolved',
      at: closed
        ? detail.resolved_at ? formatDateTime(detail.resolved_at, display) : 'No closing time recorded'
        : null,
      note: closed && detail.resolved_at ? `${durationBetween(detail.created_at, detail.resolved_at)} in total` : null,
      pending: 'Still open',
      tone: detail.status === 'cancelled' ? 'var(--color-text-muted)' : undefined,
    },
  ] : [];

  const mapLink = (primary: boolean) => (
    <ActionButton
      color={primary ? ACT_SEND : 'var(--color-text-secondary)'}
      hint="Open the live incident map"
      href={incidentId ? `/map?incident=${incidentId}` : '/map'}
      icon={MapPin}
      label="View on map"
      solidText={primary ? 'var(--color-text-inverse)' : undefined}
    />
  );

  return (
    <Dialog onOpenChange={handleOpenChange} open={incidentId !== null}>
      {/* A header across the whole dialog, then two columns, and the width to
          hold them. The report is a reading column; the map beside it is the
          thing being decided. Stacking them — which is what a 720px dialog
          forced — put the response distance below the fold of a panel nobody
          scrolls to the bottom of, so the one fact that decides which crew
          goes was the one fact hidden.

          Position follows otherPendingCount, not a fixed choice — asked for
          2026-09-23: pinning LEFT (to leave room for the alert tray on the
          right, see incident-interrupt.tsx) only makes sense when there IS a
          tray to make room for. With nothing else waiting, the reserved strip
          was empty space for no reason, so this is CENTRED and full width
          instead. `transition-*` animates between the two, so a report landing
          WHILE this is open (count going 0 -> 1+) visibly slides the dialog
          left and docks the tray beside it, rather than jumping. */}
      <DialogContent
        className={`flex max-h-[92vh] flex-col gap-0 overflow-hidden p-0 transition-[left,transform,max-width] duration-300 ease-out ${
          otherPendingCount > 0
            ? 'left-4 translate-x-0 sm:max-w-[min(1520px,calc(100vw_-_416px))]'
            : 'left-1/2 -translate-x-1/2 sm:max-w-[1520px]'
        }`}
        data-testid="incident-detail-modal"
      >
        {/* ── What this is, how bad, where it stands, how long it has waited ──
            One line a dispatcher can take in before reading anything else. The
            severity colours the top edge and the icon; it is also written out,
            with its own shape, because colour alone is never the signal.
            shrink-0: in a flex column with a max-height, a long body compresses
            its siblings. */}
        <DialogHeader
          data-demo="modal:header"
          className="shrink-0 border-b border-[var(--color-surface-border)] py-3.5 pl-5 pr-14 text-left sm:pl-6"
          style={{
            borderTop: `4px solid ${sevColor}`,
            background: `linear-gradient(90deg, color-mix(in srgb, ${sevColor} 10%, transparent) 0%, transparent 55%)`,
          }}
        >
          <div className="flex flex-wrap items-center gap-x-4 gap-y-3">
            <span
              className="hidden size-12 shrink-0 items-center justify-center rounded-[14px] sm:flex"
              style={{ color: sevColor, backgroundColor: `color-mix(in srgb, ${sevColor} 15%, transparent)` }}
            >
              <CategoryIcon size={24} />
            </span>

            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-x-2.5 gap-y-1.5">
                <DialogTitle className="text-[20px] font-extrabold leading-tight">
                  {categoryLabel}
                </DialogTitle>
                {detail && (
                  <span
                    className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11.5px] font-extrabold uppercase tracking-wide text-white"
                    data-testid="incident-severity"
                    style={{ backgroundColor: sevColor }}
                  >
                    <SeverityIcon size={13} strokeWidth={2.6} />
                    {sev ?? 'untriaged'}
                  </span>
                )}
                {statusPill && (
                  <span
                    className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[11.5px] font-bold"
                    data-testid="incident-status"
                    style={{ backgroundColor: statusPill.style.bg, color: statusPill.style.text }}
                  >
                    <statusPill.Icon size={13} />
                    {statusPill.label}
                  </span>
                )}
              </div>
              {/* Required by Radix for the dialog's accessible description. The
                  record number is what gets quoted on a form or read out over
                  the radio; a backend that predates migration 035 has none, so
                  the short id stands in rather than "undefined". */}
              <DialogDescription className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[12.5px]">
                <span className="font-mono text-[12.5px] font-bold text-foreground">{recordNo}</span>
                <span aria-hidden="true" className="hidden sm:inline">·</span>
                <span>
                  {detail ? `Reported ${formatDateTime(detail.created_at, display)}` : 'Full report detail'}
                </span>
              </DialogDescription>
            </div>

            {clock && (
              // One line, left to right: what is being timed, the time, and
              // what that means against the target. It was a small stack of
              // three, which read as three separate things.
              <div
                className="flex shrink-0 flex-wrap items-center gap-x-2.5 gap-y-1 rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3.5 py-2"
                data-testid="incident-clock"
              >
                <span className="text-[10.5px] font-bold uppercase tracking-wider text-muted-foreground">
                  {clock.label}
                </span>
                <span className="font-mono text-[22px] font-extrabold tabular-nums leading-none" style={{ color: clock.tone }}>
                  {clock.value}
                </span>
                {clock.note && (
                  <span
                    className="whitespace-nowrap rounded-full px-2 py-0.5 text-[11.5px] font-bold leading-tight"
                    style={{
                      color: clock.tone,
                      backgroundColor: `color-mix(in srgb, ${clock.tone} 12%, transparent)`,
                    }}
                  >
                    {clock.note}
                  </span>
                )}
              </div>
            )}
          </div>
        </DialogHeader>

        {/* Below lg the two columns stack and THIS is the scroll container.
            At lg each column scrolls on its own, so a long report never
            drags the map off screen. */}
        <div className="scroll-slim grid min-h-0 flex-1 grid-cols-1 overflow-y-auto bg-[var(--color-surface-raised)] lg:grid-cols-[minmax(0,1fr)_minmax(0,1.02fr)] lg:overflow-hidden">
          {/* ── The report ─────────────────────────────────────────────── */}
          {/* lg:min-h-0 is what lets this shrink inside the grid and scroll
              on its own; without it a long report pushes the footer out of the
              clipped dialog. The cards themselves never shrink: in a flex
              column that is shorter than its content they would be squeezed
              into each other instead of scrolling. */}
          <div className="scroll-slim flex flex-col gap-3 px-4 py-4 sm:px-5 lg:min-h-0 lg:overflow-y-auto lg:border-r lg:border-[var(--color-surface-border)] [&>*]:shrink-0">
            {error && <Alert message={error} variant="error" />}

            {loading && !detail && <DetailSkeleton />}

            {detail && (
              <>
                {/* Anything that should change how this report is handled, as
                    chips, before the report itself. Nothing is drawn when there
                    is nothing to warn about. */}
                {(detail.sos_flagged || detail.reported_from_elsewhere
                  || (reporter && !reporterVerified) || (reporter?.sos_warning_count ?? 0) > 0) && (
                  <div className="flex flex-wrap gap-2" data-testid="incident-flags">
                    {detail.sos_flagged && (
                      <FlagChip icon={Siren} tone="var(--color-severity-critical)">Filed with the SOS button</FlagChip>
                    )}
                    {detail.reported_from_elsewhere && (
                      <FlagChip icon={MapPin} tone="var(--color-system-warning)">Reporter is not at the scene</FlagChip>
                    )}
                    {reporter && !reporterVerified && (
                      <FlagChip icon={ShieldX} tone="var(--color-system-warning)">Reporter not verified</FlagChip>
                    )}
                    {reporter && reporter.sos_warning_count > 0 && (
                      <FlagChip icon={AlertTriangle} tone="var(--color-severity-critical)">
                        {reporter.sos_warning_count} prior false SOS
                      </FlagChip>
                    )}
                  </div>
                )}

                {/* WHY it was ranked this way, in one line, where the severity
                    badge is still in view. The full reasoning is further down.
                    Purple, per globals.css: this is the system's reading. */}
                {view.showAiSuggestion && detail.signals?.severity_reason && (
                  <p
                    className="flex items-start gap-2 rounded-[10px] border px-3 py-2 text-[13px] leading-snug"
                    data-testid="incident-why"
                    style={{ borderColor: 'var(--color-ai-suggested)', background: 'var(--color-ai-suggested-bg)' }}
                  >
                    <Sparkles aria-hidden className="mt-0.5 shrink-0" size={14} style={{ color: 'var(--color-ai-suggested)' }} />
                    <span className="min-w-0">
                      <span className="font-bold capitalize">Why {sev ?? 'this severity'}: </span>
                      {detail.signals.severity_reason}
                      {detail.signals.severity_rule && (
                        <span className="ml-1.5 font-mono text-[11.5px] font-bold" style={{ color: 'var(--color-ai-suggested)' }}>
                          {detail.signals.severity_rule}
                        </span>
                      )}
                    </span>
                  </p>
                )}

                {/* The cards follow the wizard's own order — the five Ws and the
                    H — as the dialog always has, each drawing from whichever
                    fields answer that question. The resident's answers are
                    gathered under WHAT as tiles, each tagged with the W it
                    answers, so they can be read in one look. */}

                <Section demo="modal:said" facet="What" icon={ListTree} title="What the reporter said" tone={sevColor}>
                  {/* A voice report's stored text opens with the app's own
                      "<Category> — reported by voice recording —". That is
                      scaffolding, not their words, so it is dropped here; the
                      corrected reading below and the recording itself are
                      unchanged. A report typed by the resident is shown exactly
                      as stored. */}
                  <blockquote
                    className="rounded-[10px] border-l-4 bg-[var(--color-surface-raised)] px-4 py-3 text-[15.5px] font-medium leading-relaxed text-foreground"
                    data-testid="incident-words"
                    style={{ borderLeftColor: sevColor }}
                  >
                    {voiceText.kind === 'voice-untranscribed' ? (
                      <span className="text-[14px] font-normal text-muted-foreground">
                        Voice report with no transcript — play the recording below.
                      </span>
                    ) : (
                      withoutVoicePlaceholder(detail.report_text)
                    )}
                  </blockquote>
                  {/* "What they said" is only true of the text when the
                      transcription got it right. The recording always is. */}
                  <Normalisation
                    normalisation={detail.signals?.normalisation}
                    reportText={detail.report_text}
                  />
                  {view.showRecording && (
                    <IncidentVoiceNote
                      heardText={detail.signals?.transcript?.text}
                      incidentId={detail.id}
                      token={token}
                    />
                  )}
                  {/* Not gated on showRecording: a typed report can carry photos. */}
                  <IncidentAttachments incidentId={detail.id} token={token} />

                  {hasFacts ? (
                    <div className="grid grid-cols-2 gap-2 xl:grid-cols-3" data-testid="incident-facts">
                      {showAnswers && <Answers items={facets.what} tag="What" />}
                      {showAnswers && <Answers items={facets.who} tag="Who" />}
                      {detail.victim_relationship && (
                        <Fact label="Victim is" tag="Who">
                          {VICTIM_RELATIONSHIP[detail.victim_relationship] ?? detail.victim_relationship}
                        </Fact>
                      )}
                      {showAnswers && <Answers items={facets.how} tag="How" />}
                      {detail.overlap_agencies && detail.overlap_agencies.length > 0 && (
                        <Fact label="Also present" tag="What">
                          {detail.overlap_agencies.map(f => OVERLAP_LABELS[f] ?? f).join(' · ')}
                        </Fact>
                      )}
                    </div>
                  ) : showAnswers && (
                    <p className="text-[13px] text-muted-foreground">
                      The reporter did not answer the follow-up questions.
                    </p>
                  )}
                </Section>

                <div className="grid gap-3 md:grid-cols-2" data-demo="modal:where">
                  <Section facet="Where" icon={MapPin} title="Where it is" tone="var(--color-brand)">
                    {/* The resident placed this incident on the map because
                        they are not at it (a relative called them, say). The
                        address is the INCIDENT; this says the caller is
                        elsewhere, so the dispatcher calls back to confirm
                        instead of trusting either blindly. */}
                    {detail.reported_from_elsewhere && (
                      <ReportedFromElsewhere
                        incident={geoPoint(detail.location)}
                        reporter={geoPoint(detail.reporter_location ?? null)}
                        reporterAddress={detail.reporter_address ?? null}
                      />
                    )}
                    <p className="text-[14.5px] font-bold leading-snug text-foreground" data-testid="incident-address">
                      {detail.location_address ?? 'No address resolved'}
                    </p>
                    {/* Required on every report since 2026-09-30 — the name a
                        crew can actually find, so it gets its own box. */}
                    {detail.landmark_note && (
                      <p
                        className="flex items-start gap-2 rounded-[10px] border px-3 py-2 text-[13.5px] font-semibold leading-snug text-foreground"
                        data-testid="incident-landmark"
                        style={{
                          borderColor: 'color-mix(in srgb, var(--color-brand) 35%, transparent)',
                          backgroundColor: 'color-mix(in srgb, var(--color-brand) 8%, transparent)',
                        }}
                      >
                        <Landmark aria-hidden className="mt-0.5 shrink-0" size={15} style={{ color: 'var(--color-brand)' }} />
                        <span className="min-w-0">
                          <span className="block text-[10.5px] font-bold uppercase tracking-wider text-muted-foreground">Landmark</span>
                          {detail.landmark_note}
                        </span>
                      </p>
                    )}
                    {/* Coordinates are exact; the address is a NAME derived from
                        them, and naming is the part that fails — OpenStreetMap
                        covers Biliran thinly. When the two disagree, these win,
                        so they are shown rather than hidden behind the address. */}
                    {view.showLocationDetail && detail.location?.coordinates && (
                      <InfoTile
                        action={(
                          <a
                            className="inline-flex items-center gap-1 rounded-md px-1.5 py-1 text-[12px] font-semibold text-[var(--color-system-info)] hover:underline"
                            href={`https://www.google.com/maps?q=${detail.location.coordinates[1]},${detail.location.coordinates[0]}`}
                            rel="noopener noreferrer"
                            target="_blank"
                          >
                            Open map <ExternalLink aria-hidden size={12} />
                          </a>
                        )}
                        icon={Crosshair}
                        label="Coordinates"
                        testId="incident-coordinates"
                      >
                        <span className="font-mono text-[13px] tabular-nums">
                          {formatCoordinates(
                            detail.location.coordinates[1],
                            detail.location.coordinates[0],
                            geo,
                          )}
                        </span>
                      </InfoTile>
                    )}
                    {/* The station's NAME is not repeated here. The panel beside
                        this column states it, measures the distance to it and
                        reports whether anyone there is on duty. The number
                        stays, because ringing the station is an action. */}
                    {detail.stations?.agencies?.contact_number && (
                      <InfoTile icon={Phone} label="Station contact" testId="incident-station-contact">
                        <HotlineLinks className="underline-offset-2" value={detail.stations.agencies.contact_number} />
                      </InfoTile>
                    )}
                  </Section>

                  <Section facet="Who" icon={UserRound} title="Who reported it">
                    {reporter ? (
                      <>
                        <div className="flex items-center gap-3">
                          <span className="flex size-10 shrink-0 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[13px] font-bold text-foreground">
                            {reporterInitials}
                          </span>
                          <div className="min-w-0">
                            <p className="truncate text-[14.5px] font-bold text-foreground" data-testid="incident-reporter">
                              {reporter.full_name}
                            </p>
                            <p
                              className="flex items-center gap-1 text-[12px] font-semibold"
                              style={{ color: reporterVerified ? 'var(--color-system-success)' : 'var(--color-system-warning)' }}
                            >
                              {reporterVerified ? <ShieldCheck size={13} /> : <ShieldX size={13} />}
                              {reporterVerified ? 'Verified resident' : 'Unverified — identity not confirmed'}
                            </p>
                          </div>
                        </div>
                        {/* The reporter's Ziren code: they read it off their own
                            report. Asked for on a call or by the crew on
                            arrival, so nobody is identified by how they look or
                            their gender (backend app/core/meet_code.py). */}
                        {detail.meet_code && (
                          <InfoTile
                            icon={KeyRound}
                            label="Ziren code — ask for it to confirm the reporter"
                            testId="incident-meet-code"
                            tone="var(--color-system-info)"
                          >
                            <span className="font-mono text-[15px] font-bold tracking-[0.3em] tabular-nums">
                              {detail.meet_code}
                            </span>
                          </InfoTile>
                        )}
                        {/* A tel: link: the dispatcher's next action after
                            reading the report is often to ring this number. */}
                        {reporter.phone_number && (
                          <InfoTile
                            icon={PhoneCall}
                            label="Call the reporter"
                            testId="incident-phone"
                            tone="var(--color-system-success)"
                          >
                            <span className="font-mono text-[15px] font-bold tabular-nums">
                              <MaskedContact
                                key={reporter.phone_number}
                                mask={privacy.maskContacts}
                                value={reporter.phone_number}
                              />
                            </span>
                          </InfoTile>
                        )}
                        {reporter.sos_warning_count > 0 && (
                          <InfoTile icon={AlertTriangle} label="False SOS history" tone="var(--color-severity-critical)">
                            {reporter.sos_warning_count} prior false SOS
                            {reporter.sos_suspended_until &&
                              ` · suspended until ${formatDate(reporter.sos_suspended_until, display)}`}
                          </InfoTile>
                        )}
                        {reporter.emergency_contact_name && (
                          <InfoTile icon={Contact} label="Emergency contact" testId="incident-emergency-contact">
                            {reporter.emergency_contact_name}
                            {reporter.emergency_contact_number && (
                              <>
                                {' · '}
                                <MaskedContact
                                  callable={false}
                                  key={reporter.emergency_contact_number}
                                  mask={privacy.maskContacts}
                                  value={reporter.emergency_contact_number}
                                />
                              </>
                            )}
                          </InfoTile>
                        )}
                      </>
                    ) : (
                      <p className="text-[13px] text-muted-foreground">
                        No reporter record attached to this incident.
                      </p>
                    )}
                  </Section>
                </div>

                {/* WHO IS NEAR. Responders on duty near a new report are told at the
                    same moment the agency is, without waiting to be dispatched; this
                    is where the dispatcher sees who they are, how far, and what each
                    is already on, before choosing. Only while nobody has been sent:
                    after that "Who responded" below is the record. Also shown for an
                    OPEN incident opened from Incident Records - a Provincial Admin
                    has no live queue, and that is where they meet one - where it is
                    read-only (canDispatch is false there). */}
                {token && !detail.responder && !detail.assigned_responder_id && awaiting && (
                  <Section demo="modal:nearby" facet="Response" icon={Users} title="Responders near this incident">
                    <NearbyResponders
                      active
                      incidentId={detail.id}
                      initial={detail.nearby ?? null}
                      onDispatch={canDispatch ? (id) => {
                        setDispatchPreselect(id);
                        setShowDispatchModal(true);
                        setActionError(null);
                      } : undefined}
                      scene={geoPoint(detail.location)}
                      token={token}
                    />
                  </Section>
                )}

                {/* WHO RESPONDED. The reporter is under "Who reported it"; this
                    is the other side — who the system sent. Shown only once a
                    responder was assigned, since "no responder" on an open
                    incident is the normal state, not a fact about the record. */}
                {(detail.responder || detail.assigned_responder_id) && (
                  <Section facet="Response" icon={UserCheck} title="Who responded" tone="var(--color-system-success)">
                    <div className="grid grid-cols-2 gap-2 xl:grid-cols-3">
                      <Fact label="Responder">
                        {detail.responder?.full_name ?? 'Account no longer exists'}
                        {detail.responder?.badge_id && (
                          <span className="block font-mono text-[11.5px] font-medium text-muted-foreground">
                            Badge {detail.responder.badge_id}
                          </span>
                        )}
                      </Fact>
                      {detail.stations?.name && (
                        <Fact label="Station">
                          {detail.stations.name}
                          {detail.stations.agencies?.agency_type && (
                            <span className="block text-[11.5px] font-medium text-muted-foreground">
                              {detail.stations.agencies.agency_type}
                              {detail.stations.agencies.municipality
                                ? ` · ${detail.stations.agencies.municipality}`
                                : ''}
                            </span>
                          )}
                        </Fact>
                      )}
                      <Fact label="Status">{statusLabel(detail.status)}</Fact>
                    </div>
                  </Section>
                )}

                {/* WHAT THE CREW FOUND. Severity is what the rubric guessed
                    from a civilian's account; this is what was true. Recorded
                    by the crew when they close, so it exists on closed
                    incidents only — and on those closed before the field
                    existed it is blank, which is stated rather than hidden. */}
                {closed && (
                  <Section facet="Result" icon={ClipboardCheck} title="Outcome">
                    {detail.outcome ? (
                      <div className="grid grid-cols-2 gap-2 xl:grid-cols-4">
                        <Fact label="What was found">{OUTCOME_LABEL[detail.outcome] ?? detail.outcome}</Fact>
                        {/* NULL and 0 mean different things and both are kept:
                            NULL is "not recorded", 0 is "counted, nobody hurt". */}
                        {typeof detail.casualties_injured === 'number' && (
                          <Fact label="Injured">
                            <span className="font-mono tabular-nums">{detail.casualties_injured}</span>
                          </Fact>
                        )}
                        {typeof detail.casualties_fatal === 'number' && (
                          <Fact label="Fatalities">
                            <span
                              className="font-mono tabular-nums"
                              style={detail.casualties_fatal > 0 ? { color: 'var(--color-severity-critical)' } : undefined}
                            >
                              {detail.casualties_fatal}
                            </span>
                          </Fact>
                        )}
                        {typeof detail.casualties_transported === 'number' && (
                          <Fact label="Transported">
                            <span className="font-mono tabular-nums">{detail.casualties_transported}</span>
                          </Fact>
                        )}
                      </div>
                    ) : (
                      <p className="text-[13px] text-muted-foreground">
                        No outcome was recorded for this incident.
                      </p>
                    )}
                    {detail.outcome_notes && (
                      <Row label="Crew notes">{detail.outcome_notes}</Row>
                    )}
                  </Section>
                )}

                <Section demo="modal:timeline" facet="When" icon={CalendarClock} title="Timeline">
                  <Milestones items={milestones} />
                  <div className="border-t border-[var(--color-surface-border)] pt-3">
                    <p className="mb-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">Activity</p>
                    {detail.dispatch_log.length === 0 ? (
                      <p className="text-[13px] text-muted-foreground">
                        Nothing logged yet — this report has not been acted on.
                      </p>
                    ) : (
                      <ol className="flex flex-col gap-2.5">
                        {detail.dispatch_log.map(entry => (
                          <li className="flex gap-2.5 text-[13px]" key={entry.id}>
                            <Clock className="mt-0.5 shrink-0 text-muted-foreground" size={13} />
                            <div className="min-w-0">
                              <p className="text-foreground">
                                <span className="font-semibold capitalize">{entry.action}</span>
                                {entry.users?.full_name && (
                                  <span className="text-muted-foreground">
                                    {' '}by {entry.users.full_name}
                                  </span>
                                )}
                              </p>
                              {entry.was_override && (
                                <p style={{ color: 'var(--color-system-warning)' }}>
                                  Severity overridden
                                  {entry.suggested_severity &&
                                    ` from ${entry.suggested_severity}`}
                                  {' '}to {entry.chosen_severity}
                                  {entry.override_reason && ` — ${entry.override_reason}`}
                                </p>
                              )}
                              {entry.notes && (
                                <p className="text-muted-foreground">{entry.notes}</p>
                              )}
                              <p className="text-[11.5px] text-muted-foreground">
                                {formatDateTime(entry.created_at, display)}
                              </p>
                            </div>
                          </li>
                        ))}
                      </ol>
                    )}
                  </div>
                </Section>

                {!isProvincialAdmin && (
                  <Section demo="modal:assist" icon={Handshake} title="Need another station?" tone="var(--color-brand)">
                    <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
                      <button
                        className="inline-flex items-center gap-1.5 rounded-lg border px-3.5 py-2 text-[12.5px] font-semibold transition-all hover:brightness-105"
                        onClick={() => setShowAssistDialog(true)}
                        ref={assistTriggerRef}
                        style={tintedOutline('var(--color-brand)')}
                        type="button"
                      >
                        <Handshake size={14} />
                        Request help from another station
                      </button>
                      <span className="text-[12px] text-muted-foreground">
                        Any station in Biliran. They are alerted; this report stays with you.
                      </span>
                    </div>
                    {token && <IncidentAssistList incidentId={detail.id} token={token} version={assistVersion} />}
                  </Section>
                )}

                {/* WHY, in full. The wizard never asks a resident what CAUSED the
                    emergency — nobody in one can answer that reliably — so the
                    only "why" this system holds is why it ranked the report the
                    way it did, which is the one a dispatcher can act on and the
                    one a panel will ask about. SeverityRationale draws its own
                    titled panel, so it is not wrapped in a Section. */}
                {view.showAiSuggestion && <SeverityRationale severity={sev} signals={detail.signals} />}

                {/* Feedback cannot exist before resolution — the backend
                    rejects it with 409 — so there is nothing to show, not
                    even an empty state, for the vast majority of incidents
                    being read here (open ones, in the live queue). */}
                {detail.status === 'resolved' && (
                  <Section facet="Review" icon={Star} title="Reporter feedback">
                    <IncidentFeedbackPanel
                      incidentId={detail.id}
                      status={detail.status}
                      token={token}
                    />
                  </Section>
                )}
              </>
            )}
          </div>

          {/* ── Where it is, and how far help has to come ───────────────── */}
          <div className="flex min-h-0 flex-col border-t border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-4 sm:px-5 lg:border-t-0" data-demo="modal:map">
            {detail ? (
              <IncidentLocationPanel
                detail={detail}
                // Safe here, unlike the full incident page: this column has
                // no scroll of its own at lg+ (only the report column beside
                // it scrolls), so the wheel has nothing else to conflict
                // with. See the prop's own doc comment on IncidentRouteMap.
                scrollWheelZoom
                severity={severityKey(sev)}
              />
            ) : (
              <div className="h-[300px] animate-pulse rounded-[var(--radius-card)] bg-muted lg:h-full" />
            )}
          </div>
        </div>

        {/* One bar, docked at the bottom across both columns: what can be done
            with this report on the left, Close on the right. It used to be two
            bars, the second holding only Close.
            Each choice explains itself in its tooltip (see ActionButton).
            One solid button per state is the step that moves the report
            forward; a divider then separates "what to do with the report" from
            "stop this incident". */}
        <div
          className="flex shrink-0 flex-wrap items-center gap-x-3 gap-y-2 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 shadow-[0_-6px_16px_-12px_rgba(16,24,40,0.25)] sm:px-6"
          data-demo="modal:actions"
          data-testid="incident-actions"
        >
          {actionBarVisible ? (
            <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto sm:flex-1 sm:flex-wrap sm:items-center sm:gap-2.5">
              {canReview && (
                <>
                  <ActionButton
                    color={ACT_GO}
                    hint="The report is real"
                    icon={Check}
                    label="Accept"
                    onClick={() => setShowAcceptConfirm(true)}
                    solidText="var(--color-on-success)"
                  />
                  {chatButton}
                  <ActionButton
                    color={ACT_STOP}
                    hint="Not a real emergency"
                    icon={X}
                    label="Reject"
                    onClick={() => { setShowRejectModal(true); setActionError(null); }}
                  />
                </>
              )}
              {canDispatch && (
                <ActionButton
                  color={ACT_SEND}
                  hint="Send responders now"
                  icon={Siren}
                  label="Dispatch"
                  onClick={() => { setShowDispatchModal(true); setActionError(null); }}
                  solidText="var(--color-text-inverse)"
                />
              )}
              {canResolve && (
                <ActionButton
                  color={ACT_GO}
                  hint="The incident is handled"
                  icon={CheckCheck}
                  label="Mark resolved"
                  onClick={() => setShowResolveConfirm(true)}
                  solidText="var(--color-on-success)"
                />
              )}
              {/* Chat stays reachable once the report is decided: in the
                  review group above while it is undecided, here after that. */}
              {!canReview && chatButton}
              {(canReview || canDispatch || canResolve) && (canCancel || canFlagSos) && (
                <span
                  aria-hidden
                  className="mx-1 hidden h-6 w-px shrink-0 sm:block"
                  style={{ backgroundColor: 'var(--color-surface-border)' }}
                />
              )}
              {canCancel && (
                <ActionButton
                  color={ACT_STOP}
                  hint="Stop this incident"
                  icon={Ban}
                  label="Cancel incident"
                  onClick={() => { setShowCancelModal(true); setActionError(null); }}
                />
              )}
              {canFlagSos && (
                <ActionButton
                  color={ACT_STOP}
                  hint="The SOS was misused"
                  icon={Flag}
                  label="Flag false SOS"
                  onClick={() => { setShowFlagModal(true); setActionError(null); }}
                />
              )}
            </div>
          ) : (
            <div className="grid w-full grid-cols-2 gap-2 sm:flex sm:w-auto sm:flex-1 sm:flex-wrap sm:items-center sm:gap-2.5">
              {/* No actions (a closed report, a Provincial Admin, or a record
                  opened from History) still needs a way in to the conversation,
                  or it could never be read. Only shown when there is one. */}
              {detail && hasThread && chatButton}
              {/* A resolved/cancelled incident has no crew left to send, and
                  History has no live poll behind it — either way, actions give
                  way to a plain "View on map" link. A Provincial Admin
                  (oversight only) gets the same link as their one next step. */}
              {detail && (isHistory || closed)
                ? mapLink(false)
                : isProvincialAdmin ? mapLink(true) : null}
            </div>
          )}
          <Button
            className="ml-auto h-10 w-full rounded-[11px] px-4 text-[13px] font-semibold sm:h-[38px] sm:w-auto"
            onClick={attemptClose}
            variant="outline"
          >
            Close
          </Button>
        </div>
      </DialogContent>

      {/* ── The conversation with the resident — stacked over this dialog ── */}
      {detail && (
        <IncidentChatModal
          canCompose={chatCanCompose}
          canRequestClarification={canReview}
          clarification={{
            status: detail.review_status,
            note: detail.clarification_note,
            requestedAt: detail.clarification_requested_at,
          }}
          incidentId={detail.id}
          onClarificationRequested={reload}
          onClose={() => setChatOpen(false)}
          open={chatOpen}
          recordNo={detail.record_number ?? `INC-${shortId}`}
          reporterName={detail.users?.full_name}
          thread={thread}
          token={token}
        />
      )}

      {/* ── Dispatch action modals — stacked over this dialog ─────────── */}
      {showDispatchModal && detail && token && (
        <DispatchModal
          incident={detail}
          initialResponderId={dispatchPreselect}
          onClose={() => { setShowDispatchModal(false); setDispatchPreselect(null); }}
          onError={setActionError}
          onSuccess={async msg => {
            setShowDispatchModal(false);
            setSuccessMsg(msg);
            await reload();
          }}
          token={token}
        />
      )}
      {showCancelModal && detail && token && (
        <CancelModal
          incidentId={detail.id}
          onClose={() => setShowCancelModal(false)}
          onError={setActionError}
          onSuccess={async () => {
            setShowCancelModal(false);
            setSuccessMsg('Incident cancelled.');
            await reload();
          }}
          token={token}
        />
      )}
      {showRejectModal && detail && token && (
        <RejectReportModal
          incidentId={detail.id}
          onClose={() => setShowRejectModal(false)}
          onError={setActionError}
          onSuccess={async () => {
            setShowRejectModal(false);
            setSuccessMsg('Report rejected.');
            await reload();
          }}
          token={token}
        />
      )}
      {showFlagModal && detail && token && (
        <FlagSosModal
          incidentId={detail.id}
          onClose={() => setShowFlagModal(false)}
          onError={setActionError}
          onSuccess={async () => {
            setShowFlagModal(false);
            setSuccessMsg('SOS flagged as false alarm. Reporter warning count updated.');
            await reload();
          }}
          token={token}
        />
      )}
      {showAssistDialog && detail && token && (
        <AssistRequestDialog
          incidentId={detail.id}
          onClose={() => setShowAssistDialog(false)}
          onError={setActionError}
          onSuccess={n => { setAssistVersion(v => v + 1); setSuccessMsg(n > 1 ? `Help requested from ${n} stations.` : 'Help requested. The station has been alerted.'); }}
          overlapFlags={detail.overlap_agencies ?? []}
          token={token}
          triggerRef={assistTriggerRef}
        />
      )}

      {/* ── Accept report confirm (shared with the other screen) ── */}
      <AcceptReportDialog
        dispatchable={dispatchable}
        incident={detail}
        loading={actionLoading}
        onCancel={() => setShowAcceptConfirm(false)}
        onConfirm={() => { void handleAccept(); }}
        open={showAcceptConfirm}
      />

      <AlertDialog
        onOpenChange={open => { if (!open && !actionLoading) setShowResolveConfirm(false); }}
        open={showResolveConfirm}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Mark this incident resolved?</AlertDialogTitle>
            <AlertDialogDescription>
              It moves out of the active queue and into history.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={actionLoading}>Back</AlertDialogCancel>
            <AlertDialogAction
              disabled={actionLoading}
              onClick={e => { e.preventDefault(); void handleResolve(); }}
            >
              Mark Resolved
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* See attemptClose — only reachable when this report is still open AND
          the alert tray has other reports waiting on this admin. */}
      <AlertDialog
        onOpenChange={open => { if (!open) setShowCloseConfirm(false); }}
        open={showCloseConfirm}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Close without finishing this report?</AlertDialogTitle>
            <AlertDialogDescription>
              This report hasn&apos;t been accepted, dispatched, or resolved
              yet, and {otherPendingCount === 1 ? '1 more report is' : `${otherPendingCount} more reports are`} still
              waiting to be dispatched.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep reviewing</AlertDialogCancel>
            <AlertDialogAction
              onClick={e => { e.preventDefault(); setShowCloseConfirm(false); onClose(); }}
            >
              Close anyway
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Dialog>
  );
}
