/**
 * The road between a station and an incident, and how long it takes.
 *
 * WHY THIS IS NOT JUST A STRAIGHT LINE
 *
 * A dispatcher deciding whether to send the Naval crew or the Caibiran one is
 * asking a road question, and Biliran's roads wrap a mountain. Two barangays
 * 2 km apart across the ridge are a 40-minute drive apart, and a straight line
 * drawn between them on a map states the opposite with total confidence.
 *
 * So this asks OSRM — the public routing service over the same OpenStreetMap
 * data the tiles come from — for the actual driving geometry, and falls back
 * to the straight line only when it cannot.
 *
 * THE FALLBACK IS LABELLED, ALWAYS. `source` travels with every result and the
 * caller is expected to draw the two differently, because they are different
 * claims: 'road' is a measured route, 'straight-line' is a lower bound that
 * ignores every river and ridge in between. Presenting the second as the first
 * is how a console tells a dispatcher a barangay is six minutes away when it
 * is on the far side of Mount Panamao.
 *
 * The straight-line numbers match the backend exactly: the distance is the
 * ellipsoidal (Vincenty, WGS-84) one from app/core/geo.py rather than the
 * spherical Haversine this used to use, and the ETA is the same model as
 * responder_ops_service.refresh_eta - 30 km/h, rounded up, never zero - so the
 * dashboard and the responder app never quote a resident two different ETAs for
 * the same pair of points.
 */

import { formatDistanceKm } from '@/lib/format/geo';
import { estimateEtaMinutes, geodesicKm, type LatLng } from '@/lib/geo/geodesic';
import { mapPrefs } from '@/lib/prefs/definitions';

/** [lat, lng], in the order humans read them — NOT GeoJSON order. */
export type { LatLng };

export interface ResponseRoute {
  /** The line to draw, station → incident. Two points when straight-line. */
  path: LatLng[];
  distanceKm: number;
  /** Whole minutes, rounded up. Never 0 — "0 min away" reads as "arrived". */
  minutes: number;
  /** The road that carries most of the route, when the router names one. */
  via: string | null;
  source: 'road' | 'straight-line';
}

/** Public demo server, per the OSRM project's own usage terms: light use. */
const OSRM_BASE = 'https://router.project-osrm.org/route/v1/driving';

/** Beyond this the dispatcher has waited long enough — draw the line instead. */
const ROUTE_TIMEOUT_MS = 6000;

/** Within this, no road path is drawn: the two points are joined directly. */
export const NEARBY_KM = 0.15;

/**
 * Whether a road path is worth drawing between two points `straightKm` apart,
 * when following it (joined back onto both real points) is `pathKm` long.
 *
 * OSRM starts and ends on the nearest ROAD. Two points close to each other but
 * not to a road get a "route" down to the road and straight back up - a V,
 * labelled as a road, several times the walk between them (a responder 11 m
 * from the scene saw this in the app, 2026-10-05). Same rule as the mobile
 * RoadRoute.worthDrawing.
 */
export function roadWorthDrawing(straightKm: number, pathKm: number): boolean {
  if (straightKm <= NEARBY_KM) return false;
  if (straightKm < 0.5 && pathKm > straightKm * 3) return false;
  return true;
}

/** Straight line, assumed speed, rounded up. The honest floor on a journey. */
export function straightLineRoute(from: LatLng, to: LatLng): ResponseRoute {
  const distanceKm = geodesicKm(from, to);
  return {
    path: [from, to],
    distanceKm,
    minutes: estimateEtaMinutes(distanceKm),
    via: null,
    source: 'straight-line',
  };
}

/**
 * Ask OSRM for the driving route; return the straight line if anything fails.
 *
 * Never throws and never rejects. A routing service being down is not a reason
 * for an incident panel to show an error where a map should be — the straight
 * line is still true, it just claims less, and the caller says which it got.
 */
export async function fetchResponseRoute(
  from: LatLng,
  to: LatLng,
  signal?: AbortSignal,
): Promise<ResponseRoute> {
  const fallback = straightLineRoute(from, to);

  // OSRM takes lng,lat — the GeoJSON order, the reverse of everything above.
  const coords = `${from[1]},${from[0]};${to[1]},${to[0]}`;
  const url = `${OSRM_BASE}/${coords}?overview=full&geometries=geojson&steps=true`;

  // Two abort sources: our own timeout, and the caller closing the dialog.
  // AbortSignal.any would say this in one line but is too new to rely on here.
  const timer = new AbortController();
  const timeout = setTimeout(() => timer.abort(), ROUTE_TIMEOUT_MS);
  const onCallerAbort = () => timer.abort();
  signal?.addEventListener('abort', onCallerAbort);

  try {
    const res = await fetch(url, { signal: timer.signal });
    if (!res.ok) return fallback;

    const body = (await res.json()) as OsrmResponse;
    const route = body.routes?.[0];
    const line = route?.geometry?.coordinates;
    if (!route || !Array.isArray(line) || line.length < 2) return fallback;

    // Back from GeoJSON [lng, lat] to this module's [lat, lng].
    const road = line.map(([lng, lat]) => [lat, lng] as LatLng);
    // OSRM's path stops on the nearest road at both ends; the real points are
    // joined back on so the line starts at the station and ends on the scene.
    const pathKm =
      geodesicKm(from, road[0]) + route.distance / 1000 + geodesicKm(road[road.length - 1], to);
    if (!roadWorthDrawing(fallback.distanceKm, pathKm)) return fallback;

    return {
      path: [from, ...road, to],
      distanceKm: route.distance / 1000,
      minutes: Math.max(1, Math.ceil(route.duration / 60)),
      via: longestNamedStep(route),
      source: 'road',
    };
  } catch {
    // Offline, blocked, timed out, or the caller closed the dialog. All four
    // mean the same thing to the panel: draw what we can prove.
    return fallback;
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener('abort', onCallerAbort);
  }
}

/**
 * The road the crew spends the most of the drive on.
 *
 * Not the first step, which is usually the few metres of station forecourt,
 * and not the last, which is the barangay lane at the far end. "via Naval–
 * Caibiran Road" is the phrase a dispatcher would use on the radio; the
 * forecourt is not.
 */
function longestNamedStep(route: OsrmRoute): string | null {
  let best: { name: string; distance: number } | null = null;
  for (const leg of route.legs ?? []) {
    for (const step of leg.steps ?? []) {
      const name = (step.name ?? '').trim();
      if (!name) continue;
      if (!best || step.distance > best.distance) {
        best = { name, distance: step.distance };
      }
    }
  }
  return best?.name ?? null;
}

/* ── The slice of OSRM's response this file reads ─────────────────────────── */

interface OsrmStep { name?: string; distance: number }
interface OsrmLeg { steps?: OsrmStep[] }
interface OsrmRoute {
  distance: number;
  duration: number;
  geometry?: { coordinates?: [number, number][] };
  legs?: OsrmLeg[];
}
interface OsrmResponse { routes?: OsrmRoute[] }

/**
 * Pull [lat, lng] out of a PostGIS point as PostgREST sends it.
 *
 * GeoJSON is [lng, lat]. Reading it the other way round puts every station in
 * Biliran somewhere off the coast of Somalia — the same trap the coverage page
 * documents, which is why the unpacking lives in one place now.
 *
 * Typed `unknown` because that is honestly what the API hands over for a
 * station's location: the column is nullable, and a station nobody has placed
 * yet arrives as null.
 */
export function geoPoint(value: unknown): LatLng | null {
  if (!value || typeof value !== 'object') return null;
  const coords = (value as { coordinates?: unknown }).coordinates;
  if (!Array.isArray(coords) || coords.length < 2) return null;
  const [lng, lat] = coords;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return [lat, lng];
}

/** "2.4 km" above a kilometre, "780 m" below it — never "0.8 km". */
export function formatDistance(km: number): string {
  // Kilometres or miles, per Settings → Map & Location. Read at the moment of
  // drawing: this is a plain function called from render, and a change of unit
  // is made on the Settings page, so the next screen to draw already sees it.
  return formatDistanceKm(km, mapPrefs.get());
}
