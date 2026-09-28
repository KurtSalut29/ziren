/**
 * Distances and coordinates, in the units the operator chose (Settings → Map &
 * Location). Kept apart from datetime.ts because they read a different group of
 * preferences and are used by different screens.
 */

import { MAP_DEFAULTS, type MapPrefs } from '@/lib/prefs/definitions';

const KM_PER_MILE = 1.609344;

/** A distance given in kilometres, shown in km or miles, with sensible rounding. */
export function formatDistanceKm(km: number, prefs: MapPrefs = MAP_DEFAULTS): string {
  if (!Number.isFinite(km)) return '—';
  if (prefs.units === 'mi') {
    const mi = km / KM_PER_MILE;
    return mi < 0.1 ? '<0.1 mi' : `${mi < 10 ? mi.toFixed(1) : Math.round(mi)} mi`;
  }
  if (km < 1) return `${Math.round(km * 1000)} m`;
  return `${km < 10 ? km.toFixed(1) : Math.round(km)} km`;
}

function dms(value: number, pos: string, neg: string): string {
  const hemi = value >= 0 ? pos : neg;
  const abs = Math.abs(value);
  const deg = Math.floor(abs);
  const minFloat = (abs - deg) * 60;
  const min = Math.floor(minFloat);
  const sec = (minFloat - min) * 60;
  return `${deg}°${String(min).padStart(2, '0')}′${sec.toFixed(1).padStart(4, '0')}″ ${hemi}`;
}

/** "11.56123, 124.42345" or "11°33′40.4″ N, 124°25′24.4″ E". */
export function formatCoordinates(
  lat: number,
  lon: number,
  prefs: MapPrefs = MAP_DEFAULTS,
): string {
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return '—';
  return prefs.coordFormat === 'dms'
    ? `${dms(lat, 'N', 'S')}, ${dms(lon, 'E', 'W')}`
    : `${lat.toFixed(5)}, ${lon.toFixed(5)}`;
}
