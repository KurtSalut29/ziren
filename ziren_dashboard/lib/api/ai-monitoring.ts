import { apiClient } from './client';

export interface AiCorrectionSample {
  incident_id: string;
  created_at: string;
  predicted: string | null;
  selected: string | null;
  result: string | null;
}

export interface AiMonitoringStats {
  model_version: string;
  model_status: 'active' | 'unavailable';
  total_classifications: number;
  confidence_distribution: Record<string, number>;
  verification_breakdown: Record<string, number>;
  sample_corrections: AiCorrectionSample[];
}

export const fetchAiMonitoringStats = (token: string) =>
  apiClient.get<AiMonitoringStats>('/ai-classification/stats', token);
