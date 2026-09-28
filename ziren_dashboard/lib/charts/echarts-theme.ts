/**
 * Design-token bridge for every ECharts chart on the dashboard.
 *
 * ECharts renders on <canvas>, which does not resolve CSS custom properties
 * the way the DOM does — passing the literal string "var(--color-brand)" as
 * a fillStyle silently fails. Every color has to be resolved to a concrete
 * value (e.g. "#FC5A05") at the moment an option is built, via
 * getComputedStyle. That means every option-building function that calls
 * this must be recomputed whenever the light/dark theme flips — see
 * useTheme() in lib/theme/use-theme.ts, whose `theme` value each chart
 * component includes in its useMemo dependency array so the option object
 * gets a new identity (and ECharts re-renders with the new colors) on
 * every theme change.
 */

/** Reads a CSS custom property's current resolved value, e.g. "#FC5A05". */
export function readToken(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}

/** The locked four-tier severity scale. Never invent a fifth color for
 *  "untriaged" here — callers that need one already have their own gray
 *  token (--color-text-muted). */
export function severityColors(): Record<'critical' | 'high' | 'medium' | 'low', string> {
  return {
    critical: readToken('--color-severity-critical'),
    high: readToken('--color-severity-high'),
    medium: readToken('--color-severity-medium'),
    low: readToken('--color-severity-low'),
  };
}

/** The locked per-agency identity colors. Bound to the entity, never to a
 *  ramp position. */
export function agencyColors(): Record<'BFP' | 'PNP' | 'MDRRMO', string> {
  return {
    BFP: readToken('--color-agency-bfp'),
    PNP: readToken('--color-agency-pnp'),
    MDRRMO: readToken('--color-agency-mdrrmo'),
  };
}

/**
 * Appends hex alpha to a "#RRGGBB" token, e.g. withAlpha('#FC5A05', 0.45) ->
 * "#FC5A0573". Assumes the token is a 6-digit hex, true for every severity,
 * agency, and brand color token today (see app/globals.css) — an rgb() or
 * rgba() token would break this and needs a different helper if one is
 * ever added.
 */
export function withAlpha(hex: string, alpha: number): string {
  const a = Math.round(Math.min(1, Math.max(0, alpha)) * 255)
    .toString(16)
    .padStart(2, '0');
  return `${hex}${a}`;
}

/**
 * Shared chrome every chart spreads into its own `option`, so a tooltip or
 * grid never looks different between two charts on the same page. Mirrors
 * the visual language the old Recharts-based `ChartTooltipContent` used:
 * rounded card, border/shadow tokens, tabular-nums for values.
 */
export function baseEChartsOption() {
  const border = readToken('--color-surface-border');
  const textMuted = readToken('--color-text-muted');
  const surfaceCard = readToken('--color-surface-card');
  const textPrimary = readToken('--color-text-primary');

  return {
    textStyle: {
      color: textMuted,
      fontSize: 12,
      fontFamily: 'inherit',
    },
    grid: {
      left: 8,
      right: 12,
      top: 16,
      bottom: 8,
      containLabel: true,
    },
    tooltip: {
      backgroundColor: surfaceCard,
      borderColor: border,
      borderWidth: 1,
      borderRadius: 10,
      padding: [10, 12],
      textStyle: { color: textPrimary, fontSize: 12.5 },
      extraCssText:
        'box-shadow: 0 8px 24px rgba(0,0,0,0.14), 0 2px 6px rgba(0,0,0,0.08); backdrop-filter: blur(2px);',
    },
  };
}

/**
 * A qualitative palette for data that has no locked identity color —
 * emergency categories, unlike agencies (fixed BFP/PNP/MDRRMO hues) or
 * severity (fixed 4-tier scale), are not real-world entities a dispatcher
 * must recognise on sight, so there is nothing to lock.
 *
 * Deliberately kept OUT of the red/orange/yellow/green/sky-blue hue
 * families — those belong to severity and agency and a category slice must
 * never be mistaken for either. Chosen from the violet–magenta range
 * instead, which none of the locked scales touch, and kept as a fixed
 * array (not a ramp) so a category's color is stable across renders even
 * as the ranking (and therefore array order into this palette) shifts day
 * to day.
 */
export const CATEGORY_PALETTE = [
  '#6366F1', // indigo
  '#A855F7', // purple
  '#EC4899', // pink
  '#8B5CF6', // violet
  '#D946EF', // fuchsia
  '#64748B', // slate — the "unclassified" catch-all, deliberately muted
] as const;
