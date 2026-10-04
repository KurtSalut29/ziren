import { describe, expect, it } from 'vitest';
import { formatDistance, geoPoint, straightLineRoute } from './response-route';

describe('response route helpers', () => {
  it('a straight-line route uses the shared ETA (never 0 minutes)', () => {
    const r = straightLineRoute([11.5645, 124.4031], [11.5645, 124.4031]);
    expect(r.minutes).toBe(1);
    expect(r.source).toBe('straight-line');
  });
  it('reads a PostGIS GeoJSON point as [lat, lng]', () => {
    expect(geoPoint({ type: 'Point', coordinates: [124.4, 11.56] })).toEqual([11.56, 124.4]);
    expect(geoPoint(null)).toBeNull();
  });
  it('formats short and long distances differently', () => {
    expect(formatDistance(0.45)).not.toBe(formatDistance(12.3));
  });
});
