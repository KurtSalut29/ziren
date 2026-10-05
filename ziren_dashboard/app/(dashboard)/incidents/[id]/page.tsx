'use client';

import { use, useCallback, useEffect, useState } from 'react';
import { AcceptReportDialog } from '@/components/incidents/accept-report-dialog';
import { toast } from '@/lib/toast';
import { useRouter } from 'next/navigation';
import {
  AlertTriangle, ArrowLeft, Building2, Check, Crosshair,
  Eye, Flag, MapPin, MessageSquare, Phone, Shield, Siren, Sparkles, UserCheck, X,
} from 'lucide-react';
import {
  fetchIncidentDetail, resolveIncident, acceptReport,
  type IncidentDetail, type SeverityLevel,
} from '@/lib/api/dispatch';
import { ApiError } from '@/lib/api/client';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { Button } from '@/components/ui/button';
import { Alert } from '@/components/ui/alert';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { SeverityRationale } from '@/components/ui/severity-rationale';
import { IncidentVoiceNote } from '@/components/incidents/incident-voice-note';
import { IncidentAttachments } from '@/components/incidents/incident-attachments';
import { IncidentChatModal } from '@/components/incidents/incident-chat-modal';
import { ChatButtonBadge } from '@/components/incidents/chat-button-badge';
import { useIncidentThread } from '@/lib/hooks/useIncidentThread';
import { IncidentLocationPanel } from '@/components/incidents/incident-location-panel';
import { NearbyResponders } from '@/components/incidents/nearby-responders';
import { geoPoint } from '@/lib/incidents/response-route';
import { severityKey } from '@/components/map/map-legend';
// The five dispatch-decision modals live here now, not in this file — see
// that module's docstring for why a page.tsx cannot export them itself.
import {
  CancelModal, DispatchModal, FlagSosModal, RejectReportModal,
} from '@/components/incidents/dispatch-action-modals';

export default function IncidentDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { token, isProvincialAdmin } = useAuth();
  const router = useRouter();

  const [incident, setIncident] = useState<IncidentDetail | null>(null);
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState<string | null>(null);
  // Raised as toasts, not drawn in the page: an <Alert> at the top of a scrolling
  // panel is out of sight when the button that caused it is at the bottom.
  const setActionError = useCallback((msg: string | null) => { if (msg) toast.error(msg); }, []);
  const [actionLoading, setActionLoading] = useState(false);
  const setSuccessMsg = useCallback((msg: string | null) => { if (msg) toast.success(msg); }, []);

  // The conversation with the resident is its own window (see
  // IncidentChatModal), and the thread is owned here so it keeps loading, and
  // can badge the Chat button, while the window is closed.
  const [chatOpen, setChatOpen] = useState(false);
  const thread = useIncidentThread({ incidentId: id, token, chatOpen });

  // Dispatch modal state
  const [showDispatchModal, setShowDispatchModal] = useState(false);
  const [dispatchPreselect, setDispatchPreselect] = useState<string | null>(null);
  const [showCancelModal, setShowCancelModal]     = useState(false);
  const [showFlagModal, setShowFlagModal]         = useState(false);
  const [showRejectModal, setShowRejectModal]     = useState(false);
  // Both are high-impact one-way gates: accepting forecloses Reject/Clarify
  // (see canReview below), and resolving takes the incident out of the
  // active queue. Neither had a confirmation step before.
  const [showAcceptConfirm, setShowAcceptConfirm]   = useState(false);
  const [showResolveConfirm, setShowResolveConfirm] = useState(false);

  // `silent` re-reads without swapping the whole page for the spinner - what
  // the chat window needs after a message, or it would close under the writer.
  const load = useCallback(async (silent = false) => {
    if (!token) return;
    if (!silent) setLoading(true);
    setError(null);
    try {
      const data = await fetchIncidentDetail(id, token);
      setIncident(data);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load incident.');
    } finally {
      setLoading(false);
    }
  }, [id, token]);

  useEffect(() => { load(); }, [load]);

  async function handleResolve() {
    if (!token || !incident) return;
    setShowResolveConfirm(false);
    setActionLoading(true); setActionError(null);
    try {
      await resolveIncident(incident.id, null, token);
      setSuccessMsg('Incident resolved.');
      await load();
    } catch (e: unknown) {
      setActionError(e instanceof Error ? e.message : 'Action failed.');
    } finally { setActionLoading(false); }
  }

  async function handleAccept() {
    if (!token || !incident) return;
    setShowAcceptConfirm(false);
    setActionLoading(true); setActionError(null);
    try {
      await acceptReport(incident.id, token);
      setSuccessMsg('Report accepted — ready to assign a responder.');
      await load();
    } catch (e: unknown) {
      setActionError(e instanceof Error ? e.message : 'Action failed.');
    } finally { setActionLoading(false); }
  }

  if (loading) return <_Loading />;
  if (error || !incident) return <_Error message={error ?? 'Incident not found.'} onBack={() => router.back()} />;

  const sev = (incident.suggested_severity ?? incident.severity) as SeverityLevel | null;
  const sevColor = _severityColor(sev);
  const agencyType = incident.stations?.agencies?.agency_type ?? '?';
  const agencyColor = _agencyColor(agencyType);
  // A Provincial Admin oversees every station of their agency_type and
  // belongs to none of them, so they have no responders to send and no
  // agency to commit. /dispatch enforces this — the four dispatch decisions
  // are agency_admin only — and the UI has to agree, or the console offers
  // buttons the server answers with 403. The queue list already made this
  // swap; this page did not, so a Provincial Admin who opened an incident
  // still saw a full dispatch console.

  // Verification step (Agency Admin spec Section 3). Undecided means still
  // 'pending', or a clarification was asked and the agency has not yet
  // ruled either way — both states can still move to Accepted or Rejected.
  const reviewStatus = incident.review_status ?? 'pending';
  const reviewUndecided = reviewStatus === 'pending' || reviewStatus === 'clarification_requested';

  const dispatchable = incident.status === 'received' || incident.status === 'processing';
  // reviewStatus === 'accepted' is required here, not just dispatchable status
  // — see the identical note in incident-detail-modal.tsx. Before this, a
  // brand-new report (status 'received', review_status 'pending') showed
  // Dispatch right next to Accept/Reject, even though Accept's own message
  // has always promised dispatch only becomes available once accepted.
  const canDispatch = !isProvincialAdmin && dispatchable && reviewStatus === 'accepted';
  const canResolve  = !isProvincialAdmin && ['dispatched', 'en_route', 'arrived'].includes(incident.status);
  const open        = !['resolved', 'cancelled'].includes(incident.status);
  const canCancel   = !isProvincialAdmin && open;
  // Not a dispatch decision: flagging acts on the REPORTER's account, not on
  // an agency's response, so it stays with platform oversight too.
  const canFlagSos  = open && incident.sos_flagged;
  const canReview = !isProvincialAdmin && reviewUndecided && open;

  // Chat is for the agency handling the report; a Provincial Admin reads the
  // same window without a box to type in.
  const chatCanCompose = !isProvincialAdmin;
  const hasThread =
    (thread.notes?.length ?? 0) > 0 || Boolean(incident.clarification_requested_at);
  const chatButton = (
    <Button
      variant="ghost"
      size="md"
      onClick={() => setChatOpen(true)}
      title={
        thread.unread > 0
          ? `${thread.unread} new ${thread.unread === 1 ? 'reply' : 'replies'} from the resident`
          : chatCanCompose ? 'Message the resident' : 'Read the messages on this report'
      }
    >
      <MessageSquare className="h-4 w-4 mr-1.5" /> {chatCanCompose ? 'Chat' : 'Messages'}
      <ChatButtonBadge count={thread.unread} />
    </Button>
  );

  return (
    <div className="p-6 max-w-5xl">
      {/* ── Back ─────────────────────────────────────────── */}
      <button
        onClick={() => router.back()}
        className="flex items-center gap-2 text-body-sm text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)] mb-5 transition-colors"
      >
        <ArrowLeft className="h-4 w-4" /> Back to queue
      </button>

      {/* ── Success / action error ────────────────────────── */}

      {/* ── Header card ──────────────────────────────────── */}
      <div className="bg-[var(--color-surface-card)] rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] overflow-hidden mb-5">
        <div className="h-2" style={{ backgroundColor: sevColor }} />
        <div className="p-5">
          <div className="flex items-start justify-between gap-4 flex-wrap">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-[13px] font-bold" style={{ color: agencyColor }}>{agencyType}</span>
              <span className="text-[13px] text-[var(--color-text-muted)]">·</span>
              <span className="text-[13px] font-bold uppercase tracking-wide" style={{ color: sevColor }}>
                {sev ?? 'pending'}
              </span>
              {incident.suggested_severity && !incident.severity && (
                <span className="badge-ai ml-1 inline-flex items-center gap-1">
                  <Sparkles size={11} strokeWidth={2} />
                  AI: {incident.suggested_severity}
                </span>
              )}
              {incident.sos_flagged && (
                <span title="SOS report" style={{ color: 'var(--color-severity-critical)' }}>
                  <Siren size={13} strokeWidth={2} />
                </span>
              )}
              {incident.nlp_review_needed && (
                <span title="Needs NLP review" style={{ color: 'var(--color-ai-suggested)' }}>
                  <Eye size={13} strokeWidth={2} />
                </span>
              )}
              <span className="ml-1"><_StatusPill status={incident.status} /></span>
            </div>
            <p className="text-body-sm text-[var(--color-text-muted)]">
              INC-{incident.id.replace(/-/g, '').toUpperCase().slice(-6)}
              {' · '}
              {new Date(incident.created_at).toLocaleString()}
            </p>
          </div>

          <p className="text-body-lg font-medium text-[var(--color-text-primary)] mt-4 leading-relaxed">
            {incident.report_text}
          </p>

          {/* Directly under the text on purpose: when the transcript and the
              recording disagree, the dispatcher should not have to go looking
              for the recording to find that out. */}
          <IncidentVoiceNote
            heardText={incident.signals?.transcript?.text}
            incidentId={incident.id}
            token={token}
          />
          <IncidentAttachments incidentId={incident.id} token={token} />

          {reviewStatus === 'rejected' && incident.rejection_reason && (
            <div className="mt-4 flex items-start gap-2.5 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3.5 py-3">
              <X className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-severity-critical)' }} />
              <div>
                <p className="text-[12.5px] font-semibold text-[var(--color-text-primary)]">Report rejected</p>
                <p className="text-[12.5px] text-[var(--color-text-secondary)]">{incident.rejection_reason}</p>
              </div>
            </div>
          )}

          {/* Action buttons */}
          <div className="flex flex-wrap items-center gap-3 mt-5">
            {canReview && (
              <>
                <Button variant="primary" size="md" onClick={() => setShowAcceptConfirm(true)} isLoading={actionLoading}>
                  <Check className="h-4 w-4 mr-1.5" /> Accept Report
                </Button>
                {chatButton}
                <Button
                  variant="danger"
                  size="md"
                  onClick={() => { setShowRejectModal(true); setActionError(null); }}
                >
                  <X className="h-4 w-4 mr-1.5" /> Reject
                </Button>
              </>
            )}
            {canDispatch && (
              <Button
                // Outline while Verification is still undecided, so "Accept
                // Report" reads as the one recommended next step rather than
                // two equally-loud orange buttons competing for attention.
                // Dispatching directly still works — some reports (an
                // obvious critical fire) don't need a separate Accept click
                // first, see assign_responder's implicit-accept behavior —
                // it just isn't the button a dispatcher's eye lands on.
                variant={canReview ? 'outline' : 'primary'}
                size="md"
                onClick={() => { setShowDispatchModal(true); setActionError(null); }}
                isLoading={actionLoading}
              >
                <Shield className="h-4 w-4 mr-1.5" /> Dispatch Responder
              </Button>
            )}
            {canResolve && (
              <Button
                variant="outline"
                size="md"
                onClick={() => setShowResolveConfirm(true)}
                isLoading={actionLoading}
              >
                <Check className="h-4 w-4 mr-1.5" /> Mark Resolved
              </Button>
            )}
            {/* Chat stays reachable once the report is decided: in the review
                group above while it is undecided, here after that. Read-only
                for a Provincial Admin, and only when there is something to read. */}
            {!canReview && (chatCanCompose || hasThread) && chatButton}
            {canCancel && (
              <Button
                variant="ghost"
                size="md"
                onClick={() => { setShowCancelModal(true); setActionError(null); }}
              >
                <X className="h-4 w-4 mr-1.5" /> Cancel Incident
              </Button>
            )}
            {canFlagSos && (
              <Button
                variant="danger"
                size="md"
                onClick={() => { setShowFlagModal(true); setActionError(null); }}
              >
                <Flag className="h-4 w-4 mr-1.5" /> Flag False SOS
              </Button>
            )}

            {/* Said out loud rather than left as an absence. A console with no
                buttons reads as broken or as "still loading" — and a Super
                Admin watching a critical incident needs to know instantly that
                somebody else has to move it, not wonder why Dispatch is
                missing. */}
            {isProvincialAdmin && dispatchable && (
              <div className="flex items-center gap-2 text-[13px] text-[var(--color-text-muted)]">
                <Eye className="h-4 w-4 shrink-0" />
                <span>
                  Oversight view — dispatch belongs to
                  {' '}
                  <strong className="text-[var(--color-text-secondary)]">
                    {incident.stations?.agencies?.name ?? 'the assigned agency'}
                  </strong>
                  . You can see every incident; only their admins can send a responder.
                </span>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* ── Two-column body ──────────────────────────────── */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
        {/* Left: incident details */}
        <div className="space-y-5">
          {/* First card in the column on purpose. Before a dispatcher reads
              where the incident is or who reported it, they should see why the
              system ranked it where it did — and be able to disagree with a
              named rule rather than with an opaque severity word. */}
          <SeverityRationale signals={incident.signals} severity={sev} />

          <_DetailCard title="LOCATION">
            {incident.location_address && (
              <_InfoRow icon={<MapPin className="h-4 w-4" />} label="Address" value={incident.location_address} />
            )}
            {incident.landmark_note && (
              <_InfoRow icon={<MapPin className="h-4 w-4" />} label="Landmark" value={incident.landmark_note} />
            )}
            {/* The exact figures, and a way out to a real map.

                The address above is a NAME derived from these, and naming is
                the part that goes wrong: OpenStreetMap covers Biliran thinly,
                so a barangay can be missing entirely and the nearest mapped
                name answers in its place. One report from Talustusan was
                filed as a barangay 1.66 km away.

                The coordinates have no such failure mode. When the name looks
                wrong, this is what a dispatcher should act on — so it is on
                the card, not buried in an API response. */}
            <_Coordinates location={incident.location} />
          </_DetailCard>

          {incident.wizard_answers && Object.keys(incident.wizard_answers).length > 0 && (
            <_DetailCard title="5W1H WIZARD ANSWERS">
              {Object.entries(incident.wizard_answers)
                .filter(([k]) => k !== 'catch_all')
                .map(([k, v]) => (
                  <_InfoRow key={k} label={k.replace(/_/g, ' ')} value={String(v)} />
                ))}
              {!!incident.wizard_answers['catch_all'] && (
                <_InfoRow label="Additional details" value={String(incident.wizard_answers['catch_all'])} />
              )}
            </_DetailCard>
          )}

          {incident.overlap_agencies && incident.overlap_agencies.length > 0 && (
            <_MultiAgencyPanel overlaps={incident.overlap_agencies} primaryAgency={agencyType} />
          )}
        </div>

        {/* Right: the map, then reporter + station + dispatch log */}
        <div className="space-y-5">
          {/* The modal's "Location & response distance" panel, ported over so
              the full page answers the same question the modal does: not just
              where the incident is, but how far the responding crew has to
              come and by what road. First in this column, matching where the
              modal puts it — the modal is two columns, report on the left and
              this panel as the whole of the right, so a dispatcher who has
              opened both sees it in the same place both times rather than
              having to scroll for it here specifically. Its own bordered
              card, not wrapped in _DetailCard — the panel already draws its
              own heading, and nesting it inside another titled card would
              print "Location & response distance" under a second, redundant
              label.

              flex flex-col + a real min-height on THIS wrapper, not just on
              the panel's own inner map div — IncidentLocationPanel's map
              wrapper asks to be `lg:flex-1` inside a flex column, which is
              exactly what the modal's fixed-height dialog gives it for free.
              A plain page has no such ancestor: with nothing above it
              establishing a real height, flex-grow has no space to grow
              into, and the browser resolves it to 0 — the map rendered into
              a real-width, zero-height box and never painted a tile. Giving
              this wrapper both `flex flex-col` and an explicit height
              restores the same context the dialog was providing implicitly. */}
          <div
            className="bg-[var(--color-surface-card)] rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] p-4 flex flex-col"
            style={{ minHeight: 420 }}
          >
            <IncidentLocationPanel detail={incident} severity={severityKey(sev)} />
          </div>

          {incident.users && (
            <_DetailCard title="REPORTER">
              <_InfoRow icon={<UserCheck className="h-4 w-4" />} label="Name" value={incident.users.full_name} />
              {incident.users.phone_number && (
                <_InfoRow icon={<Phone className="h-4 w-4" />} label="Phone" value={incident.users.phone_number} />
              )}
              {incident.users.emergency_contact_name && (
                <_InfoRow label="Emergency Contact" value={`${incident.users.emergency_contact_name} ${incident.users.emergency_contact_number ?? ''}`} />
              )}
              <div className="flex flex-wrap items-center gap-x-4 gap-y-1 mt-2 text-[11.5px] font-semibold">
                <span className="flex items-center gap-1.5"
                  style={{ color: incident.users.is_verified ? 'var(--color-system-success)' : 'var(--color-text-muted)' }}>
                  {incident.users.is_verified ? <Check size={12} strokeWidth={2.5} /> : <AlertTriangle size={12} strokeWidth={2} />}
                  {incident.users.is_verified ? 'Verified reporter' : 'Unverified reporter'}
                </span>
                {incident.users.sos_warning_count > 0 && (
                  <span className="flex items-center gap-1.5" style={{ color: 'var(--color-severity-critical)' }}>
                    <AlertTriangle size={12} strokeWidth={2} />
                    {incident.users.sos_warning_count} prior false SOS
                  </span>
                )}
              </div>
            </_DetailCard>
          )}

          {token && !incident.assigned_responder_id
            && ['received', 'processing'].includes(incident.status) && (
            <_DetailCard title="RESPONDERS NEAR THIS INCIDENT">
              <NearbyResponders
                active
                incidentId={incident.id}
                initial={incident.nearby ?? null}
                onDispatch={canDispatch ? (id) => {
                  setDispatchPreselect(id);
                  setShowDispatchModal(true);
                  setActionError(null);
                } : undefined}
                scene={geoPoint(incident.location)}
                token={token}
              />
            </_DetailCard>
          )}

          {incident.stations && (
            <_DetailCard title="STATION">
              <_InfoRow label="Station" value={incident.stations.name} />
              {typeof incident.station_distance_km === 'number' && (
                <_InfoRow
                  label="From the report"
                  value={`${incident.station_distance_km.toFixed(1)} km in a straight line`}
                />
              )}
              {incident.stations.address && (
                <_InfoRow label="Address" value={incident.stations.address} />
              )}
              {incident.stations.agencies?.contact_number && (
                <_InfoRow icon={<Phone className="h-4 w-4" />} label="Contact" value={incident.stations.agencies.contact_number} />
              )}
            </_DetailCard>
          )}

          {incident.dispatch_log && incident.dispatch_log.length > 0 && (
            <_DetailCard title="DISPATCH HISTORY">
              <div className="space-y-3">
                {incident.dispatch_log.map(entry => (
                  <div key={entry.id} className="text-body-sm border-l-2 border-[var(--color-surface-border)] pl-3">
                    <div className="flex items-center justify-between">
                      <span className="font-semibold text-[var(--color-text-primary)]">
                        {entry.action.toUpperCase()}
                      </span>
                      <span className="text-[var(--color-text-muted)]">
                        {new Date(entry.created_at).toLocaleString()}
                      </span>
                    </div>
                    <p className="text-[var(--color-text-secondary)]">
                      Severity: {entry.chosen_severity}
                      {entry.was_override && (
                        <span className="text-[var(--color-system-warning)] ml-2">
                          (override from {entry.suggested_severity ?? '?'})
                        </span>
                      )}
                    </p>
                    {entry.override_reason && (
                      <p className="text-[var(--color-text-muted)] italic">&ldquo;{entry.override_reason}&rdquo;</p>
                    )}
                    {entry.users && (
                      <p className="text-[var(--color-text-muted)]">by {entry.users.full_name}</p>
                    )}
                  </div>
                ))}
              </div>
            </_DetailCard>
          )}

        </div>
      </div>

      {/* ── The conversation with the resident ───────────── */}
      <IncidentChatModal
        canCompose={chatCanCompose}
        canRequestClarification={canReview}
        clarification={{
          status: incident.review_status,
          note: incident.clarification_note,
          requestedAt: incident.clarification_requested_at,
        }}
        incidentId={incident.id}
        onClarificationRequested={() => { void load(true); }}
        onClose={() => setChatOpen(false)}
        open={chatOpen}
        recordNo={incident.record_number}
        reporterName={incident.users?.full_name}
        thread={thread}
        token={token}
      />

      {/* ── Dispatch modal ───────────────────────────────── */}
      {showDispatchModal && incident && (
        <DispatchModal
          incident={incident}
          initialResponderId={dispatchPreselect}
          token={token!}
          onClose={() => { setShowDispatchModal(false); setDispatchPreselect(null); }}
          onSuccess={async (msg) => {
            setShowDispatchModal(false);
            setSuccessMsg(msg);
            await load();
          }}
          onError={setActionError}
        />
      )}

      {/* ── Cancel modal ─────────────────────────────────── */}
      {showCancelModal && incident && (
        <CancelModal
          token={token!}
          incidentId={incident.id}
          onClose={() => setShowCancelModal(false)}
          onSuccess={async () => {
            setShowCancelModal(false);
            setSuccessMsg('Incident cancelled.');
            await load();
          }}
          onError={setActionError}
        />
      )}

      {/* ── Reject report modal ──────────────────────────── */}
      {showRejectModal && incident && (
        <RejectReportModal
          token={token!}
          incidentId={incident.id}
          onClose={() => setShowRejectModal(false)}
          onSuccess={async () => {
            setShowRejectModal(false);
            setSuccessMsg('Report rejected.');
            await load();
          }}
          onError={setActionError}
        />
      )}

      {/* ── Flag false SOS modal ──────────────────────────── */}
      {showFlagModal && incident && (
        <FlagSosModal
          token={token!}
          incidentId={incident.id}
          onClose={() => setShowFlagModal(false)}
          onSuccess={async () => {
            setShowFlagModal(false);
            setSuccessMsg('SOS flagged as false alarm. Reporter warning count updated.');
            await load();
          }}
          onError={setActionError}
        />
      )}

      {/* ── Accept report confirm ─────────────────────────── */}
      <AcceptReportDialog
        dispatchable={dispatchable}
        incident={incident}
        loading={actionLoading}
        onCancel={() => setShowAcceptConfirm(false)}
        onConfirm={() => { void handleAccept(); }}
        open={showAcceptConfirm}
      />

      {/* ── Resolve confirm ────────────────────────────────── */}
      <AlertDialog
        open={showResolveConfirm}
        onOpenChange={open => { if (!open && !actionLoading) setShowResolveConfirm(false); }}
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
    </div>
  );
}

// ── Shared components ─────────────────────────────────────────

function _DetailCard({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-[var(--color-surface-card)] rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] p-4">
      <p className="text-label-sm text-[var(--color-text-muted)] mb-3">{title}</p>
      <div className="space-y-2">{children}</div>
    </div>
  );
}

/** Exact position, monospaced so digits line up, with a link to open it.
 *
 *  GeoJSON orders coordinates [lon, lat]; every map link wants lat,lon. That
 *  reversal is the classic way to put a fire truck in the Indian Ocean, so it
 *  is done once, here. */
function _Coordinates({ location }: { location: IncidentDetail['location'] }) {
  const coords = location?.coordinates;
  if (!coords || coords.length < 2) return null;
  const [lon, lat] = coords;
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null;

  const pair = `${lat.toFixed(6)}, ${lon.toFixed(6)}`;
  return (
    <div className="flex items-start gap-2">
      <span className="text-[var(--color-text-muted)] mt-0.5 shrink-0">
        <Crosshair className="h-4 w-4" />
      </span>
      <div>
        <p className="text-[11px] text-[var(--color-text-muted)]">Coordinates</p>
        <p className="text-body font-medium font-mono text-[var(--color-text-primary)]">{pair}</p>
        <a
          href={`https://www.openstreetmap.org/?mlat=${lat}&mlon=${lon}#map=17/${lat}/${lon}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-[11px] underline text-[var(--color-text-muted)] hover:text-[var(--color-text-primary)]"
        >
          Open on a map
        </a>
      </div>
    </div>
  );
}

function _InfoRow({ icon, label, value }: { icon?: React.ReactNode; label: string; value: string }) {
  return (
    <div className="flex items-start gap-2">
      {icon && <span className="text-[var(--color-text-muted)] mt-0.5 shrink-0">{icon}</span>}
      <div>
        <p className="text-[11px] text-[var(--color-text-muted)]">{label}</p>
        <p className="text-body font-medium text-[var(--color-text-primary)]">{value}</p>
      </div>
    </div>
  );
}

function _StatusPill({ status }: { status: string }) {
  const label = status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase());
  return (
    <span className="px-2 py-0.5 rounded-full text-[11px] font-bold bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]">
      {label}
    </span>
  );
}

function _severityColor(sev: SeverityLevel | null): string {
  const map: Record<string, string> = {
    critical: 'var(--color-severity-critical)',
    high:     'var(--color-severity-high)',
    medium:   'var(--color-severity-medium)',
    low:      'var(--color-severity-low)',
  };
  return sev ? (map[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
}

function _agencyColor(agencyType: string): string {
  const map: Record<string, string> = {
    BFP:    'var(--color-agency-bfp)',
    PNP:    'var(--color-agency-pnp)',
    MDRRMO: 'var(--color-agency-mdrrmo)',
  };
  return map[agencyType] ?? 'var(--color-brand)';
}

function _Loading() {
  return (
    <div className="p-6 flex items-center justify-center min-h-[400px]">
      <p className="text-body text-[var(--color-text-muted)]">Loading incident…</p>
    </div>
  );
}

function _Error({ message, onBack }: { message: string; onBack: () => void }) {
  return (
    <div className="p-6">
      <Alert variant="error" message={message} />
      <button onClick={onBack} className="mt-4 text-body-sm text-[var(--color-brand)]">
        ← Back
      </button>
    </div>
  );
}

// ── Multi-agency routing panel (Phase 9) ─────────────────────
//
// Surfaces when the Resident flagged overlapping concerns in the
// wizard (wizard_overlap_screen.dart). Maps each overlap flag to
// a concrete agency recommendation so the dispatcher knows which
// secondary agency to call — this is the dispatcher-side half of
// Phase 9's multi-agency routing logic.

const OVERLAP_TO_AGENCIES: Record<string, { agencies: string[]; reason: string }> = {
  may_sunog:           { agencies: ['BFP'],          reason: 'Fire component — BFP response required' },
  may_sugat:           { agencies: ['MDRRMO'],        reason: 'Injuries reported — MDRRMO medical support' },
  may_patay:           { agencies: ['MDRRMO', 'PNP'], reason: 'Fatality — MDRRMO mass-casualty + PNP investigation' },
  may_sandata:         { agencies: ['PNP'],            reason: 'Weapon involved — PNP armed response' },
  may_bata:            { agencies: ['MDRRMO', 'PNP'], reason: 'Children at risk — MDRRMO welfare + PNP safeguarding' },
  may_hazmat:          { agencies: ['BFP', 'MDRRMO'], reason: 'HAZMAT — BFP lead, MDRRMO evacuation support' },
  may_pagbaha:         { agencies: ['MDRRMO'],         reason: 'Flood/landslide — MDRRMO disaster response' },
  may_krimen:          { agencies: ['PNP'],             reason: 'Criminal element — PNP required' },
  may_trapik:          { agencies: ['PNP'],             reason: 'Traffic incident — PNP traffic management' },
  may_evacuees:        { agencies: ['MDRRMO'],          reason: 'Displacement — MDRRMO evacuation coordination' },
};

function _MultiAgencyPanel({ overlaps, primaryAgency }: {
  overlaps: string[];
  primaryAgency: string;
}) {
  // Derive recommended secondary agencies from overlap flags
  const recommendations: { agency: string; reasons: string[] }[] = [];

  for (const flag of overlaps) {
    const mapping = OVERLAP_TO_AGENCIES[flag];
    if (!mapping) continue;
    for (const ag of mapping.agencies) {
      if (ag === primaryAgency) continue; // skip primary — already dispatched
      const existing = recommendations.find(r => r.agency === ag);
      if (existing) {
        existing.reasons.push(mapping.reason);
      } else {
        recommendations.push({ agency: ag, reasons: [mapping.reason] });
      }
    }
  }

  const agColor = (ag: string) => ({
    BFP:    'var(--color-agency-bfp)',
    PNP:    'var(--color-agency-pnp)',
    MDRRMO: 'var(--color-agency-mdrrmo)',
  }[ag] ?? 'var(--color-brand)');

  const agBg = (ag: string) => ({
    BFP:    'var(--color-agency-bfp-bg)',
    PNP:    'var(--color-agency-pnp-bg)',
    MDRRMO: 'var(--color-agency-mdrrmo-bg)',
  }[ag] ?? 'var(--color-brand-subtle)');

  return (
    <div className="bg-[var(--color-surface-card)] rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] p-4">
      {/* Header */}
      <div className="flex items-center gap-2 mb-3">
        <AlertTriangle className="h-4 w-4 text-[var(--color-system-warning)]" />
        <p className="text-label-sm text-[var(--color-system-warning)]">MULTI-AGENCY ROUTING</p>
      </div>

      <p className="text-[12px] text-[var(--color-text-secondary)] leading-relaxed mb-3">
        The reporter flagged overlapping concerns. Secondary agency notification is recommended
        — dispatcher makes the final call. This does not auto-dispatch.
      </p>

      {/* Raw overlap flags */}
      <div className="flex flex-wrap gap-1.5 mb-3">
        {overlaps.map(flag => (
          <span
            key={flag}
            className="px-2 py-0.5 rounded-full text-[11px] font-semibold bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]"
          >
            {flag.replace(/_/g, ' ')}
          </span>
        ))}
      </div>

      {/* Agency recommendations */}
      {recommendations.length > 0 ? (
        <div className="space-y-2">
          <p className="text-[11px] font-bold text-[var(--color-text-muted)] uppercase tracking-wide">
            Recommended secondary agencies
          </p>
          {recommendations.map(({ agency, reasons }) => (
            <div
              key={agency}
              className="flex items-start gap-3 rounded-[var(--radius-md)] border px-3 py-2.5"
              style={{ backgroundColor: agBg(agency), borderColor: `color-mix(in srgb, ${agColor(agency)} 30%, transparent)` }}
            >
              <Building2 className="h-4 w-4 shrink-0 mt-0.5" style={{ color: agColor(agency) }} />
              <div>
                <p className="text-[13px] font-bold" style={{ color: agColor(agency) }}>{agency}</p>
                <ul className="mt-0.5 space-y-0.5">
                  {reasons.map((r, i) => (
                    <li key={i} className="text-[11px] text-[var(--color-text-secondary)]">· {r}</li>
                  ))}
                </ul>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-[12px] text-[var(--color-text-muted)] italic">
          No additional agency recommendations for the flagged overlaps with this primary agency.
        </p>
      )}
    </div>
  );
}
