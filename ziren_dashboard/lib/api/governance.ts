import { apiClient } from './client';
import type { AuditLogEntry } from './audit';

export interface IncidentConfiguration {
  incident_categories: string[];
  incident_statuses: string[];
  editable: boolean;
  note: string;
}

export interface PolicyRecord {
  key: string;
  value: Record<string, unknown>;
  updated_at: string | null;
}

/** Same row shape as the general audit trail — see /audit-logs's AuditLogEntry. */
export type ConfigHistoryEntry = AuditLogEntry;

export const fetchIncidentConfiguration = (token: string) =>
  apiClient.get<IncidentConfiguration>('/governance/incident-configuration', token);

export const fetchAccountPolicies = (token: string) =>
  apiClient.get<PolicyRecord>('/governance/account-policies', token);

export const updateAccountPolicies = (token: string, value: Record<string, unknown>) =>
  apiClient.patch<PolicyRecord>('/governance/account-policies', { value }, token);

export const fetchNotificationPolicies = (token: string) =>
  apiClient.get<PolicyRecord>('/governance/notification-policies', token);

export const updateNotificationPolicies = (token: string, value: Record<string, unknown>) =>
  apiClient.patch<PolicyRecord>('/governance/notification-policies', { value }, token);

export const fetchConfigurationHistory = (token: string, limit = 50, offset = 0) =>
  apiClient.get<{ items: AuditLogEntry[]; total: number }>(
    `/governance/configuration-history?limit=${limit}&offset=${offset}`, token,
  );
