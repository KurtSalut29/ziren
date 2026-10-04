import { apiClient } from './client';

export interface AuditLogEntry {
  id: string;
  actor_id: string | null;
  actor_role: string | null;
  actor_name: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  target_label: string | null;
  previous_value: Record<string, unknown> | null;
  new_value: Record<string, unknown> | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
  /** Migration 044: the row is written before the action. 'pending' = never
   *  confirmed, 'failed' = the action did not go through. */
  outcome?: 'pending' | 'succeeded' | 'failed';
  error?: string | null;
}

export interface AuditLogFilters {
  actor_id?: string;
  target_type?: string;
  action?: string;
  date_from?: string;
  date_to?: string;
  limit?: number;
  offset?: number;
}

export const fetchAuditLogs = (token: string, filters: AuditLogFilters = {}) => {
  const params = new URLSearchParams();
  for (const [key, value] of Object.entries(filters)) {
    if (value !== undefined && value !== '') params.set(key, String(value));
  }
  const query = params.toString();
  return apiClient.get<{ items: AuditLogEntry[]; total: number }>(
    `/audit-logs/${query ? `?${query}` : ''}`, token,
  );
};
