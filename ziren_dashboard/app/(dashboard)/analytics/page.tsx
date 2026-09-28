'use client';

/**
 * System Analytics — spec Section 9. Trend analysis over time, distinct
 * from the Dashboard's current-state view. Two tabs matching the spec's
 * Incident and User sub-sections.
 */

import { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';
import { BarChart3, TrendingUp, Users } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import {
  fetchIncidentAnalytics, fetchUserAnalytics,
  type IncidentAnalytics, type UserAnalytics,
} from '@/lib/api/analytics';
import { ApiError } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { NavTabs } from '@/components/ui/nav-tabs';
import { CategoryBarChart } from '@/components/charts/category-bar-chart';
import { IncidentTrendChart } from '@/components/charts/incident-trend-chart';

/** Same stagger every other list on this app uses (see responders/page.tsx). */
const fadeUp = (i: number) => ({
  initial: { opacity: 0, y: 8 },
  animate: { opacity: 1, y: 0 },
  transition: { duration: 0.22, delay: Math.min(i, 6) * 0.05, ease: [0.16, 1, 0.3, 1] as const },
});

type Tab = 'incidents' | 'users';

function BarRow({ label, count, max, color }: { label: string; count: number; max: number; color: string }) {
  return (
    <li className="flex items-center gap-3">
      <span className="w-36 shrink-0 truncate text-[12.5px] text-foreground">{label}</span>
      <div className="h-2 flex-1 overflow-hidden rounded-full bg-[var(--color-surface-raised)]">
        <div className="h-full rounded-full" style={{ width: `${(count / max) * 100}%`, backgroundColor: color }} />
      </div>
      <span className="w-10 shrink-0 text-right text-[12.5px] font-semibold text-foreground">{count}</span>
    </li>
  );
}

/** BFP/PNP/MDRRMO keep their locked agency hues; anything else falls back to the given flat color. */
const AGENCY_BAR_COLOR: Record<string, string> = {
  BFP: 'var(--color-agency-bfp)',
  PNP: 'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

/** Same locked severity hues used everywhere else — never the only cue, since the row's own label sits beside it. */
const SEVERITY_BAR_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high: 'var(--color-severity-high)',
  medium: 'var(--color-severity-medium)',
  low: 'var(--color-severity-low)',
  untriaged: 'var(--color-text-muted)',
};

function BarList({ entries, color, colorByLabel }: {
  entries: [string, number][];
  color: string;
  /** When set, resolves each row's own color by its label (e.g. per-agency hues) instead of one flat color for every row. */
  colorByLabel?: Record<string, string>;
}) {
  if (entries.length === 0) {
    return <p className="py-6 text-center text-meta text-muted-foreground">No data yet.</p>;
  }
  const max = Math.max(1, ...entries.map(([, c]) => c));
  return (
    <ul className="flex flex-col gap-2.5">
      {entries.map(([label, count]) => (
        <BarRow color={colorByLabel?.[label] ?? color} count={count} key={label} label={label.replace(/_/g, ' ')} max={max} />
      ))}
    </ul>
  );
}

export default function SystemAnalyticsPage() {
  const { token, isAgencyAdmin } = useAuth();
  const [tab, setTab] = useState<Tab>('incidents');
  const [period, setPeriod] = useState<'day' | 'month' | 'year'>('month');
  const [incidents, setIncidents] = useState<IncidentAnalytics | null>(null);
  const [users, setUsers] = useState<UserAnalytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError(null);
    const load =
      tab === 'incidents' ? fetchIncidentAnalytics(token, period).then(setIncidents) :
      fetchUserAnalytics(token).then(setUsers);
    load
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setError(e instanceof Error ? e.message : 'Failed to load analytics.');
      })
      .finally(() => setLoading(false));
  }, [token, tab, period]);

  // Agency Admin has "limited/no access" to cross-agency user data (spec's
  // own Provincial Admin vs Agency Admin table) — /analytics/users stays
  // provincial_admin-only server-side, so the tab that would 403 is never shown.
  const tabs: { key: Tab; label: string; icon: typeof BarChart3 }[] = useMemo(() => [
    { key: 'incidents', label: isAgencyAdmin ? 'Incidents' : 'Incident Analytics', icon: BarChart3 },
    ...(isAgencyAdmin ? [] : [{ key: 'users' as Tab, label: 'User Analytics', icon: Users }]),
  ], [isAgencyAdmin]);

  return (
    <div className="min-h-full">
      <div className="sticky top-0 z-30 bg-[var(--color-surface-card)]">
        <NavTabs
          activeKey={tab}
          ariaLabel="System Analytics sections"
          idPrefix="analytics-tab"
          onSelect={key => setTab(key as Tab)}
          tabs={tabs}
        />
      </div>
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {tab === 'incidents' && (
        <div className="flex justify-end">
          <Select onValueChange={v => setPeriod(v as typeof period)} value={period}>
            <SelectTrigger className="w-[120px]" size="sm">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="day">Per day</SelectItem>
              <SelectItem value="month">Per month</SelectItem>
              <SelectItem value="year">Per year</SelectItem>
            </SelectContent>
          </Select>
        </div>
      )}

      {error && <Alert variant="error" message={error} />}

      {loading ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton className="h-24 rounded-[var(--radius-card)]" key={i} />
          ))}
        </div>
      ) : tab === 'incidents' && incidents ? (
        <>
          <StatStrip>
            <StatCell
              bg="var(--color-brand-subtle)" color="var(--color-brand)"
              icon={<BarChart3 size={12} strokeWidth={2} />}
              label="Total incidents" value={incidents.total}
              trend={`Grouped by ${period}`}
            />
            <StatCell
              bg="var(--color-system-success-bg)" color="var(--color-system-success)"
              icon={<TrendingUp size={12} strokeWidth={2} />}
              label="Resolved" value={incidents.resolved_vs_unresolved.resolved}
              whole={incidents.total} wholeLabel="incidents"
              trend={`${incidents.resolved_vs_unresolved.unresolved} unresolved`}
            />
            <StatCell
              bg="var(--color-status-dispatched-bg)" color="var(--color-status-dispatched)"
              icon={<TrendingUp size={12} strokeWidth={2} />}
              label="Avg resolution time"
              value={incidents.avg_resolution_minutes !== null ? `${incidents.avg_resolution_minutes}m` : '—'}
              trend="Report to resolved"
            />
          </StatStrip>
          {/* items-start: without it, a 5-row card stretches its 1-row sibling
              to match, leaving a single bar floating in a mostly-empty box. */}
          <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
            <motion.div className="lg:col-span-2" {...fadeUp(0)}>
              <IncidentTrendChart data={incidents.by_period} period={period} />
            </motion.div>
            <motion.div {...fadeUp(1)}>
              <Card>
                <CardHeader className="gap-1"><CardTitle className="text-[15px]">By type</CardTitle></CardHeader>
                <CardContent>
                  <CategoryBarChart
                    color="var(--color-status-dispatched)"
                    entries={Object.entries(incidents.by_type).sort(([, a], [, b]) => b - a)}
                  />
                </CardContent>
              </Card>
            </motion.div>
            <motion.div {...fadeUp(2)}>
              <Card>
                <CardHeader className="gap-1"><CardTitle className="text-[15px]">By agency</CardTitle></CardHeader>
                <CardContent>
                  <CategoryBarChart
                    color="var(--color-brand)"
                    colorByLabel={AGENCY_BAR_COLOR}
                    entries={Object.entries(incidents.by_agency).sort(([, a], [, b]) => b - a)}
                  />
                </CardContent>
              </Card>
            </motion.div>
            <motion.div {...fadeUp(3)}>
              <Card>
                <CardHeader className="gap-1"><CardTitle className="text-[15px]">By municipality</CardTitle></CardHeader>
                <CardContent>
                  <CategoryBarChart
                    color="var(--color-system-success)"
                    entries={Object.entries(incidents.by_municipality).sort(([, a], [, b]) => b - a)}
                  />
                </CardContent>
              </Card>
            </motion.div>
            <motion.div {...fadeUp(4)}>
              <Card>
                <CardHeader className="gap-1"><CardTitle className="text-[15px]">By severity</CardTitle></CardHeader>
                <CardContent>
                  <CategoryBarChart
                    color="var(--color-brand)"
                    colorByLabel={SEVERITY_BAR_COLOR}
                    entries={(['critical', 'high', 'medium', 'low', 'untriaged'] as const)
                      .filter(k => incidents.by_severity[k])
                      .map(k => [k, incidents.by_severity[k]])}
                  />
                </CardContent>
              </Card>
            </motion.div>
          </div>
        </>
      ) : tab === 'users' && users ? (
        <>
          <StatStrip>
            {Object.entries(users.total_by_role).map(([role, count]) => (
              <StatCell
                key={role}
                bg="var(--color-brand-subtle)" color="var(--color-brand)"
                icon={<Users size={12} strokeWidth={2} />}
                label={role.replace('_', ' ')} value={count}
                trend="registered"
              />
            ))}
          </StatStrip>
          {/* items-start: without it, a 5-row card stretches its 1-row sibling
              to match, leaving a single bar floating in a mostly-empty box. */}
          <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
            {Object.entries(users.registration_trend).map(([role, trend]) => (
              <Card key={role}>
                <CardHeader className="gap-1">
                  <CardTitle className="text-[15px]">{role.replace('_', ' ')} registrations</CardTitle>
                  <CardDescription>Per month</CardDescription>
                </CardHeader>
                <CardContent>
                  <BarList color="var(--color-brand)" entries={trend.map(t => [t.month, t.count])} />
                </CardContent>
              </Card>
            ))}
            <Card>
              <CardHeader className="gap-1"><CardTitle className="text-[15px]">Residents by municipality</CardTitle></CardHeader>
              <CardContent>
                <BarList
                  color="var(--color-system-success)"
                  entries={Object.entries(users.by_municipality).sort(([, a], [, b]) => b - a)}
                />
              </CardContent>
            </Card>
          </div>
        </>
      ) : null}
    </div>
    </div>
  );
}
