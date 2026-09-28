import { apiClient } from './client';

export interface IncidentAnalytics {
  total: number;
  by_period: { bucket: string; count: number }[];
  by_municipality: Record<string, number>;
  by_agency: Record<string, number>;
  by_type: Record<string, number>;
  by_severity: Record<string, number>;
  resolved_vs_unresolved: { resolved: number; unresolved: number };
  avg_resolution_minutes: number | null;
}

export interface UserAnalytics {
  total_by_role: Record<string, number>;
  registration_trend: Record<string, { month: string; count: number }[]>;
  by_municipality: Record<string, number>;
  by_barangay: Record<string, number>;
}

export const fetchIncidentAnalytics = (token: string, period: 'day' | 'month' | 'year' = 'month') =>
  apiClient.get<IncidentAnalytics>(`/analytics/incidents?period=${period}`, token);

export const fetchUserAnalytics = (token: string) =>
  apiClient.get<UserAnalytics>('/analytics/users', token);
