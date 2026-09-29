'use client';

/**
 * IncidentLocationPanel — where the emergency is, and how far help has to come.
 *
 * The detail modal used to answer "where" with three lines of text: an
 * address, a pair of coordinates, and the name of a station. A dispatcher
 * cannot triage on that. "Brgy. Caraycaray, Naval" and "MDRRMO Naval" are two
 * names, and nothing in them says whether the crew is four minutes away or on
 * the far side of the ridge — which is the entire decision being made.
 *
 * So the panel draws it: the incident, the station that would answer it, the
 * road between them, and the two numbers that road produces.
 *
 * WHAT IT REFUSES TO CLAIM
 *
 * The distance and the ETA carry their source. When the router answers, the
 * line is a real driving route and the card names the road it mostly follows.
 * When it cannot — offline console, blocked host, a barangay the road graph
 * does not reach — the line is dashed, the card says "straight-line estimate",
 * and the number falls back to the same 30 km/h floor the responder app
 * quotes. Both are useful; only one of them is a route, and blurring the two
 * would hand a dispatcher a confident wrong answer at the moment it costs the
 * most.
 */

import dynamic from 'next/dynamic';
import { Building2, Car, Clock, Info, MapPin, Navigation } from 'lucide-react';
import type { IncidentDetail } from '@/lib/api/dispatch';
import {
  formatDistance,
  geoPoint,
  type ResponseRoute,
} from '@/lib/incidents/response-route';
import { useResponseRoute } from '@/lib/hooks/useResponseRoute';
import {
  agencyVar,
  severityVar,
  type AgencyKey,
  type SeverityKey,
} from '@/components/map/map-legend';

// MapLibre reads `window` on import — client-only, no SSR, as on the map page.
const IncidentRouteMap = dynamic(
  () => import('@/components/incidents/incident-route-map'),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full items-center justify-center bg-[var(--color-surface-raised)]">
        <div className="h-6 w-6 animate-spin rounded-full border-2 border-[var(--color-brand)] border-t-transparent" />
      </div>
    ),
  },
);

const AGENCY_TYPES = new Set(['BFP', 'PNP', 'MDRRMO']);

export function IncidentLocationPanel({
  detail,
  severity,
  scrollWheelZoom,
}: {
  detail: IncidentDetail;
  severity: SeverityKey;
  /** See the identical prop on IncidentRouteMap — passed straight through. */
  scrollWheelZoom?: boolean;
}) {
  const incidentPoint = geoPoint(detail.location);
  const stationPoint = geoPoint(detail.stations?.location);
  const agency = detail.stations?.agencies ?? null;
  const agencyType = (
    agency && AGENCY_TYPES.has(agency.agency_type) ? agency.agency_type : null
  ) as AgencyKey | null;

  const { route, loading } = useResponseRoute(stationPoint, incidentPoint);

  // On duty, at the agency this incident was routed to. Not "how many
  // responders exist" — a station whose whole crew is off shift cannot answer
  // this report, and the strip must not describe it as though it could.
  const onDuty = detail.available_responders?.length ?? 0;

  return (
    /* flex-1, not just flex-col. The panel is the second child of a full-
       height column; without it the map takes its content height and the
       bottom third of the dialog is empty space beside a report that is
       still scrolling. */
    <div className="flex min-h-0 flex-1 flex-col gap-3">
      <h3 className="flex items-center gap-2">
        <MapPin className="shrink-0 text-muted-foreground" size={13} />
        <span
          className="text-section-label"
          style={{ color: 'var(--color-text-tertiary)' }}
        >
          Location &amp; response distance
        </span>
      </h3>

      {/* "From [station] to [incident address]" — the map and the _RouteCard
          below it show the DISTANCE the numbers refer to, but neither one
          names the two endpoints in words. A dispatcher reading only the
          numbers has to already know which station is nearest; this says it
          outright. Reported too small/easy to miss at the first size
          (11.5px, muted-foreground, no container) — this is now its own
          bordered, tinted banner rather than a caption line, so it reads as
          a fact of the report rather than fine print underneath one. */}
      {stationPoint && incidentPoint && (
        <div
          className="flex shrink-0 items-start gap-2 rounded-[var(--radius-md)] border px-3 py-2"
          style={{
            borderColor: 'color-mix(in srgb, var(--color-brand) 35%, transparent)',
            backgroundColor: 'color-mix(in srgb, var(--color-brand) 8%, transparent)',
          }}
        >
          <Navigation
            className="mt-0.5 shrink-0"
            size={16}
            style={{ color: 'var(--color-brand)' }}
          />
          <p className="text-[14px] leading-snug text-foreground">
            From{' '}
            <span className="font-bold">
              {detail.stations?.name ?? 'the nearest station'}
            </span>
            {' '}to{' '}
            <span className="font-bold">
              {detail.location_address ?? 'the incident location'}
            </span>
          </p>
        </div>
      )}

      {incidentPoint ? (
        <div className="relative h-[300px] w-full shrink-0 overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] lg:h-auto lg:min-h-[280px] lg:flex-1">
          <IncidentRouteMap
            incident={incidentPoint}
            route={route}
            scrollWheelZoom={scrollWheelZoom}
            severity={severity}
            station={stationPoint ? { point: stationPoint, agencyType } : null}
          />

          <_Legend
            agencyLabel={agency?.agency_type ?? null}
            agencyType={agencyType}
            hasStation={Boolean(stationPoint)}
            severity={severity}
          />

          {stationPoint && <_RouteCard loading={loading} route={route} />}
        </div>
      ) : (
        /* Not an empty state to be decorated. A report with no coordinates is
           the single worst thing this console can hold, and it is the reason
           no crew can be sent — so it says that instead of drawing grey. */
        <div className="flex h-[220px] shrink-0 flex-col items-center justify-center gap-1.5 rounded-[var(--radius-card)] border border-dashed border-[var(--color-surface-border)] px-6 text-center lg:h-auto lg:flex-1">
          <MapPin className="text-muted-foreground" size={18} />
          <p className="text-[13px] font-semibold text-foreground">
            This report carries no coordinates
          </p>
          <p className="max-w-[36ch] text-[12px] text-muted-foreground">
            Nothing can be placed on a map and no distance can be measured.
            Ring the reporter for a landmark before dispatching.
          </p>
        </div>
      )}

      <_StationStrip
        agencyType={agencyType}
        onDuty={onDuty}
        route={stationPoint ? route : null}
        routing={Boolean(stationPoint) && loading}
        stationName={detail.stations?.name ?? null}
      />

      {stationPoint && incidentPoint && (
        <p className="flex items-start gap-1.5 text-[11.5px] leading-snug text-muted-foreground">
          <Info className="mt-px shrink-0" size={12} />
          {route?.source === 'road'
            ? 'Estimated from the road route. Traffic, weather and road conditions will change it.'
            : 'A straight-line estimate at 30 km/h — the real drive is always longer.'}
        </p>
      )}
    </div>
  );
}

/**
 * The key to the marks, drawn in the same shapes the map uses.
 *
 * A legend whose swatches do not match its marks is un-followable for exactly
 * the reader who most needs one — see the note on LAYER_MARK in map-legend.ts.
 */
function _Legend({
  agencyType,
  agencyLabel,
  severity,
  hasStation,
}: {
  agencyType: AgencyKey | null;
  agencyLabel: string | null;
  severity: SeverityKey;
  hasStation: boolean;
}) {
  return (
    <div className="absolute top-3 left-3 z-[1000] rounded-[var(--radius-md)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]/90 px-3 py-2 shadow-[var(--shadow-md)] backdrop-blur-sm">
      <p
        className="text-section-label mb-1.5"
        style={{ color: 'var(--color-text-tertiary)' }}
      >
        Legend
      </p>
      <ul className="flex flex-col gap-1 text-[11.5px] text-foreground">
        {hasStation && (
          <li className="flex items-center gap-2">
            {/* The teardrop the map draws, at legend size. */}
            <svg aria-hidden height="13" viewBox="0 0 11 14" width="10">
              <path
                d="M5.5 13.5S10 8.2 10 5A4.5 4.5 0 1 0 1 5c0 3.2 4.5 8.5 4.5 8.5Z"
                fill={agencyType ? agencyVar(agencyType) : 'var(--color-text-muted)'}
              />
            </svg>
            Nearest station{agencyLabel ? ` (${agencyLabel})` : ''}
          </li>
        )}
        <li className="flex items-center gap-2">
          <span
            className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
            /* severityVar, not a template — an untriaged report's key is
               `unscored`, and there is no --color-severity-unscored to
               interpolate. It would resolve to nothing and draw no swatch. */
            style={{ backgroundColor: severityVar(severity) }}
          />
          Incident location
        </li>
        {hasStation && (
          <li className="flex items-center gap-2">
            <span
              className="inline-block h-[3px] w-2.5 shrink-0 rounded-full"
              style={{ backgroundColor: 'var(--color-system-info)' }}
            />
            Route
          </li>
        )}
      </ul>
    </div>
  );
}

/** Distance and ETA, over the map, beside the line they describe. */
function _RouteCard({
  route,
  loading,
}: {
  route: ResponseRoute | null;
  loading: boolean;
}) {
  return (
    <div className="absolute right-3 bottom-7 z-[1000] w-[192px] rounded-[var(--radius-md)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]/90 px-3 py-2.5 shadow-[var(--shadow-md)] backdrop-blur-sm">
      <div className="flex items-start gap-2">
        <Car className="mt-0.5 shrink-0 text-muted-foreground" size={14} />
        <div className="min-w-0">
          <p className="text-[11px] text-muted-foreground">Distance to station</p>
          <p className="text-[15px] font-semibold tabular-nums text-foreground">
            {route
              ? formatDistance(route.distanceKm)
              : loading
                ? 'Measuring…'
                : '—'}
          </p>
        </div>
      </div>
      <div className="mt-2 flex items-start gap-2 border-t border-[var(--color-surface-border)] pt-2">
        <Clock className="mt-0.5 shrink-0 text-muted-foreground" size={14} />
        <div className="min-w-0">
          <p className="text-[11px] text-muted-foreground">Estimated response</p>
          <p className="text-[15px] font-semibold tabular-nums text-foreground">
            {route ? `~ ${route.minutes} min` : loading ? '…' : '—'}
          </p>
          {route && (
            <p className="truncate text-[11px] text-muted-foreground">
              {route.source === 'road'
                ? route.via
                  ? `via ${route.via}`
                  : 'by road'
                : 'straight-line estimate'}
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

/** The same facts as words, for anyone who cannot read them off a map. */
function _StationStrip({
  stationName,
  agencyType,
  route,
  routing,
  onDuty,
}: {
  stationName: string | null;
  agencyType: AgencyKey | null;
  route: ResponseRoute | null;
  routing: boolean;
  onDuty: number;
}) {
  if (!stationName) {
    return (
      <div
        className="shrink-0 rounded-[var(--radius-card)] border px-4 py-3 text-[13px]"
        style={{
          borderColor:
            'color-mix(in srgb, var(--color-system-warning) 40%, transparent)',
          backgroundColor: 'var(--color-system-warning-bg)',
        }}
      >
        <p
          className="font-semibold"
          style={{ color: 'var(--color-system-warning)' }}
        >
          No station matched this report
        </p>
        <p className="text-muted-foreground">
          Nobody has been notified. Route it by hand before it ages in the queue.
        </p>
      </div>
    );
  }

  const tint = agencyType ? agencyVar(agencyType) : 'var(--color-text-muted)';

  return (
    <div className="grid shrink-0 grid-cols-2 items-center gap-x-4 gap-y-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 sm:grid-cols-[minmax(0,1.5fr)_repeat(3,minmax(0,1fr))] sm:gap-y-0 sm:divide-x sm:divide-[var(--color-surface-border)]">
      <div className="flex min-w-0 items-center gap-2.5">
        <span
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--radius-md)]"
          style={{
            backgroundColor: `color-mix(in srgb, ${tint} 14%, transparent)`,
          }}
        >
          <Building2 size={15} style={{ color: tint }} />
        </span>
        <div className="min-w-0">
          <p className="text-[11px] text-muted-foreground">
            Nearest responding station
          </p>
          {/* Wraps rather than truncates. "MDRRMO Naval Station" and "MDRRMO
              Naval Sub-Station" differ in their last word, so an ellipsis
              lands exactly where the two names separate. */}
          <p className="text-[13px] leading-tight font-semibold text-foreground">
            {stationName}
          </p>
        </div>
      </div>

      <_Cell label="Distance">
        {route ? formatDistance(route.distanceKm) : routing ? '…' : '—'}
      </_Cell>

      <_Cell label="Est. response time">
        {route ? `~ ${route.minutes} min` : routing ? '…' : '—'}
      </_Cell>

      <_Cell label="Crew status">
        {/* Colour AND word. Green alone would let a colourblind dispatcher
            read an unstaffed station as a staffed one. */}
        <span
          className="inline-flex rounded-full px-2 py-0.5 text-[12px] font-semibold"
          style={
            onDuty > 0
              ? {
                  color: 'var(--color-system-success)',
                  backgroundColor: 'var(--color-system-success-bg)',
                }
              : {
                  color: 'var(--color-system-warning)',
                  backgroundColor: 'var(--color-system-warning-bg)',
                }
          }
        >
          {onDuty > 0 ? `${onDuty} on duty` : 'None on duty'}
        </span>
      </_Cell>
    </div>
  );
}

function _Cell({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="min-w-0 sm:pl-4">
      <p className="text-[11px] text-muted-foreground">{label}</p>
      <div className="truncate text-[13px] font-semibold tabular-nums text-foreground">
        {children}
      </div>
    </div>
  );
}
