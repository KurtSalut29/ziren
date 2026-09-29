import { PhoneCall, UserRound } from 'lucide-react';

import { geodesicKm, type LatLng } from '@/lib/geo/geodesic';
import { formatDistance } from '@/lib/incidents/response-route';

/**
 * "The caller is not at the incident."
 *
 * Shown when the resident placed the incident on the map instead of reporting
 * where they stand (migration 042) — a relative in Larrazabal called someone
 * in Kawayan and asked them to report it. The incident's own location is what
 * routes the report and where a crew goes; this tells the dispatcher that the
 * person who reported it is somewhere else, and how far, so they call back to
 * confirm the spot rather than trusting a pin nobody standing there placed.
 */
export function ReportedFromElsewhere({
  incident, reporter, reporterAddress,
}: {
  incident: LatLng | null;
  reporter: LatLng | null;
  reporterAddress: string | null;
}) {
  const km = incident && reporter ? geodesicKm(incident, reporter) : null;
  const where = reporterAddress ?? (reporter ? 'a location on record' : 'an unknown location');
  return (
    <div
      className="mb-3 flex items-start gap-2.5 rounded-[10px] border px-3 py-2.5"
      role="note"
      style={{
        background: 'color-mix(in srgb, var(--color-system-warning) 10%, transparent)',
        borderColor: 'color-mix(in srgb, var(--color-system-warning) 45%, transparent)',
      }}
    >
      <UserRound aria-hidden="true" className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-system-warning)' }} />
      <div className="min-w-0 text-[13px] leading-snug">
        <p className="font-semibold text-foreground">Reported from somewhere else</p>
        <p className="mt-0.5 text-[var(--color-text-secondary)]">
          The caller was at <span className="font-medium text-foreground">{where}</span>
          {km !== null && <> — <span className="font-medium tabular-nums text-foreground">{formatDistance(km)}</span> from the incident</>}
          . The address below is where the incident is.
        </p>
        <p className="mt-1 flex items-center gap-1.5 text-[12px] text-muted-foreground">
          <PhoneCall aria-hidden="true" className="size-3.5" />
          Call the reporter to confirm the exact spot before dispatching.
        </p>
      </div>
    </div>
  );
}
