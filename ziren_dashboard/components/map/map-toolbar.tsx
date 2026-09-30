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
  AlertCircle, AlertOctagon, AlertTriangle, Building2, HelpCircle, Info, Siren, Users,
} from 'lucide-react';
import {
  ToggleGroup,
  ToggleGroupItem,
} from '@/components/efferd/ui/toggle-group';
import { Fig } from '@/components/ui/fig';
import { cn } from '@/lib/utils';
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
 * One icon per severity, the same ones the queue, the records table and the
 * incident dialog use. This row used one lightning bolt for every tier and
 * left colour to say which, which is the one thing the console's own rule
 * forbids: severity is never colour alone.
 */
const SEVERITY_ICON: Record<SeverityKey, typeof Siren> = {
  critical: AlertOctagon,
  high: AlertTriangle,
  medium: AlertCircle,
  low: Info,
  unscored: HelpCircle,
};

/**
 * How every chip on this bar looks. ON is a filled card with a firm border;
 * OFF is flat, dimmed and struck with a dashed border, so which marks are
 * hidden can be read across the row without studying each chip.
 */
const CHIP =
  'h-8 gap-1.5 rounded-full border px-2 text-[12px] font-semibold transition-colors ' +
  'data-[state=on]:border-[var(--color-border-strong)] data-[state=on]:bg-[var(--color-surface-card)] ' +
  'data-[state=on]:text-foreground data-[state=on]:shadow-[0_1px_2px_rgba(16,24,40,0.06)] ' +
  'data-[state=off]:border-dashed data-[state=off]:border-[var(--color-surface-border)] ' +
  'data-[state=off]:bg-transparent data-[state=off]:text-muted-foreground';

/** A chip's icon. `on` dims it: Lucide icons are strokes, so opacity is the
 *  one treatment that works for every glyph here. */
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
      aria-hidden="true"
      className="size-[15px] shrink-0 transition-opacity"
      strokeWidth={2.4}
      style={{ color, opacity: on ? 1 : 0.45 }}
    />
  );
}

/**
 * An agency chip's icon — the same station artwork the map itself draws
 * (see AGENCY_MARKER in map-markers.ts), so the legend shows the mark a
 * dispatcher will actually look for, not a stand-in for it.
 */
function AgencyIcon({ agency, on }: { agency: AgencyKey; on: boolean }) {
  return (
    // 18px static marker asset; next/image adds nothing here.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      alt=""
      className="size-[18px] shrink-0 object-contain transition-opacity"
      src={AGENCY_MARKER[agency]}
      style={{ opacity: on ? 1 : 0.45 }}
    />
  );
}

/** The count on a chip. Mono, so the digits line up chip to chip. */
function Count({ n }: { n: number }) {
  return (
    <Fig className="text-[11px] font-semibold tabular-nums text-muted-foreground">
      {n}
    </Fig>
  );
}

/** A named group of chips: the caption says what the row of chips filters. */
function Group({ label, className, children }: { label: string; className?: string; children: React.ReactNode }) {
  return (
    <div className={cn('flex min-w-0 flex-col gap-1', className)}>
      <span className="text-[10px] leading-none font-bold tracking-[0.08em] text-[var(--color-text-tertiary)] uppercase">
        {label}
      </span>
      {children}
    </div>
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
}: MapToolbarProps) {
  const layerValue = LAYER_KEYS.filter(k => layers[k]);

  // 'unscored' earns a chip only when something is actually unscored. It is an
  // exception state, not a standing tier, and a permanent "Unscored 0" would
  // read as a category the console tracks rather than one it hopes stays empty.
  const visibleSeverities = SEVERITY_KEYS.filter(
    k => k !== 'unscored' || severityCounts.unscored > 0,
  );

  return (
    <div
      className="flex shrink-0 flex-wrap items-end gap-x-3.5 gap-y-2.5 border-b border-[var(--color-surface-border)] bg-background px-4 py-2.5 md:px-5"
      data-testid="map-toolbar"
    >
      {/* ── Layers ───────────────────────────────────────── */}
      <Group label="Show on the map">
        <ToggleGroup
          aria-label="Map layers"
          className="flex-wrap"
          onValueChange={(v: string[]) =>
            onLayersChange({
              incidents:  v.includes('incidents'),
              responders: v.includes('responders'),
              stations:   v.includes('stations'),
            })
          }
          size="sm"
          spacing={1}
          type="multiple"
          value={layerValue}
        >
          {LAYER_KEYS.map(k => (
            <ToggleGroupItem
              aria-label={`${LAYER_LABEL[k]} layer`}
              className={CHIP}
              key={k}
              value={k}
            >
              {/* Neutral, for all three. An agency hue here would claim the
                  layer belongs to that agency. The layer's identity is carried
                  by the ICON; colour on the map means severity or agency, and
                  neither applies to a layer as a whole. */}
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
      </Group>

      {/* ── Severity ─────────────────────────────────────────
          Disabled rather than hidden when the incidents layer is off. Hiding
          it would make the row jump width every time the layer is toggled,
          and the operator would lose the filter they had set. */}
      <Group label="Incident severity">
        <ToggleGroup
          aria-label="Incident severity"
          className="flex-wrap"
          onValueChange={(v: string[]) =>
            onSeveritiesChange(new Set(v as SeverityKey[]))
          }
          size="sm"
          spacing={1}
          type="multiple"
          value={[...severities]}
        >
          {visibleSeverities.map(k => (
            <ToggleGroupItem
              aria-label={`${SEVERITY_LABEL[k]} severity`}
              className={CHIP}
              disabled={!layers.incidents}
              key={k}
              value={k}
            >
              <ChipIcon color={severityVar(k)} icon={SEVERITY_ICON[k]} on={severities.has(k)} />
              {SEVERITY_LABEL[k]}
              <Count n={severityCounts[k]} />
            </ToggleGroupItem>
          ))}
        </ToggleGroup>
      </Group>

      {/* ── Agency ───────────────────────────────────────────
          Scopes stations and responders, never incidents — see the note on
          AgencyFilter. */}
      <Group label="Stations & responders of">
        <ToggleGroup
          aria-label="Agencies"
          className="flex-wrap"
          onValueChange={(v: string[]) =>
            onAgenciesChange({
              BFP: v.includes('BFP'),
              PNP: v.includes('PNP'),
              MDRRMO: v.includes('MDRRMO'),
            })
          }
          size="sm"
          spacing={1}
          type="multiple"
          value={AGENCY_KEYS.filter(k => agencies[k])}
        >
          {AGENCY_KEYS.map(k => (
            <ToggleGroupItem
              aria-label={`${k} coverage and responders`}
              className={CHIP}
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
      </Group>

      {/* ── Staleness, and ONLY staleness ──────────────────
          No clock, no refresh button. The map polls every 30 seconds, so a
          running timestamp told the operator nothing they could act on — it
          just ticked, and the button beside it re-fetched data that was at
          most half a minute old.

          A FAILED poll is different, and is the one thing worth the space:
          the marks on screen are then older than they look, and no amount of
          waiting will fix them. It says so, and names the time the data is
          actually from. */}
    </div>
  );
}

/**
 * Says the map is live, or that it is not. Drawn ON the map by the page, in
 * the corner, so the filter bar above stays one row.
 *
 * Still no clock and no refresh button. The map polls every 30 seconds, so a
 * running timestamp told the operator nothing they could act on. A FAILED poll
 * is different: the marks on screen are then older than they look, and it says
 * so and names the time the data is actually from.
 */
export function MapLiveBadge({
  stale, lastRefresh, className,
}: {
  /** Last poll failed. Whatever is drawn is older than it looks. */
  stale: boolean;
  lastRefresh: Date | null;
  className?: string;
}) {
  return stale ? (
        <span
          className={cn('inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-[12px] font-semibold shadow-[var(--shadow-md)]', className)}
          data-testid="map-live"
          style={{
            color: 'var(--color-system-warning)',
            borderColor: 'color-mix(in srgb, var(--color-system-warning) 40%, transparent)',
            backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 14%, var(--color-surface-card))',
          }}
        >
          <AlertTriangle aria-hidden="true" className="size-3.5" />
          Live update failed
          {lastRefresh && ` · showing ${lastRefresh.toLocaleTimeString()}`}
        </span>
  ) : (
        <span
          className={cn('inline-flex h-8 items-center gap-2 rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 text-[12px] font-semibold text-[var(--color-text-secondary)] shadow-[var(--shadow-md)]', className)}
          data-testid="map-live"
          title="The map refreshes by itself every 30 seconds."
        >
          <span className="relative flex size-2">
            <span className="absolute inline-flex size-full rounded-full opacity-60 motion-safe:animate-ping" style={{ backgroundColor: 'var(--color-system-success)' }} />
            <span className="relative inline-flex size-2 rounded-full" style={{ backgroundColor: 'var(--color-system-success)' }} />
          </span>
          Live
        </span>
      );
}
