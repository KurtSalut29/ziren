/**
 * Typed API calls for the rubric configuration endpoints — Phase 6A.4.
 *
 * All functions require an admin access token.
 * Agency Admins are further scoped server-side via _assert_agency_scope().
 * Never expose upload/activate to Resident or Responder tokens.
 */

import { apiClient } from './client';

// ── Types ────────────────────────────────────────────────────

export type AgencyType = 'BFP' | 'PNP' | 'MDRRMO';
export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low';
export type AuditEventType =
  | 'config_created'
  | 'config_activated'
  | 'config_deactivated'
  | 'rule_updated'
  | 'fallback_to_seed';

export interface RubricCondition {
  incident_type?: string | null;
  incident_type_in?: string[] | null;
  fire_type?: string | null;
  fire_type_in?: string[] | null;
  casualty_mentioned?: boolean | null;
  injured_count_gte?: number | null;
  injured_count_lte?: number | null;
  dead_count_gte?: number | null;
  weapon_mentioned?: boolean | null;
  weapon_type_in?: string[] | null;
  children_involved?: boolean | null;
  urgency_level_in?: string[] | null;
  structure_type_in?: string[] | null;
  multi_agency_needed?: boolean | null;
  why_category_in?: string[] | null;
  how_category_in?: string[] | null;
  incident_category_in?: string[] | null;
}

export interface RubricRule {
  rule_id: string;
  description: string;
  conditions: RubricCondition;
  severity_contribution: SeverityLevel;
  recommended_agency: AgencyType | null;
  provenance: string;
  active: boolean;
}

export interface RubricConfigSummary {
  id: string;
  agency_type: AgencyType;
  version: string;
  is_active: boolean;
  created_by: string;
  activated_by: string | null;
  activated_at: string | null;
  created_at: string;
}

export interface RubricConfigDetail extends RubricConfigSummary {
  rules: RubricRule[];
}

export interface RubricAuditEntry {
  id: string;
  event_type: AuditEventType;
  agency_type: AgencyType;
  rubric_config_id: string | null;
  config_version: string | null;
  rule_id: string | null;
  previous_value: Record<string, unknown> | null;
  new_value: Record<string, unknown> | null;
  actor_id: string | null;
  notes: string | null;
  created_at: string;
}

// ── API wrappers ─────────────────────────────────────────────

/** List all config versions for an agency (no rules in response). */
export async function listConfigs(
  agencyType: AgencyType,
  token: string,
): Promise<RubricConfigSummary[]> {
  return apiClient.get<RubricConfigSummary[]>(`/rubric/${agencyType}/configs`, token);
}

/** Get the active config with full rule list. Returns null on 404 (seed fallback). */
export async function getActiveConfig(
  agencyType: AgencyType,
  token: string,
): Promise<RubricConfigDetail | null> {
  try {
    return await apiClient.get<RubricConfigDetail>(`/rubric/${agencyType}/configs/active`, token);
  } catch (e: unknown) {
    // 404 means no DB config — engine is using seed fallback
    if (e instanceof Error && e.message.startsWith('No active rubric config')) return null;
    throw e;
  }
}

/** Get a specific config version with full rule list. */
export async function getConfig(
  agencyType: AgencyType,
  configId: string,
  token: string,
): Promise<RubricConfigDetail> {
  return apiClient.get<RubricConfigDetail>(`/rubric/${agencyType}/configs/${configId}`, token);
}

/** Upload a new config version (does NOT activate automatically). */
export async function uploadConfig(
  agencyType: AgencyType,
  payload: { version: string; rules: RubricRule[] },
  token: string,
): Promise<RubricConfigDetail> {
  return apiClient.post<RubricConfigDetail>(`/rubric/${agencyType}/configs`, payload, token);
}

/** Activate a config version. Deactivates the current active version. */
export async function activateConfig(
  agencyType: AgencyType,
  configId: string,
  reason: string | null,
  token: string,
): Promise<RubricConfigDetail> {
  return apiClient.post<RubricConfigDetail>(
    `/rubric/${agencyType}/configs/${configId}/activate`,
    { reason },
    token,
  );
}

/** Fetch audit log entries for an agency (newest first). */
export async function getAuditLog(
  agencyType: AgencyType,
  token: string,
  limit = 50,
): Promise<RubricAuditEntry[]> {
  return apiClient.get<RubricAuditEntry[]>(
    `/rubric/${agencyType}/audit-log?limit=${limit}`,
    token,
  );
}
