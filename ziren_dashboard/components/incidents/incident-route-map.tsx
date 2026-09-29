'use client';

/**
 * IncidentRouteMap — two points and the road between them.
 *
 * The Incident Map answers "what is happening across the island". This
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
 * The marker vocabulary is the Incident Map's: incidents are a resident pin
 * with the severity written on a chip beneath it, stations are the agency's
 * own pin artwork. A dispatcher who has learned to read one map surface on
 * this console must not have to learn a second one. The basemap is the same
 * too — see maplibre-style.ts. Moved from Leaflet to MapLibre 2026-09-29.
 */

import { useEffect, useRef } from 'react';
import type { Marker } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
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
  MARKER_CSS,
  markerElement,
  markerHtml,
  PERSON_H,
  PERSON_TIP_RATIO,
  PERSON_W,
  PIN_H,
  PIN_TIP_RATIO,
  PIN_W,
  RESIDENT_MARKER,
  teardropSvg,
} from '@/components/map/map-markers';
import { removeGeoJson, upsertGeoJson, useMapLibre } from '@/components/map/use-maplibre';

interface Props {
  incident: LatLng;
  /** Null when no station was matched — the incident is drawn on its own. */
  station: { point: LatLng; agencyType: AgencyKey | null } | null;
  severity: SeverityKey;
  /** Null while the route is still being fetched. */
  route: ResponseRoute | null;
  /**
   * Let the mouse wheel / trackpad zoom this map. Off by default because the
   * caller may be embedding this inline in a page that scrolls as a whole —
   * wheeling over the map there would zoom it instead of scrolling past it.
   * The incident detail MODAL's map column never scrolls, so it passes true.
   */
  scrollWheelZoom?: boolean;
}

/** Route colour lives here as a token name, resolved with the rest at paint. */
const ROUTE_TOKENS = { ...MAP_COLOR_TOKENS, route: '--color-system-info' };
const ROUTE_SRC = 'z-route';
const ROUTE_LAYERS = ['z-route-casing', 'z-route-line'];

/** [lat, lng] → MapLibre's [lng, lat]. */
const ll = (p: LatLng): [number, number] => [p[1], p[0]];

export default function IncidentRouteMap({
  incident,
  station,
  severity,
  route,
  scrollWheelZoom = false,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const { map, maplibre, styleEpoch } = useMapLibre(containerRef, {
    center: ll(incident),
    zoom: 14,
    scrollZoom: scrollWheelZoom,
    controls: 'top-right',
  });
  const color = useTokenColors(ROUTE_TOKENS);

  // ── Markers ─────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!map || !maplibre) return;
    const added: Marker[] = [];

    if (station) {
      const c = agencyColor(color, station.agencyType);
      // Just the agency type on the pin — this panel only ever has the ONE
      // station a report was routed to, and its full name is printed beside
      // the map already.
      const { element, offset } = station.agencyType
        ? markerElement(markerHtml({
            src: AGENCY_MARKER[station.agencyType], w: PIN_W, h: PIN_H,
            label: station.agencyType, labelColor: c,
          }), PIN_W, PIN_H, PIN_TIP_RATIO)
        : markerElement(teardropSvg(c, color.markStroke), 22, 28, 1);
      element.style.cursor = 'default';
      added.push(new maplibre.Marker({ element, anchor: 'top-left', offset }).setLngLat(ll(station.point)).addTo(map));
    }

    const sevColor = color[severity];
    const { element, offset } = markerElement(markerHtml({
      src: RESIDENT_MARKER, w: PERSON_W, h: PERSON_H,
      label: SEVERITY_LABEL[severity].toUpperCase(),
      labelColor: sevColor, labelBg: sevColor, alwaysLabel: true,
    }), PERSON_W, PERSON_H, PERSON_TIP_RATIO);
    element.style.cursor = 'default';
    element.style.zIndex = '5';
    added.push(new maplibre.Marker({ element, anchor: 'top-left', offset }).setLngLat(ll(incident)).addTo(map));

    return () => { for (const m of added) m.remove(); };
  }, [map, maplibre, incident, station, severity, color]);

  // ── The route line ──────────────────────────────────────────────────────
  // Re-added after a basemap swap too (styleEpoch), although use-maplibre
  // carries z- layers across swaps — a belt for the braces.
  useEffect(() => {
    if (!map) return;
    if (!route || route.path.length < 2) {
      removeGeoJson(map, ROUTE_SRC, ROUTE_LAYERS);
      return;
    }
    // A straight line is a claim about distance, not about a road. It is
    // dashed so it can never be mistaken for one the crew can drive. Layers
    // are rebuilt rather than restyled because a dash pattern cannot be
    // switched off by paint property alone.
    removeGeoJson(map, ROUTE_SRC, ROUTE_LAYERS);
    const straight = route.source === 'straight-line';
    upsertGeoJson(map, ROUTE_SRC, {
      type: 'Feature', properties: {},
      geometry: { type: 'LineString', coordinates: route.path.map(ll) },
    }, [
      {
        id: 'z-route-casing', type: 'line',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#ffffff', 'line-width': 7, 'line-opacity': 0.85 },
      },
      {
        id: 'z-route-line', type: 'line',
        layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: {
          'line-color': color.route, 'line-width': 4, 'line-opacity': 0.95,
          ...(straight ? { 'line-dasharray': [1.5, 2.2] } : {}),
        },
      },
    ]);
  }, [map, route, color.route, styleEpoch]);

  // ── Frame both ends ─────────────────────────────────────────────────────
  // Padding leaves room for the cards the panel draws over the corners — a
  // pin under the legend is a pin nobody can see. No animation: this map lives
  // in a dialog that may close a moment after opening.
  useEffect(() => {
    if (!map || !maplibre) return;
    const frame = () => {
      map.resize();
      if (station) {
        const b = new maplibre.LngLatBounds(ll(incident), ll(incident)).extend(ll(station.point));
        map.fitBounds(b, { padding: { top: 64, left: 28, right: 28, bottom: 96 }, maxZoom: 16, animate: false });
      } else {
        map.jumpTo({ center: ll(incident), zoom: 15 });
      }
    };
    frame();
    // The dialog may still be animating in: frame again once it has settled.
    const t = window.setTimeout(frame, 300);
    return () => window.clearTimeout(t);
  }, [map, maplibre, incident, station]);

  return (
    <>
      <style>{MARKER_CSS}</style>
      {/* An absolute wrapper, not `h-full` on the map itself: the parent's
          height comes from a flex chain, and a percentage height against it
          can resolve to 0 outside the modal. And the map div cannot BE the
          absolute box — MapLibre stamps `position: relative` on its container,
          which would collapse it to zero height. */}
      <div className="absolute inset-0">
        <div className="isolate h-full w-full" ref={containerRef} />
      </div>
    </>
  );
}
