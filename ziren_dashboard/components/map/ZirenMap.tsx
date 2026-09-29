'use client';

/**
 * ZirenMap — the Incident Map surface, on MapLibre GL. Marks only; no chrome,
 * no fetching.
 *
 * The page owns the data (useMapData) and the visibility state, and hands both
 * down. This file draws what it is given.
 *
 * Marks:
 *   1. Station pins      — the agency's own artwork, labelled "BFP Naval"
 *   2. Incident markers  — a resident pin, with SEVERITY on the chip below it,
 *                          clustered where reports pile up
 *   3. Responder markers — a responder pin, labelled
 *
 * Every marker carries a WORD as well as a colour. That is not decoration: an
 * island this small puts marks of different meaning on the same pixel all the
 * time, colour alone is unreadable to a red-green deficient dispatcher, and
 * the severity chip has to survive being printed in greyscale for a shift
 * handover. Station labels hide when you zoom out past LABEL_MIN_ZOOM because
 * twenty-one of them is a wall of text; incident chips never hide, because
 * severity is the one fact the widest view exists to show.
 *
 * The basemap (our own Biliran street map, or Esri satellite over it) comes
 * from maplibre-style.ts — see there for why the tiles are self-hosted.
 *
 * MOVED FROM LEAFLET 2026-09-29. The marker vocabulary, the clustering radius
 * and every behaviour below were kept as they were; only the engine changed.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import Supercluster from 'supercluster';
import type { Marker, Popup } from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { mapPrefs } from '@/lib/prefs/definitions';
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
  LABEL_MIN_ZOOM,
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
  RESPONDER_MARKER,
  SEVERITY_STACK,
  stationLabel,
  stationTooltip,
  teardropSvg,
} from './map-markers';
import { MapSearch } from './map-search';
import { useMapLibre } from './use-maplibre';

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
   * Which agencies' stations and responders to draw.
   *
   * Incidents are NOT filtered by it. An incident's colour is its severity,
   * and its agency is only where it was routed — hiding unrouted incidents
   * because they have no agency would remove exactly the ones that most need
   * looking at.
   */
  agencies: AgencyFilter;
  /** Opens the incident detail MODAL over the page. */
  onOpenIncident: (id: string) => void;
  /**
   * Frame these [lat, lng] points instead of the whole island — the
   * Operational Area screen opens on ONE municipality. Re-fits whenever `key`
   * changes, and only then: the map polls, so re-fitting on every refresh
   * would snatch the view back from wherever the viewer had panned.
   */
  fitTo?: { key: string; points: [number, number][] } | null;
}

/**
 * Cluster radius, in pixels. Deliberately small (the Leaflet default was 80):
 * this is a triage map, so incidents should stop clumping as soon as the zoom
 * is loose enough to tell them apart — clustering only absorbs literal
 * pixel-on-pixel overlap. Past CLUSTER_MAX_ZOOM nothing clusters; reports at
 * the very same spot open as a list instead (see ClusterList).
 */
const CLUSTER_RADIUS = 40;
const CLUSTER_MAX_ZOOM = 17;

type IncidentPoint = { inc: MapIncident; key: SeverityKey; rank: number; sos: number };
type ClusterProps = { rank: number; sos: number };

export default function ZirenMap({
  data,
  focusIncidentId,
  layers,
  severities,
  agencies,
  onOpenIncident,
  fitTo,
}: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const { map, maplibre } = useMapLibre(containerRef, { controls: 'top-left', rotate: true });

  const [selected, setSelected] = useState<MapIncident | null>(null);
  const [clusterList, setClusterList] = useState<MapIncident[] | null>(null);
  /** Bumped when the view settles, so incident clusters are recomputed for it. */
  const [viewTick, setViewTick] = useState(0);

  // Concrete hexes read out of globals.css, re-read when the theme flips.
  // Marker HTML is a string and cannot resolve var() inside inline styles the
  // cluster badge builds — see use-token-colors.
  const color = useTokenColors(MAP_COLOR_TOKENS);
  const { alwaysLabels } = mapPrefs.use();

  // One hover label, reused by every marker.
  const tipRef = useRef<Popup | null>(null);
  function attachTip(el: HTMLElement, lngLat: [number, number], text: string) {
    if (!map || !maplibre) return;
    el.addEventListener('mouseenter', () => {
      tipRef.current ??= new maplibre.Popup({ closeButton: false, closeOnClick: false, className: 'zmk-tip', offset: 14 });
      tipRef.current.setLngLat(lngLat).setText(text).addTo(map);
    });
    el.addEventListener('mouseleave', () => tipRef.current?.remove());
  }

  // ── Labels by zoom ──────────────────────────────────────────────────────
  // A class on the container rather than rebuilding markers: one className
  // flip shows or hides every label in CSS.
  useEffect(() => {
    if (!map) return;
    const sync = () => containerRef.current?.classList.toggle(
      'zmk-far', !mapPrefs.get().alwaysLabels && map.getZoom() < LABEL_MIN_ZOOM,
    );
    sync();
    map.on('zoomend', sync);
    return () => { map.off('zoomend', sync); };
  }, [map, alwaysLabels]);

  // Re-cluster when the view settles.
  useEffect(() => {
    if (!map) return;
    const bump = () => setViewTick(t => t + 1);
    map.on('moveend', bump);
    return () => { map.off('moveend', bump); };
  }, [map]);

  // ── Focus one incident (once per id) ────────────────────────────────────
  const focusedRef = useRef<string | null>(null);
  useEffect(() => {
    if (!focusIncidentId || !data || !map) return;
    if (focusedRef.current === focusIncidentId) return;
    const target = data.incidents.find(i => i.id === focusIncidentId);
    if (!target) return;
    focusedRef.current = focusIncidentId;
    map.flyTo({ center: [target.lng, target.lat], zoom: 16, duration: 800 });
    setSelected(target);
  }, [focusIncidentId, data, map]);

  // ── Frame a set of points (once per key) ────────────────────────────────
  const fittedRef = useRef<string | null>(null);
  useEffect(() => {
    if (!fitTo || !map || !maplibre) return;
    if (fittedRef.current === fitTo.key) return;
    fittedRef.current = fitTo.key;
    const pts = fitTo.points;
    if (pts.length === 0) return;
    map.resize();
    if (pts.length === 1) {
      map.jumpTo({ center: [pts[0][1], pts[0][0]], zoom: 15 });
      return;
    }
    const bounds = new maplibre.LngLatBounds();
    for (const [lat, lng] of pts) bounds.extend([lng, lat]);
    map.fitBounds(bounds, { padding: 48, maxZoom: 15, animate: false });
  }, [fitTo, map, maplibre]);

  // ── Stations and responders (never clustered) ───────────────────────────
  useEffect(() => {
    if (!map || !maplibre || !data) return;
    const added: Marker[] = [];
    const place = (html: string, w: number, h: number, tip: number, lng: number, lat: number, tooltip: string, z = 0) => {
      const { element, offset } = markerElement(html, w, h, tip);
      element.style.zIndex = String(z);
      attachTip(element, [lng, lat], tooltip);
      added.push(new maplibre.Marker({ element, anchor: 'top-left', offset }).setLngLat([lng, lat]).addTo(map));
    };

    if (layers.stations) {
      for (const st of data.stations) {
        if (st.agency_type && !agencies[st.agency_type as AgencyKey]) continue;
        const c = agencyColor(color, st.agency_type);
        const art = st.agency_type ? AGENCY_MARKER[st.agency_type] : null;
        // The agency's own artwork with "BFP Naval" under it; a station whose
        // agency row carries no type still gets a plain teardrop — dropping the
        // pin would hide a station that exists.
        if (art) {
          place(markerHtml({ src: art, w: PIN_W, h: PIN_H, label: stationLabel(st), labelColor: c }),
            PIN_W, PIN_H, PIN_TIP_RATIO, st.lng, st.lat, stationTooltip(st), 10);
        } else {
          place(teardropSvg(c, color.markStroke), 22, 28, 1, st.lng, st.lat, stationTooltip(st), 10);
        }
      }
    }

    if (layers.responders) {
      for (const resp of data.responders) {
        if (resp.lat === null || resp.lng === null) continue;
        // A responder with no agency is still drawn — dropping them would be
        // hiding a person on duty.
        if (resp.agency_type && !agencies[resp.agency_type as AgencyKey]) continue;
        const detail = [resp.full_name ?? 'Responder', resp.badge_id, resp.agency_type].filter(Boolean).join(' · ');
        place(markerHtml({ src: RESPONDER_MARKER, w: PERSON_W, h: PERSON_H, label: 'Responder', labelColor: agencyColor(color, resp.agency_type) }),
          PERSON_W, PERSON_H, PERSON_TIP_RATIO, resp.lng, resp.lat, detail, 20);
      }
    }

    return () => { for (const m of added) m.remove(); };
    // attachTip closes over map/maplibre, both deps already.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, maplibre, data, layers.stations, layers.responders, agencies, color]);

  // ── Incidents: a cluster index over the visible severities ──────────────
  const index = useMemo(() => {
    if (!data || !layers.incidents) return null;
    const points: Supercluster.PointFeature<IncidentPoint>[] = [];
    for (const inc of data.incidents) {
      const key = severityKey(inc.severity);
      if (!severities.has(key)) continue;
      points.push({
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [inc.lng, inc.lat] },
        properties: { inc, key, rank: SEVERITY_STACK[key] ?? 0, sos: inc.sos_flagged ? 1 : 0 },
      });
    }
    const sc = new Supercluster<IncidentPoint, ClusterProps>({
      radius: CLUSTER_RADIUS,
      maxZoom: CLUSTER_MAX_ZOOM,
      map: p => ({ rank: p.rank, sos: p.sos }),
      reduce: (acc, p) => { acc.rank = Math.max(acc.rank, p.rank); acc.sos = Math.max(acc.sos, p.sos); },
    });
    sc.load(points);
    return sc;
  }, [data, layers.incidents, severities]);

  useEffect(() => {
    if (!map || !maplibre || !index) return;
    const b = map.getBounds();
    const zoom = Math.floor(map.getZoom());
    const features = index.getClusters([b.getWest() - 0.02, b.getSouth() - 0.02, b.getEast() + 0.02, b.getNorth() + 0.02], zoom);
    const added: Marker[] = [];

    for (const f of features) {
      const [lng, lat] = f.geometry.coordinates;
      const props = f.properties as Partial<Supercluster.ClusterProperties> & (IncidentPoint | ClusterProps);

      if (props.cluster) {
        // A cluster badge: the count, filled with the WORST severity inside it,
        // pulsing if any report in it is an SOS.
        const worst = (Object.entries(SEVERITY_STACK).find(([, r]) => r === props.rank)?.[0] ?? 'unscored') as SeverityKey;
        const el = document.createElement('div');
        el.className = 'zmk-marker';
        el.style.zIndex = String(1000 + (props.rank ?? 0));
        // eslint-disable-next-line no-restricted-syntax -- only a number and token colours, no user text
        el.innerHTML = `<div class="${props.sos ? 'sos-pulse' : ''}" style="display:flex;align-items:center;justify-content:center;width:36px;height:36px;border-radius:9999px;background:${color[worst]};color:${color.markStroke};border:2px solid ${color.markStroke};box-shadow:0 1px 3px rgba(0,0,0,0.35);font:700 13px var(--font-sans, sans-serif);line-height:1;">${props.point_count}</div>`;
        const clusterId = props.cluster_id as number;
        el.addEventListener('click', e => {
          e.stopPropagation();
          const next = index.getClusterExpansionZoom(clusterId);
          if (next <= CLUSTER_MAX_ZOOM) {
            map.easeTo({ center: [lng, lat], zoom: next + 0.2, duration: 500 });
          } else {
            // The same spot, or near enough that no zoom separates them: list them.
            setClusterList(index.getLeaves(clusterId, Infinity).map(l => (l.properties as IncidentPoint).inc));
          }
        });
        attachTip(el, [lng, lat], `${props.point_count} reports here — click to zoom in`);
        added.push(new maplibre.Marker({ element: el }).setLngLat([lng, lat]).addTo(map));
        continue;
      }

      const { inc, key } = props as IncidentPoint;
      const sevColor = color[key];
      const { element, offset } = markerElement(markerHtml({
        src: RESIDENT_MARKER, w: PERSON_W, h: PERSON_H,
        label: inc.sos_flagged ? `SOS · ${SEVERITY_LABEL[key].toUpperCase()}` : SEVERITY_LABEL[key].toUpperCase(),
        labelColor: sevColor, labelBg: sevColor, alwaysLabel: true,
      }), PERSON_W, PERSON_H, PERSON_TIP_RATIO);
      // Worst on top, SOS above its own tier.
      element.style.zIndex = String(1000 + (SEVERITY_STACK[key] ?? 0) + (inc.sos_flagged ? 50 : 0));
      if (inc.sos_flagged) element.classList.add('sos-pulse');
      element.addEventListener('click', e => { e.stopPropagation(); setClusterList(null); setSelected(inc); });
      attachTip(element, [lng, lat], `${(inc.severity ?? 'unscored').toUpperCase()} · ${inc.report_text.slice(0, 60)}…`);
      added.push(new maplibre.Marker({ element, anchor: 'top-left', offset }).setLngLat([lng, lat]).addTo(map));
    }

    return () => { for (const m of added) m.remove(); tipRef.current?.remove(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, maplibre, index, color, viewTick]);

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
      <style>{MARKER_CSS}</style>
      {/* `isolate`: markers carry z-indexes (worst severity on top) that must
          stack INSIDE the map, never over the incident panel beside it. */}
      <div ref={containerRef} className="isolate h-full w-full" />

      {/* Beside the zoom buttons (top-left), clear of the incident panel that
          opens top-right. */}
      <MapSearch className="absolute left-14 top-2.5 z-[900]" map={map} maplibre={maplibre} />

      {clusterList && !selected && (
        <ClusterList
          color={color}
          incidents={clusterList}
          onClose={() => setClusterList(null)}
          onPick={inc => { setClusterList(null); setSelected(inc); }}
        />
      )}

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

/** Reports stacked on one spot, as a list — no zoom level separates them. */
function ClusterList({
  incidents, color, onPick, onClose,
}: {
  incidents: MapIncident[];
  color: Record<string, string>;
  onPick: (inc: MapIncident) => void;
  onClose: () => void;
}) {
  const sorted = [...incidents].sort((a, b) =>
    (SEVERITY_STACK[severityKey(b.severity)] ?? 0) - (SEVERITY_STACK[severityKey(a.severity)] ?? 0));
  return (
    <div className="absolute right-3 top-3 z-[1000] w-80 overflow-hidden rounded-[var(--radius-xl)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-lg)]">
      <div className="flex items-center justify-between border-b border-[var(--color-surface-border)] px-4 py-3">
        <p className="text-[13px] font-bold text-[var(--color-text-primary)]">{incidents.length} reports at this spot</p>
        <button aria-label="Close list" className="rounded-md p-1 text-[var(--color-text-muted)] hover:bg-[var(--color-surface-raised)]" onClick={onClose} type="button">
          <X aria-hidden="true" className="h-4 w-4" />
        </button>
      </div>
      <ul className="max-h-80 divide-y divide-[var(--color-surface-border)] overflow-y-auto">
        {sorted.map(inc => {
          const key = severityKey(inc.severity);
          return (
            <li key={inc.id}>
              <button className="flex w-full items-start gap-2.5 px-4 py-2.5 text-left hover:bg-[var(--color-surface-raised)]" onClick={() => onPick(inc)} type="button">
                <span className="mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-[10px] font-bold text-white" style={{ backgroundColor: color[key] }}>
                  {SEVERITY_LABEL[key].toUpperCase()}
                </span>
                <span className="line-clamp-2 text-[12.5px] text-[var(--color-text-primary)]">{inc.report_text}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
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
