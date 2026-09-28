/**
 * Typed client for /assist-requests — cross-agency "we need your help on
 * this incident" requests. See
 * ziren_backend/app/services/assist_request_service.py and
 * docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
 */

import { apiClient } from './client';

export interface AssistCandidate {
  id: string;
  name: string;
  agency_type: string;
  municipality: string | null;
  contact_number: string | null;
  email: string | null;
  /** In the incident's own municipality — the picker lists these first. */
  same_municipality: boolean;
  /** Status of the latest request this incident already sent that station, if any. */
  existing_status: AssistStatus | null;
}

export type AssistStatus = 'pending' | 'acknowledged' | 'declined';

/** Which side of the request the viewer is on. */
export type AssistDirection = 'incoming' | 'outgoing' | 'oversight';

export interface AssistRequestSummary {
  id: string;
  incident_id: string;
  requesting_agency_id: string;
  requesting_agency_name: string | null;
  requesting_agency_type: string | null;
  requesting_municipality: string | null;
  requesting_contact_number: string | null;
  requested_agency_id: string;
  requested_agency_name: string | null;
  requested_agency_type: string | null;
  requested_municipality: string | null;
  requested_contact_number: string | null;
  overlap_flag: string | null;
  status: AssistStatus;
  created_at: string;
  responded_at: string | null;
  direction: AssistDirection;
  // The situation snapshot — never the full incident, never the reporter.
  incident_category: string | null;
  severity: string | null;
  location_address: string | null;
  incident_status: string | null;
  record_number: string | null;
  report_text: string | null;
  incident_created_at: string | null;
  latitude: number | null;
  longitude: number | null;
  // List rows only (absent on a thread's own request).
  last_message_at?: string | null;
  last_message_preview?: string | null;
  last_sender_agency_id?: string | null;
  message_count?: number;
  /** Computed server-side: can THIS viewer act on it right now? See
   *  assist_request_service._hydrate_request for why this isn't derived
   *  client-side (the dashboard has no agency id in session storage). */
  can_respond: boolean;
}

export interface AssistMessage {
  id: string;
  request_id: string;
  sender_agency_id: string;
  sender_id: string;
  sender_name: string | null;
  body: string;
  created_at: string;
  /** Computed server-side — see AssistRequestSummary.can_respond's note. */
  mine: boolean;
}

export interface AssistThread {
  request: AssistRequestSummary;
  messages: AssistMessage[];
}

export function fetchAssistCandidates(incidentId: string, token: string): Promise<AssistCandidate[]> {
  return apiClient.get(`/assist-requests/candidates?incident_id=${encodeURIComponent(incidentId)}`, token);
}

export function createAssistRequest(
  incidentId: string,
  requestedAgencyId: string,
  message: string,
  overlapFlag: string | null,
  token: string,
): Promise<AssistRequestSummary> {
  return apiClient.post('/assist-requests', {
    incident_id: incidentId,
    requested_agency_id: requestedAgencyId,
    message,
    overlap_flag: overlapFlag,
  }, token);
}

/**
 * scope null is the provincial_admin oversight call — the server ignores
 * scope for that role and returns both directions for their own
 * agency_type instead (migration 037); agency_admin must pass a scope.
 * incidentId narrows the list to one incident.
 */
export function listAssistRequests(
  scope: 'sent' | 'received' | 'all' | null,
  token: string,
  incidentId?: string,
): Promise<AssistRequestSummary[]> {
  const params = new URLSearchParams();
  if (scope) params.set('scope', scope);
  if (incidentId) params.set('incident_id', incidentId);
  const qs = params.toString();
  return apiClient.get(qs ? `/assist-requests?${qs}` : '/assist-requests', token);
}

/** The station on the other side of a request, from the viewer's side. */
export function counterpart(r: AssistRequestSummary): {
  id: string; name: string | null; type: string | null; municipality: string | null; contact: string | null;
} {
  return r.direction === 'incoming'
    ? { id: r.requesting_agency_id, name: r.requesting_agency_name, type: r.requesting_agency_type, municipality: r.requesting_municipality, contact: r.requesting_contact_number }
    : { id: r.requested_agency_id, name: r.requested_agency_name, type: r.requested_agency_type, municipality: r.requested_municipality, contact: r.requested_contact_number };
}

/** True when the newest message came from the other station. */
export function lastMessageIsTheirs(r: AssistRequestSummary): boolean {
  if (!r.last_sender_agency_id || r.direction === 'oversight') return false;
  return r.last_sender_agency_id === counterpart(r).id;
}

export function fetchAssistThread(requestId: string, token: string): Promise<AssistThread> {
  return apiClient.get(`/assist-requests/${requestId}`, token);
}

export function postAssistMessage(requestId: string, body: string, token: string): Promise<AssistMessage> {
  return apiClient.post(`/assist-requests/${requestId}/messages`, { body }, token);
}

export function setAssistStatus(
  requestId: string,
  newStatus: 'acknowledged' | 'declined',
  token: string,
): Promise<AssistRequestSummary> {
  return apiClient.patch(`/assist-requests/${requestId}/status`, { status: newStatus }, token);
}
