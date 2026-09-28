'use client';

/**
 * ZirenMap — the Leaflet surface. Marks only; no chrome, no fetching.
 *
 * Everything that was not a map has moved out. This component used to own the
 * /map/data poll, a floating refresh bar and a row of count badges, which meant
 * the page above it could not read a single number it was drawing and had to
 * hand-write a legend beside it. Those two descriptions of the same data could
 * disagree, and did: the page legend listed four severities unconditionally
 * while the map might be showing none of them.
 *
 * The page now owns the data (useMapData) and the visibility state, and hands
 * both down. This file draws what it is given.
 *
 * Layers:
 *   1. Coverage polygons — agency jurisdiction, dashed outline at 10% fill
 *   2. Incident markers  — a resident pin, with SEVERITY on the chip below it
 *   3. Responder markers — a responder pin, labelled
 *   4. Station pins      — the agency's own artwork, labelled "BFP Naval"
 *
 * Every marker carries a WORD as well as a colour. That is not decoration: an
 * island this small puts marks of different meaning on the same pixel all the
 * time, colour alone is unreadable to a red-green deficient dispatcher, and
 * the severity chip has to survive being printed in greyscale for a shift
 * handover. Station labels hide when you zoom out past LABEL_MIN_ZOOM because
 * twenty-one of them is a wall of text; incident chips never hide, because
 * severity is the one fact the widest view exists to show.
 *
 * Tile source: Esri World Imagery (satellite photography) with the matching
 * Esri reference overlay for place names and boundaries, so a dispatcher
 * looking for a specific barangay isn't reading bare aerial photography with
 * no labels. Both are free, keyless tile services — no Mapbox/Google account
 * exists for this project.
 *
 * NO ATTRIBUTION CONTROL — see the identical note in incident-route-map.tsx.
 * Esri/OSM/CARTO's usual terms for these tiles ask for it to stay visible;
 * removed 2026-09-15 on an explicit request because it read as clutter over
 * the map a dispatcher is working from. Worth restoring if this ever leaves
 * a school pilot.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { mapPrefs, type MapPrefs } from '@/lib/prefs/definitions';
import { ChevronRight, X } from 'lucide-react';
import type { MapData, MapIncident } from '@/lib/api/map';
import { useTokenColors } from '@/lib/theme/use-token-colors';
import {
  agencyColor,
  MAP_COLOR_TOKENS,
  SEVERITY_LABEL,
  severityKey,
  type AgencyFilter,
  type AgencyKey,
  type MapLayerState,
  type SeverityKey,
} from './map-legend';
import {
  AGENCY_MARKER,
  escapeHtml,
  LABEL_MIN_ZOOM,
  markerHtml,
  PERSON_H,
  PERSON_TIP_RATIO,
  PERSON_W,
  PIN_H,
  PIN_TIP_RATIO,
  PIN_W,
  RESIDENT_MARKER,
  RESPONDER_MARKER,
  SEVERITY_STACK,
  stationLabel,
  stationTooltip,
} from './map-markers';

// Biliran Island centre + zoom
const BILIRAN_CENTER: [number, number] = [11.583, 124.408];
const BILIRAN_ZOOM = 11;

interface Props {
  data: MapData | null;
  /**
   * Pan to and select this incident once the data lands.
   *
   * The queue's "View on map" sends an id here. Without it that button drops
   * the viewer on an unfocused map of every open incident and calls it
   * navigation — the one report they asked about is somewhere among the dots.
   */
  focusIncidentId?: string | null;
  layers: MapLayerState;
  /** Which severity buckets to draw. Empty means none, not all. */
  severities: ReadonlySet<SeverityKey>;
  /**
   * Which agencies' coverage and responders to draw.
   *
   * Incidents are NOT filtered by it. An incident's colour is its severity,
   * and its agency is only where it was routed — hiding unrouted incidents
   * because they have no agency would remove exactly the ones that most need
   * looking at.
   */
  agencies: AgencyFilter;
  /**
   * Opens the incident detail MODAL over the queue/map, rather than the
   * marker popup's old "View full detail" link routing to /incidents/{id}.
   * That link was the one place left navigating to the full page after the
   * queue's own detail view moved into a modal — fixed 2026-09-15 on an
   * explicit "why is there still a full-page link" report.
   */
  onOpenIncident: (id: string) => void;
  /**
   * Frame these points instead of the whole island — the Operational Area
   * screen opens on ONE municipality. Re-fits whenever `key` changes (a new
   * municipality or period), and only then: the map polls, so re-fitting on
   * every data refresh would snatch the view back from wherever the viewer had
   * panned. Omit it (the Incident Map does) and the island view is unchanged.
   */
  fitTo?: { key: string; points: [number, number][] } | null;
}

/**
 * The tile layers for one basemap.
 *
 * SATELLITE (the default) is Esri's World Imagery with CARTO's labels-only layer
 * over it. maxNativeZoom 18, not just maxZoom: checked against Esri's own
 * server, their real photography over Biliran stops at 18, and a request for a
 * 19th-level tile is answered with a flat grey "Map data not yet available"
 * placeholder instead of a 404, so Leaflet cannot know to stop asking.
 * maxNativeZoom tells it to stop at 18 and scale that last real tile up, which
 * reads as an ordinary zoomed-in satellite photo. The labels are CARTO's
 * OpenStreetMap-rendered layer rather than Esri's own reference layer, which is
 * nearly empty over Biliran: every sitio and street name a dispatcher needs is
 * OSM community data.
 *
 * STREETS is CARTO Voyager — the same OpenStreetMap data drawn as a street map,
 * labels included. Clearer for reading roads and place names; satellite is
 * clearer for judging what is on the ground.
 *
 * Attribution is kept in the layer options: these tile providers' terms ask for
 * it to stay visible.
 */
function buildBasemap(
  L: typeof import('leaflet'),
  kind: MapPrefs['basemap'],
): import('leaflet').Layer[] {
  if (kind === 'streets') {
    return [
      L.tileLayer('https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', {
        maxZoom: 19,
        attribution:
          '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
          '© <a href="https://carto.com/attributions">CARTO</a>',
      }),
    ];
  }
  return [
    L.tileLayer(
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      {
        maxZoom: 19,
        maxNativeZoom: 18,
        attribution:
          'Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community',
      },
    ),
    L.tileLayer(
      'https://basemaps.cartocdn.com/rastertiles/voyager_only_labels/{z}/{x}/{y}.png',
      {
        maxZoom: 19,
        attribution:
          '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ' +
          '© <a href="https://carto.com/attributions">CARTO</a>',
      },
    ),
  ];
}

export default function ZirenMap({
  data,
  focusIncidentId,
  layers,
  severities,
  agencies,
  onOpenIncident,
  fitTo,
}: Props) {
  const mapContainerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<import('leaflet').Map | null>(null);
  const layerGroupRef = useRef<import('leaflet').LayerGroup | null>(null);
  /**
   * Incidents ONLY — stations and responders stay in `layerGroupRef` and are
   * never clustered. Reports pile up in town centres (58+ on a single-day
   * view is routine, see map-toolbar's own count), and a marker per report
   * with no grouping is a wall of overlapping pins the moment more than a
   * handful land near each other — the exact "napaka kalat" a dispatcher
   * cannot read at a glance. Stations (~21, fixed, spread island-wide) and
   * responders (a handful at a time) don't hit that density.
   */
  const incidentClusterRef = useRef<import('leaflet').MarkerClusterGroup | null>(null);

  const [selected, setSelected] = useState<MapIncident | null>(null);

  /**
   * Whether the Leaflet map exists yet — state, not just the ref beside it.
   *
   * The ref alone was a race that emptied the map. Leaflet is imported
   * asynchronously, so on a fast response the sequence is:
   *
   *   1. data lands, the layer effect runs, mapRef.current is still null
   *   2. the effect returns early
   *   3. the import resolves and builds the map
   *   4. …nothing re-renders, because a ref assignment is not a state change,
   *      so the effect never runs again and not one mark is ever drawn
   *
   * It survived in production only because a real network fetch is slower than
   * a dynamic import. Against a warm cache — or a mocked backend — the map
   * came up blank with a toolbar confidently counting six incidents.
   */
  const [mapReady, setMapReady] = useState(false);

  // Concrete hexes read out of globals.css, re-read when the theme flips.
  // Leaflet paints through SVG presentation attributes, which cannot resolve
  // var() — see use-token-colors for why this indirection is unavoidable.
  const color = useTokenColors(MAP_COLOR_TOKENS);

  // Basemap and label preferences (Settings → Map & Location). The map is built
  // once; these change it in place when the operator flips a setting, so a
  // change made on the Settings page is already in effect when they come back.
  const { basemap, alwaysLabels } = mapPrefs.use();
  const baseLayersRef = useRef<import('leaflet').Layer[]>([]);
  const applyBasemapRef = useRef<((kind: MapPrefs['basemap']) => void) | null>(null);
  const appliedBasemapRef = useRef<string | null>(null);

  useEffect(() => {
    if (!mapReady || appliedBasemapRef.current === basemap) return;
    applyBasemapRef.current?.(basemap);
  }, [basemap, mapReady]);

  useEffect(() => {
    const container = mapContainerRef.current;
    const map = mapRef.current;
    if (!mapReady || !container || !map) return;
    container.classList.toggle('zmk-far', !alwaysLabels && map.getZoom() < LABEL_MIN_ZOOM);
  }, [alwaysLabels, mapReady]);

  /**
   * Fly to the requested incident once, when it first appears in the data.
   *
   * Guarded by a ref rather than by the effect's deps: the map polls, so the
   * incident array is replaced on a timer, and re-running this would yank the
   * viewer back to the pin every refresh no matter where they had panned.
   */
  const focusedRef = useRef<string | null>(null);
  useEffect(() => {
    if (!focusIncidentId || !data || !mapReady || !mapRef.current) return;
    if (focusedRef.current === focusIncidentId) return;

    const target = data.incidents.find(i => i.id === focusIncidentId);
    if (!target) return;

    focusedRef.current = focusIncidentId;
    mapRef.current.flyTo([target.lat, target.lng], 16, { duration: 0.8 });
    setSelected(target);
  }, [focusIncidentId, data, mapReady]);

  const fittedRef = useRef<string | null>(null);
  useEffect(() => {
    if (!fitTo || !mapReady || !mapRef.current) return;
    if (fittedRef.current === fitTo.key) return;
    fittedRef.current = fitTo.key;
    const pts = fitTo.points;
    if (pts.length === 0) return;
    import('leaflet').then(L => {
      const map = mapRef.current;
      if (!map) return;
      map.invalidateSize();
      if (pts.length === 1) {
        map.setView(pts[0], 15, { animate: false });
        return;
      }
      map.fitBounds(L.latLngBounds(pts), { padding: [48, 48], maxZoom: 15, animate: false });
    });
  }, [fitTo, mapReady]);

  // ── 1. Init Leaflet map (once) ──────────────────────────────────────────
  //
  // The `cancelled` flag is load-bearing, not defensive boilerplate. Without
  // it this effect reliably throws "Map container is already initialized" in
  // development, because React StrictMode mounts effects twice and the Leaflet
  // import is asynchronous:
  //
  //   1. run #1 passes the mapRef guard and starts import('leaflet')
  //   2. StrictMode cleanup fires — but mapRef.current is STILL null, because
  //      the promise has not resolved, so `mapRef.current?.remove()` is a no-op
  //   3. run #2 sees a null ref, passes the same guard, starts a second import
  //   4. promise #1 resolves and builds a map, stamping _leaflet_id on the node
  //   5. promise #2 resolves and calls L.map() on that same node → throw
  //
  // A ref guard alone cannot close this: it only observes a FINISHED init,
  // never one in flight. Each effect run instead owns a flag that its own
  // cleanup sets, so a superseded run's continuation returns without ever
  // touching the DOM node.
  useEffect(() => {
    const container = mapContainerRef.current;
    if (mapRef.current || !container) return;

    let cancelled = false;

    // Dynamic import — avoids SSR crash (Leaflet reads window/document).
    //
    // leaflet.markercluster is loaded as a SEPARATE, sequenced import, not
    // alongside 'leaflet' in one Promise.all: its UMD wrapper throws
    // "L is not defined" the instant it is evaluated unless `window.L`
    // already exists — a handful of its internal helpers (spiderfy, the
    // distance-grid clustering algorithm) were written for a <script>-tag
    // world where `L` is already a global, and a bundler never puts it on
    // `window` on its own. Setting `window.L` has to happen BEFORE that
    // module is even requested, since the throw happens at module-evaluation
    // time, not when any of ITS exports are later called — a Promise.all
    // starts both imports in parallel and gives no such ordering guarantee.
    import('leaflet').then(L => {
      // This run was torn down while the import was in flight. Bail before
      // touching the container — the surviving run owns it now.
      if (cancelled || mapRef.current) return;
      (window as unknown as { L: typeof L }).L = L;
      return import('leaflet.markercluster').then(() => L);
    }).then(L => {
      if (!L || cancelled || mapRef.current) return;

      // Fix default icon path broken by webpack asset hashing
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      delete (L.Icon.Default.prototype as any)._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon-2x.png',
        iconUrl:       'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-icon.png',
        shadowUrl:     'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/images/marker-shadow.png',
      });

      const map = L.map(container, {
        center:             BILIRAN_CENTER,
        zoom:               BILIRAN_ZOOM,
        zoomControl:        true,
        attributionControl: false,
      });

      // Basemap: satellite or street map, per Settings → Map & Location, and
      // swappable live from the effect below without rebuilding the map. See
      // buildBasemap for what each one is and why it is built that way.
      const applyBasemap = (kind: MapPrefs['basemap']) => {
        for (const layer of baseLayersRef.current) map.removeLayer(layer);
        baseLayersRef.current = buildBasemap(L, kind);
        for (const layer of baseLayersRef.current) layer.addTo(map);
        appliedBasemapRef.current = kind;
      };
      applyBasemapRef.current = applyBasemap;
      applyBasemap(mapPrefs.get().basemap);

      layerGroupRef.current = L.layerGroup().addTo(map);
      // maxClusterRadius is deliberately small (40px, default is 80): this is
      // a triage map, not a heatmap, so incidents should stop clumping into
      // one bubble as soon as the zoom is loose enough to tell them apart —
      // clustering is only meant to absorb literal pixel-on-pixel overlap.
      // Coverage-on-hover and the default spider legs are both off; the
      // cluster's own popup-free zoom-in-on-click (Leaflet's default) is all
      // the interaction this needs. iconCreateFunction is set fresh in the
      // render-layers effect below, since it depends on the theme's current
      // severity colours.
      incidentClusterRef.current = L.markerClusterGroup({
        maxClusterRadius: 40,
        showCoverageOnHover: false,
        spiderfyOnMaxZoom: true,
      }).addTo(map);

      // ── Label visibility, by zoom ───────────────────────────────────────
      //
      // A class on the container rather than React state, and rebuilt markers
      // rather than neither: the labels live inside divIcon HTML, so toggling
      // them through the component would mean tearing down and re-creating
      // twenty-one markers on every zoom step. One className flip does it in
      // CSS, and the markers never notice.
      const syncLabels = () => {
        container.classList.toggle(
          'zmk-far',
          !mapPrefs.get().alwaysLabels && map.getZoom() < LABEL_MIN_ZOOM,
        );
      };
      syncLabels();
      map.on('zoomend', syncLabels);

      mapRef.current = map;
      setMapReady(true);

      // Cleanup can only have run before this point if `cancelled` was set,
      // which the guard above already handled — there is no await between the
      // check and this assignment. Re-checking here would be cargo cult.
    });

    return () => {
      cancelled = true;
      mapRef.current?.remove();
      mapRef.current = null;
      layerGroupRef.current = null;
      incidentClusterRef.current = null;
      setMapReady(false);
    };
    // Empty deps is correct and needs no suppression: the effect closes over
    // refs only, which are stable identities.
  }, []);

  // ── 2. Tell Leaflet when its container changes size ─────────────────────
  //
  // Leaflet measures the container at init and only recomputes on a WINDOW
  // resize. The shell's sidebar collapses without one, so the map went on
  // rendering at the old width: a grey gutter down one side, tiles offset from
  // where the pointer thinks they are, and markers landing well away from
  // their coordinates. A ResizeObserver on the container is the only thing
  // that sees a layout-driven resize.
  useEffect(() => {
    const container = mapContainerRef.current;
    if (!container) return;
    const ro = new ResizeObserver(() => mapRef.current?.invalidateSize());
    ro.observe(container);
    return () => ro.disconnect();
  }, []);

  // ── 3. Render layers ────────────────────────────────────────────────────
  useEffect(() => {
    if (!data || !mapReady || !layerGroupRef.current) return;

    let cancelled = false;
    import('leaflet').then(L => {
      const group = layerGroupRef.current;
      const cluster = incidentClusterRef.current;
      if (cancelled || !group || !cluster) return;
      group.clearLayers();
      cluster.clearLayers();

      // Rebuilt every pass (data/theme both trigger this effect), so the
      // colours it closes over are never the ones from the first mount —
      // see the ref's own doc comment for why this can't just be set once
      // where the cluster group is created.
      //
      function clusterIcon(c: import('leaflet').MarkerCluster) {
        let worst: SeverityKey = 'unscored';
        let worstRank = -1;
        let sos = false;
        for (const m of c.getAllChildMarkers()) {
          const opts = m.options as import('leaflet').MarkerOptions & { zSeverity?: SeverityKey; zSos?: boolean };
          if (opts.zSos) sos = true;
          const k = opts.zSeverity ?? 'unscored';
          const rank = SEVERITY_STACK[k] ?? 0;
          if (rank > worstRank) { worstRank = rank; worst = k; }
        }
        const badgeColor = color[worst];
        return L.divIcon({
          className: '',
          iconSize: [36, 36],
          html: `
            <div class="${sos ? 'sos-pulse' : ''}" style="
              display:flex; align-items:center; justify-content:center;
              width:36px; height:36px; border-radius:9999px;
              background:${badgeColor}; color:${color.markStroke};
              border:2px solid ${color.markStroke};
              box-shadow:0 1px 3px rgba(0,0,0,0.35);
              font:700 13px var(--font-sans, sans-serif); line-height:1;
            ">${c.getChildCount()}</div>
          `,
        });
      }
      // Cast needed: @types/leaflet.markercluster types MarkerClusterGroup's
      // own `.options` as the base LayerOptions, not the
      // MarkerClusterGroupOptions its constructor actually takes.
      (cluster.options as import('leaflet').MarkerClusterGroupOptions).iconCreateFunction = clusterIcon;

      // ── Station pins ───────────────────────────────────────────────────
      //
      // Replaces the coverage rectangles this layer used to fill in. Those are
      // one 8km box per municipality, seeded by migration 002 and shared
      // verbatim by all three of its agencies — drawing them claimed a
      // surveyed boundary that does not exist, and stacked three identical
      // shapes per box so the visible colour was just whichever drew last.
      //
      // A station is the opposite kind of fact: real coordinates, and each
      // agency's are its own. BFP, PNP and MDRRMO in Naval are three points a
      // few metres apart, so they no longer collide at all.
      if (layers.stations) {
        for (const st of data.stations) {
          if (st.agency_type && !agencies[st.agency_type as AgencyKey]) continue;
          const c = agencyColor(color, st.agency_type);

          // The agency's own artwork, with its name written underneath —
          // "BFP Naval", "PNP Almeria". Three icons have to serve twenty-one
          // stations, so the icon says what kind of station this is and the
          // label says which one. See map-markers.ts.
          //
          // iconAnchor sits at the pin's POINT, not the centre of the image:
          // the art has a drop shadow below the point, and anchoring at the
          // bottom edge would place every station a few metres north of its
          // real coordinates.
          const art = st.agency_type ? AGENCY_MARKER[st.agency_type] : null;
          const label = stationLabel(st);

          const pin = art
            ? L.divIcon({
                className:  '',
                iconSize:   [PIN_W, PIN_H],
                iconAnchor: [PIN_W / 2, Math.round(PIN_H * PIN_TIP_RATIO)],
                html: markerHtml({
                  src: art, w: PIN_W, h: PIN_H, label, labelColor: c,
                }),
              })
            // A station whose agency row carries no type still gets drawn.
            // There is no artwork for "unknown", so it falls back to the
            // teardrop this layer used before — dropping the pin would hide a
            // station that exists.
            : L.divIcon({
                className:  '',
                iconSize:   [22, 28],
                iconAnchor: [11, 28],
                html: [
                  '<svg width="22" height="28" viewBox="0 0 22 28" xmlns="http://www.w3.org/2000/svg">',
                  '<path d="M11 27C11 27 20 16.5 20 10A9 9 0 1 0 2 10C2 16.5 11 27 11 27Z"',
                  ` fill="${c}" stroke="${color.markStroke}" stroke-width="2" stroke-linejoin="round"/>`,
                  `<circle cx="11" cy="10" r="3.2" fill="${color.markStroke}"/>`,
                  '</svg>',
                ].join(''),
              });

          L.marker([st.lat, st.lng], { icon: pin })
            .bindTooltip(escapeHtml(stationTooltip(st)), { sticky: true })
            .addTo(group);
        }
      }

      // ── Incident markers ───────────────────────────────────────────────
      if (layers.incidents) {
        for (const inc of data.incidents) {
          const key = severityKey(inc.severity);
          if (!severities.has(key)) continue;

          const sevColor = color[key];

          // A resident's pin, with the severity written on a chip beneath it.
          //
          // WHY THE CHIP IS FILLED WITH THE SEVERITY COLOUR
          //
          // This layer used to be a circle whose colour WAS the severity, and
          // one piece of artwork for every report cannot carry that: twenty
          // identical blue pins say who reported and nothing about which one
          // is burning. Putting the colour on the chip keeps the fast visual
          // channel exactly where it was, and now the word is there too — so
          // a dispatcher who cannot separate red from green reads "CRITICAL"
          // instead of guessing, which the circle never let them do without
          // hovering.
          //
          // The chip is exempt from the zoom gate. See markerHtml.
          const icon = L.divIcon({
            className:  '',
            iconSize:   [PERSON_W, PERSON_H],
            iconAnchor: [PERSON_W / 2, Math.round(PERSON_H * PERSON_TIP_RATIO)],
            html: markerHtml({
              src:        RESIDENT_MARKER,
              w:          PERSON_W,
              h:          PERSON_H,
              label:      inc.sos_flagged
                            ? `SOS · ${SEVERITY_LABEL[key].toUpperCase()}`
                            : SEVERITY_LABEL[key].toUpperCase(),
              labelColor: sevColor,
              labelBg:    sevColor,
              alwaysLabel: true,
            }),
          });

          // Worst on top.
          //
          // Leaflet stacks markers by latitude, which is meaningless here: in
          // a town centre several reports land within a few hundred metres and
          // their chips overlap, and whichever happened to be furthest south
          // won. That put "LOW" over "CRITICAL" for no reason a dispatcher
          // could see. Ranking by severity means the chip left readable in a
          // clump is always the most urgent one in it, and an SOS outranks
          // everything at its own tier.
          const marker = L.marker([inc.lat, inc.lng], {
            icon,
            zIndexOffset: SEVERITY_STACK[key] + (inc.sos_flagged ? 50 : 0),
            // Read back by the cluster's iconCreateFunction above — not a
            // real Leaflet marker option, but options objects pass through
            // untouched, which is the supported way to tag a marker with
            // caller data.
            zSeverity: key,
            zSos: inc.sos_flagged,
          } as import('leaflet').MarkerOptions);

          // SOS pulsing effect via className (CSS animation defined below)
          if (inc.sos_flagged) {
            marker.on('add', () => {
              const el = marker.getElement();
              if (el) el.classList.add('sos-pulse');
            });
          }

          marker.on('click', () => setSelected(inc));
          marker.bindTooltip(
            escapeHtml(
              `${(inc.severity ?? 'unscored').toUpperCase()} · ${inc.report_text.slice(0, 60)}…`,
            ),
            { sticky: true },
          );
          cluster.addLayer(marker);
        }
      }

      // ── Responder markers ──────────────────────────────────────────────
      if (layers.responders) {
        for (const resp of data.responders) {
          if (resp.lat === null || resp.lng === null) continue;
          // A responder with no agency is still drawn — they are on duty and
          // on the island, and dropping them would be hiding a person.
          if (resp.agency_type && !agencies[resp.agency_type as AgencyKey]) continue;
          const respColor = agencyColor(color, resp.agency_type);

          // One icon for every responder, labelled "Responder", and a distinct
          // silhouette from the station pins so the two never read as the same
          // kind of thing.
          //
          // WHAT THIS GAVE UP: the triangle it replaces was filled with the
          // responder's AGENCY colour, so a dispatcher could see at a glance
          // that the nearest crew was PNP rather than BFP. A single piece of
          // artwork cannot carry that. The agency is still on the hover
          // tooltip, and the label has room for it — say the word and it
          // becomes "Responder · BFP".
          const icon = L.divIcon({
            className:  '',
            iconSize:   [PERSON_W, PERSON_H],
            iconAnchor: [PERSON_W / 2, Math.round(PERSON_H * PERSON_TIP_RATIO)],
            html: markerHtml({
              src:        RESPONDER_MARKER,
              w:          PERSON_W,
              h:          PERSON_H,
              label:      'Responder',
              labelColor: respColor,
            }),
          });

          const detail = [resp.full_name ?? 'Responder', resp.badge_id, resp.agency_type]
            .filter(Boolean)
            .join(' · ');

          L.marker([resp.lat, resp.lng], { icon })
            .bindTooltip(escapeHtml(detail), { sticky: true })
            .addTo(group);
        }
      }
    });

    return () => { cancelled = true; };
  }, [data, layers, severities, agencies, color, mapReady]);

  // A selected incident the filters have since hidden must not keep its panel
  // open — the panel would be describing a mark no longer on the map.
  useEffect(() => {
    if (!selected) return;
    if (!layers.incidents || !severities.has(severityKey(selected.severity))) {
      setSelected(null);
    }
  }, [selected, layers.incidents, severities]);

  // ── Render ───────────────────────────────────────────────────────────────
  return (
    <>
      {/* Leaflet CSS — must be loaded at runtime */}
      <link
        rel="stylesheet"
        href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"
        crossOrigin=""
      />

      {/* SOS pulse. A fade rather than a growing ring, because a circleMarker's
          radius is an SVG attribute Leaflet rewrites on every zoom — animating
          it in CSS fights the projection. */}
      <style>{`
        /* ── Marker pins ────────────────────────────────────────────────
           The label sits under the art and is allowed to overflow the
           divIcon's declared box: iconSize describes the PIN, because that is
           what iconAnchor is measured against, and a box tall enough to
           contain the label too would put the anchor in the wrong place. */
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
        /* Zoomed out past LABEL_MIN_ZOOM. Twenty-one labels over the whole
           island is a wall of text with a map behind it. */
        .zmk-far .zmk-label { display: none; }
        /* …except the severity chips. Declared after the rule above so it wins
           on equal specificity. An incident's severity is the reason the wide
           view is being looked at; hiding it there would empty the map of the
           only thing that decides where people get sent. */
        .zmk-far .zmk-label-keep { display: inline; }

        .sos-pulse { animation: sos-ring 1.2s ease-out infinite; }
        @keyframes sos-ring {
          0%   { opacity: 1; }
          50%  { opacity: 0.4; }
          100% { opacity: 1; }
        }
        @media (prefers-reduced-motion: reduce) {
          .sos-pulse { animation: none; }
        }
      `}</style>

      <div ref={mapContainerRef} className="h-full w-full" />

      {selected && (
        <IncidentPanel
          agencyColor={agencyColor(color, selected.agency_type)}
          incident={selected}
          onClose={() => setSelected(null)}
          onOpenDetail={onOpenIncident}
          severityColor={color[severityKey(selected.severity)]}
        />
      )}
    </>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function IncidentPanel({
  incident,
  onClose,
  onOpenDetail,
  severityColor,
  agencyColor,
}: {
  incident: MapIncident;
  onClose: () => void;
  onOpenDetail: (id: string) => void;
  severityColor: string;
  agencyColor: string;
}) {
  const sev = incident.severity ?? 'unscored';
  const shortId = incident.id.replace(/-/g, '').toUpperCase().slice(-6);

  const timeAgo = useMemo(() => {
    const m = Math.floor((Date.now() - new Date(incident.created_at).getTime()) / 60000);
    if (m < 1) return 'Just now';
    if (m < 60) return `${m}m ago`;
    const h = Math.floor(m / 60);
    return h < 24 ? `${h}h ago` : `${Math.floor(h / 24)}d ago`;
  }, [incident.created_at]);

  return (
    /* top-3, not top-14. The 14 was clearing a page header this route no
       longer has — the breadcrumb names the page now — and left the panel
       floating in a gap. */
    <div className="absolute top-3 right-3 z-[1000] w-80 overflow-hidden rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-lg)]">
      {/* Severity strip */}
      <div className="h-1.5 w-full" style={{ backgroundColor: severityColor }} />

      <div className="p-4">
        {/* Header row */}
        <div className="mb-3 flex items-start justify-between gap-2">
          <div className="flex flex-wrap items-center gap-1.5">
            <span
              className="rounded-full px-2 py-0.5 text-[11px] font-bold"
              style={{
                backgroundColor: `color-mix(in srgb, ${severityColor} 14%, transparent)`,
                color: severityColor,
              }}
            >
              {sev.toUpperCase()}
            </span>
            {incident.agency_type && (
              <span
                className="rounded-full px-2 py-0.5 text-[11px] font-bold"
                style={{
                  backgroundColor: `color-mix(in srgb, ${agencyColor} 14%, transparent)`,
                  color: agencyColor,
                }}
              >
                {incident.agency_type}
              </span>
            )}
            {incident.sos_flagged && (
              <span className="rounded-full bg-[var(--color-severity-critical-bg)] px-2 py-0.5 text-[11px] font-bold text-[var(--color-severity-critical)]">
                SOS
              </span>
            )}
          </div>
          <button
            aria-label="Close incident preview"
            className="shrink-0 rounded-md p-1 text-[var(--color-text-muted)] transition-colors hover:bg-[var(--color-surface-raised)]"
            onClick={onClose}
          >
            <X aria-hidden="true" className="h-4 w-4" />
          </button>
        </div>

        {/* Report text */}
        <p className="mb-3 line-clamp-3 text-[14px] leading-snug font-semibold text-[var(--color-text-primary)]">
          {incident.report_text}
        </p>

        {/* Meta */}
        <div className="mb-4 flex items-center justify-between text-[12px] text-[var(--color-text-muted)]">
          <span className="font-mono font-semibold text-[var(--color-text-secondary)]">
            INC-{shortId}
          </span>
          <span>{timeAgo}</span>
        </div>

        {/* Status pill */}
        <div className="flex items-center justify-between">
          <StatusPill status={incident.status} />
          {/* Opens the same detail modal the queue uses, not a Link to the
              full page — see this component's onOpenIncident doc comment. */}
          <button
            className="flex items-center gap-1 text-[12px] font-semibold text-[var(--color-brand)] hover:underline"
            onClick={() => onOpenDetail(incident.id)}
            type="button"
          >
            View full detail <ChevronRight className="h-3 w-3" />
          </button>
        </div>
      </div>
    </div>
  );
}

function StatusPill({ status }: { status: string }) {
  const map: Record<string, { bg: string; text: string }> = {
    received:   { bg: 'var(--color-status-received-bg)',   text: 'var(--color-status-received)'   },
    processing: { bg: 'var(--color-status-processing-bg)', text: 'var(--color-status-processing)' },
    dispatched: { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
    en_route:   { bg: 'var(--color-status-dispatched-bg)', text: 'var(--color-status-dispatched)' },
    arrived:    { bg: 'var(--color-system-success-bg)',    text: 'var(--color-system-success)'    },
  };
  const c = map[status] ?? map.received;
  return (
    <span
      className="rounded-full px-2.5 py-1 text-[11px] font-bold"
      style={{ backgroundColor: c.bg, color: c.text }}
    >
      {status.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
    </span>
  );
}
