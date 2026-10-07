/**
 * Resident accounts — how a resident stands once they are verified.
 *
 * Verification (lib/api/verification.ts) decides who someone is and changes
 * nothing they can do. This is the other half: an admin can warn an account
 * for a violation, suspend it from reporting and lift that again. A suspension
 * IS a permission, so every call here is audited on the server and the
 * resident is told on their phone.
 */

import { apiClient } from './client';

export type Standing = 'good' | 'warned' | 'suspended';
export type StandingFilter = 'verified' | 'unverified' | 'warned' | 'suspended' | 'all';

export interface Suspension {
  active: boolean;
  /** "Until further notice": `until` is null. */
  indefinite: boolean;
  until: string | null;
}

export interface ResidentAccount {
  id: string;
  email: string;
  full_name: string;
  phone_number: string | null;
  created_at: string;
  barangay: string | null;
  municipality_address: string | null;
  purok_sitio: string | null;
  street_address: string | null;
  verification_level: number;
  verification_method: string | null;
  verified_at: string | null;
  valid_id_type: string | null;
  /** verification_level is 2 or more. */
  verified: boolean;
  warning_count: number;
  suspension: Suspension;
  standing: Standing;
  report_count: number;
}

export interface ResidentList {
  items: ResidentAccount[];
  total: number;
  /** Every bucket at once, whatever is being shown. */
  counts: Record<StandingFilter, number>;
  /** The server stopped reading at its cap: there are more residents than this. */
  truncated: boolean;
}

export interface ResidentReport {
  id: string;
  record_number?: string | null;
  report_text: string;
  status: string;
  review_status?: string | null;
  incident_category?: string | null;
  submitted_via?: string | null;
  created_at: string;
}

export interface StandingEvent {
  id: string;
  kind: 'warned' | 'suspended' | 'reinstated';
  violation: string | null;
  violation_label: string | null;
  note: string | null;
  incident_id: string | null;
  suspended_until: string | null;
  indefinite: boolean;
  /** Applied by the third-warning rule, not chosen by a person. */
  automatic: boolean;
  by: string | null;
  by_role: string | null;
  at: string;
}

export interface ResidentDetail extends ResidentAccount {
  first_name: string | null;
  middle_name: string | null;
  last_name: string | null;
  name_suffix: string | null;
  date_of_birth: string | null;
  sex: string | null;
  valid_id_number: string | null;
  is_pwd: boolean;
  emergency_contact_name: string | null;
  emergency_contact_number: string | null;
  /** The approved selfie, as the photo on the Ziren ID: a short-lived signed
   *  link, null when not verified or none on file (2026-10-08). */
  photo_url?: string | null;
  rejected_report_count: number;
  recent_reports: ResidentReport[];
  history: StandingEvent[];
  /** The violations an admin can cite, as the server defines them. */
  violations: { key: string; label: string }[];
}

export interface StandingResult {
  id: string;
  warning_count: number;
  suspension: Suspension;
  standing: Standing;
}

/** The third warning suspends by itself. Must match AUTO_SUSPEND_AT on the server. */
export const AUTO_SUSPEND_AT = 3;
export const AUTO_SUSPEND_DAYS = 30;

export const residentsApi = {
  list: (token: string, opts: { standing: StandingFilter; q?: string; limit?: number; offset?: number }) => {
    const params = new URLSearchParams({ standing: opts.standing });
    if (opts.q?.trim()) params.set('q', opts.q.trim());
    if (opts.limit) params.set('limit', String(opts.limit));
    if (opts.offset) params.set('offset', String(opts.offset));
    return apiClient.get<ResidentList>(`/users/residents?${params.toString()}`, token);
  },

  detail: (token: string, userId: string) =>
    apiClient.get<ResidentDetail>(`/users/residents/${userId}`, token),

  warn: (token: string, userId: string, body: { violation: string; note: string; incident_id?: string | null }) =>
    apiClient.post<StandingResult>(`/users/residents/${userId}/warn`, body, token),

  /** `days` null means "until further notice". */
  suspend: (token: string, userId: string, body: { violation: string; note: string; days: number | null }) =>
    apiClient.post<StandingResult>(`/users/residents/${userId}/suspend`, body, token),

  reinstate: (token: string, userId: string, body: { note?: string; clear_warnings: boolean }) =>
    apiClient.post<StandingResult>(`/users/residents/${userId}/reinstate`, body, token),
};
