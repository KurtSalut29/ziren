# ECharts Dashboard Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Recharts with Apache ECharts as the charting foundation for the Ziren dashboard's Overview and Analytics pages, and add three new chart types (incident heatmap calendar, response funnel, SLA gauge) to the Overview page.

**Architecture:** A new themed wrapper (`components/charts/echart.tsx`) built on `echarts-for-react`'s tree-shaken core replaces the Recharts-specific `efferd/ui/chart.tsx` for every real chart. Each of the 7 existing chart components is edited in place — same file path, same exported component name, same props interface — so no page ever changes its import. Three new chart components are added alongside them, backed by new pure-data functions in `lib/charts/queue-series.ts`. Color rules (severity/agency CSS custom properties) are read from the DOM at option-build time via a small token-reading helper, never hardcoded.

**Tech Stack:** Next.js 15 / React 19 / TypeScript, `echarts` 6.x + `echarts-for-react` (tree-shaken via `echarts/core`), existing Tailwind + CSS-custom-property design tokens.

**Spec:** [docs/superpowers/specs/2026-09-18-echarts-migration-design.md](../specs/2026-09-18-echarts-migration-design.md)

## Global Constraints

- No backend, mobile, or `/dispatch/activity` API changes. Everything is `ziren_dashboard`-only.
- `recharts` stays an installed dependency — four unrelated `components/efferd/*-chart.tsx` reference files still use it and are out of scope.
- Severity colors always read from `--color-severity-critical/high/medium/low`; agency colors always read from `--color-agency-bfp/pnp/mdrrmo`. Never hardcode a hex value or let ECharts fall back to its default palette for these.
- `lib/` never imports from `components/` (verified: zero existing instances). Where a chart needs a constant that lives in `components/incidents/incident-vocabulary.ts` (e.g. `DISPATCH_TARGET_MINUTES`), the **page** passes it in as a parameter — the page already imports across that boundary today (`AG_COLOR`/`AG_BG`), the `lib/charts/queue-series.ts` module does not.
- This codebase has **no test runner** (no Jest/Vitest, no `test` npm script — confirmed by reading `package.json`). Every task's verification is: `npx tsc --noEmit` inside `ziren_dashboard/` for compile correctness, then a real visual check via the dev server (the `ziren-dev` skill covers auth-seeding and mock wiring for screenshotting dashboard routes) — in both light and dark theme, since color tokens differ per theme. This replaces the usual "write a failing test" step throughout this plan; it is not a shortcut, it is what this codebase's own tooling supports today.
- Every chart component keeps its exact existing domain rules: `AgencyShareChart`'s <5-active suppression text, `CategoryMixChart`'s real-5-vs-unclassified separation, `DispatchLatencyChart`'s null-day gaps (never a plotted zero), `SeverityTrendChart`'s escalating stack order with critical always on top.

---

### Task 1: Install ECharts and confirm the build still compiles

**Files:**
- Modify: `ziren_dashboard/package.json`, `ziren_dashboard/package-lock.json` (via npm)

**Interfaces:**
- Produces: `echarts` and `echarts-for-react` available as dependencies for every later task.

- [ ] **Step 1: Install the packages**

Run inside `ziren_dashboard/`:

```bash
npm install echarts echarts-for-react
```

- [ ] **Step 2: Confirm the type-check is still clean**

Run: `npx tsc --noEmit -p .`
Expected: no errors (same clean output as before this change — these packages ship their own types, nothing to wire up yet).

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore(dashboard): add echarts and echarts-for-react"
```

---

### Task 2: Design-token bridge and base option — `lib/charts/echarts-theme.ts`

**Files:**
- Create: `ziren_dashboard/lib/charts/echarts-theme.ts`

**Interfaces:**
- Consumes: nothing (reads `document.documentElement`'s computed CSS custom properties directly — client-only, must only be called from `'use client'` components after mount).
- Produces:
  - `readToken(name: string): string`
  - `severityColors(): Record<'critical' | 'high' | 'medium' | 'low', string>`
  - `agencyColors(): Record<'BFP' | 'PNP' | 'MDRRMO', string>`
  - `baseEChartsOption(): Record<string, unknown>` — shared grid/tooltip/axis defaults every chart spreads into its own `option`.

This file has no JSX and cannot be exercised by a screenshot on its own — it is verified by every chart that imports it starting in Task 4, which is why it has no separate visual-check step. `npx tsc --noEmit` still applies here for a straightforward reason: this file has no test coverage of its own until a consumer exists, so a syntax or type error here would otherwise surface confusingly in a later task instead of this one.

- [ ] **Step 1: Write the file**

```typescript
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

/** The locked four-tier severity scale. Never invent a fifth color for "untriaged" here — callers that need one already have their own gray token (--color-text-muted). */
export function severityColors(): Record<'critical' | 'high' | 'medium' | 'low', string> {
  return {
    critical: readToken('--color-severity-critical'),
    high: readToken('--color-severity-high'),
    medium: readToken('--color-severity-medium'),
    low: readToken('--color-severity-low'),
  };
}

/** The locked per-agency identity colors. Bound to the entity, never to a ramp position. */
export function agencyColors(): Record<'BFP' | 'PNP' | 'MDRRMO', string> {
  return {
    BFP: readToken('--color-agency-bfp'),
    PNP: readToken('--color-agency-pnp'),
    MDRRMO: readToken('--color-agency-mdrrmo'),
  };
}

/**
 * Shared chrome every chart spreads into its own `option`, so a tooltip or
 * grid never looks different between two charts on the same page. Mirrors
 * the visual language `ChartTooltipContent` (the old Recharts wrapper) used:
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
      borderRadius: 8,
      padding: [8, 10],
      textStyle: { color: textPrimary, fontSize: 12 },
      extraCssText: 'box-shadow: 0 4px 16px rgba(0,0,0,0.12);',
    },
  };
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/charts/echarts-theme.ts
git commit -m "feat(dashboard): add ECharts design-token bridge"
```

---

### Task 3: Shared chart wrapper — `components/charts/echart.tsx`

**Files:**
- Create: `ziren_dashboard/components/charts/echart.tsx`

**Interfaces:**
- Consumes: nothing new beyond `echarts/core` and `echarts-for-react/lib/core` (tree-shaken imports — see rationale in the step below).
- Produces:
  - `export function ZirenChart(props: { option: Record<string, unknown>; group?: string; className?: string; height?: number | string }): JSX.Element` — the ONE component every chart in Tasks 4–13 renders instead of Recharts JSX.

This registers every ECharts chart type and component the whole migration needs, in one place, tree-shaken — pulling in the full `echarts` package (its default entry point) would ship every chart type ECharts has (candlestick, sankey, tree, graph, map, …) none of which this dashboard uses, and meaningfully bloats the bundle for no reason. `echarts/core` plus explicit `.use([...])` registration is the officially documented way to avoid that.

- [ ] **Step 1: Write the file**

```tsx
'use client';

import { useEffect, useRef } from 'react';
import * as echarts from 'echarts/core';
import { LineChart, BarChart, PieChart, HeatmapChart, FunnelChart, GaugeChart } from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  DataZoomComponent,
  VisualMapComponent,
  TitleComponent,
} from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import ReactEChartsCore from 'echarts-for-react/lib/core';

echarts.use([
  LineChart, BarChart, PieChart, HeatmapChart, FunnelChart, GaugeChart,
  GridComponent, TooltipComponent, LegendComponent, DataZoomComponent,
  VisualMapComponent, TitleComponent, CanvasRenderer,
]);

export interface ZirenChartProps {
  option: Record<string, unknown>;
  /**
   * Charts sharing a group id get a synced crosshair/tooltip: hovering a
   * point on one highlights the same x-position on every other chart in the
   * group. Only meaningful between charts that share an x-axis (the three
   * time-series charts on Overview) — a pie or gauge in the same group still
   * joins for tooltip-trigger consistency but has no axis to sync against.
   */
  group?: string;
  className?: string;
  height?: number | string;
}

/**
 * The ECharts equivalent of the old Recharts-based `efferd/ui/chart.tsx`.
 * Every real chart on the dashboard renders through this; nothing should
 * import `echarts-for-react`'s default export or raw `<ReactECharts>`
 * directly, so every chart shares one resize strategy and one group-sync
 * mechanism.
 */
export function ZirenChart({ option, group, className, height = '100%' }: ZirenChartProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const chartRef = useRef<ReactEChartsCore>(null);

  // echarts-for-react listens for window resize on its own, but a sidebar
  // collapse or a card growing/shrinking inside a CSS grid never fires a
  // window resize event — Recharts' <ResponsiveContainer> handled that case
  // via its own ResizeObserver, and this reproduces the same guarantee.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const instance = chartRef.current?.getEchartsInstance();
    if (!instance) return;
    const observer = new ResizeObserver(() => instance.resize());
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Cross-chart crosshair sync. echarts.connect() operates on a group id
  // registered on each chart instance; this is the documented low-level API
  // rather than a convenience prop, so it isn't dependent on
  // echarts-for-react exposing a matching one.
  useEffect(() => {
    if (!group) return;
    const instance = chartRef.current?.getEchartsInstance();
    if (!instance) return;
    instance.group = group;
    echarts.connect(group);
  }, [group]);

  return (
    <div className={className} ref={containerRef} style={{ height }}>
      <ReactEChartsCore
        echarts={echarts}
        lazyUpdate
        notMerge={false}
        onChartReady={chart => {
          if (group) {
            chart.group = group;
            echarts.connect(group);
          }
        }}
        option={option}
        ref={chartRef}
        style={{ height: '100%', width: '100%' }}
      />
    </div>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors. If `echarts-for-react/lib/core`'s types don't resolve cleanly under this project's `moduleResolution`, check `node_modules/echarts-for-react/lib/core.d.ts` exists — if the subpath import fails to resolve, fall back to `import { default as ReactEChartsCore } from 'echarts-for-react/lib/core'` (some bundlers need the explicit `default` form for a CJS interop file); the rest of the component is unaffected either way.

- [ ] **Step 3: Commit**

```bash
git add components/charts/echart.tsx
git commit -m "feat(dashboard): add ZirenChart, the shared ECharts wrapper"
```

---

### Task 4: Migrate `incident-volume-chart.tsx` (establishes the pattern for every time-series chart after it)

**Files:**
- Modify: `ziren_dashboard/components/charts/incident-volume-chart.tsx` (full rewrite of the internals; same exported `IncidentVolumeChart` name and `{ data: VolumePoint[] }` props)

**Interfaces:**
- Consumes: `ZirenChart` (Task 3), `baseEChartsOption`/`readToken` (Task 2).
- Produces: nothing new — `VolumePoint` stays exactly as defined today, so `overview/page.tsx` needs no change for this task.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * IncidentVolumeChart — arrivals per day, on the Overview chart deck.
 *
 * Gradient line-area, a range Select (7/14/30 days), a delta badge — same
 * shape as before the ECharts migration. `smoothMonotone: 'x'` is the direct
 * ECharts equivalent of Recharts' `type="monotone"`: plain `smooth: true`
 * fits a spline that can overshoot past a data point's value, which on daily
 * arrival counts this small (0–4 some days) drew arrival counts that never
 * happened, including negative ones. smoothMonotone constrains the curve to
 * never leave the range its neighboring points define.
 *
 * The data is real — reads /dispatch/activity, which includes resolved and
 * cancelled incidents, unlike /dispatch/queue. See lib/charts/queue-series.ts.
 */

import { useMemo, useState } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import { ZirenChart } from './echart';
import { baseEChartsOption, readToken } from '@/lib/charts/echarts-theme';
import { DeltaBadge } from './delta-badge';
import { useTheme } from '@/lib/theme/use-theme';

export interface VolumePoint {
  date: string;
  received: number;
}

type PeriodDays = 7 | 14 | 30;

export function IncidentVolumeChart({ data }: { data: VolumePoint[] }) {
  const { theme } = useTheme();
  const [periodDays, setPeriodDays] = useState<PeriodDays>(14);

  const rows = useMemo(
    () => data.slice(Math.max(0, data.length - periodDays)),
    [data, periodDays],
  );

  const growthPct = useMemo(() => {
    if (rows.length < 6) return 0;
    const third = Math.max(1, Math.floor(rows.length / 3));
    const mean = (xs: VolumePoint[]) =>
      xs.reduce((a, r) => a + r.received, 0) / xs.length;
    const first = mean(rows.slice(0, third));
    const last = mean(rows.slice(-third));
    if (first === 0) return 0;
    return Math.round(((last - first) / first) * 100);
  }, [rows]);

  const total = rows.reduce((a, r) => a + r.received, 0);

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    const dates = rows.map(r => r.date);
    return {
      ...baseEChartsOption(),
      xAxis: {
        type: 'category',
        data: dates,
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: readToken('--color-text-muted'),
          formatter: (v: string) =>
            new Date(v).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
        },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: readToken('--color-surface-border') } },
        axisLabel: { color: readToken('--color-text-muted') },
      },
      tooltip: {
        ...baseEChartsOption().tooltip,
        trigger: 'axis',
        formatter: (params: { value: number; axisValue: string }[]) => {
          const p = params[0];
          const label = new Date(p.axisValue).toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          });
          return `<div style="font-weight:600;margin-bottom:4px">${label}</div>${p.value} reports`;
        },
      },
      dataZoom: [{ type: 'inside' }],
      series: [
        {
          type: 'line',
          data: rows.map(r => r.received),
          smooth: true,
          smoothMonotone: 'x',
          symbol: 'circle',
          symbolSize: 0,
          showSymbol: false,
          lineStyle: { color: brand, width: 2 },
          itemStyle: { color: brand },
          areaStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: `${brand}73` },
                { offset: 0.55, color: `${brand}1F` },
                { offset: 1, color: `${brand}00` },
              ],
            },
          },
        },
      ],
    };
    // theme is a dependency so colors are re-read from the DOM after a
    // light/dark flip, giving the option a new identity ECharts re-renders.
  }, [rows, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-3">
      <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-1.5">
          <div className="flex items-center gap-2">
            <CardTitle>Reports received per day</CardTitle>
            <DeltaBadge riseIsBad value={growthPct} suffix="%" />
          </div>
          <CardDescription>
            {total} over {rows.length} days · today is still filling
          </CardDescription>
        </div>
        <Select
          onValueChange={v => setPeriodDays(Number(v) as PeriodDays)}
          value={String(periodDays)}
        >
          <SelectTrigger className="w-[150px]" size="sm">
            <SelectValue placeholder="Range" />
          </SelectTrigger>
          <SelectContent align="end">
            <SelectItem value="7">Last 7 days</SelectItem>
            <SelectItem value="14">Last 14 days</SelectItem>
            <SelectItem value="30">Last 30 days</SelectItem>
          </SelectContent>
        </Select>
      </CardHeader>
      <CardContent>
        <ZirenChart className="aspect-22/8 w-full" group="overview" option={option} />
      </CardContent>
    </Card>
  );
}
```

Note: `${brand}73` / `${brand}1F` / `${brand}00` append hex alpha to a `#RRGGBB` token (`73`≈45%, `1F`≈12%, `00`=0% — matching the old gradient's `stopOpacity` values 0.45/0.12/0). This assumes every color token this migration reads is a 6-digit hex, which is true for all `--color-severity-*`, `--color-agency-*`, and `--color-brand` tokens (confirmed in `app/globals.css`). If a future token is ever added as an `rgb()`/`rgba()` string instead, this concatenation trick breaks — not a concern for the tokens this plan touches, but worth a comment where it's used (already added above).

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

Start the dashboard dev server (use the `ziren-dev` skill for auth-seeding/mocking), open the Overview page as a Provincial Admin, and confirm: the gradient area renders in brand orange, hovering shows a tooltip with the weekday/date and report count, the 7/14/30-day range Select still switches the window, scrolling over the chart zooms the range in/out, and switching the OS/app theme between light and dark changes the gradient and axis colors correctly (re-open Settings to toggle theme, or use the account menu's theme switcher already in `ZirenHeader`).

- [ ] **Step 4: Commit**

```bash
git add components/charts/incident-volume-chart.tsx
git commit -m "feat(dashboard): migrate IncidentVolumeChart to ECharts"
```

---

### Task 5: Migrate `agency-share-chart.tsx`

**Files:**
- Modify: `ziren_dashboard/components/charts/agency-share-chart.tsx` (same exported `AgencyShareChart` name and `{ data: AgencySlice[] }` props)

**Interfaces:**
- Consumes: `ZirenChart`, `agencyColors()` (Task 2).
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * AgencyShareChart — the active queue split by responding agency.
 *
 * Donut, not a plain pie — rounded segment gap via itemStyle.borderWidth,
 * share percentage printed inside each segment, a legend underneath. Agency
 * colors are fixed to the entity (BFP coral-red, PNP sky-blue, MDRRMO
 * emerald) and never bound to a ramp position — see agencyColors() in
 * lib/charts/echarts-theme.ts.
 *
 * Below five open incidents the donut is suppressed for a sentence instead,
 * unchanged from before this migration: "2 of 3" drawn as 67% invites a
 * reader to see a trend in what is one incident either way.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { agencyColors, readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';

export interface AgencySlice {
  agency: 'BFP' | 'PNP' | 'MDRRMO';
  active: number;
}

const MIN_FOR_PROPORTION = 5;

export function AgencyShareChart({ data }: { data: AgencySlice[] }) {
  const { theme } = useTheme();
  const total = data.reduce((a, d) => a + d.active, 0);

  const rows = data
    .filter(d => d.active > 0)
    .map(d => ({ ...d, share: Math.round((d.active / total) * 100) }));

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const colors = agencyColors();
    const cardBg = readToken('--color-surface-card');
    const textMuted = readToken('--color-text-muted');
    return {
      tooltip: {
        trigger: 'item',
        formatter: (p: { name: string; value: number }) => `${p.name}: ${p.value} active`,
      },
      legend: {
        bottom: 0,
        icon: 'circle',
        itemWidth: 8,
        itemHeight: 8,
        textStyle: { color: textMuted, fontSize: 12 },
      },
      series: [
        {
          type: 'pie',
          radius: ['36%', '88%'],
          center: ['50%', '45%'],
          data: rows.map(r => ({
            name: r.agency,
            value: r.active,
            itemStyle: { color: colors[r.agency] },
            label: {
              show: true,
              position: 'inside',
              formatter: () => `${r.share}%`,
              color: cardBg,
              fontWeight: 500,
            },
          })),
          itemStyle: { borderColor: cardBg, borderWidth: 4, borderRadius: 8 },
          labelLine: { show: false },
        },
      ],
    };
  }, [rows, theme]);

  return (
    <Card className="col-span-1 flex flex-col">
      <CardHeader className="space-y-1 pb-0">
        <CardTitle>By agency</CardTitle>
        <CardDescription>Share of the active queue</CardDescription>
      </CardHeader>
      <CardContent className="my-auto">
        {total < MIN_FOR_PROPORTION ? (
          <p className="py-8 text-center text-sm text-muted-foreground">
            {total === 0
              ? 'Nothing in the queue.'
              : `Only ${total} active — too few to read as a split.`}
          </p>
        ) : (
          <ZirenChart className="mx-auto aspect-square max-h-72 w-full" group="overview" option={option} />
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

On the Overview page, confirm the donut renders with the correct locked agency colors, the inside labels show the right percentages, hovering a segment shows a tooltip with the exact count, the legend below names all agencies present, and the <5-active suppression sentence still appears when the queue is that quiet.

- [ ] **Step 4: Commit**

```bash
git add components/charts/agency-share-chart.tsx
git commit -m "feat(dashboard): migrate AgencyShareChart to ECharts"
```

---

### Task 6: Migrate `severity-trend-chart.tsx`

**Files:**
- Modify: `ziren_dashboard/components/charts/severity-trend-chart.tsx` (same exported `SeverityTrendChart` name and `{ data: SeverityDay[] }` props)

**Interfaces:**
- Consumes: `ZirenChart`, `severityColors()`.
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * SeverityTrendChart — arrivals per day split by severity, stacked columns.
 *
 * Severity hues are the locked four-tier scale, stacked in escalating order
 * so critical always sits on top — the position a scanning eye reaches
 * first — and never gets re-ordered by which tier happens to be largest
 * that week. The hand-rolled legend below the chart (rather than ECharts'
 * own <legend>) exists for the same reason it did before this migration:
 * severity is an ORDERED scale a dispatcher reads as a ladder, and any
 * auto-generated legend sorts alphabetically, destroying that order.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { baseEChartsOption, severityColors, readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';

export interface SeverityDay {
  date: string;
  low: number;
  medium: number;
  high: number;
  critical: number;
}

const TIERS = ['low', 'medium', 'high', 'critical'] as const;
const TIER_LABEL: Record<(typeof TIERS)[number], string> = {
  low: 'Low', medium: 'Medium', high: 'High', critical: 'Critical',
};

export function SeverityTrendChart({ data }: { data: SeverityDay[] }) {
  const { theme } = useTheme();

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const colors = severityColors();
    const cardBg = readToken('--color-surface-card');
    return {
      ...baseEChartsOption(),
      xAxis: {
        type: 'category',
        data: data.map(d => d.date),
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: readToken('--color-text-muted'),
          formatter: (v: string) =>
            new Date(v).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
        },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: readToken('--color-surface-border') } },
        axisLabel: { color: readToken('--color-text-muted') },
      },
      tooltip: {
        ...baseEChartsOption().tooltip,
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
      },
      dataZoom: [{ type: 'inside' }],
      series: TIERS.map((tier, i) => ({
        name: TIER_LABEL[tier],
        type: 'bar',
        stack: 'severity',
        data: data.map(d => d[tier]),
        itemStyle: {
          color: colors[tier],
          borderColor: cardBg,
          borderWidth: 1,
          borderRadius: i === TIERS.length - 1 ? [4, 4, 0, 0] : 0,
        },
      })),
    };
  }, [data, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-4">
      <CardHeader className="space-y-1">
        <CardTitle>Severity mix over time</CardTitle>
        <CardDescription>Reports by the severity they were triaged at, per day</CardDescription>
      </CardHeader>
      <CardContent>
        <ZirenChart className="aspect-22/9 w-full" group="overview" option={option} />
        <div className="mt-3 flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5">
          {TIERS.map(tier => (
            <span
              className="flex items-center gap-1.5 text-meta"
              key={tier}
              style={{ color: 'var(--color-text-muted)' }}
            >
              <span
                aria-hidden="true"
                className="size-2 shrink-0 rounded-[2px]"
                style={{ backgroundColor: `var(--color-severity-${tier})` }}
              />
              {TIER_LABEL[tier]}
            </span>
          ))}
        </div>
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

Confirm the stack order is low→medium→high→critical bottom-to-top, only the top (critical) segment has rounded top corners, hovering a day shows all four tiers in one tooltip, and the hand-written legend below still reads left-to-right in the same ladder order (not alphabetical).

- [ ] **Step 4: Commit**

```bash
git add components/charts/severity-trend-chart.tsx
git commit -m "feat(dashboard): migrate SeverityTrendChart to ECharts"
```

---

### Task 7: Migrate `dispatch-latency-chart.tsx`

**Files:**
- Modify: `ziren_dashboard/components/charts/dispatch-latency-chart.tsx` (same exported `DispatchLatencyChart` name and `{ data: LatencyPoint[]; days: number }` props)

**Interfaces:**
- Consumes: `ZirenChart`, `baseEChartsOption`/`readToken`.
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * DispatchLatencyChart — median minutes from report to dispatch, per day.
 *
 * A day with no dispatches is a GAP in the line (a null in the data array,
 * `connectNulls: false`), never a plotted zero — nothing happened is not
 * the same as instant response, and a zero would read as the best day on
 * the chart. See dispatchLatency() in lib/charts/queue-series.ts.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { baseEChartsOption, readToken } from '@/lib/charts/echarts-theme';
import { DeltaBadge } from './delta-badge';
import { useTheme } from '@/lib/theme/use-theme';

export interface LatencyPoint {
  date: string;
  minutes: number | null;
  dispatched: number;
}

function humanise(mins: number): string {
  if (mins < 1) return '<1m';
  if (mins < 60) return `${Math.round(mins)}m`;
  const h = mins / 60;
  if (h < 24) return h < 10 ? `${h.toFixed(1)}h` : `${Math.round(h)}h`;
  return `${Math.round(h / 24)}d`;
}

export function DispatchLatencyChart({ data, days }: { data: LatencyPoint[]; days: number }) {
  const { theme } = useTheme();
  const withValues = data.filter(d => d.minutes !== null);

  const trendPct = useMemo(() => {
    if (withValues.length < 4) return null;
    const half = Math.floor(withValues.length / 2);
    const mean = (xs: LatencyPoint[]) =>
      xs.reduce((a, r) => a + (r.minutes ?? 0), 0) / xs.length;
    const first = mean(withValues.slice(0, half));
    const last = mean(withValues.slice(-half));
    if (first === 0) return null;
    return Math.round(((last - first) / first) * 100);
  }, [withValues]);

  const overall = useMemo(() => {
    if (!withValues.length) return null;
    const sorted = withValues.map(d => d.minutes as number).sort((a, b) => a - b);
    const mid = Math.floor(sorted.length / 2);
    return sorted.length % 2 === 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid];
  }, [withValues]);

  const totalDispatched = data.reduce((a, d) => a + d.dispatched, 0);

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    return {
      ...baseEChartsOption(),
      xAxis: {
        type: 'category',
        data: data.map(d => d.date),
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: {
          color: readToken('--color-text-muted'),
          formatter: (v: string) =>
            new Date(v).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
        },
      },
      yAxis: {
        type: 'value',
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: readToken('--color-surface-border') } },
        axisLabel: {
          color: readToken('--color-text-muted'),
          formatter: (v: number) => (v === 0 ? '0' : humanise(v)),
        },
      },
      tooltip: {
        ...baseEChartsOption().tooltip,
        trigger: 'axis',
        formatter: (params: { axisValue: string; data: number | null }[]) => {
          const p = params[0];
          if (p.data === null || p.data === undefined) return 'No dispatches';
          const row = data.find(d => d.date === p.axisValue);
          const label = new Date(p.axisValue).toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          });
          return `<div style="font-weight:600;margin-bottom:4px">${label}</div>${humanise(p.data)} · ${row?.dispatched ?? 0} dispatched`;
        },
      },
      dataZoom: [{ type: 'inside' }],
      series: [
        {
          type: 'line',
          data: data.map(d => d.minutes),
          connectNulls: false,
          symbol: 'circle',
          symbolSize: 6,
          lineStyle: { color: brand, width: 2 },
          itemStyle: { color: brand },
          label: {
            show: true,
            position: 'top',
            color: readToken('--color-text-muted'),
            fontSize: 11,
            formatter: (p: { value: number | null }) =>
              p.value === null || p.value === undefined ? '' : humanise(p.value),
          },
        },
      ],
    };
  }, [data, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle>Time to dispatch</CardTitle>
          {trendPct !== null && <DeltaBadge riseIsBad suffix="%" value={trendPct} />}
        </div>
        <CardDescription>
          {overall !== null
            ? `Median ${humanise(overall)} across ${totalDispatched} dispatches in ${days} days`
            : `No dispatches in the last ${days} days`}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ZirenChart className="aspect-22/9 w-full" group="overview" option={option} />
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

Confirm days with no dispatches show as a genuine gap in the line (not a dip to zero), point labels above each dot show the humanised duration, and the tooltip on a hovered point reads "{duration} · {n} dispatched".

- [ ] **Step 4: Commit**

```bash
git add components/charts/dispatch-latency-chart.tsx
git commit -m "feat(dashboard): migrate DispatchLatencyChart to ECharts"
```

---

### Task 8: Migrate `category-bar-chart.tsx` (Analytics — used 4 times: by type/agency/municipality/severity)

**Files:**
- Modify: `ziren_dashboard/components/charts/category-bar-chart.tsx` (same exported `CategoryBarChart` name and `{ entries: [string, number][]; color: string; colorByLabel?: Record<string, string> }` props — `app/(dashboard)/analytics/page.tsx` needs no change)

**Interfaces:**
- Consumes: `ZirenChart`.
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * CategoryBarChart — one label, one count, animated horizontal bars.
 * Used four times on System Analytics (by type, by agency, by municipality,
 * by severity) — same component, different `entries`/`color`/`colorByLabel`.
 */

import { useMemo } from 'react';
import { ZirenChart } from './echart';
import { useTheme } from '@/lib/theme/use-theme';

export function CategoryBarChart({
  entries,
  color,
  colorByLabel,
}: {
  entries: [string, number][];
  color: string;
  colorByLabel?: Record<string, string>;
}) {
  const { theme } = useTheme();

  const rows = entries.map(([label, count]) => ({
    label: label.replace(/_/g, ' '),
    count,
    fill: colorByLabel?.[label] ?? color,
  }));
  const height = Math.max(120, rows.length * 32);

  const option = useMemo(() => {
    if (typeof window === 'undefined' || rows.length === 0) return {};
    return {
      grid: { left: 8, right: 32, top: 8, bottom: 8, containLabel: true },
      xAxis: { type: 'value', show: false },
      yAxis: {
        type: 'category',
        data: rows.map(r => r.label).reverse(),
        axisLine: { show: false },
        axisTick: { show: false },
      },
      tooltip: {
        trigger: 'item',
        formatter: (p: { name: string; value: number }) => `${p.name}: ${p.value}`,
      },
      series: [
        {
          type: 'bar',
          data: rows.map(r => ({ value: r.count, itemStyle: { color: r.fill } })).reverse(),
          barMaxWidth: 22,
          label: { show: true, position: 'right', fontWeight: 600 },
          animationDuration: 800,
          animationEasing: 'cubicOut',
        },
      ],
    };
    // ECharts draws category axes top-to-bottom in array order; .reverse()
    // keeps the highest-count entry (rows[0], since callers already sort
    // descending) at the TOP of the chart, matching the old Recharts version.
  }, [rows, theme]);

  if (entries.length === 0) {
    return <p className="py-6 text-center text-meta text-muted-foreground">No data yet.</p>;
  }

  return <ZirenChart className="w-full" height={height} option={option} />;
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

On the Analytics page (Incidents tab), confirm all four "By type / By agency / By municipality / By severity" cards render bars sorted descending top-to-bottom, "By agency" and "By severity" show the locked agency/severity colors per bar (`colorByLabel`), bars animate in on load, and the "No data yet." empty state still appears for an entries array of length 0.

- [ ] **Step 4: Commit**

```bash
git add components/charts/category-bar-chart.tsx
git commit -m "feat(dashboard): migrate CategoryBarChart to ECharts"
```

---

### Task 9: Migrate `incident-trend-chart.tsx` (Analytics)

**Files:**
- Modify: `ziren_dashboard/components/charts/incident-trend-chart.tsx` (same exported `IncidentTrendChart` name and `{ data: TrendPoint[]; period: 'day' | 'month' | 'year' }` props)

**Interfaces:**
- Consumes: `ZirenChart`, `readToken`.
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * IncidentTrendChart — incidents over time, gradient area, on System
 * Analytics. Same visual language as Overview's IncidentVolumeChart, built
 * for Analytics' own day/month/year period selector (owned by the page,
 * not this component).
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';

export interface TrendPoint {
  bucket: string;
  count: number;
}

function formatBucket(bucket: string, period: 'day' | 'month' | 'year'): string {
  if (period === 'year') return bucket;
  if (period === 'month') {
    const [y, m] = bucket.split('-');
    return new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(undefined, {
      month: 'short', year: 'numeric',
    });
  }
  return new Date(bucket).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function IncidentTrendChart({
  data,
  period,
}: {
  data: TrendPoint[];
  period: 'day' | 'month' | 'year';
}) {
  const { theme } = useTheme();
  const total = data.reduce((a, d) => a + d.count, 0);

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    const border = readToken('--color-surface-border');
    const textMuted = readToken('--color-text-muted');
    return {
      grid: { left: 8, right: 12, top: 16, bottom: 8, containLabel: true },
      xAxis: {
        type: 'category',
        data: data.map(d => d.bucket),
        boundaryGap: false,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: textMuted, formatter: (v: string) => formatBucket(v, period) },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: border } },
        axisLabel: { color: textMuted },
      },
      tooltip: {
        trigger: 'axis',
        borderColor: border,
        formatter: (params: { axisValue: string; value: number }[]) => {
          const p = params[0];
          return `${formatBucket(p.axisValue, period)}: ${p.value}`;
        },
      },
      series: [
        {
          type: 'line',
          data: data.map(d => d.count),
          smooth: true,
          smoothMonotone: 'x',
          showSymbol: false,
          lineStyle: { color: brand, width: 2 },
          itemStyle: { color: brand },
          areaStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: `${brand}73` },
                { offset: 0.55, color: `${brand}1F` },
                { offset: 1, color: `${brand}00` },
              ],
            },
          },
        },
      ],
    };
  }, [data, period, theme]);

  return (
    <Card className="col-span-1 lg:col-span-2">
      <CardHeader className="gap-1">
        <CardTitle className="text-[15px]">Incidents over time</CardTitle>
        <CardDescription>{total} total, by {period}</CardDescription>
      </CardHeader>
      <CardContent>
        <ZirenChart className="aspect-21/9 w-full" option={option} />
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

On the Analytics page (Incidents tab), confirm the gradient area renders, switching the day/month/year Select re-labels the x-axis correctly, and hovering shows the right formatted bucket label.

- [ ] **Step 4: Commit**

```bash
git add components/charts/incident-trend-chart.tsx
git commit -m "feat(dashboard): migrate IncidentTrendChart to ECharts"
```

---

### Task 10: Fold `category-mix-chart.tsx` into ECharts

**Files:**
- Modify: `ziren_dashboard/components/charts/category-mix-chart.tsx` (same exported `CategoryMixChart` name and `{ ranked: CategoryCount[]; unclassified: number; total: number; days: number }` props)

**Interfaces:**
- Consumes: `ZirenChart`, `CategoryCount` from `lib/charts/queue-series.ts` (unchanged).
- Produces: nothing new.

- [ ] **Step 1: Rewrite the component**

```tsx
'use client';

/**
 * CategoryMixChart — which kinds of emergency this province actually gets.
 *
 * RANKED HORIZONTAL BARS, not a pie or a donut — six categories of similar
 * size is the case a pie reads worst, and bars sorted descending give the
 * ranking for free. ONE HUE (brand), not six: this is a magnitude
 * comparison, not identity, and six hues would collide with the locked
 * agency and severity scales. `other`/null is held apart below the chart —
 * see the footnote — never ranked among the five real categories.
 *
 * ECharts scales its value axis to the data's own max automatically, which
 * reproduces "bars compared against the largest CATEGORY, not the total"
 * (the old hand-rolled version computed this max manually) with no extra
 * code.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Fig } from '@/components/ui/fig';
import { ZirenChart } from './echart';
import { readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';
import type { CategoryCount } from '@/lib/charts/queue-series';

export function CategoryMixChart({
  ranked,
  unclassified,
  total,
  days,
}: {
  ranked: CategoryCount[];
  unclassified: number;
  total: number;
  days: number;
}) {
  const { theme } = useTheme();
  const classified = total - unclassified;

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    const rows = ranked.map(r => ({
      ...r,
      pct: classified > 0 ? Math.round((r.count / classified) * 100) : 0,
    }));
    return {
      grid: { left: 8, right: 48, top: 8, bottom: 8, containLabel: true },
      xAxis: { type: 'value', show: false },
      yAxis: {
        type: 'category',
        data: rows.map(r => r.label).reverse(),
        axisLine: { show: false },
        axisTick: { show: false },
      },
      tooltip: {
        trigger: 'item',
        formatter: (p: { dataIndex: number }) => {
          const row = rows[rows.length - 1 - p.dataIndex];
          return `${row.label}: ${row.count} (${row.pct}%)`;
        },
      },
      series: [
        {
          type: 'bar',
          data: rows.map(r => r.count).reverse(),
          itemStyle: { color: brand, borderRadius: [0, 4, 4, 0] },
          barMaxWidth: 20,
          label: {
            show: true,
            position: 'right',
            formatter: (p: { dataIndex: number }) => {
              const row = rows[rows.length - 1 - p.dataIndex];
              return `${row.count}  ${row.pct}%`;
            },
          },
          animationDuration: 700,
          animationEasing: 'cubicOut',
        },
      ],
    };
  }, [ranked, classified, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>What kind of emergency</CardTitle>
        <CardDescription>All reports in the last {days} days, resolved ones included</CardDescription>
      </CardHeader>
      <CardContent>
        {total === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">No reports in this window.</p>
        ) : (
          <>
            <ZirenChart className="w-full" height={Math.max(160, ranked.length * 40)} option={option} />
            {unclassified > 0 && (
              <p
                className="mt-4 border-t pt-2.5 text-meta"
                style={{ borderColor: 'var(--color-surface-border)', color: 'var(--color-text-muted)' }}
              >
                <Fig className="text-meta font-semibold">{unclassified}</Fig>{' '}
                {unclassified === 1 ? 'report' : 'reports'} unclassified — the reporter skipped the
                category step, or the report predates the current category set. Not a category of
                its own, so it is not ranked above.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 2: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 3: Visual check**

On Overview, confirm the five real categories still render ranked descending, the bar chart is scaled by the largest category (the largest bar reaches close to the chart's edge, not a fixed fraction of the total), hovering a bar shows "{label}: {count} ({pct}%)", and the unclassified footnote still sits below the chart untouched.

- [ ] **Step 4: Commit**

```bash
git add components/charts/category-mix-chart.tsx
git commit -m "feat(dashboard): migrate CategoryMixChart to ECharts"
```

---

### Task 11: New chart — Incident heatmap calendar

**Files:**
- Modify: `ziren_dashboard/lib/charts/queue-series.ts` (add `heatmapBuckets`)
- Create: `ziren_dashboard/components/charts/incident-heatmap-chart.tsx`

**Interfaces:**
- Consumes: `ActivityIncident` (existing type from `lib/api/dispatch.ts`), `ZirenChart`.
- Produces:
  - `export function heatmapBuckets(incidents: ActivityIncident[], days: number): { day: number; hour: number; count: number }[]` — always 168 entries (7 days × 24 hours), zero-filled for empty cells.
  - `export function IncidentHeatmapChart({ data, days }: { data: ReturnType<typeof heatmapBuckets>; days: number })`

- [ ] **Step 1: Add `heatmapBuckets` to `lib/charts/queue-series.ts`**

Append to the file (near `unassignedSeries`, at the end):

```typescript
/**
 * Report volume by day-of-week × hour-of-day, over a window this function
 * takes directly rather than sharing TREND_DAYS — 14 days is too thin to
 * show a real weekly pattern (a single unusually busy Tuesday would look
 * like "Tuesdays are busy"), so the Overview page calls this with a longer,
 * separate window (56 days) fetched independently of the 14-day activity
 * used everywhere else on the page.
 *
 * Always returns all 168 buckets (7 × 24), zero-filled, so the heatmap
 * renders a complete grid rather than a sparse one with holes where nothing
 * happened to arrive in a given hour.
 */
export function heatmapBuckets(
  incidents: ActivityIncident[],
  days: number,
): { day: number; hour: number; count: number }[] {
  const since = Date.now() - days * 86_400_000;
  const counts = new Map<string, number>();

  for (const inc of incidents) {
    const t = ms(inc.created_at);
    if (t === null || t < since) continue;
    const d = new Date(t);
    const key = `${d.getDay()}-${d.getHours()}`;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }

  const out: { day: number; hour: number; count: number }[] = [];
  for (let day = 0; day < 7; day++) {
    for (let hour = 0; hour < 24; hour++) {
      out.push({ day, hour, count: counts.get(`${day}-${hour}`) ?? 0 });
    }
  }
  return out;
}
```

- [ ] **Step 2: Create `components/charts/incident-heatmap-chart.tsx`**

```tsx
'use client';

/**
 * IncidentHeatmapChart — day-of-week × hour-of-day report volume, over a
 * longer window (56 days, passed in as `days`) than the rest of the
 * Overview deck. Color intensity, not a fixed hue scale — this is a
 * magnitude question ("when do reports actually arrive"), not an identity
 * one, so it uses the same single-hue-by-magnitude reasoning as
 * CategoryMixChart rather than the locked severity/agency scales.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';
import type { heatmapBuckets } from '@/lib/charts/queue-series';

const DAY_LABELS = Array.from({ length: 7 }, (_, i) =>
  // 2024-01-07 was a Sunday — an arbitrary known-Sunday anchor, used only to
  // generate locale-correct short weekday names, getDay()-indexed the same
  // way heatmapBuckets() buckets its `day` field (0 = Sunday).
  new Date(2024, 0, 7 + i).toLocaleDateString(undefined, { weekday: 'short' }),
);
const HOUR_LABELS = Array.from({ length: 24 }, (_, h) => `${h}:00`);

export function IncidentHeatmapChart({
  data,
  days,
}: {
  data: ReturnType<typeof heatmapBuckets>;
  days: number;
}) {
  const { theme } = useTheme();
  const total = data.reduce((a, d) => a + d.count, 0);
  const max = Math.max(1, ...data.map(d => d.count));

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    const textMuted = readToken('--color-text-muted');
    const surfaceRaised = readToken('--color-surface-raised');
    return {
      grid: { left: 48, right: 16, top: 16, bottom: 48, containLabel: false },
      xAxis: {
        type: 'category',
        data: HOUR_LABELS,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: textMuted, interval: 2, fontSize: 10 },
        splitArea: { show: true },
      },
      yAxis: {
        type: 'category',
        data: DAY_LABELS,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { color: textMuted, fontSize: 11 },
        splitArea: { show: true },
      },
      visualMap: {
        min: 0,
        max,
        show: false,
        inRange: { color: [surfaceRaised, brand] },
      },
      tooltip: {
        formatter: (p: { data: [number, number, number] }) => {
          const [hourIdx, dayIdx, count] = p.data;
          return `${DAY_LABELS[dayIdx]} ${HOUR_LABELS[hourIdx]}: ${count} ${count === 1 ? 'report' : 'reports'}`;
        },
      },
      series: [
        {
          type: 'heatmap',
          data: data.map(d => [d.hour, d.day, d.count]),
          itemStyle: { borderColor: readToken('--color-surface-card'), borderWidth: 1 },
          label: { show: false },
        },
      ],
    };
  }, [data, max, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-4">
      <CardHeader className="space-y-1">
        <CardTitle>When reports arrive</CardTitle>
        <CardDescription>{total} reports over the last {days} days, by day and hour</CardDescription>
      </CardHeader>
      <CardContent>
        {total === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">No reports in this window.</p>
        ) : (
          <ZirenChart className="w-full" height={280} option={option} />
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/charts/queue-series.ts components/charts/incident-heatmap-chart.tsx
git commit -m "feat(dashboard): add incident heatmap calendar chart"
```

(Visual verification for this chart happens in Task 14, once it's actually wired into a page — there's no page rendering it yet.)

---

### Task 12: New chart — Response funnel

**Files:**
- Modify: `ziren_dashboard/lib/charts/queue-series.ts` (add `funnelCounts`)
- Create: `ziren_dashboard/components/charts/response-funnel-chart.tsx`

**Interfaces:**
- Consumes: `ActivityIncident`, `ZirenChart`.
- Produces:
  - `export function funnelCounts(incidents: ActivityIncident[], days: number): { received: number; dispatched: number; resolved: number }`
  - `export function ResponseFunnelChart({ counts, days }: { counts: ReturnType<typeof funnelCounts>; days: number })`

- [ ] **Step 1: Add `funnelCounts` to `lib/charts/queue-series.ts`**

```typescript
/**
 * Received → Dispatched → Resolved, over the window, counted honestly.
 *
 * "Resolved" is gated on `status === 'resolved'` specifically, NOT on
 * `resolved_at` being non-null — resolved_at is also written for
 * cancellations (see the note on openAt() above). A cancelled-but-dispatched
 * incident therefore counts in the Dispatched stage and drops out before
 * Resolved, which is the honest reading for a funnel: cancellation is
 * attrition, not a completed pipeline stage.
 */
export function funnelCounts(
  incidents: ActivityIncident[],
  days: number,
): { received: number; dispatched: number; resolved: number } {
  const since = Date.now() - days * 86_400_000;
  const inWindow = incidents.filter(inc => {
    const t = ms(inc.created_at);
    return t !== null && t >= since;
  });

  return {
    received: inWindow.length,
    dispatched: inWindow.filter(i => i.dispatched_at !== null).length,
    resolved: inWindow.filter(i => i.status === 'resolved').length,
  };
}
```

- [ ] **Step 2: Create `components/charts/response-funnel-chart.tsx`**

```tsx
'use client';

/**
 * ResponseFunnelChart — Received → Dispatched → Resolved, over the window.
 *
 * Stage colors reuse the SAME status tokens the rest of the console already
 * uses for these exact states (STATUS_STYLE in overview/page.tsx uses the
 * same --color-status-dispatched / --color-status-resolved), rather than
 * inventing a new three-color scale for this one chart.
 *
 * `sort: 'none'` is load-bearing: ECharts funnels default to sorting stages
 * by value descending, which would silently reorder the pipeline whenever
 * Dispatched happened to be smaller than Resolved (impossible here, but the
 * chart type's default is still wrong for a process that has a fixed order
 * by definition) into something that no longer reads as a pipeline at all.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';
import type { funnelCounts } from '@/lib/charts/queue-series';

export function ResponseFunnelChart({
  counts,
  days,
}: {
  counts: ReturnType<typeof funnelCounts>;
  days: number;
}) {
  const { theme } = useTheme();

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const brand = readToken('--color-brand');
    const dispatched = readToken('--color-status-dispatched');
    const resolved = readToken('--color-status-resolved');
    const cardBg = readToken('--color-surface-card');
    const stages = [
      { name: 'Received', value: counts.received, color: brand },
      { name: 'Dispatched', value: counts.dispatched, color: dispatched },
      { name: 'Resolved', value: counts.resolved, color: resolved },
    ];
    return {
      tooltip: {
        trigger: 'item',
        formatter: (p: { name: string; value: number }) => {
          const pct = counts.received > 0 ? Math.round((p.value / counts.received) * 100) : 0;
          return `${p.name}: ${p.value} (${pct}%)`;
        },
      },
      series: [
        {
          type: 'funnel',
          sort: 'none',
          left: '10%',
          right: '10%',
          top: 8,
          bottom: 8,
          gap: 2,
          label: {
            show: true,
            position: 'inside',
            formatter: (p: { name: string; value: number }) => `${p.name}\n${p.value}`,
            color: cardBg,
            fontWeight: 600,
          },
          itemStyle: { borderColor: cardBg, borderWidth: 2 },
          data: stages.map(s => ({ name: s.name, value: s.value, itemStyle: { color: s.color } })),
        },
      ],
    };
  }, [counts, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>Response funnel</CardTitle>
        <CardDescription>{counts.received} received in the last {days} days</CardDescription>
      </CardHeader>
      <CardContent>
        {counts.received === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">No reports in this window.</p>
        ) : (
          <ZirenChart className="w-full" height={220} option={option} />
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add lib/charts/queue-series.ts components/charts/response-funnel-chart.tsx
git commit -m "feat(dashboard): add response funnel chart"
```

---

### Task 13: New chart — SLA gauge

**Files:**
- Modify: `ziren_dashboard/components/incidents/incident-vocabulary.ts` (export `DUE_SOON_FRACTION`)
- Create: `ziren_dashboard/components/charts/sla-gauge-chart.tsx`

**Interfaces:**
- Consumes: `DISPATCH_TARGET_MINUTES`, `DEFAULT_TARGET_MINUTES`, `DUE_SOON_FRACTION` (all from `components/incidents/incident-vocabulary.ts`), `ActivityIncident`, `ZirenChart`.
- Produces: `export function SlaGaugeChart({ incidents, days }: { incidents: ActivityIncident[]; days: number })` — this component does its OWN aggregation internally (median + severity-weighted target) rather than through `lib/charts/queue-series.ts`, specifically so `lib/` never has to import from `components/incidents/incident-vocabulary.ts` — see the Global Constraints note on layering.

- [ ] **Step 1: Export `DUE_SOON_FRACTION` from `incident-vocabulary.ts`**

Find this line (around line 138):

```typescript
const DUE_SOON_FRACTION = 0.25;
```

Change it to:

```typescript
export const DUE_SOON_FRACTION = 0.25;
```

Nothing else in that file changes — every existing internal use of `DUE_SOON_FRACTION` keeps working unmodified, `export` only adds visibility.

- [ ] **Step 2: Create `components/charts/sla-gauge-chart.tsx`**

```tsx
'use client';

/**
 * SlaGaugeChart — median minutes from report to dispatch over the window,
 * against a target.
 *
 * The target is NOT a flat number. It's DISPATCH_TARGET_MINUTES (the
 * existing per-severity policy in incident-vocabulary.ts: critical 5 / high
 * 10 / medium 30 / low 60, default 5 for untriaged — the same table
 * urgencyTimeColor() already uses to color a single incident's age
 * elsewhere on this console) weighted by the actual severity mix of
 * incidents DISPATCHED in this window. A flat "5 minutes" target would
 * misread as failing on a day that was mostly low-severity reports.
 *
 * Needle color bands reuse the same three-state logic and the same
 * DUE_SOON_FRACTION threshold urgencyTimeColor() uses for a single incident
 * — green under target, amber within DUE_SOON_FRACTION of it, red at or past
 * it — so a dispatcher who already reads that color rule elsewhere on the
 * console doesn't have to learn a second one here.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { readToken } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';
import {
  DISPATCH_TARGET_MINUTES, DEFAULT_TARGET_MINUTES, DUE_SOON_FRACTION,
} from '@/components/incidents/incident-vocabulary';
import type { ActivityIncident } from '@/lib/api/dispatch';

const ms = (iso: string | null): number | null => (iso ? new Date(iso).getTime() : null);

function humanise(mins: number): string {
  if (mins < 1) return '<1m';
  if (mins < 60) return `${Math.round(mins)}m`;
  return `${(mins / 60).toFixed(1)}h`;
}

/**
 * Median dispatch gap and the severity-weighted target, over the window.
 * Dated by DISPATCH (same rule dispatchLatency() in queue-series.ts uses):
 * an incident that arrived last night and was dispatched this morning is
 * this morning's work.
 */
function computeGauge(incidents: ActivityIncident[], days: number) {
  const since = Date.now() - days * 86_400_000;
  const dispatchedInWindow = incidents.filter(inc => {
    const d = ms(inc.dispatched_at);
    return d !== null && d >= since;
  });

  const gaps = dispatchedInWindow
    .map(inc => {
      const c = ms(inc.created_at);
      const d = ms(inc.dispatched_at);
      return c !== null && d !== null ? (d - c) / 60000 : null;
    })
    .filter((n): n is number => n !== null && n >= 0)
    .sort((a, b) => a - b);

  let medianMinutes: number | null = null;
  if (gaps.length) {
    const mid = Math.floor(gaps.length / 2);
    medianMinutes = gaps.length % 2 === 0 ? (gaps[mid - 1] + gaps[mid]) / 2 : gaps[mid];
  }

  let targetMinutes: number | null = null;
  if (dispatchedInWindow.length > 0) {
    const weighted = dispatchedInWindow.reduce((sum, inc) => {
      const t = inc.severity ? (DISPATCH_TARGET_MINUTES[inc.severity] ?? DEFAULT_TARGET_MINUTES) : DEFAULT_TARGET_MINUTES;
      return sum + t;
    }, 0);
    targetMinutes = weighted / dispatchedInWindow.length;
  }

  return { medianMinutes, targetMinutes, dispatchedCount: dispatchedInWindow.length };
}

export function SlaGaugeChart({ incidents, days }: { incidents: ActivityIncident[]; days: number }) {
  const { theme } = useTheme();
  const { medianMinutes, targetMinutes, dispatchedCount } = useMemo(
    () => computeGauge(incidents, days),
    [incidents, days],
  );

  const option = useMemo(() => {
    if (typeof window === 'undefined' || medianMinutes === null || targetMinutes === null) return {};
    const success = readToken('--color-system-success');
    const warning = readToken('--color-system-warning');
    const critical = readToken('--color-severity-critical');
    const textMuted = readToken('--color-text-muted');
    const textPrimary = readToken('--color-text-primary');

    // Same three-state read as urgencyTimeColor(): under the due-soon band
    // is green, inside it is amber, at or past target is red.
    const dueSoonAt = targetMinutes * (1 - DUE_SOON_FRACTION);
    const needleColor = medianMinutes >= targetMinutes ? critical : medianMinutes >= dueSoonAt ? warning : success;

    // At least 1.5x the larger of median/target, rounded up to the nearest
    // 5, so the needle never pins at the gauge's max and the target band
    // stays visible even on a very fast day.
    const max = Math.max(10, Math.ceil((Math.max(medianMinutes, targetMinutes) * 1.5) / 5) * 5);

    return {
      series: [
        {
          type: 'gauge',
          min: 0,
          max,
          radius: '90%',
          progress: { show: true, width: 14, itemStyle: { color: needleColor } },
          axisLine: { lineStyle: { width: 14, color: [[1, readToken('--color-surface-raised')]] } },
          pointer: { itemStyle: { color: needleColor } },
          axisTick: { show: false },
          splitLine: { length: 10, lineStyle: { color: textMuted } },
          axisLabel: { color: textMuted, fontSize: 10, distance: 18 },
          anchor: { show: true, itemStyle: { color: needleColor } },
          detail: {
            valueAnimation: true,
            formatter: () => humanise(medianMinutes),
            color: textPrimary,
            fontSize: 22,
            fontWeight: 700,
            offsetCenter: [0, '65%'],
          },
          data: [{ value: Math.round(medianMinutes * 10) / 10 }],
        },
      ],
    };
  }, [medianMinutes, targetMinutes, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>Time-to-dispatch SLA</CardTitle>
        <CardDescription>
          {dispatchedCount > 0 && targetMinutes !== null
            ? `Median vs. a ${humanise(targetMinutes)} severity-weighted target · ${dispatchedCount} dispatched in ${days} days`
            : `No dispatches in the last ${days} days`}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {medianMinutes === null ? (
          <p className="py-6 text-center text-sm text-muted-foreground">No dispatches in this window.</p>
        ) : (
          <ZirenChart className="w-full" height={220} option={option} />
        )}
      </CardContent>
    </Card>
  );
}
```

- [ ] **Step 3: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add components/incidents/incident-vocabulary.ts components/charts/sla-gauge-chart.tsx
git commit -m "feat(dashboard): add SLA gauge chart"
```

---

### Task 14: Wire the 3 new charts into the Overview page

**Files:**
- Modify: `ziren_dashboard/app/(dashboard)/overview/page.tsx`

**Interfaces:**
- Consumes: `IncidentHeatmapChart` + `heatmapBuckets` (Task 11), `ResponseFunnelChart` + `funnelCounts` (Task 12), `SlaGaugeChart` (Task 13), `fetchActivity` (existing, from `lib/api/dispatch.ts`).

- [ ] **Step 1: Add the 56-day heatmap fetch**

In `app/(dashboard)/overview/page.tsx`, add a new state slot near the existing `activity` state (find `const [activity, setActivity] = useState<ActivityIncident[]>([]);`):

```typescript
// A separate, longer window than `activity`'s 14 days — see
// IncidentHeatmapChart's comment for why 14 days is too thin to show a real
// weekly pattern. Loaded once per visit, like `platform` below, not on the
// 30s queue-refresh cadence: this shape does not meaningfully change within
// a single session.
const [heatmapActivity, setHeatmapActivity] = useState<ActivityIncident[]>([]);
const HEATMAP_DAYS = 56;
```

Add the fetch effect near the existing `platform` effect (find the `useEffect` that calls `fetchPlatformCounts`):

```typescript
useEffect(() => {
  if (!token) return;
  let cancelled = false;
  fetchActivity(token, HEATMAP_DAYS)
    .then(rows => { if (!cancelled) setHeatmapActivity(rows); })
    .catch(() => {});
  return () => { cancelled = true; };
}, [token]);
```

- [ ] **Step 2: Derive the funnel and heatmap data**

Near the existing `const categories = categoryMix(activity, TREND_DAYS);` line, add:

```typescript
const heatmapRows = heatmapBuckets(heatmapActivity, HEATMAP_DAYS);
const funnel = funnelCounts(activity, TREND_DAYS);
```

- [ ] **Step 3: Update the imports**

At the top of the file, extend the existing `lib/charts/queue-series` import:

```typescript
import {
  volumePoints,
  severityDays,
  categoryMix,
  dispatchLatency,
  heatmapBuckets,
  funnelCounts,
} from '@/lib/charts/queue-series';
```

Add three new chart imports below the existing chart imports:

```typescript
import { IncidentHeatmapChart } from '@/components/charts/incident-heatmap-chart';
import { ResponseFunnelChart } from '@/components/charts/response-funnel-chart';
import { SlaGaugeChart } from '@/components/charts/sla-gauge-chart';
```

- [ ] **Step 4: Add the three charts to the chart deck grid**

Find the chart deck grid (the `<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">` that currently renders `IncidentVolumeChart` through `CategoryMixChart`) and add the three new charts after `CategoryMixChart`:

```tsx
<CategoryMixChart
  days={TREND_DAYS}
  ranked={categories.ranked}
  total={categories.total}
  unclassified={categories.unclassified}
/>
<ResponseFunnelChart counts={funnel} days={TREND_DAYS} />
<SlaGaugeChart days={TREND_DAYS} incidents={activity} />
<IncidentHeatmapChart data={heatmapRows} days={HEATMAP_DAYS} />
```

- [ ] **Step 5: Type-check**

Run: `npx tsc --noEmit -p .`
Expected: no errors.

- [ ] **Step 6: Visual check**

Open Overview as a Provincial Admin and confirm all three new cards render below the existing five: the funnel shows Received/Dispatched/Resolved narrowing left to right (or top to bottom per the layout above) with the right counts, the SLA gauge needle sits at the correct color band for the current median-vs-target relationship, and the heatmap shows a 7×24 grid with visibly darker cells at whatever hours the mock/real data concentrates reports. Confirm the whole deck still looks correct after a 30-second refresh (the funnel and gauge update; the heatmap does not, since it's on its own longer-lived fetch).

- [ ] **Step 7: Commit**

```bash
git add "app/(dashboard)/overview/page.tsx"
git commit -m "feat(dashboard): add heatmap, funnel, and SLA gauge to Overview"
```

---

### Task 15: Final verification pass

**Files:** none (verification only)

- [ ] **Step 1: Confirm no chart component still imports Recharts**

Run: `grep -rn "from 'recharts'" ziren_dashboard/components/charts/`
Expected: no output. (The four unrelated `components/efferd/*-chart.tsx` files are untouched and still import Recharts — that's correct and expected; this check is scoped to `components/charts/` only.)

- [ ] **Step 2: Full type-check**

Run: `npx tsc --noEmit -p .` from `ziren_dashboard/`
Expected: no errors.

- [ ] **Step 3: Full visual pass, both pages, both themes**

Using the `ziren-dev` skill: start the dashboard, sign in as a Provincial Admin, and check the Overview page in both light and dark theme — every chart renders with correct colors, hover tooltips work, the range Select and dataZoom scroll-zoom work on the three time-series charts, and the crosshair sync (`group="overview"`) is visible when hovering one time-series chart and seeing the same x-position highlighted on the others. Then switch to the Analytics page (Incidents tab) and confirm the trend chart and all four category bar charts render correctly in both themes, and the day/month/year period Select still works.

- [ ] **Step 4: Confirm `package.json` didn't pick up unrelated changes**

Run: `git diff package.json`
Expected: only the `echarts`/`echarts-for-react` additions from Task 1 — no accidental version bumps to unrelated dependencies from `npm install`.
