'use client';

/**
 * CategoryMixChart — which kinds of emergency this province actually gets.
 *
 * PIE, by explicit request. The five real wizard categories, each a fixed
 * slice from CATEGORY_PALETTE — a small qualitative set chosen from the
 * violet–magenta range specifically because it does NOT touch the locked
 * severity scale (red/orange/yellow/green) or the locked agency scale
 * (BFP red / PNP sky-blue / MDRRMO emerald). A category slice must never be
 * mistaken for a severity or an agency, which is why this palette exists
 * separately from either.
 *
 * `other`/null is STILL held apart, unchanged from the ranked-bar version
 * this replaces: it is not a sixth kind of emergency, it means the
 * resident skipped the wizard's category step (migration 019 also rewrote
 * the retired hazmat/missing_person rows into it). It is never a pie
 * slice — folding it in would let a "not an answer" bucket compete for
 * visual share against five real answers — and sits below the chart as a
 * coverage note instead, which is what it actually is.
 *
 * Counts come from /dispatch/activity, so a fire resolved yesterday still
 * counts as a fire this province had.
 */

import { useMemo } from 'react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Fig } from '@/components/ui/fig';
import { ZirenChart } from './echart';
import { CATEGORY_PALETTE, readToken, withAlpha } from '@/lib/charts/echarts-theme';
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

  const rows = ranked
    .filter(r => r.count > 0)
    .map((r, i) => ({
      ...r,
      pct: classified > 0 ? Math.round((r.count / classified) * 100) : 0,
      color: CATEGORY_PALETTE[i % CATEGORY_PALETTE.length],
    }));

  const option = useMemo(() => {
    if (typeof window === 'undefined') return {};
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
          `<div style="font-weight:600">${p.name}</div>${p.value} report${p.value === 1 ? '' : 's'} · ${p.percent}%`,
      },
      legend: {
        orient: 'vertical',
        right: 4,
        top: 'center',
        icon: 'circle',
        itemWidth: 8,
        itemHeight: 8,
        itemGap: 12,
        textStyle: { color: textMuted, fontSize: 12 },
        formatter: (name: string) => {
          const row = rows.find(r => r.label === name);
          return row ? `${name}  ${row.pct}%` : name;
        },
      },
      series: [
        {
          type: 'pie',
          radius: ['46%', '78%'],
          center: ['32%', '50%'],
          avoidLabelOverlap: false,
          data: rows.map(r => ({
            name: r.label,
            value: r.count,
            itemStyle: {
              color: r.color,
              shadowColor: withAlpha(r.color, 0.35),
              shadowBlur: 8,
            },
          })),
          label: { show: false },
          labelLine: { show: false },
          itemStyle: { borderColor: cardBg, borderWidth: 3, borderRadius: 8 },
          emphasis: {
            scale: true,
            scaleSize: 6,
            label: {
              show: true,
              formatter: (p: { name: string; percent: number }) => `${p.name}\n${p.percent}%`,
              fontWeight: 600,
              color: textPrimary,
            },
          },
          animationType: 'scale',
          animationEasing: 'elasticOut',
          animationDelay: (idx: number) => idx * 80,
        },
      ],
    };
    // theme re-runs readToken(), which reads CSS variables at call time.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, theme]);

  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>What kind of emergency</CardTitle>
        <CardDescription>
          All reports in the last {days} days, resolved ones included
        </CardDescription>
      </CardHeader>
      <CardContent>
        {total === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            No reports in this window.
          </p>
        ) : rows.length === 0 ? (
          // total > 0 but every real category is at zero — every report in
          // the window is unclassified. A pie with an empty data array
          // still draws its track (a bare ring, no slices, no legend),
          // which reads as broken rather than as "nothing to categorise
          // yet" — this message is the honest version of that state.
          <p className="py-6 text-center text-sm text-muted-foreground">
            Every report in this window is unclassified — nothing to chart yet.
          </p>
        ) : (
          <>
            <ZirenChart className="aspect-video w-full" height={220} option={option} />

            {/* Below the chart, deliberately — see the header comment for
                why this is not a slice. */}
            {unclassified > 0 && (
              <p
                className="mt-3 border-t pt-2.5 text-meta"
                style={{
                  borderColor: 'var(--color-surface-border)',
                  color: 'var(--color-text-muted)',
                }}
              >
                <Fig className="text-meta font-semibold">{unclassified}</Fig>{' '}
                {unclassified === 1 ? 'report' : 'reports'} unclassified — the
                reporter skipped the category step, or the report predates the
                current category set. Not a category of its own, so it is not
                a slice above.
              </p>
            )}
          </>
        )}
      </CardContent>
    </Card>
  );
}
