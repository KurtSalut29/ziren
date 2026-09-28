'use client';

/**
 * AgencyShareChart — the active queue split by responding agency.
 *
 * Donut, not a plain pie — rounded segment gap via itemStyle.borderWidth,
 * share percentage printed inside each segment, a legend underneath, and a
 * center label giving the raw total so the percentages have a number to
 * anchor to.
 *
 * The hues are NOT a generic ramp. Agency colour is fixed on this product —
 * BFP coral-red, PNP sky-blue, MDRRMO emerald — and it identifies a
 * real-world organisation a dispatcher recognises on sight. Binding a
 * segment to a ramp position would repaint an agency whenever another one
 * drops out of the queue, which is the exact failure the "colour follows
 * the entity, never its rank" rule exists to stop.
 *
 * Below five open incidents the donut is suppressed for a sentence instead:
 * "2 of 3" drawn as 67% invites a reader to see a trend in what is one
 * incident either way.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Fig } from '@/components/ui/fig';
import { ZirenChart } from './echart';
import { agencyColors, readToken, withAlpha } from '@/lib/charts/echarts-theme';
import { useTheme } from '@/lib/theme/use-theme';

export interface AgencySlice {
  agency: 'BFP' | 'PNP' | 'MDRRMO';
  active: number;
}

/** Below this the shape says more than the numbers support. */
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
    const textPrimary = readToken('--color-text-primary');
    return {
      tooltip: {
        trigger: 'item',
        backgroundColor: cardBg,
        borderColor: readToken('--color-surface-border'),
        borderWidth: 1,
        borderRadius: 10,
        padding: [10, 12],
        textStyle: { color: textPrimary, fontSize: 12.5 },
        extraCssText: 'box-shadow: 0 8px 24px rgba(0,0,0,0.14);',
        formatter: (p: { name: string; value: number; percent: number }) =>
          `<div style="font-weight:600">${p.name}</div>${p.value} active · ${p.percent}%`,
      },
      legend: {
        bottom: 0,
        icon: 'circle',
        itemWidth: 8,
        itemHeight: 8,
        itemGap: 16,
        textStyle: { color: textMuted, fontSize: 12 },
      },
      series: [
        {
          type: 'pie',
          radius: ['58%', '82%'],
          center: ['50%', '44%'],
          avoidLabelOverlap: false,
          data: rows.map(r => ({
            name: r.agency,
            value: r.active,
            itemStyle: {
              color: colors[r.agency],
              shadowColor: withAlpha(colors[r.agency], 0.35),
              shadowBlur: 10,
            },
            label: {
              show: true,
              position: 'inside',
              formatter: () => `${r.share}%`,
              color: cardBg,
              fontWeight: 600,
              fontSize: 13,
            },
          })),
          itemStyle: { borderColor: cardBg, borderWidth: 4, borderRadius: 10 },
          labelLine: { show: false },
          emphasis: {
            scale: true,
            scaleSize: 6,
            itemStyle: { shadowBlur: 16 },
          },
          animationType: 'scale',
          animationEasing: 'cubicOut',
          animationDuration: 700,
        },
      ],
    };
    // theme re-runs readToken(), which reads CSS variables at call time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
          <div className="relative mx-auto aspect-square max-h-72 w-full">
            <ZirenChart className="h-full w-full" group="overview" option={option} />
            {/* Center readout — the donut's hole is otherwise empty space;
                this gives the percentages inside each segment a total to
                anchor to without adding a competing label on the ring
                itself. */}
            <div
              className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center"
              style={{ paddingBottom: '14%' }}
            >
              <Fig className="text-[26px] font-bold leading-none" tone="var(--color-text-primary)">
                {total}
              </Fig>
              <span className="mt-0.5 text-[11px] text-muted-foreground">active</span>
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
