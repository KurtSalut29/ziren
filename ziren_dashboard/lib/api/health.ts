import { apiClient } from './client';

/** What GET /health reports. Every part is best-effort; see the endpoint. */
export interface HealthResponse {
  status: string;
  service?: string;
  triage?: {
    model_loaded: boolean;
    version: string;
    flag_threshold?: number | null;
    error?: string | null;
  };
  transcription?: {
    engine: string | null;
    version: string | null;
    available: boolean;
    reason: string | null;
  };
}

export const fetchHealth = (token: string) => apiClient.get<HealthResponse>('/health', token);

/** The dashboard's own version — kept in one place for About and Diagnostics. */
export const DASHBOARD_VERSION = '0.1.0';
