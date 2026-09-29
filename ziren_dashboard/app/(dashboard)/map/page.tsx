'use client';

import { Suspense, useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import { useSearchParams } from 'next/navigation';
import { useAuth } from '@/lib/hooks/useAuth';
import { useMapData } from '@/lib/hooks/useMapData';
import { mapPrefs } from '@/lib/prefs/definitions';
import { IncidentDetailModal } from '@/components/incidents/incident-detail-modal';
import { MapToolbar } from '@/components/map/map-toolbar';
import {
  AGENCY_KEYS,
  ALL_AGENCIES,
  ALL_LAYERS,
  LAYER_KEYS,
  SEVERITY_KEYS,
  severityKey,
  type AgencyFilter,
  type AgencyKey,
  type MapLayerKey,
  type MapLayerState,
  type SeverityKey,
} from '@/components/map/map-legend';

// MapLibre reads `window` on mount — must be client-only, no SSR.
const ZirenMap = dynamic(() => import('@/components/map/ZirenMap'), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-[var(--color-brand)] border-t-transparent" />
        <p className="text-[14px] text-[var(--color-text-muted)]">Loading map…</p>
      </div>
    </div>
  ),
});

/**
 * useSearchParams forces the nearest boundary to render on the client, so the
 * page needs a Suspense wrapper or the build fails prerendering it.
 */
export default function MapPage() {
  return (
    <Suspense fallback={null}>
      <MapView />
    </Suspense>
  );
}

function MapView() {
  const { token } = useAuth();
  // Set by the queue's "View on map": pan to this one and open its panel.
  const focusIncidentId = useSearchParams().get('incident');

  // Which layers are on when the map opens is the operator's choice (Settings →
  // Map & Location). They can still be toggled from the toolbar for this visit
  // without touching the saved default.
  const [layers, setLayers] = useState<MapLayerState>(() => {
    const p = mapPrefs.get();
    return { ...ALL_LAYERS, incidents: p.layerIncidents, responders: p.layerResponders, stations: p.layerStations };
  });
  const [severities, setSeverities] = useState<Set<SeverityKey>>(
    () => new Set(SEVERITY_KEYS),
  );
  const [agencies, setAgencies] = useState<AgencyFilter>(ALL_AGENCIES);
  // The marker popup's "View full detail" used to be a Link to
  // /incidents/{id} — the one place on the map still routing to the full
  // page after the queue's own detail view moved into a modal. Fixed
  // 2026-09-15; this is the same open-in-place pattern active-view.tsx uses.
  const [openId, setOpenId] = useState<string | null>(null);

  // Always 'operational' — the live, active-incidents map. This page used to
  // offer Provincial Admin a Network/History toggle the Agency Admin never
  // saw (spec Section 7A/7B), which made the two roles' maps look like
  // different features rather than the same one. At the user's request the
  // Incident Map is now identical for both: same toolbar, same layers, same
  // always-live view. Historical/resolved incidents are Incident History's
  // job (see /incident-history), not this page's.
  const { data, loading, error, lastRefresh } = useMapData(token, 'operational');

  /**
   * How many incidents sit in each bucket — computed BEFORE the severity
   * filter, so a chip can honestly say how much it would reveal. A count that
   * dropped to zero the moment you switched a tier off would make the filter
   * impossible to undo by eye.
   */
  const severityCounts = useMemo(() => {
    const out = Object.fromEntries(
      SEVERITY_KEYS.map(k => [k, 0]),
    ) as Record<SeverityKey, number>;
    for (const inc of data?.incidents ?? []) out[severityKey(inc.severity)] += 1;
    return out;
  }, [data]);

  /**
   * How many marks of each layer are actually DRAWN. The incidents figure
   * follows the severity filter, because the chip stands beside the map and a
   * number that disagreed with the dots under it would be the same defect the
   * old static legend had.
   */
  /**
   * Coverage polygons per agency, BEFORE the agency filter — so a chip can
   * say what it would reveal rather than collapsing to zero when switched off.
   */
  const agencyCounts = useMemo(() => {
    const out = Object.fromEntries(AGENCY_KEYS.map(k => [k, 0])) as Record<AgencyKey, number>;
    for (const st of data?.stations ?? []) {
      const k = st.agency_type as AgencyKey;
      if (k in out) out[k] += 1;
    }
    return out;
  }, [data]);

  const layerCounts = useMemo(() => {
    const drawnIncidents = (data?.incidents ?? []).filter(i =>
      severities.has(severityKey(i.severity)),
    ).length;
    return {
      incidents: layers.incidents ? drawnIncidents : 0,
      responders: layers.responders
        ? (data?.responders ?? []).filter(
            r =>
              r.lat !== null &&
              r.lng !== null &&
              (!r.agency_type || agencies[r.agency_type as AgencyKey]),
          ).length
        : 0,
      stations: layers.stations
        ? (data?.stations ?? []).filter(
            st => !st.agency_type || agencies[st.agency_type as AgencyKey],
          ).length
        : 0,
    } as Record<MapLayerKey, number>;
  }, [data, layers, severities, agencies]);

  if (!token) return null;

  /**
   * h-full, NOT 100vh.
   *
   * The shell gives this page a pane that is already the viewport minus the
   * header, inside an overflow-hidden inset. A 100vh child was therefore taller
   * than the box holding it by the height of the header — enough to push the
   * OSM attribution and the map's own bottom controls below the fold, on a
   * page that must not scroll at all.
   */
  return (
    <div className="flex h-full flex-col">
      <MapToolbar
        lastRefresh={lastRefresh}
        layerCounts={layerCounts}
        layers={layers}
        agencies={agencies}
        agencyCounts={agencyCounts}
        onAgenciesChange={setAgencies}
        onLayersChange={setLayers}
        onSeveritiesChange={setSeverities}
        severities={severities}
        severityCounts={severityCounts}
        stale={Boolean(error)}
      />

      {/* min-h-0 so this pane can shrink inside the flex column. Without it a
          flex item's implicit min-height:auto floors it at its content height
          and the toolbar gets pushed off the top. */}
      <div className="relative min-h-0 flex-1">
        {loading && !data ? (
          <div className="flex h-full items-center justify-center">
            <div className="flex flex-col items-center gap-3">
              <div className="h-8 w-8 animate-spin rounded-full border-4 border-[var(--color-brand)] border-t-transparent" />
              <p className="text-[14px] text-[var(--color-text-muted)]">
                Loading incidents…
              </p>
            </div>
          </div>
        ) : error && !data ? (
          /* Only when there is nothing to show. A failed poll over data
             already on screen is reported as staleness in the toolbar, not as
             a blank map — a dispatcher losing the network should keep the
             incidents they had, clearly marked as no longer live. */
          <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
            <p className="text-[15px] font-semibold text-[var(--color-text-primary)]">
              Could not load the map
            </p>
            <p className="max-w-sm text-[13px] text-[var(--color-text-muted)]">
              {error}
            </p>
          </div>
        ) : (
          <ZirenMap
            agencies={agencies}
            data={data}
            focusIncidentId={focusIncidentId}
            layers={layers}
            onOpenIncident={setOpenId}
            severities={severities}
          />
        )}

        {/* Every layer switched off is a legitimate state, not an empty one —
            but an unexplained blank island reads as a broken page. */}
        {data && LAYER_KEYS.every(k => !layers[k]) && (
          <div className="pointer-events-none absolute inset-x-0 top-4 z-[999] flex justify-center">
            <p className="pointer-events-auto rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-1.5 text-meta text-[var(--color-text-secondary)] shadow-[var(--shadow-md)]">
              All layers hidden — turn one on above to see the map data.
            </p>
          </div>
        )}
      </div>

      <IncidentDetailModal incidentId={openId} onClose={() => setOpenId(null)} />
    </div>
  );
}

