import { describe, expect, it, vi } from 'vitest';
import { fetchResponseRoute, formatDistance, geoPoint, roadWorthDrawing, straightLineRoute } from './response-route';

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

describe('road path only when it helps (the 11 m "V" route, 2026-10-05)', () => {
  it('close pairs are joined directly', () => {
    expect(roadWorthDrawing(0.011, 0.25)).toBe(false);
    expect(roadWorthDrawing(0.15, 0.16)).toBe(false);
  });
  it('a short hop made several times longer by the road snap is not drawn', () => {
    expect(roadWorthDrawing(0.3, 1.2)).toBe(false);
  });
  it('a real road route is kept, even a long detour over a ridge', () => {
    expect(roadWorthDrawing(0.3, 0.6)).toBe(true);
    expect(roadWorthDrawing(2, 14)).toBe(true);
  });
  it('a fetched route that is only a V falls back to the straight line', async () => {
    const from: [number, number] = [11.5645, 124.4031];
    const to: [number, number] = [11.5646, 124.4031]; // ~11 m
    const fake = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        routes: [{ distance: 4, duration: 2, geometry: { coordinates: [[124.4045, 11.5640], [124.4045, 11.5641]] } }],
      }),
    });
    vi.stubGlobal('fetch', fake);
    try {
      const r = await fetchResponseRoute(from, to);
      expect(r.source).toBe('straight-line');
      expect(r.path).toEqual([from, to]);
    } finally {
      vi.unstubAllGlobals();
    }
  });
  it('a kept road route starts and ends on the real points', async () => {
    const from: [number, number] = [11.56, 124.40];
    const to: [number, number] = [11.58, 124.42];
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        routes: [{ distance: 3500, duration: 400, geometry: { coordinates: [[124.4001, 11.5601], [124.41, 11.57], [124.4199, 11.5799]] } }],
      }),
    }));
    try {
      const r = await fetchResponseRoute(from, to);
      expect(r.source).toBe('road');
      expect(r.path[0]).toEqual(from);
      expect(r.path[r.path.length - 1]).toEqual(to);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
