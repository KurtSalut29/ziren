'use client';

/**
 * Charts for the Operational Area. ECharts for the two that are real axes (the
 * trend and the hour-of-day bars), plain CSS for the weekday × hour grid, where
 * a canvas would only add a tooltip the cell's own title already gives.
 *
 * The trend DOES use severity colour, on purpose: each segment's height is the
 * actual count of that severity that day (critical red, high orange, everything
 * else neutral) — a true, proportional figure, not a claim about the whole bar.
 * That is different from painting an entire day's bar red because it HAD a
 * critical report; here red is exactly as much of the bar as critical reports
 * are of that day's total, so the colour never overstates what happened. Same
 * SEV_COLOR tokens as every other severity chip in the console (see
 * incident-vocabulary.ts) — a reader who already knows red=critical elsewhere
 * doesn't have to learn a second colour language for this one chart.
 */

import { useMemo } from 'react';
import { ZirenChart } from '@/components/charts/echart';
import { baseEChartsOption, readToken, withAlpha } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';
import { SEV_COLOR } from '@/components/incidents/incident-vocabulary';
import type { TimePatterns, Trend } from '@/lib/api/operational-area';
import { cn } from '@/lib/utils';

const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const WEEKDAYS_LONG = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

export const weekdayLong = (i: number | null) => (i === null ? '—' : WEEKDAYS_LONG[i]);

/** 0 -> "12 AM", 13 -> "1 PM". */
export function hourLabel(h: number): string {
  const suffix = h < 12 ? 'AM' : 'PM';
  const hh = h % 12 === 0 ? 12 : h % 12;
  return `${hh} ${suffix}`;
}

function bucketLabel(bucket: string, unit: Trend['unit'], long = false): string {
  if (unit === 'month') {
    const [y, m] = bucket.split('-');
    return new Date(Number(y), Number(m) - 1, 1).toLocaleDateString('en-PH', { month: 'short', year: 'numeric' });
  }
  const d = new Date(`${bucket}T00:00:00`);
  const base = d.toLocaleDateString('en-PH', long ? { weekday: 'short', month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric' });
  return unit === 'week' ? `Week of ${base}` : base;
}

// ── Trend ────────────────────────────────────────────────────────────────

export function TrendChart({ trend, height = 260, fill = false }: { trend: Trend; height?: number; fill?: boolean }) {
  const { theme } = useTheme();
  const total = trend.points.reduce((a, p) => a + p.count, 0);

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const base = baseEChartsOption();
    const critical = readToken('--color-severity-critical');
    const high = readToken('--color-severity-high');
    const other = readToken('--color-text-tertiary');
    const border = readToken('--color-surface-border');
    const muted = readToken('--color-text-muted');
    const many = trend.points.length > 45;
    const barWidth = many ? 10 : 26;
    // A soft top-to-bottom sheen per segment rather than a flat fill — subtle
    // enough not to read as decoration, just enough to give each bar some
    // depth instead of a flat poster-color block.
    const sheen = (hex: string, top: number, bottom: number) => ({
      type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
      colorStops: [
        { offset: 0, color: withAlpha(hex, top) },
        { offset: 1, color: withAlpha(hex, bottom) },
      ],
    });
    // Critical sits on the shared baseline (the axis), high stacks directly on
    // top of it, other stacks last — a reader comparing critical counts across
    // days is comparing bars that all start from the same zero, which is the
    // one thing a stacked chart makes easy to read precisely; comparing the
    // topmost segment's size across bars is the one thing it makes hard, and
    // "other" is the segment nobody needs to eyeball that precisely.
    return {
      ...base,
      grid: { left: 4, right: 8, top: 16, bottom: 4, containLabel: true },
      xAxis: {
        type: 'category',
        data: trend.points.map(p => p.bucket),
        axisLine: { lineStyle: { color: border } },
        axisTick: { show: false },
        axisLabel: {
          color: muted,
          hideOverlap: true,
          formatter: (v: string) => bucketLabel(v, trend.unit).replace('Week of ', ''),
        },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: border, type: 'dashed' } },
        axisLabel: { color: muted },
      },
      tooltip: {
        ...base.tooltip,
        trigger: 'axis',
        axisPointer: { type: 'shadow', shadowStyle: { color: withAlpha(border, 0.35) } },
        formatter: (params: { axisValue: string; dataIndex: number }[]) => {
          const p = trend.points[params[0].dataIndex];
          const label = bucketLabel(p.bucket, trend.unit, true);
          const rest = p.count - p.critical - p.high;
          const line = (color: string, text: string) =>
            `<span style="display:inline-block;width:7px;height:7px;border-radius:50%;background:${color};margin-right:6px"></span>${text}`;
          return `<div style="font-weight:600;margin-bottom:5px">${label} · ${p.count} report${p.count === 1 ? '' : 's'}</div>` +
            `<div style="line-height:1.6">` +
            `${line(critical, `${p.critical} critical`)}<br/>` +
            `${line(high, `${p.high} high`)}<br/>` +
            `<span style="color:${muted}">${line(other, `${rest} other`)}</span>` +
            `</div>`;
        },
      },
      series: [
        {
          name: 'Critical',
          type: 'bar',
          stack: 'all',
          barMaxWidth: barWidth,
          barCategoryGap: '38%',
          data: trend.points.map(p => p.critical),
          itemStyle: { color: sheen(critical, 0.92, 1), borderRadius: [0, 0, 4, 4] },
          emphasis: { itemStyle: { color: sheen(critical, 1, 1) } },
        },
        {
          name: 'High',
          type: 'bar',
          stack: 'all',
          barMaxWidth: barWidth,
          data: trend.points.map(p => p.high),
          itemStyle: { color: sheen(high, 0.92, 1) },
          emphasis: { itemStyle: { color: sheen(high, 1, 1) } },
        },
        {
          name: 'Other',
          type: 'bar',
          stack: 'all',
          barMaxWidth: barWidth,
          data: trend.points.map(p => p.count - p.critical - p.high),
          itemStyle: { color: sheen(other, 0.28, 0.48), borderRadius: [4, 4, 0, 0] },
          emphasis: { itemStyle: { color: sheen(other, 0.4, 0.6) } },
        },
      ],
    };
    // theme: re-read the tokens after a light/dark flip.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [trend, theme]);

  if (total === 0) {
    return (
      <div className="flex h-full items-center justify-center text-[13px] text-muted-foreground" style={{ minHeight: height }}>
        No reports in this period.
      </div>
    );
  }
  return (
    <div className={fill ? 'flex h-full flex-col' : undefined}>
      {/* fill: take whatever height the panel has left, never less than `height`. */}
      <div className={fill ? 'flex-1' : undefined} style={fill ? { minHeight: height } : undefined}>
        <ZirenChart height={fill ? '100%' : height} option={option} />
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-[12px] font-medium text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: SEV_COLOR.critical }} />
          Critical
        </span>
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: SEV_COLOR.high }} />
          High
        </span>
        <span className="flex items-center gap-1.5">
          <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: 'var(--color-text-tertiary)', opacity: 0.5 }} />
          Everything else
        </span>
      </div>
    </div>
  );
}

// ── Hour of day ──────────────────────────────────────────────────────────

export function HourChart({ patterns, height = 200 }: { patterns: TimePatterns; height?: number }) {
  const { theme } = useTheme();
  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
    const base = baseEChartsOption();
    const border = readToken('--color-surface-border');
    const muted = readToken('--color-text-muted');
    const accent = readToken('--color-status-processing');
    const peak = patterns.peak_hour;
    return {
      ...base,
      grid: { left: 4, right: 8, top: 12, bottom: 4, containLabel: true },
      xAxis: {
        type: 'category',
        data: patterns.by_hour.map((_, h) => h),
        axisLine: { lineStyle: { color: border } },
        axisTick: { show: false },
        axisLabel: { color: muted, interval: 2, formatter: (v: string) => hourLabel(Number(v)) },
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        splitLine: { lineStyle: { color: border, type: 'dashed' } },
        axisLabel: { color: muted },
      },
      tooltip: {
        ...base.tooltip,
        trigger: 'axis',
        axisPointer: { type: 'shadow', shadowStyle: { color: withAlpha(border, 0.35) } },
        formatter: (params: { dataIndex: number }[]) => {
          const h = params[0].dataIndex;
          const n = patterns.by_hour[h];
          return `<div style="font-weight:600;margin-bottom:2px">${hourLabel(h)} – ${hourLabel((h + 1) % 24)}</div>${n} report${n === 1 ? '' : 's'}`;
        },
      },
      series: [{
        type: 'bar',
        barMaxWidth: 18,
        data: patterns.by_hour.map((n, h) => ({
          value: n,
          itemStyle: { color: h === peak ? accent : withAlpha(accent, 0.38), borderRadius: [3, 3, 0, 0] },
        })),
      }],
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [patterns, theme]);
  return <ZirenChart height={height} option={option} />;
}

// ── Weekday × hour grid ──────────────────────────────────────────────────

/**
 * Seven rows (Mon–Sun) by 24 columns of cells, shaded by how many reports
 * arrived in that hour on that weekday. Every cell has its count in its
 * title and aria-label, so the shade is never the only carrier of the number.
 */
export function HeatGrid({ patterns, compact = false }: { patterns: TimePatterns; compact?: boolean }) {
  const max = Math.max(1, ...patterns.heatmap.flat());
  return (
    <div className="overflow-x-auto">
      <div className={compact ? 'min-w-[400px]' : 'min-w-[560px]'}>
        <div className="grid items-center gap-[3px]" style={{ gridTemplateColumns: '36px repeat(24, minmax(0, 1fr))' }}>
          <span />
          {Array.from({ length: 24 }, (_, h) => (
            <span className="text-center text-[10px] text-muted-foreground" key={h}>
              {h % 3 === 0 ? (h % 12 === 0 ? 12 : h % 12) : ''}
            </span>
          ))}
          {patterns.heatmap.map((row, d) => (
            <div className="contents" key={d}>
              <span className="pr-1 text-right text-[11px] font-medium text-muted-foreground">{WEEKDAYS[d]}</span>
              {row.map((n, h) => {
                const level = n === 0 ? 0 : Math.max(0.16, n / max);
                return (
                  <span
                    aria-label={`${WEEKDAYS_LONG[d]} ${hourLabel(h)}: ${n} report${n === 1 ? '' : 's'}`}
                    className={cn('aspect-square rounded-[4px]', n === 0 && 'bg-[var(--color-surface-raised)]')}
                    key={h}
                    role="img"
                    style={n === 0 ? undefined : { backgroundColor: `color-mix(in srgb, var(--color-status-processing) ${Math.round(level * 100)}%, transparent)` }}
                    title={`${WEEKDAYS_LONG[d]} ${hourLabel(h)}: ${n} report${n === 1 ? '' : 's'}`}
                  />
                );
              })}
            </div>
          ))}
        </div>
        <div className="mt-2 flex items-center justify-between text-[11px] text-muted-foreground">
          <span>{compact ? 'Philippine time' : 'Hours are Philippine time. 12 = midnight and noon (AM then PM).'}</span>
          <span className="flex items-center gap-1.5">
            Fewer
            {[0.12, 0.35, 0.6, 0.85, 1].map(l => (
              <span
                aria-hidden="true"
                className="size-3 rounded-[3px]"
                key={l}
                style={{ backgroundColor: `color-mix(in srgb, var(--color-status-processing) ${Math.round(l * 100)}%, transparent)` }}
              />
            ))}
            More
          </span>
        </div>
      </div>
    </div>
  );
}
