/**
 * Shared TypeScript types for incidents.
 * Mirrors ziren_backend/app/models/incident.py — keep in sync.
 *
 * NOTE: nothing in the app imports this file today. The types the dashboard
 * actually renders from are `QueueIncident` / `IncidentDetail` in
 * lib/api/dispatch.ts, because the dashboard talks to /dispatch/queue, not to
 * /incidents (which is the mobile app's endpoint). Treat this file as a
 * reference mirror of the backend models, and change dispatch.ts when you
 * change what the dashboard displays.
 */

export type IncidentStatus = 'received' | 'processing' | 'dispatched' | 'resolved' | 'cancelled';
export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low';
export type AgencyType = 'BFP' | 'PNP' | 'MDRRMO';
export type SubmissionChannel = 'internet' | 'offline_sync' | 'sos';

/**
 * The 15-signal vocabulary the rubric engine evaluates against.
 *
 * This is NOT the shape of `incidents.signals` any more. Phase 4 replaced the
 * placeholder pipeline with the trained triage model, which writes its own
 * richer payload — see `TriageSignals` in lib/api/dispatch.ts and
 * `TriageSignals` in ziren_backend/app/models/incident.py. This interface
 * survives because the rubric's condition vocabulary still uses these names.
 */
export interface ExtractedSignals {
  incident_type: string | null;        // Signal 1
  fire_type: string | null;            // Signal 2
  casualty_mentioned: boolean;          // Signal 3
  injured_count: number | null;         // Signal 4
  dead_count: number | null;            // Signal 5
  weapon_mentioned: boolean;            // Signal 6
  weapon_type: string | null;           // Signal 7
  why_category: string | null;          // Signal 8
  how_category: string | null;          // Signal 9
  structure_type: string | null;        // Signal 10
  children_involved: boolean;           // Signal 11
  urgency_level: string | null;         // Signal 12
  location_specificity: string | null;  // Signal 13
  multi_agency_needed: boolean;         // Signal 14
  language_detected: string | null;     // Signal 15
  confidence_score: number;             // 0–1; low = flagged for review
}

export interface Incident {
  id: string;
  reporter_id: string;
  report_text: string;
  location_address: string | null;
  latitude: number | null;
  longitude: number | null;
  status: IncidentStatus;
  severity: SeverityLevel | null;
  suggested_agency_id: string | null;
  assigned_agency_id: string | null;
  /** Triage-model output. See TriageSignals in lib/api/dispatch.ts. */
  signals: Record<string, unknown> | null;
  signals_confidence: number | null;
  submitted_via: SubmissionChannel;
  created_at: string;   // ISO 8601
  updated_at: string;
  dispatched_at: string | null;
  resolved_at: string | null;
}

export interface Agency {
  id: string;
  name: string;
  agency_type: AgencyType;
  municipality: string;
  province: string;
  region: string;
  contact_number: string | null;
  is_active: boolean;
}

export interface DispatchLogEntry {
  id: string;
  incident_id: string;
  dispatcher_id: string;
  agency_id: string;
  suggested_severity: SeverityLevel | null;
  chosen_severity: SeverityLevel;
  was_override: boolean;
  override_reason: string | null;
  action: 'dispatched' | 'resolved' | 'cancelled' | 'reassigned';
  notes: string | null;
  created_at: string;
}
