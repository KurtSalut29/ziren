/**
 * Distance between two points on the ground, on the WGS-84 ellipsoid.
 *
 * The dashboard, the backend and the responder app must quote the SAME distance
 * for the same pair of points, so this is a port of `app/core/geo.py`, not a
 * second opinion. See that file for the whole argument; the short version:
 *
 *   Haversine treats the Earth as a sphere. At Biliran's latitude a degree of
 *   latitude is about half a percent shorter than that sphere says, so every
 *   north-south leg came out ~50 m too long per 10 km. Vincenty's inverse formula
 *   on the WGS-84 ellipsoid (the model GPS reports in, and the one PostGIS uses)
 *   is accurate to half a millimetre.
 *
 * Vincenty can fail to converge for nearly antipodal points - impossible inside
 * one province, but a dispatch screen must not throw over it - so those pairs fall
 * back to Haversine.
 *
 * Straight-line (geodesic) distance is still a lower bound on the drive. Where a
 * road matters the dashboard asks a routing service (see response-route.ts) and
 * says which of the two it is showing.
 */

/** [latitude, longitude], in the order humans read them - NOT GeoJSON order. */
export type LatLng = [number, number];

const A = 6378137.0; // WGS-84 semi-major axis, metres
const F = 1 / 298.257223563; // flattening
const B = A * (1 - F); // semi-minor axis
const MEAN_RADIUS_M = 6371008.7714; // IUGG mean radius, fallback only

const rad = (deg: number) => (deg * Math.PI) / 180;

export function validCoordinates(lat: unknown, lng: unknown): boolean {
  return (
    typeof lat === 'number' && typeof lng === 'number' &&
    Number.isFinite(lat) && Number.isFinite(lng) &&
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
  );
}

/** Spherical great-circle distance in metres. A fallback and a cheap pre-filter. */
export function haversineM(a: LatLng, b: LatLng): number {
  const dPhi = rad(b[0] - a[0]);
  const dLmb = rad(b[1] - a[1]);
  const h =
    Math.sin(dPhi / 2) ** 2 +
    Math.cos(rad(a[0])) * Math.cos(rad(b[0])) * Math.sin(dLmb / 2) ** 2;
  return 2 * MEAN_RADIUS_M * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

/**
 * Shortest distance in metres between two points on the WGS-84 ellipsoid
 * (Vincenty's inverse formula, iterated to 1e-12 rad). Returns NaN for a
 * coordinate that is not a real latitude/longitude, so a caller that formats it
 * shows a dash rather than a confident wrong number.
 */
export function geodesicM(p1: LatLng, p2: LatLng): number {
  const [lat1, lon1] = p1;
  const [lat2, lon2] = p2;
  if (!validCoordinates(lat1, lon1) || !validCoordinates(lat2, lon2)) return NaN;
  if (lat1 === lat2 && lon1 === lon2) return 0;

  const L = rad(lon2 - lon1);
  const U1 = Math.atan((1 - F) * Math.tan(rad(lat1)));
  const U2 = Math.atan((1 - F) * Math.tan(rad(lat2)));
  const sinU1 = Math.sin(U1), cosU1 = Math.cos(U1);
  const sinU2 = Math.sin(U2), cosU2 = Math.cos(U2);

  let lam = L;
  let sinSigma = 0, cosSigma = 0, sigma = 0, cosSqAlpha = 0, cos2SigmaM = 0;
  let converged = false;
  for (let i = 0; i < 200; i++) {
    const sinLam = Math.sin(lam), cosLam = Math.cos(lam);
    sinSigma = Math.hypot(
      cosU2 * sinLam,
      cosU1 * sinU2 - sinU1 * cosU2 * cosLam,
    );
    if (sinSigma === 0) return 0; // coincident points
    cosSigma = sinU1 * sinU2 + cosU1 * cosU2 * cosLam;
    sigma = Math.atan2(sinSigma, cosSigma);
    const sinAlpha = (cosU1 * cosU2 * sinLam) / sinSigma;
    cosSqAlpha = 1 - sinAlpha * sinAlpha;
    // cosSqAlpha is 0 only on the equator; the term is then defined as 0.
    cos2SigmaM = cosSqAlpha !== 0 ? cosSigma - (2 * sinU1 * sinU2) / cosSqAlpha : 0;
    const C = (F / 16) * cosSqAlpha * (4 + F * (4 - 3 * cosSqAlpha));
    const prev = lam;
    lam =
      L +
      (1 - C) * F * sinAlpha *
        (sigma + C * sinSigma * (cos2SigmaM + C * cosSigma * (-1 + 2 * cos2SigmaM ** 2)));
    if (Math.abs(lam - prev) < 1e-12) {
      converged = true;
      break;
    }
  }
  if (!converged) return haversineM(p1, p2); // nearly antipodal

  const uSq = (cosSqAlpha * (A * A - B * B)) / (B * B);
  const bigA = 1 + (uSq / 16384) * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)));
  const bigB = (uSq / 1024) * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)));
  const deltaSigma =
    bigB * sinSigma *
    (cos2SigmaM +
      (bigB / 4) *
        (cosSigma * (-1 + 2 * cos2SigmaM ** 2) -
          (bigB / 6) * cos2SigmaM * (-3 + 4 * sinSigma ** 2) * (-3 + 4 * cos2SigmaM ** 2)));
  return B * bigA * (sigma - deltaSigma);
}

export function geodesicKm(a: LatLng, b: LatLng): number {
  return geodesicM(a, b) / 1000;
}

/** Assumed average road speed. Keep equal to ASSUMED_SPEED_KMH in app/core/geo.py. */
export const ASSUMED_SPEED_KMH = 30;

/**
 * Minutes to cover `km` at the assumed road speed, rounded UP and never 0 - the
 * same model as `estimate_eta_minutes` in the backend and the responder app, so
 * nobody is quoted two different ETAs for one trip. Capped at the database
 * column's ceiling. A NaN distance gives 1, never NaN.
 */
export function estimateEtaMinutes(km: number): number {
  const safe = Number.isFinite(km) ? Math.max(0, km) : 0;
  return Math.max(1, Math.min(600, Math.floor((safe / ASSUMED_SPEED_KMH) * 60) + 1));
}
