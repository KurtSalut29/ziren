'use client';

import { useEffect, useRef } from 'react';
import * as echarts from 'echarts/core';
import { LineChart, BarChart, PieChart } from 'echarts/charts';
import {
  GridComponent,
  TooltipComponent,
  LegendComponent,
  MarkLineComponent,
  TitleComponent,
} from 'echarts/components';
import { CanvasRenderer } from 'echarts/renderers';
import ReactEChartsCore from 'echarts-for-react/lib/core';

echarts.use([
  LineChart, BarChart, PieChart,
  GridComponent, TooltipComponent, LegendComponent,
  MarkLineComponent, TitleComponent, CanvasRenderer,
]);

export interface ZirenChartProps {
  option: Record<string, unknown>;
  /**
   * Charts sharing a group id get a synced crosshair/tooltip: hovering a
   * point on one highlights the same x-position on every other chart in the
   * group. Only meaningful between charts that share an x-axis (the
   * time-series charts on Overview) — a pie in the same group still joins
   * for tooltip-trigger consistency but has no axis to sync against.
   */
  group?: string;
  className?: string;
  height?: number | string;
  /**
   * When set, the plot area is covered by this message instead of drawing
   * bare axes. An empty chart is not an error, but a card of gridlines with
   * nothing on them reads as one — "did it fail to load?" — and the honest
   * answer ("no reports in this window") is one sentence.
   */
  empty?: string;
}

/**
 * The ECharts equivalent of the old Recharts-based `efferd/ui/chart.tsx`.
 * Every real chart on the dashboard renders through this; nothing should
 * import `echarts-for-react`'s default export or raw `<ReactECharts>`
 * directly, so every chart shares one resize strategy and one group-sync
 * mechanism.
 *
 * Registers only the chart types this dashboard actually uses (line, bar,
 * pie), tree-shaken via `echarts/core` — pulling in the default `echarts`
 * entry point would ship every chart type ECharts has (candlestick,
 * sankey, tree, graph, map, …), none of which this dashboard needs.
 */
export function ZirenChart({ option, group, className, height = '100%', empty }: ZirenChartProps) {
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
    <div className={`relative ${className ?? ''}`} ref={containerRef} style={{ height }}>
      {empty && (
        <p
          className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center px-6 text-center text-meta"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <span className="rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-1.5">
            {empty}
          </span>
        </p>
      )}
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
