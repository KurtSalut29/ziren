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
  contact_number: string | null;
  email: string | null;
}

export type AssistStatus = 'pending' | 'acknowledged' | 'declined';

export interface AssistRequestSummary {
  id: string;
  incident_id: string;
  requesting_agency_id: string;
  requesting_agency_name: string | null;
  requested_agency_id: string;
  requested_agency_name: string | null;
  overlap_flag: string | null;
  status: AssistStatus;
  created_at: string;
  responded_at: string | null;
  incident_category: string | null;
  severity: string | null;
  location_address: string | null;
  incident_status: string | null;
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
 */
export function listAssistRequests(scope: 'sent' | 'received' | null, token: string): Promise<AssistRequestSummary[]> {
  return apiClient.get(scope ? `/assist-requests?scope=${scope}` : '/assist-requests', token);
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
