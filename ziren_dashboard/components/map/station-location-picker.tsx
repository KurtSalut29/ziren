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
import { Crosshair, LoaderCircle, MapPin, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';
import { Fig } from '@/components/ui/fig';
import { useTokenColors } from '@/lib/theme/use-token-colors';
import { MAP_COLOR_TOKENS } from './map-legend';

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

const BILIRAN_CENTER: [number, number] = [11.583, 124.408];

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
  const mapRef = useRef<import('leaflet').Map | null>(null);
  const markerRef = useRef<import('leaflet').Marker | null>(null);
  const circleRef = useRef<import('leaflet').Circle | null>(null);
  const [ready, setReady] = useState(false);

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

  // ── Map init ────────────────────────────────────────────────
  useEffect(() => {
    const container = containerRef.current;
    if (mapRef.current || !container) return;
    let cancelled = false;

    import('leaflet').then(L => {
      if (cancelled || mapRef.current) return;
      const map = L.map(container, {
        center: initial ? [initial.lat, initial.lng] : BILIRAN_CENTER,
        zoom: initial ? 16 : 11,
        zoomControl: true,
        attributionControl: true,
      });
      L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      }).addTo(map);

      // Click anywhere to place. The whole point of this control is that a
      // coordinate is a place, not a pair of numbers.
      map.on('click', (e: import('leaflet').LeafletMouseEvent) => {
        setGeoError(null);
        setPoint({ lat: e.latlng.lat, lng: e.latlng.lng, accuracy: null });
      });

      mapRef.current = map;
      setReady(true);
    });

    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
      markerRef.current = null;
      circleRef.current = null;
      setReady(false);
    };
    // Mount once. `initial` only seeds the opening view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Leaflet measures its container at init. This one is born inside a dialog
  // that may still be animating, so without this the map renders into a box of
  // the wrong size and every click maps to the wrong coordinate.
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const ro = new ResizeObserver(() => mapRef.current?.invalidateSize());
    ro.observe(container);
    return () => ro.disconnect();
  }, []);

  // ── Draw the pin and its accuracy ───────────────────────────
  useEffect(() => {
    if (!ready || !mapRef.current || !point) return;
    let cancelled = false;

    import('leaflet').then(L => {
      const map = mapRef.current;
      if (cancelled || !map) return;

      markerRef.current?.remove();
      circleRef.current?.remove();

      const icon = L.divIcon({
        className: '',
        iconSize: [26, 34],
        iconAnchor: [13, 34],
        html: [
          '<svg width="26" height="34" viewBox="0 0 22 28" xmlns="http://www.w3.org/2000/svg">',
          '<path d="M11 27C11 27 20 16.5 20 10A9 9 0 1 0 2 10C2 16.5 11 27 11 27Z"',
          ` fill="${pinColor}" stroke="${color.markStroke}" stroke-width="2" stroke-linejoin="round"/>`,
          `<circle cx="11" cy="10" r="3.2" fill="${color.markStroke}"/>`,
          '</svg>',
        ].join(''),
      });

      // Draggable: a click gets you close, a drag gets you onto the building.
      const marker = L.marker([point.lat, point.lng], { icon, draggable: true });
      marker.on('dragend', () => {
        const ll = marker.getLatLng();
        setGeoError(null);
        // Dragging invalidates the device's accuracy — the operator has moved
        // the pin somewhere the GPS never claimed.
        setPoint({ lat: ll.lat, lng: ll.lng, accuracy: null });
      });
      marker.addTo(map);
      markerRef.current = marker;

      // The accuracy radius, to scale. A 400m fix should LOOK like 400m.
      if (point.accuracy && point.accuracy > 0) {
        circleRef.current = L.circle([point.lat, point.lng], {
          radius: point.accuracy,
          color: pinColor,
          fillColor: pinColor,
          fillOpacity: 0.1,
          weight: 1,
        }).addTo(map);
      }
    });

    return () => { cancelled = true; };
  }, [ready, point, pinColor, color.markStroke]);

  // ── Device location ─────────────────────────────────────────
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
        mapRef.current?.setView([next.lat, next.lng], 17);
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

      <link
        crossOrigin=""
        href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
        rel="stylesheet"
      />
      <div
        className="h-[320px] w-full overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)]"
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
