import { readFileSync } from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { ASSUMED_SPEED_KMH, estimateEtaMinutes, geodesicM } from './geodesic';

// Evaluator finding #24: held to the same reference cases as the backend and
// the responder app (shared/geo_reference_cases.json at the repository root).
const cases = JSON.parse(
  readFileSync(path.resolve(__dirname, '../../../shared/geo_reference_cases.json'), 'utf-8'),
) as {
  assumed_speed_kmh: number;
  distance_tolerance_m: number;
  distances: { name: string; from: [number, number]; to: [number, number]; metres: number }[];
  eta: { km: number; minutes: number }[];
};

describe('distance matches the shared reference', () => {
  for (const c of cases.distances) {
    it(c.name, () => {
      expect(Math.abs(geodesicM(c.from, c.to) - c.metres)).toBeLessThanOrEqual(cases.distance_tolerance_m);
    });
  }
});

describe('ETA matches the shared reference', () => {
  it('uses the shared speed', () => expect(ASSUMED_SPEED_KMH).toBe(cases.assumed_speed_kmh));
  for (const c of cases.eta) {
    it(`${c.km} km -> ${c.minutes} min`, () => expect(estimateEtaMinutes(c.km)).toBe(c.minutes));
  }
  it('a NaN distance is 1 minute, never NaN', () => expect(estimateEtaMinutes(Number.NaN)).toBe(1));
});
