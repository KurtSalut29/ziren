/**
 * The map's shared vocabulary — layers, severity buckets, and the tokens that
 * paint them.
 *
 * It lives beside the map rather than inside it because the page's toolbar and
 * the map surface must agree on every one of these. They previously did
 * not: the page hard-coded a legend of four severity swatches while the map
 * hard-coded its own copy of the same four hexes, and neither knew whether the
 * other was showing anything. A legend that can disagree with its map is worse
 * than no legend, because it is read as a claim about what is on screen.
 *
 * The hex values are NOT here. Only token names are, so globals.css stays the
 * one place a colour is decided — see use-token-colors for why the map has to
 * resolve them at paint time instead of importing them.
 */

import type { SeverityLevel } from '@/lib/api/map';

/** Severity, plus the bucket for incidents the model has not scored yet. */
export type SeverityKey = SeverityLevel | 'unscored';

/**
 * Severity order, worst first.
 *
 * Fixed, and never sorted at render. An alphabetical legend would read
 * critical, high, low, medium — putting the least urgent tier between the two
 * most urgent, on a console whose whole job is triage.
 */
export const SEVERITY_KEYS: readonly SeverityKey[] = [
  'critical',
  'high',
  'medium',
  'low',
  'unscored',
] as const;

export const SEVERITY_LABEL: Record<SeverityKey, string> = {
  critical: 'Critical',
  high:     'High',
  medium:   'Medium',
  low:      'Low',
  unscored: 'Unscored',
};

/** Every incident falls in exactly one bucket, including the un-triaged ones. */
export function severityKey(severity: SeverityLevel | null): SeverityKey {
  return severity ?? 'unscored';
}

export interface MapLayerState {
  incidents: boolean;
  responders: boolean;
  /**
   * Station pins, NOT coverage rectangles.
   *
   * The map used to fill in each agency's coverage polygon. Those polygons are
   * migration 002's seed: one axis-aligned 8km box per municipality, shared
   * byte-for-byte by its BFP, PNP and MDRRMO. Drawing them asserted a boundary
   * precise to the metre that nobody had surveyed, stacked twenty-four shapes
   * into eight boxes, and made the colour of a box mean nothing but render
   * order.
   *
   * A pin claims less and is true: a station's coordinates are real and each
   * agency's are its own. The polygons still drive the fail-open coverage
   * check and are still edited in Coverage Areas — they are simply no longer
   * drawn as if they were surveyed.
   */
  stations: boolean;
}

export type MapLayerKey = keyof MapLayerState;

export const LAYER_KEYS: readonly MapLayerKey[] = [
  'incidents',
  'responders',
  'stations',
] as const;

export const LAYER_LABEL: Record<MapLayerKey, string> = {
  incidents:  'Incidents',
  responders: 'Responders',
  stations:   'Stations',
};

/**
 * What each layer looks like on the map, so the legend can draw the same mark.
 *
 * The old legend showed all three as coloured squares. Nothing on the map is a
 * square: incidents are filled circles, responders are triangles, coverage is
 * a dashed outline. A swatch whose shape does not match its mark makes the
 * legend un-followable for the exact reader who needs it — the one who cannot
 * tell the colours apart.
 */
export type LayerMark = 'circle' | 'triangle' | 'pin';

export const LAYER_MARK: Record<MapLayerKey, LayerMark> = {
  incidents:  'circle',
  responders: 'triangle',
  stations:   'pin',
};

/**
 * Token names the map surface resolves to concrete colours.
 *
 * Severity paints incidents; agency paints responders and coverage. The two
 * sets never cross — an incident is never drawn in an agency colour, because
 * on this console colour answers "how bad" and shape answers "whose".
 */
export const MAP_COLOR_TOKENS = {
  critical: '--color-severity-critical',
  high:     '--color-severity-high',
  medium:   '--color-severity-medium',
  low:      '--color-severity-low',
  unscored: '--color-text-muted',

  agency_BFP:    '--color-agency-bfp',
  agency_PNP:    '--color-agency-pnp',
  agency_MDRRMO: '--color-agency-mdrrmo',

  /** The keyline that separates a marker from whatever it sits on. Was a
   *  literal `white`, which vanished against dark tiles in dark mode. */
  markStroke: '--color-surface-card',
} as const;

/** The CSS token a legend swatch should use, straight from the same table. */
export function severityVar(key: SeverityKey): string {
  return `var(${MAP_COLOR_TOKENS[key]})`;
}

/** The resolved palette, once useTokenColors has turned the names into hexes. */
export type MapPalette = Record<keyof typeof MAP_COLOR_TOKENS, string>;

/**
 * The colour for an agency, including the case there isn't one.
 *
 * `agency_type` is nullable on both incidents and responders — an unassigned
 * report and a responder whose account predates the agency link both arrive
 * with null. Indexing the palette by a template string built from it silently
 * produced `agency_null`, so the guard belongs here once rather than at each
 * of the three call sites.
 */
export function agencyColor(
  palette: MapPalette,
  type: 'BFP' | 'PNP' | 'MDRRMO' | null | undefined,
): string {
  return type ? palette[`agency_${type}`] : palette.unscored;
}

// ── Agencies ──────────────────────────────────────────────────

export type AgencyKey = 'BFP' | 'PNP' | 'MDRRMO';

export const AGENCY_KEYS: readonly AgencyKey[] = ['BFP', 'PNP', 'MDRRMO'] as const;

/**
 * Which agencies' coverage and responders to draw.
 *
 * WHY THIS EXISTS
 *
 * Every municipality's three agencies were seeded with byte-identical
 * geometry — BFP/Naval, PNP/Naval and MDRRMO/Naval are the same rectangle —
 * so the map stacks twenty-four polygons into eight visible boxes. Three
 * consequences, all bad: the colour of a box is whichever agency the map drew
 * last rather than anything meaningful, the 10% fill reads as ~27% because it
 * is painted three times, and only the topmost tooltip can ever be hovered.
 *
 * Filtering is the honest fix. Offsetting or insetting the rings so all three
 * are visible would draw areas that are not the areas — a smaller boundary
 * than the one the coverage check actually uses. Showing one agency at a time
 * draws each area exactly as it is stored, in its own colour, fully hoverable.
 *
 * It does NOT make the three areas different. Only real jurisdiction data can
 * do that, and Coverage Areas is where it would be entered.
 */
export type AgencyFilter = Record<AgencyKey, boolean>;

export const ALL_AGENCIES: AgencyFilter = { BFP: true, PNP: true, MDRRMO: true };

export const ALL_LAYERS: MapLayerState = {
  incidents: true,
  responders: true,
  stations: true,
};

export function agencyVar(key: AgencyKey): string {
  return `var(${MAP_COLOR_TOKENS[`agency_${key}`]})`;
}
