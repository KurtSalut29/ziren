import { apiClient } from './client';

export interface ServiceCheck {
  name: string;
  status: 'operational' | 'down';
  latency_ms: number;
  detail: string | null;
}

export interface SystemStatus {
  checks: ServiceCheck[];
  all_operational: boolean;
}

export const fetchSystemStatus = (token: string) =>
  apiClient.get<SystemStatus>('/system-status/', token);
