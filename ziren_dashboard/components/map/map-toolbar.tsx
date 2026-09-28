'use client';

/**
 * MapToolbar — the map's legend, its counters and its filters, as one control.
 *
 * The page previously carried a static legend of seven coloured swatches while
 * the map carried its own floating row of three count badges. Neither could
 * see the other, so the legend claimed four severities were on the map whether
 * or not any incident had been scored, and the counters restated numbers the
 * legend had no access to.
 *
 * Folding them together is not just tidier — it makes the legend do something.
 * Each chip carries the mark it stands for, the number of that mark currently
 * drawn, and a pressed state that adds or removes it. A dispatcher hunting a
 * critical call can drop every other tier off the island in one click, which
 * is the whole reason a live map has filters and this one previously had none.
 *
 * SWATCH SHAPES MATCH THE MAP. Incidents are circles, responders are triangles,
 * coverage is a dashed outline — on the map and here. The old legend drew all
 * three as squares, which makes a legend unusable for exactly the reader who
 * most needs one: the person who cannot separate the colours.
 */

import {
  AlertTriangle, Building2, Siren, Users, Zap,
} from 'lucide-react';
import { Separator } from '@/components/efferd/ui/separator';
import {
  ToggleGroup,
  ToggleGroupItem,
} from '@/components/efferd/ui/toggle-group';
import { Fig } from '@/components/ui/fig';
import {
  AGENCY_KEYS,
  LAYER_KEYS,
  LAYER_LABEL,
  SEVERITY_KEYS,
  SEVERITY_LABEL,
  severityVar,
  type AgencyFilter,
  type AgencyKey,
  type MapLayerKey,
  type MapLayerState,
  type SeverityKey,
} from './map-legend';
import { AGENCY_MARKER } from './map-markers';

/**
 * What each layer actually IS, not an abstract shape standing in for it.
 * A hollow circle and a hollow triangle told a dispatcher two layers were
 * different; they said nothing about what either one meant. Siren/Users/
 * Building2 are the same icons this console already uses for the same
 * concepts elsewhere (nav-config.ts's Incident Monitoring and Responders
 * items, and the agency icon set's Building2 for MDRRMO).
 */
const LAYER_ICON: Record<MapLayerKey, typeof Siren> = {
  incidents:  Siren,
  responders: Users,
  stations:   Building2,
};

/**
 * A legend chip's icon, drawn at a size a dispatcher can actually read at a
 * glance rather than squint at. `on` dims it rather than hollowing it out —
 * Lucide icons are strokes, not fillable shapes the way the old SVG swatches
 * were, so opacity is the one treatment that works for every icon here
 * without a bespoke filled/hollow variant per glyph.
 */
function ChipIcon({
  icon: Icon,
  color,
  on,
}: {
  icon: typeof Siren;
  color: string;
  on: boolean;
}) {
  return (
    <Icon
      className="size-6 shrink-0 transition-opacity"
      style={{ color, opacity: on ? 1 : 0.4 }}
    />
  );
}

/**
 * An agency chip's icon — the same station artwork the map itself draws
 * (see AGENCY_MARKER in map-markers.ts), not a generic pin shape tinted by
 * agency colour. The pin `Swatch` used before was already coloured per
 * agency, but a hollow red teardrop and a hollow blue teardrop are the same
 * shape twice — this legend is the one place a dispatcher learns what an
 * agency's mark on the map actually looks like, so it should show that mark,
 * not a stand-in for it.
 */
function AgencyIcon({ agency, on }: { agency: AgencyKey; on: boolean }) {
  return (
    // 24px static marker asset; next/image adds nothing here.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      alt=""
      className="size-6 shrink-0 object-contain transition-opacity"
      src={AGENCY_MARKER[agency]}
      style={{ opacity: on ? 1 : 0.4 }}
    />
  );
}

/** The count on a chip. Mono, so the digits line up chip to chip. */
function Count({ n }: { n: number }) {
  return (
    <Fig className="ml-0.5 text-[11px] font-semibold tabular-nums opacity-80">
      {n}
    </Fig>
  );
}

export interface MapToolbarProps {
  layers: MapLayerState;
  onLayersChange: (next: MapLayerState) => void;
  severities: ReadonlySet<SeverityKey>;
  onSeveritiesChange: (next: Set<SeverityKey>) => void;
  /** Marks currently DRAWN per layer, not marks that exist. */
  layerCounts: Record<MapLayerKey, number>;
  /** Incidents per bucket, before the severity filter is applied. */
  severityCounts: Record<SeverityKey, number>;
  agencies: AgencyFilter;
  onAgenciesChange: (next: AgencyFilter) => void;
  /** Stations per agency, before the agency filter is applied. */
  agencyCounts: Record<AgencyKey, number>;
  lastRefresh: Date | null;
  /** Last poll failed. Whatever is drawn is older than it looks. */
  stale: boolean;
}

export function MapToolbar({
  layers,
  onLayersChange,
  severities,
  onSeveritiesChange,
  layerCounts,
  severityCounts,
  agencies,
  onAgenciesChange,
  agencyCounts,
  lastRefresh,
  stale,
}: MapToolbarProps) {
  const layerValue = LAYER_KEYS.filter(k => layers[k]);

  // 'unscored' earns a chip only when something is actually unscored. It is an
  // exception state, not a standing tier, and a permanent "Unscored 0" would
  // read as a category the console tracks rather than one it hopes stays empty.
  const visibleSeverities = SEVERITY_KEYS.filter(
    k => k !== 'unscored' || severityCounts.unscored > 0,
  );

  return (
    <div className="flex shrink-0 flex-wrap items-center gap-x-4 gap-y-2 border-b border-[var(--color-surface-border)] bg-background px-4 py-2.5 md:px-6">
      {/* ── Layers ───────────────────────────────────────── */}
      <ToggleGroup
        aria-label="Map layers"
        onValueChange={(v: string[]) =>
          onLayersChange({
            incidents:  v.includes('incidents'),
            responders: v.includes('responders'),
            stations:   v.includes('stations'),
          })
        }
        size="sm"
        type="multiple"
        value={layerValue}
        variant="outline"
      >
        {LAYER_KEYS.map(k => (
          <ToggleGroupItem
            aria-label={`${LAYER_LABEL[k]} layer`}
            className="h-9"
            key={k}
            value={k}
          >
            {/* Neutral, for all three. An agency hue here would claim the
                layer belongs to that agency — the sky-blue this chip first
                used reads as "PNP" to anyone who knows the palette, on a
                control that covers every agency at once. The layer's identity
                is carried by the ICON; colour on the map means severity or
                agency, and neither applies to a layer as a whole. */}
            <ChipIcon
              color="var(--color-text-secondary)"
              icon={LAYER_ICON[k]}
              on={layers[k]}
            />
            {LAYER_LABEL[k]}
            <Count n={layerCounts[k]} />
          </ToggleGroupItem>
        ))}
      </ToggleGroup>

      <Separator className="hidden h-5 sm:block" orientation="vertical" />

      {/* ── Severity ─────────────────────────────────────────
          Disabled rather than hidden when the incidents layer is off. Hiding
          it would make the row jump width every time the layer is toggled,
          and the operator would lose the filter they had set. */}
      <ToggleGroup
        aria-label="Incident severity"
        onValueChange={(v: string[]) =>
          onSeveritiesChange(new Set(v as SeverityKey[]))
        }
        size="sm"
        type="multiple"
        value={[...severities]}
        variant="outline"
      >
        {visibleSeverities.map(k => (
          <ToggleGroupItem
            aria-label={`${SEVERITY_LABEL[k]} severity`}
            className="h-9"
            disabled={!layers.incidents}
            key={k}
            value={k}
          >
            {/* One icon shape for all four tiers — severity is a single
                dimension, and colour (not a different glyph per level)
                is what already carries "which tier" everywhere else on
                this console. */}
            <ChipIcon color={severityVar(k)} icon={Zap} on={severities.has(k)} />
            {SEVERITY_LABEL[k]}
            <Count n={severityCounts[k]} />
          </ToggleGroupItem>
        ))}
      </ToggleGroup>

      <Separator className="hidden h-5 sm:block" orientation="vertical" />

      {/* ── Agency ───────────────────────────────────────────
          Scopes coverage and responders, never incidents — see the note on
          AgencyFilter. Its real job is untangling the coverage layer: all
          three agencies in a municipality were seeded with the SAME rectangle,
          so with everything on you are looking at twenty-four polygons stacked
          into eight boxes, whose colour is just whichever drew last. One
          agency at a time draws each area as it is actually stored. */}
      <ToggleGroup
        aria-label="Agencies"
        onValueChange={(v: string[]) =>
          onAgenciesChange({
            BFP: v.includes('BFP'),
            PNP: v.includes('PNP'),
            MDRRMO: v.includes('MDRRMO'),
          })
        }
        size="sm"
        type="multiple"
        value={AGENCY_KEYS.filter(k => agencies[k])}
        variant="outline"
      >
        {AGENCY_KEYS.map(k => (
          <ToggleGroupItem
            aria-label={`${k} coverage and responders`}
            className="h-9"
            disabled={!layers.stations && !layers.responders}
            key={k}
            value={k}
          >
            <AgencyIcon agency={k} on={agencies[k]} />
            {k}
            <Count n={agencyCounts[k]} />
          </ToggleGroupItem>
        ))}
      </ToggleGroup>

      {/* ── Staleness, and ONLY staleness ──────────────────
          No clock, no refresh button. The map polls every 30 seconds, so a
          running timestamp told the operator nothing they could act on — it
          just ticked, and the button beside it re-fetched data that was at
          most half a minute old.

          A FAILED poll is different, and is the one thing worth the space:
          the marks on screen are then older than they look, and no amount of
          waiting will fix them. It says so, and names the time the data is
          actually from. */}
      {stale && (
        <span className="ml-auto flex items-center gap-1.5 text-meta text-[var(--color-system-warning)]">
          <AlertTriangle className="size-3.5" />
          Live update failed
          {lastRefresh && ` · showing ${lastRefresh.toLocaleTimeString()}`}
        </span>
      )}
    </div>
  );
}
