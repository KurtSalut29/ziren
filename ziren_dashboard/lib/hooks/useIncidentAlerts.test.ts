import { describe, expect, it } from 'vitest';
import type { QueueIncident } from '@/lib/api/dispatch';
import { decideAlerts, type NotificationRules } from './useIncidentAlerts';

// Evaluator finding #25: what sounds the alarm is unit-tested.
const ALL: NotificationRules = { critical: true, high: true, medium: true, low: true };

function inc(id: string, severity: string | null): QueueIncident {
  return {
    id, severity, suggested_severity: null, report_text: 'Fire', location_address: 'Naval',
    incident_category: 'fire', sos_flagged: false, created_at: '2026-10-05T00:00:00Z',
    stations: { agencies: { agency_type: 'BFP' } },
  } as unknown as QueueIncident;
}

describe('decideAlerts', () => {
  it('announces each new report once, never again on the next poll', () => {
    const seen = new Set<string>();
    expect(decideAlerts([inc('a', 'high')], seen, ALL).fresh.map(a => a.id)).toEqual(['a']);
    expect(decideAlerts([inc('a', 'high')], seen, ALL).fresh).toEqual([]);
  });

  it('respects a severity the agency switched off, but still lists it as arrived', () => {
    const { fresh, arrived } = decideAlerts([inc('b', 'low')], new Set(), { ...ALL, low: false });
    expect(fresh).toEqual([]);
    expect(arrived).toEqual(['b']);
  });

  it('always alerts on an unscored report, whatever the rules say', () => {
    const none: NotificationRules = { critical: false, high: false, medium: false, low: false };
    const { fresh } = decideAlerts([inc('c', null)], new Set(), none);
    expect(fresh).toHaveLength(1);
    expect(fresh[0].severity).toBe('untriaged');
  });

  it('keeps every report in a burst (no cap)', () => {
    const burst = Array.from({ length: 12 }, (_, i) => inc(`x${i}`, 'critical'));
    expect(decideAlerts(burst, new Set(), ALL).fresh).toHaveLength(12);
  });
});
