'use client';

/**
 * useMapLibre — one MapLibre map on one container, the way every dashboard
 * map needs it.
 *
 * Owns the parts all three maps (Incident Map, the incident's route map, the
 * station picker) would otherwise each get subtly wrong:
 *
 *  - StrictMode. Effects mount twice in development and MapLibre loads
 *    asynchronously, so a ref guard alone lets two maps be built on one node.
 *    Each run owns a `cancelled` flag its own cleanup sets.
 *  - Size. MapLibre measures its container at construction and only follows
 *    window resizes. The shell's sidebar collapses and dialogs animate in
 *    without one, so a ResizeObserver calls resize().
 *  - Basemap and theme. Switching Satellite/Streets (Settings → Map & Location)
 *    or light/dark swaps the style in place. Anything a caller added with an
 *    id starting "z-" — the route line, the accuracy circle — is carried
 *    across the swap instead of vanishing with the old style.
 */

import { useEffect, useRef, useState, type RefObject } from 'react';
import type { Map as MlMap, StyleSpecification } from 'maplibre-gl';
import { useTheme } from '@/lib/theme/use-theme';
import { mapPrefs } from '@/lib/prefs/definitions';
import {
  BILIRAN_CENTER, BILIRAN_MAX_BOUNDS, BILIRAN_ZOOM, MAX_ZOOM,
  buildMapStyle, isDarkTheme, loadMapLibre, type Basemap,
} from './maplibre-style';

type MapLibre = typeof import('maplibre-gl');

/** Sources and layers a caller adds are named with this prefix. */
export const CUSTOM_PREFIX = 'z-';

export interface UseMapLibreOptions {
  center?: [number, number];
  zoom?: number;
  /** Mouse-wheel zoom. Off where the map sits in a page that scrolls as a whole. */
  scrollZoom?: boolean;
  /** Where the zoom buttons go; false for none. */
  controls?: 'top-left' | 'top-right' | 'bottom-right' | false;
  /** Allow right-drag rotation (with a compass to reset north). */
  rotate?: boolean;
  /** Force a basemap instead of following Settings → Map & Location. */
  basemap?: Basemap;
}

export interface MapLibreHandle {
  map: MlMap | null;
  maplibre: MapLibre | null;
  /** Bumped every time the style finishes (re)loading. */
  styleEpoch: number;
}

export function useMapLibre(
  containerRef: RefObject<HTMLDivElement | null>,
  opts: UseMapLibreOptions = {},
): MapLibreHandle {
  const [handle, setHandle] = useState<{ map: MlMap; maplibre: MapLibre } | null>(null);
  const [styleEpoch, setStyleEpoch] = useState(0);
  const { theme } = useTheme();
  const prefBasemap = mapPrefs.use().basemap;
  const basemap = opts.basemap ?? prefBasemap;
  const optsRef = useRef(opts);
  const appliedRef = useRef<string | null>(null);

  // ── Build (once) ────────────────────────────────────────────────────────
  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    let cancelled = false;
    let built: MlMap | null = null;

    loadMapLibre().then(maplibre => {
      if (cancelled || !containerRef.current) return;
      const o = optsRef.current;
      const kind = o.basemap ?? mapPrefs.get().basemap;
      const dark = isDarkTheme();
      const map = new maplibre.Map({
        container,
        style: buildMapStyle(kind, dark, window.location.origin),
        center: o.center ?? BILIRAN_CENTER,
        zoom: o.zoom ?? BILIRAN_ZOOM,
        maxZoom: MAX_ZOOM,
        minZoom: 8,
        maxBounds: BILIRAN_MAX_BOUNDS,
        scrollZoom: o.scrollZoom ?? true,
        dragRotate: Boolean(o.rotate),
        pitchWithRotate: false,
        touchPitch: false,
        attributionControl: { compact: true },
        // Hand the dispatcher's own clicks to the page, not to a MapLibre
        // hash in the URL.
        hash: false,
      });
      if (!o.rotate) map.touchZoomRotate.disableRotation();
      if (o.controls !== false) {
        map.addControl(
          new maplibre.NavigationControl({ showCompass: Boolean(o.rotate), visualizePitch: false }),
          o.controls ?? 'top-left',
        );
      }
      appliedRef.current = `${kind}:${dark}`;
      map.on('style.load', () => setStyleEpoch(e => e + 1));
      built = map;
      setHandle({ map, maplibre });
    });

    return () => {
      cancelled = true;
      built?.remove();
      setHandle(null);
    };
    // Build once per container; options only seed the first view.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Follow the container's size ─────────────────────────────────────────
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !handle) return;
    const ro = new ResizeObserver(() => handle.map.resize());
    ro.observe(container);
    // One re-measure after the layout this mount interrupted has settled.
    requestAnimationFrame(() => handle.map.resize());
    return () => ro.disconnect();
  }, [containerRef, handle]);

  // ── Basemap / theme swaps ───────────────────────────────────────────────
  useEffect(() => {
    if (!handle) return;
    const dark = theme === 'dark';
    const key = `${basemap}:${dark}`;
    if (appliedRef.current === key) return;
    appliedRef.current = key;
    const next = buildMapStyle(basemap, dark, window.location.origin);
    handle.map.setStyle(next, {
      diff: false,
      transformStyle: (prev: StyleSpecification | undefined, incoming: StyleSpecification) => {
        if (!prev) return incoming;
        const keptSources = Object.fromEntries(
          Object.entries(prev.sources).filter(([id]) => id.startsWith(CUSTOM_PREFIX)),
        );
        const keptLayers = prev.layers.filter(l => l.id.startsWith(CUSTOM_PREFIX));
        return { ...incoming, sources: { ...incoming.sources, ...keptSources }, layers: [...incoming.layers, ...keptLayers] };
      },
    });
  }, [handle, basemap, theme]);

  return { map: handle?.map ?? null, maplibre: handle?.maplibre ?? null, styleEpoch };
}

/**
 * Put a GeoJSON source + layer on the map, or update its data if it is already
 * there. Safe to call before the style has loaded: it waits.
 */
export function upsertGeoJson(
  map: MlMap,
  id: string,
  data: GeoJSON.GeoJSON,
  layers: Omit<import('maplibre-gl').LayerSpecification, 'source'>[],
): void {
  const apply = () => {
    const src = map.getSource(id) as import('maplibre-gl').GeoJSONSource | undefined;
    if (src) src.setData(data);
    else map.addSource(id, { type: 'geojson', data });
    for (const layer of layers) {
      if (!map.getLayer(layer.id)) map.addLayer({ ...layer, source: id } as import('maplibre-gl').LayerSpecification);
    }
  };
  if (map.isStyleLoaded()) apply();
  else map.once('idle', apply);
}

/** Remove a source and the given layers, if present. */
export function removeGeoJson(map: MlMap, id: string, layerIds: string[]): void {
  if (!map.getStyle()) return;
  for (const l of layerIds) if (map.getLayer(l)) map.removeLayer(l);
  if (map.getSource(id)) map.removeSource(id);
}
