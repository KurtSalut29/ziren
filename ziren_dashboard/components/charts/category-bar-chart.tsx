'use client';

/**
 * CategoryBarChart — one label, one count, animated horizontal bars.
 *
 * Replaces the plain CSS-width BarList that used to draw every "by X"
 * breakdown on System Analytics (by type, by agency, by municipality, by
 * severity) — same job, same colorByLabel escape hatch for a fixed palette
 * (agency/severity hues), but an actual chart: axes, a tooltip, and bars
 * that grow in on load instead of just appearing at full width.
 */

import { Bar, BarChart, Cell, LabelList, XAxis, YAxis } from 'recharts';
import {
  type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent,
} from '@/components/efferd/ui/chart';

const chartConfig = { count: { label: 'Count' } } satisfies ChartConfig;

export function CategoryBarChart({
  entries,
  color,
  colorByLabel,
}: {
  entries: [string, number][];
  color: string;
  /** Resolves each row's own colour by its raw label (e.g. locked agency/severity hues) instead of one flat colour for every row. */
  colorByLabel?: Record<string, string>;
}) {
  if (entries.length === 0) {
    return <p className="py-6 text-center text-meta text-muted-foreground">No data yet.</p>;
  }

  const rows = entries.map(([label, count]) => ({
    label: label.replace(/_/g, ' '),
    count,
    fill: colorByLabel?.[label] ?? color,
  }));
  const height = Math.max(120, rows.length * 32);

  return (
    <ChartContainer className="w-full" config={chartConfig} style={{ height }}>
      <BarChart data={rows} layout="vertical" margin={{ left: 4, right: 20, top: 4, bottom: 4 }}>
        <XAxis allowDecimals={false} axisLine={false} hide type="number" />
        <YAxis
          axisLine={false}
          dataKey="label"
          tickLine={false}
          type="category"
          width={112}
        />
        <ChartTooltip content={<ChartTooltipContent hideLabel />} cursor={{ fill: 'var(--color-surface-raised)' }} />
        <Bar
          animationDuration={800}
          animationEasing="ease-out"
          background={{ fill: 'var(--color-surface-raised)', radius: 4 }}
          dataKey="count"
          radius={[0, 4, 4, 0]}
        >
          {rows.map((r, i) => (
            <Cell fill={r.fill} key={i} />
          ))}
          <LabelList
            className="fill-foreground"
            dataKey="count"
            fontSize={12}
            fontWeight={600}
            offset={8}
            position="right"
          />
        </Bar>
      </BarChart>
    </ChartContainer>
  );
}
