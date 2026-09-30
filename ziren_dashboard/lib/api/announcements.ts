import { apiClient } from './client';

/** Safety alerts first, then information. Mirrors announcement_service.CATEGORIES. */
export type AnnouncementCategory =
  | 'evacuation' | 'weather' | 'hazard' | 'road_closure' | 'missing_person' | 'all_clear' | 'emergency'
  | 'relief' | 'health' | 'drill' | 'utility'
  | 'service_interruption' | 'maintenance' | 'feature' | 'reminder' | 'general';

export type AnnouncementTarget = 'all' | 'agency_admin' | 'responder' | 'resident' | 'agency';

export interface TargetBarangay { id: string; name: string; municipality: string }

export interface EvacuationCenter { name: string; place?: string }

/** The facts a kind carries. Every field is optional on the wire; the backend
 *  checks which ones a kind requires. */
export interface AnnouncementDetails {
  signal?: number;
  rainfall?: 'yellow' | 'orange' | 'red';
  storm_name?: string;
  hazard?: 'flood' | 'landslide' | 'storm_surge' | 'earthquake' | 'tsunami' | 'volcanic' | 'fire' | 'other';
  area?: string;
  kind?: 'preemptive' | 'forced';
  centers?: EvacuationCenter[];
  bring?: string;
  road?: string;
  alternate?: string;
  reopens?: string;
  name?: string;
  age?: number;
  last_seen?: string;
  description?: string;
  contact?: string;
  where?: string;
  when?: string;
  provider?: string;
  /** Set by the server on an all clear. */
  ends_title?: string;
  ends_category?: AnnouncementCategory;
}

export interface ResponseCounts {
  safe: number;
  need_help: number;
  need_help_open: number;
  /** Residents the alert asked (in the viewer's scope). Null if it could not be counted. */
  audience?: number | null;
}

export interface Announcement {
  id: string;
  title: string;
  body: string;
  category: AnnouncementCategory;
  target_type: AnnouncementTarget;
  target_agency_id: string | null;
  is_active: boolean;
  created_by: string;
  created_at: string;
  expires_at: string | null;
  // Migration 043. Absent on a database that has not run it.
  details?: AnnouncementDetails | null;
  target_municipalities?: string[] | null;
  target_barangays?: TargetBarangay[] | null;
  asks_response?: boolean;
  issuer_agency_type?: string | null;
  ends_announcement_id?: string | null;
  ended_at?: string | null;
  ended_by_announcement_id?: string | null;
  /** On alerts that ask for answers (admin lists). */
  response_counts?: ResponseCounts;
  /** Agency Admin list: addressed to agency admins, as against "announced to your town". */
  for_you?: boolean;
}

export interface CreateAnnouncementRequest {
  title: string;
  body: string;
  category: AnnouncementCategory;
  target_type: AnnouncementTarget;
  target_agency_id?: string | null;
  expires_at?: string | null;
  details?: AnnouncementDetails;
  target_municipalities?: string[] | null;
  target_barangay_ids?: string[] | null;
  asks_response?: boolean;
  ends_announcement_id?: string | null;
}

export interface Reach {
  provincial_admin: number;
  agency_admin: number;
  responder: number;
  resident: number;
  total: number;
}

export type ResponseStatus = 'safe' | 'need_help' | 'no_answer';

export interface ResponseItem {
  user_id: string;
  full_name: string | null;
  phone_number: string | null;
  barangay: string | null;
  municipality: string | null;
  status: ResponseStatus;
  note: string | null;
  latitude: number | null;
  longitude: number | null;
  responded_at: string | null;
  handled_at: string | null;
  handled_by_name: string | null;
}

export interface ResponseBoard {
  announcement: Pick<Announcement, 'id' | 'title' | 'category' | 'created_at' | 'is_active' | 'target_municipalities' | 'target_barangays'>;
  scope: string;
  tally: { audience: number; safe: number; need_help: number; need_help_open: number; no_answer: number };
  items: ResponseItem[];
}

export interface BarangayRef { id: string; name: string; municipality: string }

export const fetchAnnouncements = (token: string, mineOnly = true) =>
  apiClient.get<Announcement[]>(`/announcements/?mine_only=${mineOnly}`, token);

export const createAnnouncement = (token: string, body: CreateAnnouncementRequest) =>
  apiClient.post<Announcement & { reach: Reach }>('/announcements/', body, token);

export const previewAudience = (token: string, body: CreateAnnouncementRequest) =>
  apiClient.post<Reach>('/announcements/audience', body, token);

export const deactivateAnnouncement = (token: string, id: string) =>
  apiClient.patch<Announcement>(`/announcements/${id}/deactivate`, {}, token);

export const fetchResponses = (token: string, id: string) =>
  apiClient.get<ResponseBoard>(`/announcements/${id}/responses`, token);

export const markReached = (token: string, id: string, userId: string, reached = true) =>
  apiClient.post<unknown>(`/announcements/${id}/responses/${userId}/reached`, { reached }, token);

export const fetchBarangays = (token: string) =>
  apiClient.get<BarangayRef[]>('/users/barangays', token);
