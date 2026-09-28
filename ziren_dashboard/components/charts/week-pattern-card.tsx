'use client';

/**
 * WeekPatternCard — when reports arrive, by weekday and hour.
 *
 * The same grid the Operational Area's Response tab draws (HeatGrid), fed from
 * the activity feed so the dashboard needs no new endpoint. Ninety days, not the
 * fourteen every other card here uses: a weekday pattern needs several of each
 * weekday before it means anything, and two Mondays is an anecdote.
 *
 * One card for both admins, worded for what each does with it — an Agency Admin
 * is deciding who is on duty when; a Provincial Admin is reading the province's
 * rhythm. The figures are scoped server-side, so the wording is the only fork.
 */

import { Clock } from 'lucide-react';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { HeatGrid, hourLabel, weekdayLong } from '@/components/operational-area/charts';
import type { TimePatterns } from '@/lib/api/operational-area';

export function WeekPatternCard({
  patterns,
  days,
  isAgencyAdmin,
}: {
  patterns: TimePatterns;
  days: number;
  isAgencyAdmin: boolean;
}) {
  const empty = patterns.total === 0;
  return (
    <Card className="col-span-1 sm:col-span-2">
      <CardHeader className="space-y-1">
        <CardTitle>{isAgencyAdmin ? 'When your crews are needed' : 'When reports come in'}</CardTitle>
        <CardDescription>
          {empty ? (
            `No reports in the last ${days} days.`
          ) : (
            <>
              Last {days} days · busiest{' '}
              <strong className="font-semibold text-foreground">{weekdayLong(patterns.peak_weekday)}</strong>
              {patterns.peak_hour !== null && (
                <>
                  ,{' '}
                  <strong className="font-semibold text-foreground">{hourLabel(patterns.peak_hour)}</strong>
                </>
              )}
            </>
          )}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {empty ? (
          <div className="flex flex-col items-center gap-2 py-10 text-center text-meta text-muted-foreground">
            <Clock aria-hidden="true" className="size-6" />
            Nothing to chart yet — the pattern appears as reports arrive.
          </div>
        ) : (
          <HeatGrid compact patterns={patterns} />
        )}
      </CardContent>
    </Card>
  );
}
