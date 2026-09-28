'use client';

/**
 * IncidentVolumeChart — arrivals per day, on the Overview chart deck.
 *
 * Gradient line-area on ECharts (canvas, not SVG) — a range Select (7/14/30
 * days), a delta badge, and a synced crosshair with
 * every other time-series chart on the page (see the `group` prop on
 * ZirenChart). `smoothMonotone: 'x'` is the shape-preserving spline: plain
 * `smooth: true` can overshoot past a data point, which on daily arrival
 * counts this small (0–4 some days) drew arrivals that never happened,
 * including negative ones.
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
import { baseEChartsOption, readToken, withAlpha } from '@/lib/charts/echarts-theme';
import { DeltaBadge } from './delta-badge';
import { useTheme } from '@/lib/theme/use-theme';

export interface VolumePoint {
  /** ISO date, midnight. */
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

  /**
   * Change across the window, as a percentage of where it started.
   *
   * Compares the first and last THIRD rather than the endpoint pair: on a
   * provincial queue a single quiet Sunday at either end would otherwise
   * swing the headline number by triple digits and say nothing about the
   * trend.
   */
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
    const base = baseEChartsOption();
    return {
      ...base,
      xAxis: {
        type: 'category',
        data: rows.map(r => r.date),
        boundaryGap: false,
        axisLine: { lineStyle: { color: readToken('--color-surface-border') } },
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
        splitLine: { lineStyle: { color: readToken('--color-surface-border'), type: 'dashed' } },
        axisLabel: { color: readToken('--color-text-muted') },
      },
      tooltip: {
        ...base.tooltip,
        trigger: 'axis',
        axisPointer: { type: 'line', lineStyle: { color: readToken('--color-surface-border') } },
        formatter: (params: { value: number; axisValue: string }[]) => {
          const p = params[0];
          const label = new Date(p.axisValue).toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          });
          return `<div style="font-weight:600;margin-bottom:4px">${label}</div>${p.value} report${p.value === 1 ? '' : 's'}`;
        },
      },
      series: [
        {
          type: 'line',
          data: rows.map(r => r.received),
          smooth: true,
          smoothMonotone: 'x',
          symbol: 'circle',
          symbolSize: 6,
          showSymbol: false,
          emphasis: { focus: 'series', itemStyle: { borderWidth: 2, borderColor: brand } },
          lineStyle: { color: brand, width: 2.5, shadowColor: withAlpha(brand, 0.35), shadowBlur: 8, shadowOffsetY: 4 },
          itemStyle: { color: brand, borderColor: readToken('--color-surface-card'), borderWidth: 2 },
          areaStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: withAlpha(brand, 0.5) },
                { offset: 0.55, color: withAlpha(brand, 0.14) },
                { offset: 1, color: withAlpha(brand, 0) },
              ],
            },
          },
        },
      ],
    };
    // theme is a dependency so colors are re-read from the DOM after a
    // light/dark flip, giving the option a new identity ECharts re-renders.
    // theme re-runs readToken(), which reads CSS variables at call time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2 lg:col-span-3">
      <CardHeader className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex flex-col gap-1.5">
          <div className="flex items-center gap-2">
            <CardTitle>Reports received per day</CardTitle>
            {/* riseIsBad: more emergencies arriving is not good news, so an
                upward trend must not read as green on this product. */}
            <DeltaBadge riseIsBad value={growthPct} suffix="%" />
          </div>
          <CardDescription>
            {total === 0 ? `No reports in the last ${periodDays} days` : `${total} over ${periodDays} days · today is still filling`}
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
        <ZirenChart
          className="aspect-22/8 w-full"
          empty={total === 0 ? `No reports in the last ${periodDays} days` : undefined}
          group="overview"
          option={option}
        />
      </CardContent>
    </Card>
  );
}
