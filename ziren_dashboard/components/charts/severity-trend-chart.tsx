'use client';

/**
 * SeverityTrendChart — arrivals per day split by severity, stacked columns.
 *
 * Severity hues are the locked four-tier scale, stacked in escalating order
 * so critical always sits on top — the position a scanning eye reaches
 * first — and never gets re-ordered by which tier happens to be largest
 * that week. The hand-rolled legend below the chart (rather than ECharts'
 * own <legend>) exists for the same reason it did before: severity is an
 * ORDERED scale a dispatcher reads as a ladder, and any auto-generated
 * legend sorts alphabetically, destroying that order.
 *
 * "Professional" here means restraint, not decoration: rounded caps only on
 * the outward-facing edge of each stack, a soft card-colour gap between
 * tiers so adjacent similar-luminance segments don't visually merge, a
 * shared crosshair with the other Overview time-series charts, and one
 * tooltip that breaks down all four tiers for the hovered day instead of
 * just the segment under the cursor.
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

/** Escalating order — this is also the stack order, bottom to top. */
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
    const base = baseEChartsOption();
    return {
      ...base,
      xAxis: {
        type: 'category',
        data: data.map(d => d.date),
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
        axisPointer: { type: 'shadow' },
        formatter: (params: { axisValue: string; seriesName: string; value: number; color: string }[]) => {
          const label = new Date(params[0].axisValue).toLocaleDateString(undefined, {
            weekday: 'long', month: 'long', day: 'numeric',
          });
          const total = params.reduce((a, p) => a + p.value, 0);
          const rows = [...params].reverse().map(p => `
            <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:3px">
              <span style="display:flex;align-items:center;gap:6px">
                <span style="display:inline-block;width:8px;height:8px;border-radius:2px;background:${p.color}"></span>
                ${p.seriesName}
              </span>
              <span style="font-weight:600">${p.value}</span>
            </div>`).join('');
          return `<div style="font-weight:600">${label}</div><div style="margin-top:2px;opacity:0.7">${total} total</div>${rows}`;
        },
      },
      series: TIERS.map((tier, i) => ({
        name: TIER_LABEL[tier],
        type: 'bar',
        stack: 'severity',
        data: data.map(d => d[tier]),
        barMaxWidth: 22,
        itemStyle: {
          color: colors[tier],
          borderColor: cardBg,
          borderWidth: 1,
          borderRadius: i === TIERS.length - 1 ? [5, 5, 0, 0] : 0,
        },
        emphasis: { itemStyle: { opacity: 0.85 } },
        animationDuration: 600,
        animationEasing: 'cubicOut',
      })),
    };
    // theme re-runs readToken(), which reads CSS variables at call time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>Severity mix over time</CardTitle>
        <CardDescription>Reports by the severity they were triaged at, per day</CardDescription>
      </CardHeader>
      <CardContent>
        <ZirenChart
          className="aspect-22/9 w-full"
          empty={
            data.every(d => TIERS.every(t => d[t] === 0))
              ? 'No reports in this period'
              : undefined
          }
          group="overview"
          option={option}
        />
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
