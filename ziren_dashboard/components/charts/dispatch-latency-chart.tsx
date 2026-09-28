'use client';

/**
 * DispatchLatencyChart — median minutes from report to dispatch, per day.
 *
 * Bars, not a line — this is the metric the Overview was missing. Every
 * other card says how MUCH work there is; none said how fast it is being
 * cleared. Bars read as discrete daily performance more readily than a
 * line does, and the dashed reference line marks the window's own overall
 * median so a reader can see at a glance which days ran faster or slower
 * than the province's typical pace — WITHOUT inventing an external target.
 * A flat "5 minutes" band would misread as failing on a day that was
 * mostly low-severity reports, since the per-severity dispatch targets
 * (DISPATCH_TARGET_MINUTES in incident-vocabulary.ts) aren't known per day
 * from this data shape — the median-of-the-window is a real number this
 * data actually supports, not a guess.
 *
 * MEDIAN, not mean — see dispatchLatency() for why one stalled report would
 * otherwise wreck the series. Days with no dispatches are OMITTED bars, not
 * zero-height ones: nothing happened is not the same as instant response,
 * and a zero would plot as the best day on the chart.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { ZirenChart } from './echart';
import { baseEChartsOption, readToken, withAlpha } from '@/lib/charts/echarts-theme';
import { DeltaBadge } from './delta-badge';
import { useTheme } from '@/lib/theme/use-theme';

export interface LatencyPoint {
  date: string;
  minutes: number | null;
  dispatched: number;
}

/** Minutes into something a person reads without doing arithmetic. */
function humanise(mins: number): string {
  if (mins < 1) return '<1m';
  if (mins < 60) return `${Math.round(mins)}m`;
  const h = mins / 60;
  if (h < 24) return h < 10 ? `${h.toFixed(1)}h` : `${Math.round(h)}h`;
  return `${Math.round(h / 24)}d`;
}

export function DispatchLatencyChart({
  data,
  days,
}: {
  data: LatencyPoint[];
  days: number;
}) {
  const { theme } = useTheme();
  const withValues = data.filter(d => d.minutes !== null);

  // First half against second half. Endpoint-to-endpoint would compare two
  // single days, and on this volume a day is often one incident.
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
    const textMuted = readToken('--color-text-muted');
    const base = baseEChartsOption();
    return {
      ...base,
      xAxis: {
        type: 'category',
        data: data.map(d => d.date),
        axisLine: { lineStyle: { color: readToken('--color-surface-border') } },
        axisTick: { show: false },
        axisLabel: {
          color: textMuted,
          formatter: (v: string) =>
            new Date(v).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }),
        },
      },
      yAxis: {
        type: 'value',
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: readToken('--color-surface-border'), type: 'dashed' } },
        axisLabel: {
          color: textMuted,
          formatter: (v: number) => (v === 0 ? '0' : humanise(v)),
        },
      },
      tooltip: {
        ...base.tooltip,
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        formatter: (params: { axisValue: string; data: number | null }[]) => {
          const p = params[0];
          const label = new Date(p.axisValue).toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          });
          if (p.data === null || p.data === undefined) {
            return `<div style="font-weight:600;margin-bottom:2px">${label}</div>No dispatches`;
          }
          const row = data.find(d => d.date === p.axisValue);
          return `<div style="font-weight:600;margin-bottom:2px">${label}</div>${humanise(p.data)} · ${row?.dispatched ?? 0} dispatched`;
        },
      },
      series: [
        {
          type: 'bar',
          data: data.map(d => d.minutes),
          barMaxWidth: 22,
          itemStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: brand },
                { offset: 1, color: withAlpha(brand, 0.55) },
              ],
            },
            borderRadius: [4, 4, 0, 0],
          },
          emphasis: { itemStyle: { color: brand } },
          label: {
            show: true,
            position: 'top',
            color: textMuted,
            fontSize: 11,
            formatter: (p: { value: number | null }) =>
              p.value === null || p.value === undefined ? '' : humanise(p.value),
          },
          // The window's own median, not an invented external target — see
          // the header comment for why. Dashed so it reads as a reference,
          // not a fifth day's data.
          markLine: overall === null ? undefined : {
            silent: true,
            symbol: 'none',
            lineStyle: { color: textMuted, type: 'dashed', width: 1.5 },
            label: {
              position: 'insideEndTop',
              color: textMuted,
              fontSize: 11,
              formatter: () => `median ${humanise(overall)}`,
            },
            data: [{ yAxis: overall }],
          },
          animationDuration: 600,
          animationEasing: 'cubicOut',
        },
      ],
    };
    // theme re-runs readToken(), which reads CSS variables at call time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, overall, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle>Time to dispatch</CardTitle>
          {trendPct !== null && (
            // riseIsBad: a rising response time is the bad direction.
            <DeltaBadge riseIsBad suffix="%" value={trendPct} />
          )}
        </div>
        <CardDescription>
          {overall !== null
            ? `Median ${humanise(overall)} across ${totalDispatched} dispatches in ${days} days`
            : `No dispatches in the last ${days} days`}
        </CardDescription>
      </CardHeader>
      <CardContent>
        <ZirenChart
          className="aspect-22/9 w-full"
          empty={overall === null ? `No dispatches in the last ${days} days` : undefined}
          group="overview"
          option={option}
        />
      </CardContent>
    </Card>
  );
}
