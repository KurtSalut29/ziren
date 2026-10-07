import { describe, expect, it } from 'vitest';
import type { QueueIncident } from '@/lib/api/dispatch';
import { decideAlerts, seedKnown, type NotificationRules } from './useIncidentAlerts';

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

describe('seedKnown (a console opening for the first time)', () => {
  const now = Date.parse('2026-10-07T10:00:00Z');
  const at = (id: string, status: string, minsAgo: number) => ({
    ...inc(id, 'high'), status, created_at: new Date(now - minsAgo * 60_000).toISOString(),
  }) as QueueIncident;

  it('does not alert for what has been waiting a while', () => {
    const queue = [at('old', 'received', 45), at('enroute', 'dispatched', 3)];
    const seen = seedKnown(queue, now);
    expect(decideAlerts(queue, seen, ALL).fresh).toEqual([]);
  });

  it('still alerts for a report that arrived minutes ago and is waiting', () => {
    // Tester report 2026-10-07: landed while the dispatcher was opening
    // Incident Management; the page's strip said "just arrived" and no alert
    // appeared on any page.
    const queue = [at('old', 'received', 45), at('new', 'received', 2), at('triage', 'processing', 9)];
    const seen = seedKnown(queue, now);
    expect(decideAlerts(queue, seen, ALL).fresh.map(a => a.id).sort()).toEqual(['new', 'triage']);
    // ...and only once.
    expect(decideAlerts(queue, seen, ALL).fresh).toEqual([]);
  });
});
