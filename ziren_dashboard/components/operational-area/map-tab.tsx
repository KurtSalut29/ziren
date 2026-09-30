'use client';

import { useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import { Info } from 'lucide-react';
import type { OperationalArea } from '@/lib/api/operational-area';
import { MapToolbar } from '@/components/map/map-toolbar';
import {
  AGENCY_KEYS,
  ALL_AGENCIES,
  ALL_LAYERS,
  SEVERITY_KEYS,
  severityKey,
  type AgencyFilter,
  type AgencyKey,
  type MapLayerKey,
  type MapLayerState,
  type SeverityKey,
} from '@/components/map/map-legend';
import { mapPrefs } from '@/lib/prefs/definitions';
import { periodLong } from './period';

// MapLibre reads `window` on mount — client-only, no SSR.
const ZirenMap = dynamic(() => import('@/components/map/ZirenMap'), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center">
      <div className="h-8 w-8 animate-spin rounded-full border-4 border-[var(--color-brand)] border-t-transparent" />
    </div>
  ),
});

/**
 * The area's map: this municipality's stations, the responders on duty, and
 * every report from the chosen period that carried coordinates — framed on the
 * area, not on the whole island.
 *
 * It is the SAME map as the Incident Map, with the same legend and filters, fed
 * a different question: the Incident Map answers "what is open right now", this
 * one "where did things happen in this period".
 *
 * Coverage polygons are deliberately not drawn (payload.coverage_polygons is
 * always empty): the stored ones are seed rectangles shared by every agency in a
 * municipality, and drawing them would claim a surveyed boundary nobody drew.
 */
export function MapTab({
  data,
  onOpenIncident,
}: {
  data: OperationalArea;
  onOpenIncident: (id: string) => void;
}) {
  const map = data.map;
  const [layers, setLayers] = useState<MapLayerState>(() => {
    const p = mapPrefs.get();
    // The area map is about reports, so it opens with them on whatever the
    // Incident Map's default is.
    return { ...ALL_LAYERS, incidents: true, responders: p.layerResponders, stations: p.layerStations };
  });
  const [severities, setSeverities] = useState<Set<SeverityKey>>(() => new Set(SEVERITY_KEYS));
  const [agencies, setAgencies] = useState<AgencyFilter>(ALL_AGENCIES);

  const severityCounts = useMemo(() => {
    const out = Object.fromEntries(SEVERITY_KEYS.map(k => [k, 0])) as Record<SeverityKey, number>;
    for (const i of map.incidents) out[severityKey(i.severity)] += 1;
    return out;
  }, [map.incidents]);

  const agencyCounts = useMemo(() => {
    const out = Object.fromEntries(AGENCY_KEYS.map(k => [k, 0])) as Record<AgencyKey, number>;
    for (const s of map.stations) if (s.agency_type && s.agency_type in out) out[s.agency_type as AgencyKey] += 1;
    return out;
  }, [map.stations]);

  const layerCounts = useMemo(() => ({
    incidents: layers.incidents ? map.incidents.filter(i => severities.has(severityKey(i.severity))).length : 0,
    responders: layers.responders
      ? map.responders.filter(r => r.lat !== null && r.lng !== null && (!r.agency_type || agencies[r.agency_type as AgencyKey])).length
      : 0,
    stations: layers.stations ? map.stations.filter(s => !s.agency_type || agencies[s.agency_type as AgencyKey]).length : 0,
  }) as Record<MapLayerKey, number>, [map, layers, severities, agencies]);

  // Frame the area: its stations, its on-duty crew and its reports.
  const fitTo = useMemo(() => {
    const points: [number, number][] = [
      ...map.stations.map(s => [s.lat, s.lng] as [number, number]),
      ...map.incidents.map(i => [i.lat, i.lng] as [number, number]),
      ...map.responders.filter(r => r.lat !== null && r.lng !== null).map(r => [r.lat!, r.lng!] as [number, number]),
    ];
    return { key: `${data.area.municipality}|${data.filters.days}|${data.filters.date_from ?? ''}|${data.filters.date_to ?? ''}|${data.filters.barangay ?? ''}`, points };
  }, [map, data.area.municipality, data.filters.days, data.filters.date_from, data.filters.date_to, data.filters.barangay]);

  const total = data.kpis.incidents;
  const missing = total - map.incidents_with_coordinates;

  return (
    <div className="flex flex-col gap-3">
      <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]">
        <MapToolbar
          agencies={agencies}
          agencyCounts={agencyCounts}
          layerCounts={layerCounts}
          layers={layers}
          onAgenciesChange={setAgencies}
          onLayersChange={setLayers}
          onSeveritiesChange={setSeverities}
          severities={severities}
          severityCounts={severityCounts}
        />
        <div className="relative h-[max(460px,calc(var(--app-h,100svh)-360px))]">
          <ZirenMap
            agencies={agencies}
            data={map}
            fitTo={fitTo}
            layers={layers}
            onOpenIncident={onOpenIncident}
            severities={severities}
          />
        </div>
      </div>

      <p className="flex items-start gap-2 px-1 text-[12.5px] leading-relaxed text-muted-foreground">
        <Info aria-hidden="true" className="mt-0.5 size-4 shrink-0" />
        <span>
          Showing <strong className="font-semibold text-foreground">{map.incidents.length}</strong> of {total} report{total === 1 ? '' : 's'} from {periodLong(data.filters)}
          {missing > 0 && <> — {missing} carried no coordinates (address only) and cannot be pinned</>}
          {map.incidents_with_coordinates > map.incidents_shown && <> — the map draws the newest {map.incidents_shown}</>}.
          {' '}No coverage boundary is drawn: the stored ones are placeholder boxes, not surveyed areas. Click a report’s pin to open its record.
        </span>
      </p>
    </div>
  );
}
