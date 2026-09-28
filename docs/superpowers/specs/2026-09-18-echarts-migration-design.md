# Ziren Dashboard: ECharts Migration & New Charts

Status: approved, pending implementation plan
Date: 2026-09-18
Scope: `ziren_dashboard` only — no backend or mobile changes

## Context

The dashboard currently renders charts with Recharts, wrapped in a shadcn-derived
`ChartContainer` (`components/efferd/ui/chart.tsx`) that is written directly
against Recharts primitives (`RechartsPrimitive.ResponsiveContainer`,
`Tooltip`, `Legend`). Seven chart components live under `components/charts/`
and are used on two pages:

- Overview (`app/(dashboard)/overview/page.tsx`, Provincial Admin): 5 charts
  — `IncidentVolumeChart`, `AgencyShareChart`, `SeverityTrendChart`,
  `DispatchLatencyChart`, `CategoryMixChart`.
- Analytics (`app/(dashboard)/analytics/page.tsx`): 2 charts —
  `CategoryBarChart`, `IncidentTrendChart`.

Goal: move to a more capable, more interactive charting foundation, add three
new chart types the current lineup doesn't cover, and read as a premium,
"high-end" dashboard — without breaking the existing color rules (severity
and agency colors are safety-critical, per project memory) or the design-token
driven light/dark theming already in place.

## Decision: Apache ECharts, via `echarts-for-react`

Canvas-rendered (not SVG), which matters because charts re-render on every
30-second poll and the requirement is smooth transitions, not layout thrash.
Free (Apache-2.0) — no Highcharts-style commercial licensing question. Ships
`heatmap`, `funnel`, and `gauge` chart types natively, which the three new
visualizations below need; neither Nivo nor ApexCharts has all three at
comparable maturity. Built-in `dataZoom` (brush/zoom) and `axisPointer`
group-sync (shared crosshair across charts) deliver the richer-interaction
ask without hand-rolled work.

Cost accepted: new dependency; `efferd/ui/chart.tsx` doesn't carry over as-is
since it's Recharts-specific, so a new wrapper is part of this work.

`recharts` stays installed as a dependency — four files under
`components/efferd/*-chart.tsx` (`conversation-volume-chart.tsx`,
`first-reply-time-chart.tsx`, `csat-responses-chart.tsx`,
`channel-breakdown-chart.tsx`) are unused template/reference files not wired
into any real page, and are out of scope for this change. They are left
alone; removing `recharts` entirely is not part of this migration.

## New shared wrapper: `components/charts/echart.tsx`

Replaces `efferd/ui/chart.tsx` as the foundation for every chart going
forward.

- Wraps `echarts-for-react`'s `ReactECharts`.
- Builds an ECharts theme from the app's CSS custom properties at mount
  (`--color-severity-critical/high/medium/low`,
  `--color-agency-bfp/pnp/mdrrmo`, `--color-brand`, surface/border/text
  tokens), and re-reads them when `lib/theme/use-theme`'s preference changes
  (light/dark/system) — colors are never ECharts' default palette, matching
  the rule the current charts already follow.
- Accepts a `group` prop, wired to `echarts.connect(group)` — the mechanism
  behind synced crosshair/tooltip across multiple charts on the same page.
- Tooltip visual styling matched to the current `ChartTooltipContent` look
  (rounded card, border/shadow tokens, tabular-nums mono figures for values)
  so there's no visual fork between charts mid-migration.
- Animation on the 30s poll refresh is close to free: ECharts animates
  between old and new `series.data` on `setOption` in merge mode by default.
  The wrapper just needs to call `setOption` on data change (via
  `useEffect` keyed on the data prop) rather than remounting the chart
  instance.

## Migrating the existing 7

| Component | Today (Recharts) | Becomes (ECharts) |
|---|---|---|
| `incident-volume-chart` | gradient `AreaChart` | `line` + `areaStyle` gradient |
| `agency-share-chart` | donut `PieChart` | donut `pie`, same locked BFP/PNP/MDRRMO colors, same <5-active suppression rule |
| `severity-trend-chart` | stacked `BarChart` | stacked `bar` |
| `dispatch-latency-chart` | `LineChart` | `line` |
| `category-bar-chart` | horizontal `BarChart` w/ per-bar `Cell` | horizontal `bar`, per-item `itemStyle.color` |
| `incident-trend-chart` (Analytics) | gradient `AreaChart` | `line` + `areaStyle` |
| `category-mix-chart` | hand-rolled ranked bars (not Recharts) | folded into ECharts horizontal `bar` for interaction consistency — keeps the one-hue-magnitude-only rule and the "other" carve-out from ranking with the five real categories |

No changes to `lib/charts/queue-series.ts` or any API client function — the
same data shapes feed the new chart option builders. Card chrome (`Card`,
`CardHeader`, `CardTitle`, `CardDescription`, the range `Select`) is
unchanged; only the plotting area underneath changes libraries.

Every migrated chart keeps its existing domain rules exactly:
- Agency colors are fixed to the entity (BFP/PNP/MDRRMO), never bound to a
  palette ramp position.
- Severity colors read from the same `--color-severity-*` tokens.
- `AgencyShareChart`'s "too few to read as a split" suppression below 5
  active incidents.
- `CategoryMixChart`'s separation of the 5 real wizard categories from
  `other`/null (never ranked together).
- `DispatchLatencyChart`'s null-when-no-dispatches day (never rendered as a
  misleading zero).

## Three new charts

All three land on the Overview page, alongside the existing 5+1 (folded
category-mix), per your placement choice.

### Incident heatmap calendar

Day-of-week × hour-of-day grid; color intensity = report volume in that
bucket.

14 days (`TREND_DAYS`) is too thin to show a real weekly pattern reliably, so
this chart reads a longer, separate window: 8 weeks (56 days), via a second
`fetchActivity(token, 56)` call. No backend change — the endpoint already
accepts an arbitrary `days` parameter. This is an additional network call on
page load (not on every 30s poll — see Refresh cadence below).

### Response funnel

Three stages: Received → Dispatched → Resolved, counted over the existing
`TREND_DAYS` (14-day) window from `activity`.

- **Received**: every incident with `created_at` in the window (i.e. same
  population `categoryMix`/`severityDays` already use).
- **Dispatched**: subset with `dispatched_at` not null.
- **Resolved**: subset with `status === 'resolved'` specifically — NOT
  "`resolved_at` not null," because `resolved_at` is also written for
  cancellations. Gating on `status` means a cancelled-but-dispatched incident
  counts in the Dispatched stage and drops out before Resolved, which is the
  honest reading: cancellation is attrition, not a completed funnel stage.

### SLA gauge

Single gauge, needle position = median dispatch-to-report minutes over the
14-day window (the window-level collapse of what `dispatchLatency` already
computes per-day — take the median of all non-null daily medians, or
recompute directly from the same underlying gaps for a truer window-median;
implementation plan decides which).

Target band is NOT a flat number — it's the existing per-severity policy
(`DISPATCH_TARGET_MINUTES` in `components/incidents/incident-vocabulary.ts`:
critical 5 / high 10 / medium 30 / low 60, default 5 for untriaged), weighted
by the actual severity mix of incidents dispatched in the window. A flat "5
minutes" target would misread as failing on a day that was mostly low-severity
reports. Needle color: green under target, amber near it, red over — same
three-state logic `urgencyTimeColor` already uses elsewhere, reused rather
than reinvented.

## Interactions

Per your answer: **hover-only, no click-to-navigate.**

- Synced crosshair/tooltip across all Overview charts via the `group`
  mechanism in the shared wrapper — hovering a point on one chart highlights
  the same x-position on every other time-series chart on the page.
- `dataZoom` brush/zoom on the three time-series charts (volume, severity
  trend, dispatch latency) — drag to inspect a sub-range, reset on
  double-click (ECharts default).
- Richer tooltips: multi-series breakdown on hover where relevant (e.g.
  severity trend's stacked bars show all four tiers in one tooltip, not just
  the hovered segment).
- No click handlers that navigate or open panels — this was explicitly
  ruled out in favor of keeping the surface lighter.

## Refresh cadence

The existing 30s poll (`REFRESH_MS` in `overview/page.tsx`) continues to
drive `incidents` and `activity`, which feeds every chart except the heatmap
calendar. The heatmap's 56-day fetch loads once per page visit (mirroring
how `platform` totals already work — loaded once, not on the queue's 15s/30s
cadence) rather than being re-fetched every 30 seconds for a shape that
does not meaningfully change within a session.

## Rollout (single effort, internally staged)

1. Install `echarts` + `echarts-for-react`. Build `components/charts/echart.tsx`
   (the wrapper) and its theme-token bridge.
2. Migrate Overview's existing 5 charts + fold in `category-mix-chart`
   (6 total) onto the new wrapper. Wire `group` sync + `dataZoom` on the
   three time-series ones.
3. Migrate Analytics' 2 charts.
4. Add the 3 new charts (heatmap calendar, funnel, gauge) to the Overview
   chart deck.
5. Delete the 7 old Recharts-based chart components once nothing imports
   them; `efferd/ui/chart.tsx` stays (still used by the 4 unrelated
   reference files) but is no longer used by any real page.

## Out of scope

- Analytics page's own filters/date-range beyond what already exists.
- Any backend or `/dispatch/activity` endpoint changes.
- Click-to-drill-down navigation (explicitly declined).
- Removing `recharts` as a dependency.
- Mobile app — this is dashboard-only.
