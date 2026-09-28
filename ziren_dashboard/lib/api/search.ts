import { apiClient } from './client';

export interface SearchHit {
  id: string;
  label: string;
  sublabel: string | null;
  link: string;
}

export interface SearchResults {
  residents: SearchHit[];
  responders: SearchHit[];
  agency_admins: SearchHit[];
  stations: SearchHit[];
  incidents: SearchHit[];
  barangays: SearchHit[];
  municipalities: SearchHit[];
}

export const GROUP_LABELS: Record<keyof SearchResults, string> = {
  residents: 'Residents',
  responders: 'Responders',
  agency_admins: 'Agency Admins',
  stations: 'Stations',
  incidents: 'Incidents',
  barangays: 'Barangays',
  municipalities: 'Municipalities',
};

export const globalSearch = (token: string, q: string) =>
  apiClient.get<SearchResults>(`/search/?q=${encodeURIComponent(q)}`, token);
