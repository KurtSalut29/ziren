import { apiClient } from './client';

export type AnnouncementCategory =
  | 'maintenance' | 'emergency' | 'service_interruption' | 'feature' | 'reminder' | 'general';
export type AnnouncementTarget = 'all' | 'agency_admin' | 'responder' | 'resident' | 'agency';

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
}

export interface CreateAnnouncementRequest {
  title: string;
  body: string;
  category: AnnouncementCategory;
  target_type: AnnouncementTarget;
  target_agency_id?: string;
  expires_at?: string;
}

export const fetchAnnouncements = (token: string, mineOnly = true) =>
  apiClient.get<Announcement[]>(`/announcements/?mine_only=${mineOnly}`, token);

export const createAnnouncement = (token: string, body: CreateAnnouncementRequest) =>
  apiClient.post<Announcement>('/announcements/', body, token);

export const deactivateAnnouncement = (token: string, id: string) =>
  apiClient.patch<Announcement>(`/announcements/${id}/deactivate`, {}, token);
