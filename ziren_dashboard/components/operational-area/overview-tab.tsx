'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import {
  AlertTriangle, ArrowRight, CheckCircle2, CheckCheck, Clock, Flame, Info, Radio, Siren, Timer, Users, Zap,
} from 'lucide-react';
import type { OperationalArea, ReadinessCheck } from '@/lib/api/operational-area';
import { CATEGORY_ICON, SEV_COLOR } from '@/components/incidents/incident-vocabulary';
import { DeltaBadge } from '@/components/charts/delta-badge';
import { useAuth } from '@/lib/hooks/useAuth';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDate, formatTime } from '@/lib/format/datetime';
import { periodLong, previousLabel } from './period';
import { TrendChart, hourLabel, weekdayLong } from './charts';
import {
  BarList, Change, Empty, Kpi, Panel, SEVERITY_WORD, SevChip, StatusChip, categoryLabel, fmtInt, fmtMin,
  CHANNEL_LABEL, SIGNAL_LABEL,
} from './kit';

const SEV_ORDER = ['critical', 'high', 'medium', 'low', 'untriaged'];

export function OverviewTab({
  data,
  onOpenIncident,
  onTab,
}: {
  data: OperationalArea;
  onOpenIncident: (id: string) => void;
  onTab: (tab: string) => void;
}) {
  const router = useRouter();
  const { isProvincialAdmin } = useAuth();
  const k = data.kpis;
  const window = periodLong(data.filters);
  const display = displayPrefs.use();

  const change = k.previous_incidents === null ? null : k.incidents - k.previous_incidents;
  const changePct =
    change === null || !k.previous_incidents ? null : Math.round((change / k.previous_incidents) * 100);

  const sevItems = SEV_ORDER
    .filter(s => (data.mix.severity[s] ?? 0) > 0)
    .map(s => ({ key: s, label: SEVERITY_WORD[s], count: data.mix.severity[s], color: SEV_COLOR[s] ?? 'var(--color-text-muted)' }));

  const catItems = Object.entries(data.mix.categories)
    .sort(([, a], [, b]) => b - a)
    .map(([key, count]) => ({ key, label: categoryLabel(key), count, icon: CATEGORY_ICON[key] ?? Flame }));

  const tp = data.time_patterns;
  const prev = k.previous;
  const since = previousLabel(data.filters);

  return (
    <div className="flex flex-col gap-4">
      {/* ── Headline figures ─────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi
          delta={
            changePct !== null ? <DeltaBadge suffix="%" value={changePct} />
              : change !== null && change !== 0 ? <DeltaBadge value={change} /> : undefined
          }
          icon={Siren}
          label="Reports"
          sub={
            k.previous_incidents === null
              ? 'All time — nothing earlier to compare with'
              : `${fmtInt(k.previous_incidents)} in ${since}`
          }
          tone="brand"
          value={fmtInt(k.incidents)}
        />
        {!isProvincialAdmin && (
          <Kpi
            icon={Radio}
            label="Active now"
            onClick={() => router.push('/incidents')}
            sub={
              k.awaiting_dispatch > 0
                ? <span className="font-medium" style={{ color: 'var(--color-system-warning)' }}>{k.awaiting_dispatch} waiting for a dispatcher</span>
                : 'Nothing waiting for dispatch'
            }
            tone={k.awaiting_dispatch > 0 ? 'warning' : 'info'}
            value={fmtInt(k.active_now)}
          />
        )}
        <Kpi
          icon={AlertTriangle}
          delta={prev ? <Change before={prev.critical} now={k.critical} since={since} /> : undefined}
          label="Critical"
          sub={`${k.incidents ? Math.round((k.critical / k.incidents) * 100) : 0}% of reports${k.sos ? ` · ${k.sos} SOS` : ''}`}
          tone="critical"
          value={fmtInt(k.critical)}
        />
        <Kpi
          icon={CheckCheck}
          delta={prev ? <Change before={prev.resolved_rate} now={k.resolved_rate} riseIsBad={false} since={since} unit=" pts" /> : undefined}
          label="Resolved"
          sub={`${fmtInt(k.resolved)} resolved · ${fmtInt(k.cancelled)} cancelled${k.false_alarms ? ` · ${k.false_alarms} false alarm${k.false_alarms === 1 ? '' : 's'}` : ''}`}
          tone="success"
          unit={k.resolved_rate === null ? undefined : 'of closed'}
          value={k.resolved_rate === null ? '—' : `${k.resolved_rate}%`}
        />
        <Kpi
          delta={prev ? <Change before={prev.dispatch_avg} now={k.dispatch.avg} since={since} unit=" min" /> : undefined}
          icon={Zap}
          label="Time to dispatch"
          onClick={() => onTab('response')}
          sub={
            k.dispatch.n
              ? <>Median {fmtMin(k.dispatch.p50)} · 90th {fmtMin(k.dispatch.p90)}{k.dispatch_compliance !== null && <> · <strong className="font-semibold text-foreground">{k.dispatch_compliance}%</strong> within target</>}</>
              : 'No dispatched reports yet'
          }
          tone="warning"
          value={fmtMin(k.dispatch.avg)}
        />
        {!isProvincialAdmin && (
          <Kpi
            delta={prev ? <Change before={prev.ack_avg} now={k.ack.avg} since={since} unit=" min" /> : undefined}
            icon={Timer}
            label="Time to accept"
            onClick={() => onTab('response')}
            sub={k.ack.n ? <>Median {fmtMin(k.ack.p50)} · 90th {fmtMin(k.ack.p90)}</> : 'No accepted dispatches yet'}
            tone="info"
            value={fmtMin(k.ack.avg)}
          />
        )}
        {!isProvincialAdmin && (
          <Kpi
            delta={prev ? <Change before={prev.resolution_avg} now={k.resolution.avg} since={since} unit=" min" /> : undefined}
            icon={Clock}
            label="Time to resolve"
            sub={k.resolution.n ? <>Median {fmtMin(k.resolution.p50)} · 90th {fmtMin(k.resolution.p90)}</> : 'No resolved reports yet'}
            tone="success"
            value={fmtMin(k.resolution.avg)}
          />
        )}
        {!isProvincialAdmin && (
          <Kpi
            icon={Users}
            label="Registered residents"
            onClick={() => onTab('barangays')}
            sub={
              <>
                {fmtInt(k.verified_residents)} verified · {fmtInt(k.vulnerable_residents)} vulnerable
                {k.new_residents !== null && <> · <strong className="font-semibold text-foreground">+{fmtInt(k.new_residents)}</strong> new</>}
              </>
            }
            tone="brand"
            value={fmtInt(k.residents)}
          />
        )}
      </div>

      {/* ── Trend + readiness ────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Panel
          className="xl:col-span-2"
          description={
            <>
              {fmtInt(k.incidents)} report{k.incidents === 1 ? '' : 's'} in {window}, by {data.trend.unit}
              {tp.peak_hour !== null && <> · busiest hour <strong className="font-semibold text-foreground">{hourLabel(tp.peak_hour)}</strong>, busiest day <strong className="font-semibold text-foreground">{weekdayLong(tp.peak_weekday)}</strong></>}
            </>
          }
          bodyClassName="flex-1"
          title="Reports over time"
        >
          <TrendChart fill trend={data.trend} />
        </Panel>

        <Panel
          description="Plain checks, each from a real count — not a score."
          title="Readiness"
        >
          <ul className="flex flex-col divide-y divide-[var(--color-surface-border)]">
            {data.readiness.map(c => <ReadinessRow check={c} key={c.key} onTab={onTab} />)}
          </ul>
        </Panel>
      </div>

      {/* ── Mix ──────────────────────────────────────────────────────── */}
      {/* Not shown to provincial_admin at all — an oversight read across
          several municipalities has less use for one municipality's severity/
          type/channel breakdown than an agency_admin actually dispatching
          reports does; see this session's Overview-trimming request. */}
      {!isProvincialAdmin && (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
          <Panel description="How serious the reports were, as scored." title="By severity">
            {sevItems.length ? (
              <>
                <div aria-hidden="true" className="mb-4 flex h-3 overflow-hidden rounded-full bg-[var(--color-surface-raised)]">
                  {sevItems.map(s => (
                    <span key={s.key} style={{ width: `${(s.count / k.incidents) * 100}%`, backgroundColor: s.color }} />
                  ))}
                </div>
                <BarList items={sevItems} />
              </>
            ) : <Empty icon={Info} title="No reports in this period" />}
          </Panel>

          <Panel description="What people reported." title="By type">
            <BarList color="var(--color-status-processing)" icon items={catItems} />
          </Panel>

          <Panel description="How the report reached you, and what else was flagged." title="Channel & signals">
            <BarList
              color="var(--color-status-processing)"
              items={Object.entries(data.mix.channels).sort(([, a], [, b]) => b - a).map(([key, count]) => ({ key, label: CHANNEL_LABEL[key] ?? key, count }))}
            />
            {Object.keys(data.mix.multi_agency_signals).length > 0 && (
              <div className="mt-5 border-t border-[var(--color-surface-border)] pt-4">
                <p className="mb-3 text-[12px] font-semibold uppercase tracking-wide text-muted-foreground">Flagged by the reporter</p>
                <BarList
                  color="var(--color-text-secondary)"
                  items={Object.entries(data.mix.multi_agency_signals).sort(([, a], [, b]) => b - a).map(([key, count]) => ({ key, label: SIGNAL_LABEL[key] ?? key, count }))}
                />
              </div>
            )}
          </Panel>
        </div>
      )}

      {/* ── Recent + hot spots ───────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Panel
          action={<Link className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" href="/incident-history">All records <ArrowRight className="size-3.5" /></Link>}
          className="xl:col-span-2"
          description="The latest reports in this area, newest first."
          flush
          title="Recent reports"
        >
          {data.recent.length === 0 ? (
            <Empty icon={Siren} title="No reports in this period">Reports filed in this area will appear here as they come in.</Empty>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full min-w-[700px] text-[13px]">
                <thead>
                  <tr className="border-y border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50 text-left text-[11.5px] uppercase tracking-wide text-muted-foreground">
                    <th className="whitespace-nowrap px-5 py-2 font-semibold">Record &amp; place</th>
                    <th className="whitespace-nowrap px-3 py-2 font-semibold">Type</th>
                    <th className="whitespace-nowrap px-3 py-2 font-semibold">Severity</th>
                    <th className="whitespace-nowrap px-3 py-2 font-semibold">Status</th>
                    <th className="whitespace-nowrap px-5 py-2 text-right font-semibold">When</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-[var(--color-surface-border)]">
                  {data.recent.map(r => {
                    const Icon = CATEGORY_ICON[r.category ?? ''] ?? Flame;
                    return (
                      <tr className="hover:bg-[var(--color-surface-raised)]/40" key={r.id}>
                        <td className="px-5 py-2.5">
                          <div className="flex items-center gap-2 whitespace-nowrap">
                            <button
                              className="font-mono text-[12.5px] font-semibold text-foreground hover:underline focus-visible:underline focus-visible:outline-none"
                              onClick={() => onOpenIncident(r.id)}
                              type="button"
                            >
                              {r.record_number ?? r.id.slice(0, 8)}
                            </button>
                            {r.sos_flagged && <span className="rounded bg-[var(--color-severity-critical-bg)] px-1 text-[10px] font-bold text-[var(--color-severity-critical)]">SOS</span>}
                          </div>
                          <p className="mt-0.5 max-w-[210px] truncate text-[12px] text-muted-foreground" title={r.address ?? undefined}>
                            {r.barangay ?? r.address ?? 'No address'}
                          </p>
                        </td>
                        <td className="whitespace-nowrap px-3 py-2.5"><span className="flex items-center gap-1.5"><Icon aria-hidden="true" className="size-3.5 text-muted-foreground" />{categoryLabel(r.category)}</span></td>
                        <td className="whitespace-nowrap px-3 py-2.5"><SevChip severity={r.severity} /></td>
                        <td className="whitespace-nowrap px-3 py-2.5"><StatusChip status={r.status} /></td>
                        <td className="whitespace-nowrap px-5 py-2.5 text-right tabular-nums">
                          <p className="text-foreground">{formatDate(r.created_at, display)}</p>
                          <p className="text-[12px] text-muted-foreground">{formatTime(r.created_at, display)}</p>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </Panel>

        <Panel
          action={<button className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" onClick={() => onTab('barangays')} type="button">All barangays <ArrowRight className="size-3.5" /></button>}
          description="Where reports name a barangay in their address."
          title="Busiest barangays"
        >
          <BarList
            empty="No report in this period names a barangay."
            items={[...data.barangays.items].filter(b => b.incidents > 0).sort((a, b) => b.incidents - a.incidents).slice(0, 6)
              .map(b => ({ key: b.id, label: b.name, count: b.incidents, hint: b.critical ? `${b.critical} critical` : undefined }))}
          />
          {data.barangays.unmatched_incidents + data.barangays.unlocated_incidents > 0 && (
            <p className="mt-4 text-[12px] leading-relaxed text-muted-foreground">
              {data.barangays.unmatched_incidents + data.barangays.unlocated_incidents} report{data.barangays.unmatched_incidents + data.barangays.unlocated_incidents === 1 ? '' : 's'} name no barangay, so they are not counted here.
            </p>
          )}
        </Panel>
      </div>
    </div>
  );
}

function ReadinessRow({ check, onTab }: { check: ReadinessCheck; onTab: (t: string) => void }) {
  const Icon = check.status === 'ok' ? CheckCircle2 : check.status === 'warn' ? AlertTriangle : Info;
  const color =
    check.status === 'ok' ? 'var(--color-system-success)' : check.status === 'warn' ? 'var(--color-system-warning)' : 'var(--color-status-processing)';
  const action = check.href ? (
    <Link className="shrink-0 text-[12px] font-semibold text-[var(--color-brand)] hover:underline" href={check.href}>Open</Link>
  ) : check.tab ? (
    <button className="shrink-0 text-[12px] font-semibold text-[var(--color-brand)] hover:underline" onClick={() => onTab(check.tab!)} type="button">View</button>
  ) : null;
  return (
    <li className="flex items-start gap-3 py-3 first:pt-1 last:pb-0">
      <Icon aria-hidden="true" className="mt-0.5 size-[18px] shrink-0" style={{ color }} />
      <div className="min-w-0 flex-1">
        <p className="text-[13px] font-medium leading-snug text-foreground">
          <span className="sr-only">{check.status === 'ok' ? 'OK: ' : check.status === 'warn' ? 'Needs attention: ' : 'Note: '}</span>
          {check.title}
        </p>
        <p className="mt-0.5 text-[12px] leading-snug text-muted-foreground">{check.detail}</p>
      </div>
      {check.status !== 'ok' && action}
    </li>
  );
}
