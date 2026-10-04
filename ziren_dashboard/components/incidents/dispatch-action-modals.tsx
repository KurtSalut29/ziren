'use client';

/**
 * The four dispatch-decision modals — Dispatch, Cancel, Reject, Flag False
 * SOS. (Request Clarification used to be a fifth, its own confirm dialog
 * with its own textarea — removed 2026-09-23 in favour of just sending the
 * question through the chat window's own composer (IncidentChatModal), which now calls
 * requestClarification itself when the report's review is still undecided.
 * See that component's file comment.)
 *
 * Split out from the incident detail page so IncidentDetailModal (the
 * queue's without-leaving-the-page dialog) can reuse them directly instead
 * of a second implementation of each. They used to live in page.tsx and be
 * exported from it, which Next.js's App Router rejects at the type level —
 * a page.tsx may only export the route-reserved names (default, metadata,
 * generateStaticParams, ...), so any other export fails
 * `.next/types/.../page.ts` validation. A plain component module has no
 * such restriction.
 */

import { useEffect, useMemo, useState } from 'react';
import { Ban, Check, Flag, Shield, Siren, Sparkles, TriangleAlert, XCircle } from 'lucide-react';
import {
  assignResponder, cancelIncident, fetchNearbyResponders, flagFalseSos, rejectReport,
  type IncidentDetail, type NearbyResponder, type Responder, type SeverityLevel,
} from '@/lib/api/dispatch';
import { apiClient } from '@/lib/api/client';
import { formatDistance } from '@/lib/incidents/response-route';
import {
  StatusPill, type CurrentStatus, type CurrentIncidentRef,
} from '@/components/responders/status-pill';
import { Button } from '@/components/ui/button';
import { SeverityRule } from '@/components/ui/severity-rationale';
import { SearchInput } from '@/components/ui/search-input';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogMedia,
  AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogMedia, DialogTitle,
} from '@/components/efferd/ui/dialog';

const SEVERITY_ORDER: SeverityLevel[] = ['critical', 'high', 'medium', 'low'];

function _severityColor(sev: SeverityLevel | null): string {
  const map: Record<string, string> = {
    critical: 'var(--color-severity-critical)',
    high:     'var(--color-severity-high)',
    medium:   'var(--color-severity-medium)',
    low:      'var(--color-severity-low)',
  };
  return sev ? (map[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
}

interface ResponderStatusInfo {
  status: CurrentStatus;
  currentIncident: CurrentIncidentRef | null;
}

// ── Dispatch modal ────────────────────────────────────────────

export function DispatchModal({ incident, token, initialResponderId, onClose, onSuccess, onError }: {
  incident: IncidentDetail;
  token: string;
  /** A responder chosen elsewhere (the 'near this incident' panel) - opens with them ticked. */
  initialResponderId?: string | null;
  onClose: () => void;
  onSuccess: (msg: string) => void;
  onError: (msg: string) => void;
}) {
  const sev = (incident.suggested_severity ?? incident.severity) as SeverityLevel | null;
  // No silent default when the model could not read the report: "medium"
  // used to be pre-selected, so a crew could be sent on a severity nobody
  // chose. The dispatcher picks it (evaluator finding #4).
  const [chosenSeverity, setChosenSeverity] = useState<SeverityLevel | null>(sev);
  // The person takes the decision: they confirm they read the severity and
  // the reason for it. The server refuses a dispatch without this.
  const [confirmed, setConfirmed] = useState(false);
  const [selectedResponder, setSelectedResponder] = useState<string>(initialResponderId ?? '');
  const [overrideReason, setOverrideReason] = useState('');
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(false);
  // Best-effort only: the responder list itself already comes scoped and
  // filtered from /dispatch/queue/{id} (agency, approved, on_duty). This is
  // a second, non-critical call purely for the status pill — see
  // responders/page.tsx for the same shape, already agency-scoped
  // server-side. A failure here must never block dispatching, so it fails
  // silently into "no status shown", the same pattern overview/page.tsx's
  // roster fetch uses.
  const [statusById, setStatusById] = useState<Record<string, ResponderStatusInfo>>({});

  useEffect(() => {
    let cancelled = false;
    apiClient.get<{ id: string; current_status: CurrentStatus; current_incident: CurrentIncidentRef | null }[]>(
      '/users/agency/responders', token,
    ).then(rows => {
      if (cancelled) return;
      const map: Record<string, ResponderStatusInfo> = {};
      for (const r of rows) map[r.id] = { status: r.current_status, currentIncident: r.current_incident };
      setStatusById(map);
    }).catch(() => { /* status is a nicety, not the responder list itself */ });
    return () => { cancelled = true; };
  }, [token]);

  // The roster came with the detail, which may be minutes old by the time the
  // dispatcher opens this dialog: a responder may have answered "I can respond", moved,
  // or been sent elsewhere. One fresh reading on open, overlaid on the roster, so the
  // distance, state and answer they choose by are current at the moment of choosing.
  // Best effort: without it the roster's own figures stand.
  const [fresh, setFresh] = useState<Record<string, NearbyResponder>>({});
  useEffect(() => {
    let cancelled = false;
    fetchNearbyResponders(incident.id, token).then(panel => {
      if (cancelled) return;
      setFresh(Object.fromEntries(panel.responders.map(r => [r.responder_id, r])));
    }).catch(() => { /* the roster's own figures stand */ });
    return () => { cancelled = true; };
  }, [incident.id, token]);
  const merged = (r: Responder): Responder => {
    const n = fresh[r.id];
    return n ? {
      ...r, state: n.state, distance_km: n.distance_km, eta_min: n.eta_min, direction: n.direction,
      located: n.located, level: n.level, reason: n.reason, current_calls: n.current_calls,
      notified_at: n.notified_at, answer: n.answer, answered_at: n.answered_at, rank: n.rank,
    } : r;
  };
  const roster = incident.available_responders.map(merged);

  // Best fit first — the SAME ordering proximity.nearby_for_admin already
  // computed server-side for the read-only "who's near this incident" panel
  // (rank 1 is who that panel would tell first). A roster of two or three
  // barely needs this, but the roster this dialog was actually built to
  // scale to — every on-duty responder in a whole agency — is unusable
  // sorted by database insertion order, which is what "no sort at all" is.
  // Unranked (off-radius, or the nearby fetch hasn't landed) sinks to the
  // bottom rather than null-first, since a rank of "unknown" is not a claim
  // of "best".
  const [query, setQuery] = useState('');
  const sortedRoster = useMemo(() => {
    const busyOrder: Partial<Record<NonNullable<Responder['state']>, number>> = {
      free: 0, committed: 1, en_route: 1, on_scene: 1,
    };
    return [...roster].sort((a, b) => {
      const ra = a.rank ?? Infinity;
      const rb = b.rank ?? Infinity;
      if (ra !== rb) return ra - rb;
      const sa = a.state ? busyOrder[a.state] ?? 2 : 2;
      const sb = b.state ? busyOrder[b.state] ?? 2 : 2;
      if (sa !== sb) return sa - sb;
      const da = a.distance_km ?? Infinity;
      const db = b.distance_km ?? Infinity;
      if (da !== db) return da - db;
      return a.full_name.localeCompare(b.full_name);
    });
  }, [roster]);

  const filteredRoster = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sortedRoster;
    return sortedRoster.filter(r =>
      r.full_name.toLowerCase().includes(q) || (r.badge_id ?? '').toLowerCase().includes(q),
    );
  }, [sortedRoster, query]);

  // Choosing a severity where the model gave none is not an override of anything.
  const wasOverride = sev !== null && chosenSeverity !== sev;

  async function handleDispatch() {
    if (!selectedResponder) { onError('Select a responder before dispatching.'); return; }
    if (!chosenSeverity) { onError('Choose a severity. The system could not assess this report.'); return; }
    if (wasOverride && !overrideReason.trim()) { onError('Provide an override reason.'); return; }
    if (!confirmed) { onError('Confirm that you checked the severity and its reason.'); return; }

    setLoading(true);
    try {
      await assignResponder(incident.id, {
        responder_id:       selectedResponder,
        chosen_severity:    chosenSeverity,
        suggested_severity: sev,
        override_reason:    wasOverride ? overrideReason.trim() : null,
        notes:              notes.trim() || null,
        severity_confirmed: confirmed,
      }, token);
      onSuccess('Responder dispatched successfully.');
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Dispatch failed.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <Dialog open onOpenChange={open => { if (!open && !loading) onClose(); }}>
      <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg" showCloseButton={!loading}>
        <DialogHeader className="flex-row items-center gap-3">
          <DialogMedia tone="brand"><Siren /></DialogMedia>
          <DialogTitle>Dispatch Responder</DialogTitle>
        </DialogHeader>
      <div className="space-y-4">
        {/* Severity selector */}
        <div>
          <label className="text-[13px] font-medium text-[var(--color-text-secondary)] block mb-1.5">
            Severity
            {incident.suggested_severity && (
              <span className="ml-2 badge-ai">AI: {incident.suggested_severity}</span>
            )}
          </label>
          <div className="flex gap-2 flex-wrap">
            {SEVERITY_ORDER.map(s => (
              <button
                key={s}
                aria-pressed={chosenSeverity === s}
                onClick={() => setChosenSeverity(s)}
                className="px-3 py-1.5 rounded-[var(--radius-md)] text-[13px] font-semibold border transition-colors"
                style={{
                  backgroundColor: chosenSeverity === s ? `color-mix(in srgb, ${_severityColor(s)} 15%, transparent)` : 'transparent',
                  borderColor:     chosenSeverity === s ? _severityColor(s) : 'var(--color-surface-border)',
                  color:           chosenSeverity === s ? _severityColor(s) : 'var(--color-text-secondary)',
                }}
              >
                {s.toUpperCase()}
              </button>
            ))}
          </div>
        </div>

        {/* Why the system suggested it, right where the decision is made: the
            rule and the reason, or a plain statement that there is none. */}
        {sev ? (
          <SeverityRule severity={sev} signals={incident.signals} />
        ) : (
          <p
            className="rounded-[var(--radius-md)] border px-3 py-2 text-[12.5px]"
            style={{
              borderColor: 'color-mix(in srgb, var(--color-system-warning) 45%, transparent)',
              backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 8%, transparent)',
              color: 'var(--color-text-primary)',
            }}
          >
            The system could not assess this report. Read it and choose the severity yourself.
          </p>
        )}

        {/* Override reason */}
        {wasOverride && (
          <div>
            <label className="text-[13px] font-medium text-[var(--color-text-secondary)] block mb-1.5">
              Override reason <span className="text-[var(--color-system-error)]">*</span>
            </label>
            <textarea
              rows={2}
              value={overrideReason}
              onChange={e => setOverrideReason(e.target.value)}
              placeholder="Why are you changing the AI-suggested severity?"
              className="w-full"
              style={{ resize: 'none' }}
            />
          </div>
        )}

        {/* Responder selector.
            The id is a link target: the queue's "Assign" button used to
            deep-link straight here rather than dropping the dispatcher at
            the top of a long detail page to hunt for it. Now that Dispatch
            opens this dialog directly (see IncidentDetailModal), the id
            mostly documents the history; scroll-mt stays harmless if
            anything still jumps to it. */}
        <div className="scroll-mt-20" id="assign">
          <label className="text-[13px] font-medium text-[var(--color-text-secondary)] block mb-1.5">
            Assign Responder <span className="text-[var(--color-system-error)]">*</span>
          </label>
          {incident.available_responders.length === 0 ? (
            <p className="text-body-sm text-[var(--color-system-warning)]">
              No on-duty responders available in this agency.{' '}
              <a href="/responders" className="underline hover:no-underline">
                Check the roster
              </a>{' '}
              for who might be back on duty soon.
            </p>
          ) : (
            <>
              {/* A search box earns its place once the roster is long enough
                  that scrolling past it to find one name by eye is slower
                  than typing it — a handful of responders needs no filter. */}
              {roster.length > 6 && (
                <SearchInput
                  className="mb-2"
                  label="Search responders"
                  onValueChange={setQuery}
                  placeholder="Search by name or badge…"
                  value={query}
                />
              )}
              {filteredRoster.length === 0 ? (
                <p className="text-body-sm text-[var(--color-text-muted)]">
                  No responder matches “{query}”.
                </p>
              ) : (
                <div className="space-y-2 max-h-[360px] overflow-y-auto pr-1 scroll-slim">
                  {filteredRoster.map((r: Responder) => (
                    <button
                      key={r.id}
                      onClick={() => setSelectedResponder(r.id)}
                      className="w-full flex items-center justify-between gap-2 px-3 py-2.5 rounded-[var(--radius-md)] border transition-colors text-left"
                      style={{
                        borderColor:     selectedResponder === r.id ? 'var(--color-brand)' : 'var(--color-surface-border)',
                        backgroundColor: selectedResponder === r.id ? 'var(--color-brand-subtle)' : 'transparent',
                      }}
                    >
                      <div className="flex min-w-0 flex-wrap items-center gap-x-2.5 gap-y-1">
                        {/* The proximity engine's own top 3 — free and
                            nearest, the same figures the read-only "who's
                            near this incident" panel already showed. Not
                            drawn past 3rd: a badge on every row stops
                            meaning "pick me" and starts meaning nothing. */}
                        {typeof r.rank === 'number' && r.rank <= 3 && (
                          <span
                            className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide"
                            data-dispatch-suggested={r.rank}
                            style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
                          >
                            <Sparkles className="h-3 w-3" /> #{r.rank} fit
                          </span>
                        )}
                        <div className="min-w-0">
                          <p className="truncate text-[14px] font-semibold text-[var(--color-text-primary)]">{r.full_name}</p>
                          {r.badge_id && (
                            <p className="text-[12px] text-[var(--color-text-muted)]">Badge: {r.badge_id}</p>
                          )}
                        </div>
                        <StatusPill
                          status={statusById[r.id]?.status ?? null}
                          currentIncident={statusById[r.id]?.currentIncident}
                        />
                        {/* How close, measured on the ellipsoid from their last fresh position. */}
                        {typeof r.distance_km === 'number' ? (
                          <span className="text-[12px] text-[var(--color-text-secondary)]" data-dispatch-distance>
                            <b className="font-semibold text-[var(--color-text-primary)]">{formatDistance(r.distance_km)}</b>
                            {typeof r.eta_min === 'number' ? ` · about ${r.eta_min} min` : ''}
                          </span>
                        ) : r.state ? (
                          <span className="inline-flex items-center gap-1 text-[12px] text-[var(--color-system-warning)]" data-dispatch-distance>
                            <TriangleAlert className="h-3 w-3" /> position unknown
                          </span>
                        ) : null}
                        {r.answer === 'can_respond' && (
                          <span
                            className="rounded-full px-2 py-0.5 text-[11px] font-semibold"
                            data-dispatch-answer="can_respond"
                            style={{ backgroundColor: 'var(--color-system-success-bg)', color: 'var(--color-system-success)' }}
                          >
                            Says they can respond
                          </span>
                        )}
                      </div>
                      {selectedResponder === r.id && (
                        <Check className="h-4 w-4 shrink-0 text-[var(--color-brand)]" />
                      )}
                    </button>
                  ))}
                </div>
              )}
            </>
          )}
          {/* Choosing a responder who is already on a call is allowed - the queue
              holds several - but it is the dispatcher's informed choice: the
              system never takes them off what they hold. */}
          {(() => {
            const picked = roster.find(r => r.id === selectedResponder);
            if (!picked || !picked.state || picked.state === 'free' || !picked.current_calls?.length) return null;
            const call = picked.current_calls[0];
            const doing = { committed: 'already dispatched to', en_route: 'already en route to', on_scene: 'on scene at' }[picked.state];
            const what = `${(call.category ?? 'another incident').replace(/_/g, ' ')}${call.severity ? ` (${call.severity.toUpperCase()})` : ''}`;
            return (
              <p
                className="mt-2 rounded-[var(--radius-md)] border px-3 py-2 text-[12.5px] leading-snug"
                data-dispatch-busy-warning
                style={{ borderColor: 'var(--color-system-warning)', color: 'var(--color-text-primary)' }}
              >
                <b>{picked.full_name}</b> is {doing} {what}. Dispatching adds this incident to their queue;
                nothing is taken off the call they are on.
              </p>
            );
          })()}
        </div>

        {/* Notes */}
        <div>
          <label className="text-[13px] font-medium text-[var(--color-text-secondary)] block mb-1.5">
            Notes (optional)
          </label>
          <textarea
            rows={2}
            value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="Additional instructions for the responder…"
            className="w-full"
            style={{ resize: 'none' }}
          />
        </div>

        <label className="flex items-start gap-2.5 rounded-[var(--radius-md)] border border-[var(--color-surface-border)] px-3 py-2.5 text-[13px] text-[var(--color-text-primary)]">
          <input
            checked={confirmed}
            className="mt-0.5 size-4 shrink-0 accent-[var(--color-brand)]"
            data-testid="severity-confirm"
            onChange={e => setConfirmed(e.target.checked)}
            type="checkbox"
          />
          <span>
            I have checked the severity
            {chosenSeverity ? <strong> ({chosenSeverity.toUpperCase()})</strong> : null}
            {' '}and the reason for it. The decision to send this crew is mine.
          </span>
        </label>

      </div>
      <DialogFooter>
        <Button variant="outline" size="md" onClick={onClose}>Cancel</Button>
        <Button
          variant="primary"
          size="md"
          onClick={handleDispatch}
          isLoading={loading}
          disabled={!selectedResponder || !chosenSeverity || !confirmed || incident.available_responders.length === 0}
        >
          <Shield className="h-4 w-4" data-icon="inline-start" />
          Dispatch
        </Button>
      </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ── Cancel modal ──────────────────────────────────────────────

export function CancelModal({ token, incidentId, onClose, onSuccess, onError }: {
  token: string; incidentId: string;
  onClose: () => void; onSuccess: () => void; onError: (m: string) => void;
}) {
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);

  async function handle() {
    if (!reason.trim()) { onError('Reason is required to cancel.'); return; }
    setLoading(true);
    try {
      await cancelIncident(incidentId, reason.trim(), token);
      onSuccess();
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Cancel failed.');
    } finally { setLoading(false); }
  }

  return (
    <AlertDialog open onOpenChange={open => { if (!open && !loading) onClose(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogMedia tone="danger"><Ban /></AlertDialogMedia>
          <AlertDialogTitle>Cancel Incident</AlertDialogTitle>
          <AlertDialogDescription>
            Provide a reason for cancellation. This is logged in the dispatch audit trail.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <textarea
          rows={3}
          value={reason}
          onChange={e => setReason(e.target.value)}
          placeholder="e.g. Duplicate report, false alarm confirmed…"
          className="w-full"
          style={{ resize: 'none' }}
        />
        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>Back</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={loading}
            onClick={e => { e.preventDefault(); void handle(); }}
          >
            Cancel Incident
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

// ── Reject report modal ────────────────────────────────────────

export function RejectReportModal({ token, incidentId, onClose, onSuccess, onError }: {
  token: string; incidentId: string;
  onClose: () => void; onSuccess: () => void; onError: (m: string) => void;
}) {
  const [reason, setReason] = useState('');
  const [loading, setLoading] = useState(false);

  async function handle() {
    if (!reason.trim()) { onError('A reason is required to reject a report.'); return; }
    setLoading(true);
    try {
      await rejectReport(incidentId, reason.trim(), token);
      onSuccess();
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Reject failed.');
    } finally { setLoading(false); }
  }

  return (
    <AlertDialog open onOpenChange={open => { if (!open && !loading) onClose(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogMedia tone="danger"><XCircle /></AlertDialogMedia>
          <AlertDialogTitle>Reject Report</AlertDialogTitle>
          <AlertDialogDescription>
            The report is not real, or does not belong to your agency. This also cancels the
            incident — logged in the dispatch audit trail.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <textarea
          rows={3}
          value={reason}
          onChange={e => setReason(e.target.value)}
          placeholder="e.g. Duplicate of another report, wrong agency, unable to verify…"
          className="w-full"
          style={{ resize: 'none' }}
        />
        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>Back</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={loading}
            onClick={e => { e.preventDefault(); void handle(); }}
          >
            Reject Report
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}


// ── Flag false SOS modal ──────────────────────────────────────

export function FlagSosModal({ token, incidentId, onClose, onSuccess, onError }: {
  token: string; incidentId: string;
  onClose: () => void; onSuccess: () => void; onError: (m: string) => void;
}) {
  const [loading, setLoading] = useState(false);

  async function handle() {
    setLoading(true);
    try {
      await flagFalseSos(incidentId, token);
      onSuccess();
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Action failed.');
    } finally { setLoading(false); }
  }

  return (
    <AlertDialog open onOpenChange={open => { if (!open && !loading) onClose(); }}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogMedia tone="danger"><Flag /></AlertDialogMedia>
          <AlertDialogTitle>Flag as False SOS</AlertDialogTitle>
          <AlertDialogDescription>
            Marking this as a confirmed false alarm will increment the reporter&apos;s warning count.
            At 3 warnings, the reporter&apos;s SOS access is suspended for 30 days.
            This action is logged and cannot be undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={loading}
            onClick={e => { e.preventDefault(); void handle(); }}
          >
            <Flag className="h-4 w-4 mr-1.5" /> Confirm False SOS
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
