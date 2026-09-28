'use client';

/**
 * IncidentTrendChart — incidents over time, as a gradient area instead of
 * the flat CSS-width bars the rest of System Analytics still used before
 * this. Same visual language as IncidentVolumeChart (Overview's own arrivals
 * chart) — gradient fill, borderless axes, line-indicator tooltip — but
 * built for THIS page's own day/month/year period selector instead of
 * carrying a second, competing range picker of its own.
 */

import { useId } from 'react';
import { Area, AreaChart, CartesianGrid, XAxis, YAxis } from 'recharts';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import {
  type ChartConfig, ChartContainer, ChartTooltip, ChartTooltipContent,
} from '@/components/efferd/ui/chart';

export interface TrendPoint {
  bucket: string;
  count: number;
}

const chartConfig = {
  count: { label: 'Incidents', color: 'var(--color-brand)' },
} satisfies ChartConfig;

/** 'YYYY-MM-DD' / 'YYYY-MM' / 'YYYY' (see analytics_service.py's _bucket_key) into something readable. */
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
  const gradientId = useId();
  const total = data.reduce((a, d) => a + d.count, 0);

  return (
    <Card className="col-span-1 lg:col-span-2">
      <CardHeader className="gap-1">
        <CardTitle className="text-[15px]">Incidents over time</CardTitle>
        <CardDescription>{total} total, by {period}</CardDescription>
      </CardHeader>
      <CardContent>
        <ChartContainer className="aspect-21/9 w-full" config={chartConfig}>
          <AreaChart data={data} margin={{ left: 4, right: 8, top: 8, bottom: 0 }}>
            <defs>
              <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" stopColor="var(--color-count)" stopOpacity={0.45} />
                <stop offset="55%" stopColor="var(--color-count)" stopOpacity={0.12} />
                <stop offset="100%" stopColor="var(--color-count)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid className="stroke-border" strokeDasharray="3 3" vertical={false} />
            <XAxis
              axisLine={false}
              dataKey="bucket"
              minTickGap={16}
              tickFormatter={v => formatBucket(String(v), period)}
              tickLine={false}
              tickMargin={8}
            />
            <YAxis
              allowDecimals={false}
              axisLine={false}
              tickLine={false}
              tickMargin={8}
              width={30}
            />
            <ChartTooltip
              content={
                <ChartTooltipContent
                  indicator="line"
                  labelFormatter={(_, payload) => {
                    const row = payload?.[0]?.payload as TrendPoint | undefined;
                    return row ? formatBucket(row.bucket, period) : '';
                  }}
                />
              }
              cursor={false}
            />
            <Area
              animationDuration={1000}
              animationEasing="ease-out"
              dataKey="count"
              dot={{ r: 3, fill: 'var(--color-count)', strokeWidth: 0 }}
              fill={`url(#${gradientId})`}
              stroke="var(--color-count)"
              strokeWidth={2}
              type="monotone"
            />
          </AreaChart>
        </ChartContainer>
      </CardContent>
    </Card>
  );
}
