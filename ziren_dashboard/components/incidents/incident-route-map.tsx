'use client';

/**
 * IncidentRouteMap — two points and the road between them.
 *
 * The queue's map page answers "what is happening across the island". This
 * answers the one question a dispatcher asks with an incident already open in
 * front of them: how far away is the nearest crew, and what do they have to
 * drive to get there. So it draws exactly two marks and one line, and nothing
 * else competes for the space.
 *
 * Marks, no chrome and no fetching — same division as ZirenMap. The legend and
 * the distance card are drawn by the panel above this, in ordinary DOM, from
 * the same route object that is passed in here. One route, one set of numbers:
 * the card cannot claim a distance the line does not show.
 *
 * The marker vocabulary is deliberately the map page's, not the mockup's:
 * incidents are a resident pin with the severity written on a chip beneath
 * it, stations are the agency's own pin artwork (glyph and all). This used to
 * draw its own plain circle-for-incident and a hand-rolled SVG teardrop for
 * stations — two more copies of shapes ZirenMap.tsx already owned, which is
 * how a dispatcher could see one icon for "BFP Naval" here and a different
 * one for it on the main map. A dispatcher who has learned to read one map
 * surface on this console must not have to learn a second one.
 *
 * Tile source: the same Esri satellite imagery + reference overlay as
 * ZirenMap.tsx, for the same reason as the marker vocabulary above — this and
 * the main map are one visual surface to a dispatcher, not two.
 *
 * NO ATTRIBUTION CONTROL. Esri/OSM/CARTO's usual terms for these free,
 * keyless tiles ask for attribution to stay visible — this used to carry it
 * (`attributionControl: true`) for exactly that reason. Removed 2026-09-15 on
 * an explicit request: the credit line was reading as visual clutter on a
 * report a dispatcher is trying to act on quickly. Worth knowing if this ever
 * moves past a school pilot into something Esri/CARTO would notice.
 */

import { useEffect, useRef, useState } from 'react';
import type { LatLng, ResponseRoute } from '@/lib/incidents/response-route';
import { useTokenColors } from '@/lib/theme/use-token-colors';
import {
  agencyColor,
  MAP_COLOR_TOKENS,
  SEVERITY_LABEL,
  type AgencyKey,
  type SeverityKey,
} from '@/components/map/map-legend';
import {
  AGENCY_MARKER,
  markerHtml,
  PERSON_H,
  PERSON_TIP_RATIO,
  PERSON_W,
  PIN_H,
  PIN_TIP_RATIO,
  PIN_W,
  RESIDENT_MARKER,
} from '@/components/map/map-markers';

interface Props {
  incident: LatLng;
  /** Null when no station was matched — the incident is drawn on its own. */
  station: { point: LatLng; agencyType: AgencyKey | null } | null;
  severity: SeverityKey;
  /** Null while the route is still being fetched. */
  route: ResponseRoute | null;
  /**
   * Let the mouse wheel / trackpad zoom this map. Off by default because the
   * caller may be embedding this inline in a page that scrolls as a whole
   * (the full incident page does) — wheeling over the map there would zoom it
   * instead of continuing to scroll past it. The incident detail MODAL's map
   * column never scrolls on its own (see incident-detail-modal.tsx), so it
   * passes true — that is also what "the laptop's own zoom gesture doesn't
   * work" (reported 2026-09-15) was actually about: scrollWheelZoom was
   * unconditionally off, so only the on-map +/- buttons ever worked.
   */
  scrollWheelZoom?: boolean;
}

/** Route colour lives here as a token name, resolved with the rest at paint. */
const ROUTE_TOKENS = { ...MAP_COLOR_TOKENS, route: '--color-system-info' };

export default function IncidentRouteMap({
  incident,
  station,
  severity,
  route,
  scrollWheelZoom = false,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<import('leaflet').Map | null>(null);
  const groupRef = useRef<import('leaflet').LayerGroup | null>(null);
  const [ready, setReady] = useState(false);

  const color = useTokenColors(ROUTE_TOKENS);

  // ── 1. Init (once) ──────────────────────────────────────────────────────
  //
  // The `cancelled` flag guards the same StrictMode double-mount race that is
  // documented at length in ZirenMap: a ref guard cannot see an init that is
  // still in flight inside the Leaflet import, so run #2 gets a null ref and
  // calls L.map() on a container run #1 has already stamped.
  useEffect(() => {
    const container = containerRef.current;
    if (mapRef.current || !container) return;

    let cancelled = false;

    import('leaflet').then(L => {
      if (cancelled || mapRef.current) return;

      const map = L.map(container, {
        center: incident,
        zoom: 14,
        zoomControl: false,
        attributionControl: false,
        scrollWheelZoom,
      });

      L.control.zoom({ position: 'topright' }).addTo(map);

      // maxNativeZoom caps requests at Esri's real coverage over Biliran
      // (verified at 18 — see the identical note in ZirenMap.tsx) and lets
      // Leaflet scale that last tile up instead of hitting their grey "Map
      // data not yet available" placeholder. This map opens at zoom 14 and a
      // dispatcher zooming in on a specific street is exactly who would hit
      // that wall first.
      L.tileLayer(
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        {
          maxZoom:       19,
          maxNativeZoom: 18,
          attribution:
            'Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community',
        },
      ).addTo(map);

      // CARTO's labels-only layer, same as ZirenMap.tsx and for the same
      // reason — Esri's own Reference/Boundaries layer barely has anything
      // over Biliran below the municipality level, while this street/sitio
      // detail comes FROM OpenStreetMap. This map is the close-up "how do we
      // get there" view, where a road name matters more than on the
      // province-wide map, not less. Added second so it paints over the
      // imagery layer by draw order within Leaflet's shared tilePane.
      L.tileLayer(
        'https://basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png',
        {
          maxZoom: 19,
          attribution:
            '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
            '© <a href="https://carto.com/attributions">CARTO</a>',
        },
      ).addTo(map);

      groupRef.current = L.layerGroup().addTo(map);
      mapRef.current = map;
      setReady(true);

      // Leaflet reads the container's size ONCE, synchronously, on this
      // exact line — and this line can run before the two-column grid
      // outside it has settled into its final width (the dynamic import
      // above and this component's own mount both land mid-layout, not
      // after). A too-narrow read here is never fixed by the ResizeObserver
      // below, because the container's size never actually CHANGES
      // afterwards — Leaflet just goes on painting tiles into the box it
      // measured at this instant, leaving real empty space down one side
      // that looks like a bug because it is one. One re-measure next frame,
      // after the browser has finished the layout this effect interrupted,
      // costs nothing and is the standard fix for this exact Leaflet gotcha.
      requestAnimationFrame(() => map.invalidateSize());
    });

    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
      groupRef.current = null;
      setReady(false);
    };
    // Init only. The incident coordinates seed the first centre; the layer
    // effect below re-frames the map whenever they change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── 2. Follow the container's size ──────────────────────────────────────
  //
  // The dialog animates in from 95% scale and the panel reflows when the
  // viewport narrows, neither of which fires a window resize. Without this the
  // map keeps the width it was measured at mid-animation: a grey gutter down
  // one side and markers offset from their own coordinates.
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    const ro = new ResizeObserver(() => mapRef.current?.invalidateSize());
    ro.observe(container);
    return () => ro.disconnect();
  }, []);

  // ── 3. Draw ─────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!ready || !groupRef.current) return;

    let cancelled = false;
    import('leaflet').then(L => {
      const group = groupRef.current;
      const map = mapRef.current;
      if (cancelled || !group || !map) return;
      group.clearLayers();

      // The route first, so both markers sit on top of their own line.
      if (route && route.path.length >= 2) {
        L.polyline(route.path, {
          color: color.route,
          weight: 4,
          opacity: 0.9,
          lineCap: 'round',
          lineJoin: 'round',
          // A straight line is a claim about distance, not about a road. It is
          // dashed so it can never be mistaken for one the crew can drive.
          dashArray: route.source === 'straight-line' ? '6 9' : undefined,
        }).addTo(group);
      }

      if (station) {
        const c = agencyColor(color, station.agencyType);
        // The agency's own pin — same artwork ZirenMap.tsx draws for this
        // agency, not a second, hand-rolled shape. A station whose agency row
        // carries no type still gets drawn, same fallback ZirenMap.tsx uses:
        // there is no glyph for "unknown", so it falls back to a plain
        // teardrop rather than hiding a station that exists.
        const pin = station.agencyType
          ? L.divIcon({
              className:  '',
              iconSize:   [PIN_W, PIN_H],
              iconAnchor: [PIN_W / 2, Math.round(PIN_H * PIN_TIP_RATIO)],
              html: markerHtml({
                src: AGENCY_MARKER[station.agencyType], w: PIN_W, h: PIN_H,
                // Just the agency type, not the full "BFP Naval" ZirenMap.tsx
                // prints — this panel only ever has the ONE station a report
                // was routed to, and its full name is already printed by
                // IncidentLocationPanel's own _StationStrip, so repeating it
                // on the pin would be a second copy of the same fact rather
                // than a second fact.
                label: station.agencyType, labelColor: c,
              }),
            })
          : L.divIcon({
              className: '',
              iconSize: [22, 28],
              iconAnchor: [11, 28],
              html: [
                '<svg width="22" height="28" viewBox="0 0 22 28" xmlns="http://www.w3.org/2000/svg">',
                '<path d="M11 27C11 27 20 16.5 20 10A9 9 0 1 0 2 10C2 16.5 11 27 11 27Z"',
                ` fill="${c}" stroke="${color.markStroke}" stroke-width="2" stroke-linejoin="round"/>`,
                `<circle cx="11" cy="10" r="3.2" fill="${color.markStroke}"/>`,
                '</svg>',
              ].join(''),
            });
        L.marker(station.point, { icon: pin, keyboard: false }).addTo(group);
      }

      // The same resident pin + severity chip ZirenMap.tsx draws for every
      // incident, not the plain circle this used to be — see the header note.
      const sevColor = color[severity];
      const incidentIcon = L.divIcon({
        className:  '',
        iconSize:   [PERSON_W, PERSON_H],
        iconAnchor: [PERSON_W / 2, Math.round(PERSON_H * PERSON_TIP_RATIO)],
        html: markerHtml({
          src:        RESIDENT_MARKER,
          w:          PERSON_W,
          h:          PERSON_H,
          label:      SEVERITY_LABEL[severity].toUpperCase(),
          labelColor: sevColor,
          labelBg:    sevColor,
          alwaysLabel: true,
        }),
      });
      L.marker(incident, { icon: incidentIcon, keyboard: false }).addTo(group);

      // Frame both ends of the journey, or the incident alone when there is no
      // station to reach it. padding leaves room for the cards drawn over the
      // corners by the panel — a pin under the legend is a pin nobody can see.
      //
      // animate:false, deliberately. Leaflet's animated zoom schedules a 250ms
      // timer that runs _onZoomTransitionEnd on the map, and it is not cancelled
      // by map.remove(). This map lives in a dialog, and closing the dialog
      // within that quarter-second (Esc right after opening is enough) removed
      // the map first and let the timer fire on it afterwards: an uncaught
      // "Cannot read properties of undefined (reading '_leaflet_pos')". About
      // three closes in ten reproduced it. Framing a close-up needs no swoosh,
      // and snapping straight to the frame also means the pins are already in
      // place when the dialog finishes opening.
      const points: LatLng[] = station ? [incident, station.point] : [incident];
      if (points.length > 1) {
        map.fitBounds(L.latLngBounds(points), {
          paddingTopLeft: [28, 64],
          paddingBottomRight: [28, 96],
          maxZoom: 16,
          animate: false,
        });
      } else {
        map.setView(incident, 15, { animate: false });
      }
    });

    return () => { cancelled = true; };
  }, [ready, incident, station, severity, route, color]);

  return (
    <>
      {/* Leaflet's own CSS — must be loaded at runtime, as on the map page. */}
      <link
        rel="stylesheet"
        href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
        crossOrigin=""
      />
      {/* `absolute inset-0`, not `h-full w-full`. This div's parent
          (IncidentLocationPanel's map wrapper) is `position:relative` with a
          height that a flex chain resolves at runtime rather than a literal
          CSS `height` value — `lg:h-auto` + `lg:flex-1` inside a column that
          may itself have no definite height above it. Percentage heights
          only resolve against a parent height the spec considers DEFINITE,
          and a flex-grown `height:auto` doesn't reliably count, so `h-full`
          measured 0 the moment this rendered outside the modal's own
          fixed-height dialog — the map initialized into a real-width,
          zero-height box and never painted a tile. Absolute positioning
          against the same relative ancestor sizes from its rendered box
          instead, sidestepping the percentage-resolution rule entirely, and
          costs nothing in the dialog, where the old sizing already worked. */}
      <div ref={containerRef} className="absolute inset-0" />
      {/* markerHtml() (map-markers.ts) emits these classes — ZirenMap.tsx
          defines the same rules for its own copy of the same markup. This map
          has no LABEL_MIN_ZOOM/zoom-far behaviour (it is a fixed two-point
          close-up, never zoomed out to a whole-island view), so only the base
          positioning is needed, not the zmk-far hide/keep pair. */}
      <style>{`
        .zmk { position: relative; width: 100%; }
        .zmk-art {
          display: block;
          filter: drop-shadow(0 1px 2px rgba(0,0,0,0.3));
        }
        .zmk-label {
          position: absolute;
          top: 100%;
          left: 50%;
          transform: translateX(-50%);
          margin-top: 1px;
          padding: 1px 5px;
          border-radius: 999px;
          background: rgba(255,255,255,0.94);
          border: 1px solid rgba(0,0,0,0.08);
          box-shadow: 0 1px 2px rgba(0,0,0,0.14);
          font-size: 10px;
          font-weight: 700;
          line-height: 1.3;
          white-space: nowrap;
          pointer-events: none;
        }
      `}</style>
    </>
  );
}
