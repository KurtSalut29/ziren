'use client';

/**
 * StationLocationPicker — put a station exactly where it stands.
 *
 * Two ways in, because the two people who would use this are in different
 * places. Someone sitting AT the station taps "Use my current location" and is
 * done. Someone in a provincial office correcting a record for a station they
 * have never visited drags a pin on a map. Typing decimal degrees, which is
 * what this app offered before, serves neither of them.
 *
 * WHAT IT REFUSES TO HIDE
 *
 * A browser's location is not a survey. It can be a cell-tower fix hundreds of
 * metres wide, and indoors it usually is. The accuracy radius comes back with
 * every fix and is drawn to scale on the map, so a 400 m circle looks like
 * what it is rather than resolving to a confident-looking pin. The operator is
 * always the one who commits it.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import type { Marker } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { Crosshair, LoaderCircle, MapPin, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';
import { Fig } from '@/components/ui/fig';
import { useTokenColors } from '@/lib/theme/use-token-colors';
import { MAP_COLOR_TOKENS } from './map-legend';
import { teardropSvg } from './map-markers';
import { removeGeoJson, upsertGeoJson, useMapLibre } from './use-maplibre';

/**
 * Biliran, generously boxed.
 *
 * Used to WARN, never to block. A pin outside this is almost certainly a typo
 * or a bad GPS fix, and a station in the wrong province misroutes every report
 * near it — but the province edge is fuzzy, and refusing a legitimate point
 * with no explanation is worse than flagging a suspicious one.
 */
const BILIRAN_BOUNDS = { minLat: 11.3, maxLat: 12.0, minLng: 124.2, maxLng: 124.8 };

const inProvince = (lat: number, lng: number) =>
  lat >= BILIRAN_BOUNDS.minLat && lat <= BILIRAN_BOUNDS.maxLat &&
  lng >= BILIRAN_BOUNDS.minLng && lng <= BILIRAN_BOUNDS.maxLng;

/** Anything looser than this is worth saying out loud before it is committed. */
const ACCURACY_WARN_M = 50;

const ACCURACY_SRC = 'z-accuracy';
const ACCURACY_LAYERS = ['z-accuracy-fill', 'z-accuracy-line'];

/** A circle of `radiusM` metres around a point, as a 64-sided polygon. */
function circlePolygon(lat: number, lng: number, radiusM: number): GeoJSON.Feature<GeoJSON.Polygon> {
  const dLat = radiusM / 111_320;
  const dLng = radiusM / (111_320 * Math.cos((lat * Math.PI) / 180));
  const ring: [number, number][] = [];
  for (let i = 0; i <= 64; i++) {
    const a = (i / 64) * 2 * Math.PI;
    ring.push([lng + dLng * Math.cos(a), lat + dLat * Math.sin(a)]);
  }
  return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } };
}

export interface PickedPoint {
  lat: number;
  lng: number;
  /** Metres, from the device. Null when the point was placed by hand. */
  accuracy: number | null;
}

export function StationLocationPicker({
  initial,
  agencyType,
  onChange,
}: {
  initial: { lat: number; lng: number } | null;
  agencyType: string | null;
  onChange: (p: PickedPoint | null) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  // Streets, always: placing a pin on a building is a job for a map that
  // shows buildings and road names, whatever the Incident Map is set to.
  const { map, maplibre, styleEpoch } = useMapLibre(containerRef, {
    center: initial ? [initial.lng, initial.lat] : undefined,
    zoom: initial ? 16 : undefined,
    controls: 'top-left',
    basemap: 'streets',
  });
  const markerRef = useRef<Marker | null>(null);

  const [point, setPoint] = useState<PickedPoint | null>(
    initial ? { ...initial, accuracy: null } : null,
  );
  const [locating, setLocating] = useState(false);
  const [geoError, setGeoError] = useState<string | null>(null);

  const color = useTokenColors(MAP_COLOR_TOKENS);
  const pinColor =
    agencyType && `agency_${agencyType}` in color
      ? color[`agency_${agencyType}` as keyof typeof color]
      : color.unscored;

  // onChange is called from effects below; holding it in a ref keeps it out of
  // their dependency lists, so a parent that re-creates the callback on every
  // render cannot send this component into a loop.
  const onChangeRef = useRef(onChange);
  useEffect(() => { onChangeRef.current = onChange; }, [onChange]);
  useEffect(() => { onChangeRef.current(point); }, [point]);

  // ── Click anywhere to place ─────────────────────────────────
  // The whole point of this control is that a coordinate is a place, not a
  // pair of numbers.
  useEffect(() => {
    if (!map) return;
    const onClick = (e: import('maplibre-gl').MapMouseEvent) => {
      setGeoError(null);
      setPoint({ lat: e.lngLat.lat, lng: e.lngLat.lng, accuracy: null });
    };
    map.on('click', onClick);
    map.getCanvas().style.cursor = 'crosshair';
    return () => { map.off('click', onClick); };
  }, [map]);

  // ── Draw the pin and its accuracy ───────────────────────────
  useEffect(() => {
    if (!map || !maplibre) return;
    markerRef.current?.remove();
    markerRef.current = null;
    removeGeoJson(map, ACCURACY_SRC, ACCURACY_LAYERS);
    if (!point) return;

    const el = document.createElement('div');
    el.style.width = '26px';
    el.style.height = '34px';
    el.style.cursor = 'grab';
    // eslint-disable-next-line no-restricted-syntax -- an SVG built from two colour tokens, no user text
    el.innerHTML = teardropSvg(pinColor, color.markStroke, 26, 34);
    // Draggable: a click gets you close, a drag gets you onto the building.
    const marker = new maplibre.Marker({ element: el, anchor: 'bottom', draggable: true })
      .setLngLat([point.lng, point.lat])
      .addTo(map);
    marker.on('dragend', () => {
      const p = marker.getLngLat();
      setGeoError(null);
      // Dragging invalidates the device's accuracy — the operator has moved
      // the pin somewhere the GPS never claimed.
      setPoint({ lat: p.lat, lng: p.lng, accuracy: null });
    });
    markerRef.current = marker;

    // The accuracy radius, to scale. A 400 m fix should LOOK like 400 m.
    if (point.accuracy && point.accuracy > 0) {
      upsertGeoJson(map, ACCURACY_SRC, circlePolygon(point.lat, point.lng, point.accuracy), [
        { id: 'z-accuracy-fill', type: 'fill', paint: { 'fill-color': pinColor, 'fill-opacity': 0.12 } },
        { id: 'z-accuracy-line', type: 'line', paint: { 'line-color': pinColor, 'line-width': 1 } },
      ]);
    }
  }, [map, maplibre, point, pinColor, color.markStroke, styleEpoch]);

  useEffect(() => () => { markerRef.current?.remove(); }, []);

  // ── Device location ─────────────────────────────────────────
  const mapRef = useRef(map);
  mapRef.current = map;
  const useMyLocation = useCallback(() => {
    if (typeof navigator === 'undefined' || !navigator.geolocation) {
      setGeoError('This browser cannot report a location.');
      return;
    }
    setLocating(true);
    setGeoError(null);
    navigator.geolocation.getCurrentPosition(
      pos => {
        setLocating(false);
        const next = {
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy ?? null,
        };
        setPoint(next);
        mapRef.current?.flyTo({ center: [next.lng, next.lat], zoom: 17, duration: 600 });
      },
      err => {
        setLocating(false);
        setGeoError(
          err.code === err.PERMISSION_DENIED
            ? 'Location permission was refused. Allow it from the padlock in the address bar, or place the pin by hand.'
            : err.code === err.POSITION_UNAVAILABLE
              ? 'No location fix available here. Place the pin by hand instead.'
              : 'Locating timed out. Place the pin by hand instead.',
        );
      },
      // A station is a fixed building, so it is worth waiting for the good fix
      // rather than taking a fast cell-tower estimate.
      { enableHighAccuracy: true, timeout: 15_000, maximumAge: 0 },
    );
  }, []);

  const outside = point && !inProvince(point.lat, point.lng);
  const loose = point?.accuracy != null && point.accuracy > ACCURACY_WARN_M;

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button disabled={locating} onClick={useMyLocation} size="sm" variant="outline">
          {locating ? (
            <LoaderCircle className="animate-spin" data-icon="inline-start" />
          ) : (
            <Crosshair data-icon="inline-start" />
          )}
          {locating ? 'Locating…' : 'Use my current location'}
        </Button>
        <span className="text-meta text-muted-foreground">
          or click the map to drop a pin, then drag it to adjust
        </span>
      </div>

      <div
        className="relative isolate h-[320px] w-full overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)]"
        ref={containerRef}
      />

      {geoError && (
        <p className="flex items-start gap-2 text-meta text-[var(--color-system-warning)]">
          <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
          {geoError}
        </p>
      )}

      {point ? (
        <div className="flex flex-col gap-1.5">
          <p className="flex flex-wrap items-center gap-2 text-meta text-[var(--color-text-secondary)]">
            <MapPin aria-hidden="true" className="size-3.5 shrink-0" />
            <Fig className="text-[12px] font-semibold">
              {point.lat.toFixed(6)}, {point.lng.toFixed(6)}
            </Fig>
            {point.accuracy != null && (
              <span className={loose ? 'text-[var(--color-system-warning)]' : ''}>
                · accurate to about{' '}
                <Fig className="text-[12px] font-semibold">
                  {Math.round(point.accuracy)}
                </Fig>
                m
              </span>
            )}
          </p>

          {/* Both warnings state the operational consequence, not the rule.
              "Outside the bounding box" means nothing to an administrator;
              "reports near it will route to the wrong agency" does. */}
          {outside && (
            <p className="flex items-start gap-2 text-meta text-[var(--color-severity-critical)]">
              <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
              This point is outside Biliran. A station in the wrong place
              misroutes every report near it — check before saving.
            </p>
          )}
          {loose && !outside && (
            <p className="flex items-start gap-2 text-meta text-[var(--color-system-warning)]">
              <TriangleAlert className="mt-0.5 size-3.5 shrink-0" />
              That is a loose fix — the true position is somewhere in the
              circle. Indoors this is normal; drag the pin onto the building if
              you can see it.
            </p>
          )}
        </div>
      ) : (
        <p className="text-meta text-muted-foreground">
          No location set yet. This station cannot be pinned on the Incident Map
          until it has one.
        </p>
      )}
    </div>
  );
}
