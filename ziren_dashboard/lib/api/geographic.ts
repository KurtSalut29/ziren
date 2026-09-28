import { apiClient } from './client';

export interface GeographicOverview {
  municipality: string;
  barangay: string | null;
  registered_residents: number;
  registered_responders: number;
  agency_stations: { id: string; name: string; agency_type: string }[];
  nearby_agencies: string[];
  incident_count: number;
  incident_types: Record<string, number>;
  resolved_incidents: number;
  active_incidents: number;
  historical_activity: { month: string; count: number }[];
}

export interface MunicipalityOption {
  name: string;
  resident_count: number;
}

export const fetchMunicipalities = (token: string) =>
  apiClient.get<MunicipalityOption[]>('/geographic/municipalities', token);

export const fetchGeographicOverview = (token: string, municipality: string, barangay?: string) =>
  apiClient.get<GeographicOverview>(
    `/geographic/overview?municipality=${encodeURIComponent(municipality)}` +
      (barangay ? `&barangay=${encodeURIComponent(barangay)}` : ''),
    token,
  );
