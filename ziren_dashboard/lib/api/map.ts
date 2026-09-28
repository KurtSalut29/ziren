/**
 * Typed API calls for the map data endpoint.
 */

import { apiClient } from './client';

export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low';
export type AgencyType    = 'BFP' | 'PNP' | 'MDRRMO';

export interface MapIncident {
  id:          string;
  lng:         number;
  lat:         number;
  severity:    SeverityLevel | null;
  status:      string;
  sos_flagged: boolean;
  agency_type: AgencyType | null;
  agency_id:   string | null;
  report_text: string;
  created_at:  string;
  /** Only populated on the history view. */
  resolved_at?: string | null;
  /** Always null — no view of this map ever computes an operational route. */
  route?: null;
}

/**
 * Provincial Admin only — an Agency Admin's map is always "operational" and
 * never sends this. "network" and "history" are the spec's Section 7A/7B
 * Ziren Network Map / Incident History Map.
 */
export type MapView = 'operational' | 'network' | 'history';

export interface CoveragePolygon {
  agency_id:    string;
  name:         string;
  agency_type:  AgencyType;
  municipality: string;
  /** Raw GeoJSON Polygon object returned by PostgREST */
  geojson: {
    type:        'Polygon';
    coordinates: number[][][];
  };
}

export interface MapResponder {
  id:           string;
  full_name:    string | null;
  badge_id:     string | null;
  availability: 'on_duty' | 'off_duty';
  agency_type:  AgencyType | null;
  lat:          number | null;
  lng:          number | null;
}

/**
 * Where an agency physically is.
 *
 * Distinct from CoveragePolygon in kind, not just in shape. A station carries
 * surveyed coordinates — BFP, PNP and MDRRMO in Naval sit on three points a
 * few metres apart — while the coverage polygon is one 8km rectangle migration
 * 002 seeded per municipality and shared verbatim between all three of its
 * agencies. One is a fact; the other is a placeholder for a boundary nobody
 * has drawn.
 */
export interface MapStation {
  id: string;
  name: string;
  address: string | null;
  agency_type: AgencyType | null;
  agency_name: string | null;
  municipality: string | null;
  lat: number;
  lng: number;
}

export interface MapData {
  incidents:         MapIncident[];
  coverage_polygons: CoveragePolygon[];
  responders:        MapResponder[];
  /** Only stations with coordinates. One without is counted, never pinned. */
  stations:          MapStation[];
}

export async function fetchMapData(token: string, view: MapView = 'operational'): Promise<MapData> {
  const query = view === 'operational' ? '' : `?view=${view}`;
  return apiClient.get<MapData>(`/map/data${query}`, token);
}
