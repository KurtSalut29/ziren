/**
 * Typed client for GET /geographic/operational-area — the whole Operational Area
 * screen in one payload. See ziren_backend/app/services/operational_area_service.py
 * for what each figure means and how it is scoped.
 */

import { apiClient } from './client';
import type { MapData } from './map';

/** n / average / median / 90th percentile / worst — minutes. All null when n = 0. */
export interface TimeStats {
  n: number;
  avg: number | null;
  p50: number | null;
  p90: number | null;
  max: number | null;
}

export type SeverityKey = 'critical' | 'high' | 'medium' | 'low' | 'untriaged';

export interface Kpis {
  incidents: number;
  /** null when the window is "all time" — there is no earlier period to compare with. */
  previous_incidents: number | null;
  active_now: number;
  awaiting_dispatch: number;
  critical: number;
  sos: number;
  resolved: number;
  cancelled: number;
  resolved_rate: number | null;
  false_alarms: number;
  dispatch: TimeStats;
  ack: TimeStats;
  resolution: TimeStats;
  dispatch_compliance: number | null;
  residents: number;
  verified_residents: number;
  pwd_residents: number;
  /** Aged 60 or over, on the Philippine date. */
  senior_residents: number;
  /** Under 12. */
  child_residents: number;
  /** PWD, senior or child — each resident counted once. */
  vulnerable_residents: number;
  new_residents: number | null;
  /** The same measures for the period before this one. null for "all time". */
  previous: PreviousPeriod | null;
}

export interface PreviousPeriod {
  incidents: number;
  critical: number;
  resolved_rate: number | null;
  dispatch_avg: number | null;
  ack_avg: number | null;
  resolution_avg: number | null;
  dispatch_compliance: number | null;
}

/** A place named by two or more reports — a pattern, not a one-off. */
export interface Hotspot {
  place: string;
  barangay: string | null;
  count: number;
  critical: number;
  top_category: string;
  last_at: string | null;
}

export interface TrendPoint {
  bucket: string;
  count: number;
  critical: number;
  high: number;
  /** critical + high, kept alongside them rather than replaced. */
  serious: number;
}
export interface Trend { unit: 'day' | 'week' | 'month'; points: TrendPoint[] }

export interface Mix {
  severity: Record<string, number>;
  categories: Record<string, number>;
  status: Record<string, number>;
  channels: Record<string, number>;
  multi_agency_signals: Record<string, number>;
}

export interface TimePatterns {
  /** [weekday 0=Mon..6=Sun][hour 0..23], Philippine time. */
  heatmap: number[][];
  by_hour: number[];
  by_weekday: number[];
  peak_hour: number | null;
  peak_weekday: number | null;
  total: number;
}

export interface SeverityResponse {
  severity: SeverityKey;
  n: number;
  dispatch: TimeStats;
  dispatch_target_min: number;
  on_time: number;
  late: number;
  awaiting: number;
  dispatch_compliance: number | null;
  ack: TimeStats;
  ack_deadline_min: number;
  ack_compliance: number | null;
  resolution: TimeStats;
}

export interface ResponseFigures {
  dispatch: TimeStats;
  ack: TimeStats;
  resolution: TimeStats;
  dispatch_compliance: number | null;
  by_severity: SeverityResponse[];
}

export interface Outcomes {
  counts: Record<string, number>;
  recorded: number;
  casualties: { injured: number; fatal: number; transported: number };
}

export interface BarangayRow {
  id: string;
  name: string;
  residents: number;
  verified: number;
  pwd: number;
  seniors: number;
  children: number;
  /** PWD, senior or child — each resident counted once. */
  vulnerable: number;
  resident_share: number;
  incidents: number;
  critical: number;
  active: number;
  incident_share: number;
  last_incident_at: string | null;
}

export interface Barangays {
  items: BarangayRow[];
  matched_incidents: number;
  unmatched_incidents: number;
  unlocated_incidents: number;
  empty_barangays: number;
}

export interface StationRow {
  id: string;
  name: string | null;
  address: string | null;
  agency_id: string | null;
  agency_name: string | null;
  agency_type: string | null;
  is_active: boolean;
  is_own: boolean;
  lat: number | null;
  lng: number | null;
  /** null for another agency's station — their incident data is not shown. */
  incidents: number | null;
  dispatch: TimeStats | null;
  last_incident_at: string | null;
}

export interface ResponderRow {
  id: string;
  full_name: string | null;
  badge_id: string | null;
  agency_type: string | null;
  approval_status: string | null;
  availability: string | null;
  has_location: boolean;
  location_updated_at: string | null;
  incidents: number;
  resolved: number;
  ack: TimeStats;
}

export interface Responders {
  approved: number;
  on_duty: number;
  off_duty: number;
  pending: number;
  roster: ResponderRow[];
}

export interface AgencyPresence {
  id: string;
  name: string;
  agency_type: string | null;
  contact_number: string | null;
  email: string | null;
  is_active: boolean;
  is_own: boolean;
  stations: number;
  mapped_stations: number;
  /** null for another agency — their incident data is not shown. */
  incidents: number | null;
}

export interface ReadinessCheck {
  key: string;
  status: 'ok' | 'warn' | 'info';
  title: string;
  detail: string;
  /** A route to fix it on. */
  href?: string;
  /** Or a tab of this same screen. */
  tab?: string;
}

export interface RecentIncident {
  id: string;
  record_number: string | null;
  category: string | null;
  severity: string | null;
  status: string | null;
  address: string | null;
  barangay: string | null;
  created_at: string;
  sos_flagged: boolean;
}

export interface ComparisonRow {
  municipality: string;
  barangays: number;
  residents: number;
  stations: number;
  responders: number;
  on_duty: number;
  incidents: number;
  critical: number;
  active: number;
}

/** The period and narrowing the payload was made for, as the server understood them. */
export interface AreaFilters {
  /** The rolling look-back in days (0 = all time); for a chosen range, its length in days. */
  days: number;
  barangay: string | null;
  since: string | null;
  /** Exclusive end of a chosen range; null for a rolling window. */
  until: string | null;
  /** First and last day, both included, of a range the reader chose — Philippine calendar days. Null for a rolling window. */
  date_from: string | null;
  date_to: string | null;
}

export interface OperationalArea {
  generated_at: string;
  area: {
    municipality: string;
    province: string | null;
    region: string | null;
    barangay_count: number;
    barangays: string[];
    agency: { id: string; name: string; agency_type: string | null; contact_number: string | null; email: string | null } | null;
  };
  filters: AreaFilters;
  kpis: Kpis;
  trend: Trend;
  mix: Mix;
  time_patterns: TimePatterns;
  response: ResponseFigures;
  outcomes: Outcomes;
  barangays: Barangays;
  hotspots: Hotspot[];
  stations: { items: StationRow[]; unassigned_incidents: number };
  responders: Responders;
  agencies: AgencyPresence[];
  readiness: ReadinessCheck[];
  recent: RecentIncident[];
  map: MapData & { incidents_shown: number; incidents_with_coordinates: number };
  /** Provincial Admin only. */
  comparison?: ComparisonRow[];
}

export interface OperationalAreaQuery {
  /** Provincial Admin only — an Agency Admin's is fixed by the server. */
  municipality?: string;
  barangay?: string | null;
  /** Look-back window in days; 0 = all time. Ignored when `range` is given. */
  days: number;
  /** A range the reader chose: 'YYYY-MM-DD' days, both included, Philippine time. Replaces `days`. */
  range?: { from: string; to: string } | null;
}

export function fetchOperationalArea(token: string, q: OperationalAreaQuery): Promise<OperationalArea> {
  // A chosen range replaces the look-back rather than joining it: sending both would
  // leave the reader guessing which one the server honoured.
  const p = q.range
    ? new URLSearchParams({ date_from: q.range.from, date_to: q.range.to })
    : new URLSearchParams({ days: String(q.days) });
  if (q.municipality) p.set('municipality', q.municipality);
  if (q.barangay) p.set('barangay', q.barangay);
  return apiClient.get<OperationalArea>(`/geographic/operational-area?${p.toString()}`, token);
}
