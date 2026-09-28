/**
 * Standing platform totals for the Provincial Admin overview.
 *
 * Separate from lib/api/dispatch.ts on purpose: everything there describes
 * what is happening right now and is polled on a short timer. These are
 * counts of people and infrastructure — they move when someone signs up or a
 * station is added, not second to second — so the overview loads them once
 * rather than folding them into its refresh loop.
 */

import { apiClient } from './client';

export interface PlatformCounts {
  /** Every account with role = resident. */
  residents: number;
  /** Of those, the ones an admin has approved (verification_level >= 2). */
  residents_verified: number;

  responders: number;
  /** Available to be dispatched at this moment. */
  responders_on_duty: number;
  /** Accounts an Agency Admin still has to approve or reject. */
  responders_pending: number;

  /** Active stations — where reports are actually routed. */
  stations: number;
  agencies: number;
  /**
   * Agencies that have at least one active station.
   *
   * The gap between this and `agencies` is the number that matters: an agency
   * with no station cannot receive a dispatch, so a report routed to it has
   * nowhere to land.
   */
  agencies_with_a_station: number;

  /**
   * When each account or station created in the last 14 days was created —
   * timestamps only, never rows. It is the only history these totals have, and
   * what `standingSeries` walks back from to draw each tile's trend line.
   * Absent from an older backend, which simply draws no line.
   */
  recent?: {
    residents: string[];
    responders: string[];
    stations: string[];
  };
}

/** Provincial Admin only — the endpoint is gated with require_role("provincial_admin"). */
export async function fetchPlatformCounts(token: string): Promise<PlatformCounts> {
  return apiClient.get<PlatformCounts>('/users/provincial/counts', token);
}

/**
 * One responder on an agency's roster.
 *
 * From GET /users/agency/responders, which scopes itself to the caller's own
 * agency_id — an Agency Admin cannot see another agency's people, and does not
 * pass an id to say so.
 */
export interface AgencyResponder {
  id: string;
  full_name: string | null;
  badge_id: string | null;
  approval_status: string;
  availability: string | null;
  is_verified: boolean;
  created_at: string;
}

/**
 * The roster, counted three ways.
 *
 * NOT per station. Responders carry agency_id and no station_id, so "the
 * responders at my station" is not a question this schema can answer — the
 * roster belongs to the agency. Labelled as the agency's throughout rather
 * than borrowing the word "station" for a grouping that does not exist.
 */
export interface RosterCounts {
  total: number;
  /** Able to be dispatched at all. */
  approved: number;
  /** Of the approved ones, available right now. */
  onDuty: number;
  /** Waiting on this admin to approve or reject them. */
  pending: number;
}

export function countRoster(rows: AgencyResponder[]): RosterCounts {
  const approved = rows.filter(r => r.approval_status === 'approved');
  return {
    total: rows.length,
    approved: approved.length,
    // Counted over APPROVED only. A pending account can carry availability
    // like any other row, but it cannot be sent to an incident, so including
    // it would inflate the number a dispatcher reads as "available now".
    onDuty: approved.filter(r => r.availability === 'on_duty').length,
    pending: rows.filter(r => r.approval_status === 'pending').length,
  };
}

export async function fetchAgencyResponders(token: string): Promise<AgencyResponder[]> {
  return apiClient.get<AgencyResponder[]>('/users/agency/responders', token);
}

/**
 * Move a station to an exact point.
 *
 * Agency-scoped server-side: an Agency Admin may set their own agency's
 * stations and takes a 403 on anyone else's. Deliberately not Super-Admin-only
 * — the people who work at a station know where it stands better than a
 * provincial office does, and before this endpoint existed the coordinates
 * could only be typed once, at creation, and never corrected.
 */
export async function updateStationLocation(
  token: string,
  stationId: string,
  point: { latitude: number; longitude: number },
): Promise<{ station_id: string; latitude: number; longitude: number }> {
  return apiClient.patch(`/stations/${stationId}/location`, point, token);
}
