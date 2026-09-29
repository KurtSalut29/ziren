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
import { toast } from '@/lib/toast';
import { announceOpened } from '@/lib/incidents/arrivals';
import Link from 'next/link';
import {
  AlertTriangle, CalendarClock, Check, ClipboardCheck, Clock,
  Flag, Handshake, HelpCircle, Landmark, ListTree, MapPin, MessageSquare, Phone, Shield,
  ShieldCheck, ShieldX, Siren, Star, UserCheck, UserRound, Users, X,
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
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader,
  DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Button } from '@/components/efferd/ui/button';
import {
  CLOSED_STATUSES, durationBetween, statusLabel,
} from '@/components/incidents/incident-vocabulary';
import { Alert } from '@/components/ui/alert';
import { SeverityRationale } from '@/components/ui/severity-rationale';
import { IncidentFeedbackPanel } from '@/components/incidents/incident-feedback-panel';
import { IncidentVoiceNote } from '@/components/incidents/incident-voice-note';
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
import { ChatButtonBadge } from '@/components/incidents/chat-button-badge';
import { useIncidentThread } from '@/lib/hooks/useIncidentThread';
import {
  Answers, DetailSkeleton, MaskedContact, Normalisation, Row, Section,
} from '@/components/incidents/incident-detail-parts';
import { HotlineLinks } from '@/components/ui/hotline-links';

const SEV_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

/**
 * Tinted-outline treatment for the action bar's "asks a question" and "stops
 * something" buttons — redesigned 2026-09-23 ("mas professional... easy to
 * notice"). A bare `variant="outline"` (Cancel incident's old style) reads as
 * neutral chrome and got lost next to Accept/Dispatch's solid fills; a full
 * solid fill on every button would fight Accept/Dispatch for the eye's first
 * stop. A colour-tinted outline — background wash + matching border + matching
 * text, the same recipe the severity badge in the header already uses — sits
 * between the two: reads as a real, deliberate choice, not a lesser one.
 */
function tintedOutline(color: string): React.CSSProperties {
  return {
    color,
    borderColor: `color-mix(in srgb, ${color} 45%, transparent)`,
    backgroundColor: `color-mix(in srgb, ${color} 10%, transparent)`,
  };
}
const DANGER_STYLE = tintedOutline('var(--color-severity-critical)');
const ASK_STYLE = tintedOutline('var(--color-system-warning)');

/** Shared by every solid-fill action button (Accept, Dispatch, Mark
 * resolved) — a soft shadow plus a brightness lift on hover, so they read as
 * raised/pressable rather than flat colour blocks. */
const SOLID_ACTION_CLASS = 'shadow-[var(--shadow-sm)] transition-all hover:brightness-105 hover:shadow-[var(--shadow-md)]';

export function IncidentDetailModal({
  incidentId,
  onClose,
  isHistory = false,
  otherPendingCount = 0,
  fromAlert = false,
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
}) {
  const { token, isProvincialAdmin } = useAuth();

  useEffect(() => {
    if (incidentId) announceOpened({ id: incidentId, fromAlert });
  }, [incidentId, fromAlert]);
  // A Provincial Admin oversees every station of their agency_type and
  // dispatches for none of them — assignment belongs to the agency that
  // owns the incident. Their useful next step is spatial: see where this
  // sits relative to everything else.
  const [detail, setDetail] = useState<IncidentDetail | null>(null);
  const [loading, setLoading] = useState(false);
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
    <Button
      onClick={() => setChatOpen(true)}
      size="sm"
      style={ASK_STYLE}
      title={
        thread.unread > 0
          ? `${thread.unread} new ${thread.unread === 1 ? 'reply' : 'replies'} from the resident`
          : chatCanCompose ? 'Message the resident' : 'Read the messages on this report'
      }
      variant="outline"
    >
      <MessageSquare data-icon="inline-start" /> {chatCanCompose ? 'Chat' : 'Messages'}
      <ChatButtonBadge count={thread.unread} />
    </Button>
  );

  return (
    <Dialog onOpenChange={handleOpenChange} open={incidentId !== null}>
      {/* Two columns, and the width to hold them. The report is a reading
          column; the map beside it is the thing being decided. Stacking them
          — which is what a 720px dialog forced — put the response distance
          below the fold of a panel nobody scrolls to the bottom of, so the
          one fact that decides which crew goes was the one fact hidden.

          Position now follows otherPendingCount, not a fixed choice — asked
          for 2026-09-23: pinning LEFT (to leave room for the alert tray on
          the right, see incident-interrupt.tsx) only makes sense when there
          IS a tray to make room for. With nothing else waiting, the reserved
          strip was empty space for no reason, so this is CENTRED and full
          width instead — the original, tray-agnostic layout. `transition-*`
          animates between the two, so a report landing WHILE this is open
          (count going 0 -> 1+) visibly slides the dialog left and docks the
          tray beside it, rather than jumping. */}
      <DialogContent
        className={`flex max-h-[88vh] flex-col gap-0 overflow-hidden p-0 transition-[left,transform,max-width] duration-300 ease-out ${
          otherPendingCount > 0
            ? 'left-4 translate-x-0 sm:max-w-[min(1520px,calc(100vw_-_416px))]'
            : 'left-1/2 -translate-x-1/2 sm:max-w-[1520px]'
        }`}
      >
        {/* Below lg the two columns stack and THIS is the scroll container.
            At lg each column scrolls on its own, so a long report never
            drags the map off screen. */}
        <div className="scroll-slim grid min-h-0 flex-1 grid-cols-1 overflow-y-auto lg:grid-cols-[minmax(0,1fr)_minmax(0,1.02fr)] lg:overflow-hidden">
          {/* ── The report ─────────────────────────────────────────────── */}
          <div className="flex min-h-0 flex-col lg:border-r lg:border-[var(--color-surface-border)]">
            {/* shrink-0 on both header and footer. In a flex column with a
                max-height, a long body compresses its siblings — which is why
                the footer's buttons were rendering clipped at the dialog
                edge. */}
            <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] px-6 py-4 text-left">
              <div className="flex flex-wrap items-center gap-2">
                <span
                  className="rounded-[var(--radius-sm)] border px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide"
                  style={{
                    color: sevColor,
                    borderColor: `color-mix(in srgb, ${sevColor} 45%, transparent)`,
                    backgroundColor: `color-mix(in srgb, ${sevColor} 10%, transparent)`,
                  }}
                >
                  {sev ?? 'untriaged'}
                </span>
                {/* The record number — what gets quoted on a form or read out
                    over the radio. A backend that predates migration 035 has
                    none, so the short id stands in rather than "undefined". */}
                <span className="font-mono text-[12px] font-semibold text-foreground">
                  {detail?.record_number ?? `INC-${shortId}`}
                </span>
              </div>
              <DialogTitle className="mt-1 text-[17px] leading-snug">
                {detail
                  ? voiceText.kind === 'voice-untranscribed'
                    ? 'Voice report — no transcript'
                    : voiceText.text
                  : loading
                    ? 'Loading incident…'
                    : 'Incident'}
              </DialogTitle>
              {/* Required by Radix for the dialog's accessible description. It
                  is also the one line that dates the report. */}
              <DialogDescription>
                {detail
                  ? `Reported ${formatDateTime(detail.created_at, display)}`
                  : 'Full report detail'}
              </DialogDescription>
            </DialogHeader>

            {/* min-h-0 is what lets this shrink inside the flex column; without
                it a long report pushes the footer out of the clipped dialog. */}
            <div className="scroll-slim px-6 py-4 lg:min-h-0 lg:flex-1 lg:overflow-y-auto">
              {error && <Alert message={error} variant="error" />}

              {loading && !detail && <DetailSkeleton />}

              {detail && (
                <div className="flex flex-col gap-5">
                  {/* The modal is organised as the wizard is: the five Ws and the
                      H, in the order a dispatcher asks them out loud. Each section
                      draws from whichever fields answer that question, which is
                      why the wizard answers are split across three of them rather
                      than dumped in one block — a resident answering "Ilang
                      biktima?" is answering WHO, not HOW. */}

                  <Section facet="What" icon={ListTree} title="What happened">
                    <Row label="Category">
                      {detail.incident_category && detail.incident_category !== 'other'
                        ? CATEGORY_LABELS[detail.incident_category] ?? detail.incident_category
                        : 'Not chosen by the reporter'}
                    </Row>
                    <Row label="In their words">
                      {/* A voice report's stored text opens with the app's own
                          "<Category> — reported by voice recording —". That is
                          scaffolding, not their words, so it is dropped here;
                          the corrected reading below and the recording itself
                          are unchanged. A report typed by the resident is shown
                          exactly as stored. */}
                      {voiceText.kind === 'voice-untranscribed' ? (
                        <span className="text-muted-foreground">
                          No transcript — play the recording below.
                        </span>
                      ) : (
                        <span className="italic">
                          {withoutVoicePlaceholder(detail.report_text)}
                        </span>
                      )}
                      {/* "In their words" is only true of the text when the
                          transcription got it right. The recording always is. */}
                      <Normalisation
                        reportText={detail.report_text}
                        normalisation={detail.signals?.normalisation}
                      />
                      {view.showRecording && (
                        <IncidentVoiceNote
                          heardText={detail.signals?.transcript?.text}
                          incidentId={detail.id}
                          token={token}
                        />
                      )}
                    </Row>
                    {detail.overlap_agencies && detail.overlap_agencies.length > 0 && (
                      <Row label="Also present">
                        {detail.overlap_agencies
                          .map(f => OVERLAP_LABELS[f] ?? f)
                          .join(' · ')}
                      </Row>
                    )}
                    {!isProvincialAdmin && (
                      <Row icon={Handshake} label="Coordination">
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
                      </Row>
                    )}
                    {view.showWizardAnswers && <Answers items={facets.what} />}
                  </Section>

                  <Section facet="Who" icon={UserRound} title="Who is involved">
                    {detail.victim_relationship && (
                      <Row label="Victim is">
                        {VICTIM_RELATIONSHIP[detail.victim_relationship] ??
                          detail.victim_relationship}
                      </Row>
                    )}
                    {view.showWizardAnswers && <Answers items={facets.who} />}
                    {detail.users ? (
                      <>
                        <Row icon={UserRound} label="Reported by">
                          {detail.users.full_name}
                        </Row>
                        {detail.users.phone_number && (
                          <Row icon={Phone} label="Phone">
                            {/* A tel: link, because the dispatcher's next action
                                after reading this is often to ring the number. */}
                            <MaskedContact
                              key={detail.users.phone_number}
                              mask={privacy.maskContacts}
                              value={detail.users.phone_number}
                            />
                          </Row>
                        )}
                        <Row
                          icon={detail.users.is_verified ? ShieldCheck : ShieldX}
                          label="Verification"
                        >
                          <span
                            style={{
                              color: detail.users.is_verified
                                ? 'var(--color-system-success)'
                                : 'var(--color-system-warning)',
                            }}
                          >
                            {detail.users.is_verified
                              ? 'Verified resident'
                              : 'Unverified — identity not confirmed'}
                          </span>
                        </Row>
                        {detail.users.sos_warning_count > 0 && (
                          <Row icon={AlertTriangle} label="False SOS history">
                            <span style={{ color: 'var(--color-severity-critical)' }}>
                              {detail.users.sos_warning_count} prior false SOS
                              {detail.users.sos_suspended_until &&
                                ` · suspended until ${formatDate(detail.users.sos_suspended_until, display)}`}
                            </span>
                          </Row>
                        )}
                        {detail.users.emergency_contact_name && (
                          <Row label="Emergency contact">
                            {detail.users.emergency_contact_name}
                            {detail.users.emergency_contact_number && (
                              <>
                                {' · '}
                                <MaskedContact
                                  callable={false}
                                  key={detail.users.emergency_contact_number}
                                  mask={privacy.maskContacts}
                                  value={detail.users.emergency_contact_number}
                                />
                              </>
                            )}
                          </Row>
                        )}
                      </>
                    ) : (
                      <p className="text-[13px] text-muted-foreground">
                        No reporter record attached to this incident.
                      </p>
                    )}
                  </Section>

                  <Section facet="When" icon={CalendarClock} title="When it came in">
                    <Row icon={Clock} label="Reported">
                      {formatDateTime(detail.created_at, display)}
                    </Row>
                    <Row label="Dispatched">
                      {detail.dispatched_at
                        ? formatDateTime(detail.dispatched_at, display)
                        : 'Not yet dispatched'}
                      {/* Time to dispatch: the figure an after-action review is
                          actually looking for, beside the timestamp it comes
                          from. */}
                      {detail.dispatched_at && (
                        <span className="ml-2 font-mono text-[12px] tabular-nums text-muted-foreground">
                          after {durationBetween(detail.created_at, detail.dispatched_at)}
                        </span>
                      )}
                    </Row>
                    {/* Only when the crew actually answered. Absent, not "Not
                        accepted": an incident closed before acceptance was
                        recorded has no such moment, and saying so would state a
                        fact nobody knows. */}
                    {detail.accepted_at && (
                      <Row label="Accepted by crew">
                        {formatDateTime(detail.accepted_at, display)}
                      </Row>
                    )}
                    {CLOSED_STATUSES.includes(detail.status) && (
                      <Row label={detail.status === 'cancelled' ? 'Cancelled' : 'Resolved'}>
                        {detail.resolved_at ? (
                          <>
                            {formatDateTime(detail.resolved_at, display)}
                            <span className="ml-2 font-mono text-[12px] tabular-nums text-muted-foreground">
                              {durationBetween(detail.created_at, detail.resolved_at)} in total
                            </span>
                          </>
                        ) : (
                          'No closing time recorded'
                        )}
                      </Row>
                    )}
                  </Section>

                  {/* WHO IS NEAR. Responders on duty near a new report are told at the
                      same moment the agency is, without waiting to be dispatched; this
                      is where the dispatcher sees who they are, how far, and what each
                      is already on, before choosing. Only while nobody has been sent:
                      after that "Who responded" below is the record. Also shown for an
                      OPEN incident opened from Incident Records - a Provincial Admin
                      has no live queue, and that is where they meet one - where it is
                      read-only (canDispatch is false there). */}
                  {token && !detail.responder && !detail.assigned_responder_id
                    && ['received', 'processing'].includes(detail.status) && (
                    <Section facet="Response" icon={Users} title="Responders near this incident">
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

                  {/* WHO RESPONDED. The reporter is under "Who is involved"; this
                      is the other side — who the system sent. Shown only once a
                      responder was assigned, since "no responder" on an open
                      incident is the normal state, not a fact about the record. */}
                  {(detail.responder || detail.assigned_responder_id) && (
                    <Section facet="Response" icon={UserCheck} title="Who responded">
                      <Row label="Responder">
                        {detail.responder?.full_name ?? 'Account no longer exists'}
                        {detail.responder?.badge_id && (
                          <span className="ml-2 font-mono text-[12px] text-muted-foreground">
                            Badge {detail.responder.badge_id}
                          </span>
                        )}
                      </Row>
                      {detail.stations?.name && (
                        <Row label="Station">
                          {detail.stations.name}
                          {detail.stations.agencies?.agency_type && (
                            <span className="ml-2 text-muted-foreground">
                              {detail.stations.agencies.agency_type}
                              {detail.stations.agencies.municipality
                                ? ` · ${detail.stations.agencies.municipality}`
                                : ''}
                            </span>
                          )}
                        </Row>
                      )}
                      <Row label="Status">{statusLabel(detail.status)}</Row>
                    </Section>
                  )}

                  {/* WHAT THE CREW FOUND. Severity is what the rubric guessed
                      from a civilian's account; this is what was true. Recorded
                      by the crew when they close, so it exists on closed
                      incidents only — and on those closed before the field
                      existed it is blank, which is stated rather than hidden. */}
                  {CLOSED_STATUSES.includes(detail.status) && (
                    <Section facet="Result" icon={ClipboardCheck} title="Outcome">
                      {detail.outcome ? (
                        <Row label="What was found">{OUTCOME_LABEL[detail.outcome]}</Row>
                      ) : (
                        <p className="text-[13px] text-muted-foreground">
                          No outcome was recorded for this incident.
                        </p>
                      )}
                      {/* NULL and 0 mean different things and both are kept:
                          NULL is "not recorded", 0 is "counted, nobody hurt". */}
                      {typeof detail.casualties_injured === 'number' && (
                        <Row label="Injured">
                          <span className="font-mono tabular-nums">{detail.casualties_injured}</span>
                        </Row>
                      )}
                      {typeof detail.casualties_fatal === 'number' && (
                        <Row label="Fatalities">
                          <span
                            className="font-mono tabular-nums"
                            style={detail.casualties_fatal > 0 ? { color: 'var(--color-severity-critical)', fontWeight: 700 } : undefined}
                          >
                            {detail.casualties_fatal}
                          </span>
                        </Row>
                      )}
                      {typeof detail.casualties_transported === 'number' && (
                        <Row label="Transported">
                          <span className="font-mono tabular-nums">{detail.casualties_transported}</span>
                        </Row>
                      )}
                      {detail.outcome_notes && (
                        <Row label="Crew notes">{detail.outcome_notes}</Row>
                      )}
                    </Section>
                  )}

                  <Section facet="Where" icon={MapPin} title="Where it is">
                    {/* The resident placed this incident on the map because
                        they are not at it (a relative called them, say). The
                        address above the fold is the INCIDENT; this says the
                        caller is elsewhere, so the dispatcher calls back to
                        confirm instead of trusting either blindly. */}
                    {detail.reported_from_elsewhere && (
                      <ReportedFromElsewhere
                        incident={geoPoint(detail.location)}
                        reporter={geoPoint(detail.reporter_location ?? null)}
                        reporterAddress={detail.reporter_address ?? null}
                      />
                    )}
                    <Row icon={MapPin} label="Address">
                      {detail.location_address ?? 'No address resolved'}
                    </Row>
                    {/* Required on every report since 2026-09-30 — the name a
                        crew can actually find, so it is always shown. */}
                    {detail.landmark_note && (
                      <Row icon={Landmark} label="Landmark">{detail.landmark_note}</Row>
                    )}
                    {/* Coordinates are exact; the address is a NAME derived from
                        them, and naming is the part that fails — OpenStreetMap
                        covers Biliran thinly. When the two disagree, these win,
                        so they are shown rather than hidden behind the address. */}
                    {view.showLocationDetail && detail.location?.coordinates && (
                      <Row label="Coordinates">
                        <span className="font-mono tabular-nums">
                          {formatCoordinates(
                            detail.location.coordinates[1],
                            detail.location.coordinates[0],
                            geo,
                          )}
                        </span>
                      </Row>
                    )}
                    {/* The station's NAME is not repeated here. The panel
                        beside this one states it, measures the distance to it
                        and reports whether anyone there is on duty — three
                        facts a bare name cannot carry, in the place a
                        dispatcher is already looking. The number below stays,
                        because ringing the station is an action and actions
                        belong next to the other ones. */}
                    {detail.stations?.agencies?.contact_number && (
                      <Row icon={Phone} label="Station contact">
                        <HotlineLinks className="underline-offset-2" value={detail.stations.agencies.contact_number} />
                      </Row>
                    )}
                  </Section>

                  <Section facet="How" icon={HelpCircle} title="How it is unfolding">
                    {detail.sos_flagged && (
                      <Row icon={Siren} label="Filed via">
                        <span style={{ color: 'var(--color-severity-critical)' }}>
                          The SOS button
                        </span>
                      </Row>
                    )}
                    {!view.showWizardAnswers ? null : facets.how.length === 0 && !detail.sos_flagged ? (
                      <p className="text-[13px] text-muted-foreground">
                        The reporter did not answer the circumstance questions.
                      </p>
                    ) : (
                      <Answers items={facets.how} />
                    )}
                  </Section>

                  {/* WHY, last. The wizard never asks a resident what CAUSED the
                      emergency — nobody in one can answer that reliably — so the
                      only "why" this system holds is why it ranked the report the
                      way it did, which is the one a dispatcher can act on and the
                      one a panel will ask about. SeverityRationale draws its own
                      titled panel, so it is not wrapped in a Section. */}
                  {view.showAiSuggestion && <SeverityRationale severity={sev} signals={detail.signals} />}

                  <Section facet="Log" icon={Clock} title="Activity">
                    {detail.dispatch_log.length === 0 ? (
                      <p className="text-[13px] text-muted-foreground">
                        Nothing logged yet — this report has not been acted on.
                      </p>
                    ) : (
                      <ol className="flex flex-col gap-2.5">
                        {detail.dispatch_log.map(entry => (
                          <li className="flex gap-2.5 text-[13px]" key={entry.id}>
                            <Clock
                              className="mt-0.5 shrink-0 text-muted-foreground"
                              size={13}
                            />
                            <div className="min-w-0">
                              <p className="text-foreground">
                                <span className="font-medium">{entry.action}</span>
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
                  </Section>

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
                </div>
              )}
            </div>
          </div>

          {/* ── Where it is, and how far help has to come ───────────────── */}
          <div className="flex min-h-0 flex-col border-t border-[var(--color-surface-border)] px-6 py-4 lg:border-t-0">
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

        {/* Full-width strip, spanning both columns, docked at the bottom of
            the dialog right above Close — the place a person looks once
            they've actually finished reading the report AND the distance
            panel beside it and are ready to decide, not before. Its own
            background/border pull it visually apart from everything above.
            Colour carries the decision at a glance: green moves the report
            forward, red stops or refuses it, amber asks the reporter
            something, brand orange is "send help now" — Dispatch is this
            whole panel's one primary CTA, so it gets the same colour every
            other CTA on the console does. A divider then separates "what to
            do with the report" from "stop this incident". */}
        {actionBarVisible && (
          <div
            className="shrink-0 border-t px-6 py-3"
            style={{
              borderColor: 'var(--color-surface-border)',
              backgroundColor: 'var(--color-surface-raised)',
            }}
          >
            <p className="mb-2 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
              What do you want to do with this report?
            </p>
            <div className="flex flex-wrap items-center gap-2">
              {canReview && (
                <>
                  <Button
                    className={SOLID_ACTION_CLASS}
                    onClick={() => setShowAcceptConfirm(true)}
                    size="sm"
                    style={{
                      backgroundColor: 'var(--color-system-success)',
                      color: 'var(--color-on-success)',
                    }}
                  >
                    <Check data-icon="inline-start" /> Accept
                  </Button>
                  {chatButton}
                  <Button
                    onClick={() => { setShowRejectModal(true); setActionError(null); }}
                    size="sm"
                    style={DANGER_STYLE}
                    variant="outline"
                  >
                    <X data-icon="inline-start" /> Reject
                  </Button>
                </>
              )}
              {canDispatch && (
                <Button
                  className={SOLID_ACTION_CLASS}
                  onClick={() => { setShowDispatchModal(true); setActionError(null); }}
                  size="sm"
                  style={{
                    backgroundColor: 'var(--color-brand)',
                    color: 'var(--color-text-inverse)',
                  }}
                >
                  <Shield data-icon="inline-start" /> Dispatch
                </Button>
              )}
              {canResolve && (
                <Button
                  className={SOLID_ACTION_CLASS}
                  onClick={() => setShowResolveConfirm(true)}
                  size="sm"
                  style={{
                    backgroundColor: 'var(--color-system-success)',
                    color: 'var(--color-on-success)',
                  }}
                >
                  <Check data-icon="inline-start" /> Mark resolved
                </Button>
              )}
              {/* Chat stays reachable once the report is decided: in the
                  review group above while it is undecided, here after that. */}
              {!canReview && chatButton}
              {(canReview || canDispatch || canResolve) && (canCancel || canFlagSos) && (
                <span
                  aria-hidden
                  className="mx-1 h-5 w-px shrink-0"
                  style={{ backgroundColor: 'var(--color-surface-border)' }}
                />
              )}
              {canCancel && (
                <Button
                  onClick={() => { setShowCancelModal(true); setActionError(null); }}
                  size="sm"
                  style={DANGER_STYLE}
                  variant="outline"
                >
                  <X data-icon="inline-start" /> Cancel incident
                </Button>
              )}
              {canFlagSos && (
                <Button
                  onClick={() => { setShowFlagModal(true); setActionError(null); }}
                  size="sm"
                  style={DANGER_STYLE}
                  variant="outline"
                >
                  <Flag data-icon="inline-start" /> Flag false SOS
                </Button>
              )}
            </div>
          </div>
        )}

        {/* mb-0 is load-bearing. shadcn's DialogFooter ships a NEGATIVE bottom
            margin sized to cancel the container's default p-4/gap-4. This
            dialog sets p-0 and gap-0 so it can own its own spacing, which left
            that -16px uncompensated: the footer hung 16px past the content box
            and overflow-hidden clipped it — taking the bottom 4px of the
            buttons with it. */}
        <DialogFooter className="mb-0 shrink-0 border-t border-[var(--color-surface-border)] px-6 py-3">
          <div className="flex gap-2">
            <Button onClick={attemptClose} size="sm" variant="outline">
              Close
            </Button>
            {/* No action bar (a closed report, a Provincial Admin, or a record
                opened from History) still needs a way in to the conversation,
                or it could never be read. Only shown when there is one. */}
            {detail && !actionBarVisible && hasThread && chatButton}
            {/* Same rule as the History card this modal opens from: a
                resolved/cancelled incident has no crew left to send, and
                History itself has no live poll behind it — either way,
                actions give way to a plain, read-only "View on map" link.
                Otherwise nothing extra belongs here — Accept/Dispatch/
                Resolve/Cancel/Flag all live in the action bar above the
                report now, so a Provincial Admin (oversight only, no actions
                of their own) is the only remaining case that needs a footer
                button. */}
            {detail && (isHistory || CLOSED_STATUSES.includes(detail.status)) ? (
              <Button asChild size="sm" variant="outline">
                <Link href={incidentId ? `/map?incident=${incidentId}` : '/map'}>
                  <MapPin data-icon="inline-start" />
                  View on map
                </Link>
              </Button>
            ) : isProvincialAdmin ? (
              <Button
                asChild
                size="sm"
                style={{
                  backgroundColor: 'var(--color-brand)',
                  color: 'var(--color-text-inverse)',
                }}
              >
                <Link href={incidentId ? `/map?incident=${incidentId}` : '/map'}>
                  <MapPin data-icon="inline-start" />
                  View on map
                </Link>
              </Button>
            ) : null}
          </div>
        </DialogFooter>
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

      {/* ── Accept / Resolve confirm — same copy as page.tsx's ─────────── */}
      <AlertDialog
        onOpenChange={open => { if (!open && !actionLoading) setShowAcceptConfirm(false); }}
        open={showAcceptConfirm}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Accept this report?</AlertDialogTitle>
            <AlertDialogDescription>
              You won&apos;t be able to Reject or Request Clarification after this.
              {/* dispatchable, not canDispatch — canDispatch now also requires
                  review_status === 'accepted', which is only true AFTER this
                  very confirmation goes through, so it always reads false here. */}
              {dispatchable && ' Dispatch becomes available after this.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={actionLoading}>Back</AlertDialogCancel>
            <AlertDialogAction
              disabled={actionLoading}
              onClick={e => { e.preventDefault(); void handleAccept(); }}
            >
              Accept Report
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

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
