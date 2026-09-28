'use client';

import { Ambulance, Clock, ShieldCheck, Skull, Timer, Zap } from 'lucide-react';
import type { OperationalArea, TimeStats } from '@/lib/api/operational-area';
import { periodLong } from './period';
import { HeatGrid, HourChart, hourLabel, weekdayLong } from './charts';
import {
  BarList, Empty, Kpi, Meter, Note, Panel, SEVERITY_WORD, SevChip, fmtInt, fmtMin, fmtPct, outcomeLabel,
} from './kit';

/** Success above 90, amber below — never red, which belongs to critical severity. */
const complianceColor = (pct: number | null) =>
  pct === null ? 'var(--color-text-muted)' : pct >= 90 ? 'var(--color-system-success)' : 'var(--color-system-warning)';

function Clock3({
  icon: Icon,
  tone,
  title,
  description,
  stats,
  footer,
}: {
  icon: typeof Zap;
  tone: string;
  title: string;
  description: string;
  stats: TimeStats;
  footer?: React.ReactNode;
}) {
  return (
    <Panel description={description} title={title}>
      <div className="flex items-center gap-4">
        <span aria-hidden="true" className="flex size-11 shrink-0 items-center justify-center rounded-[12px]" style={{ color: tone, backgroundColor: `color-mix(in srgb, ${tone} 12%, transparent)` }}>
          <Icon className="size-5" />
        </span>
        <div>
          <p className="text-[30px] font-bold leading-none tracking-tight tabular-nums text-foreground">{fmtMin(stats.avg)}</p>
          <p className="mt-1 text-[12px] text-muted-foreground">average · {fmtInt(stats.n)} report{stats.n === 1 ? '' : 's'}</p>
        </div>
      </div>
      <dl className="mt-4 grid grid-cols-3 gap-3 border-t border-[var(--color-surface-border)] pt-4 text-center">
        {([['Median', stats.p50], ['90th percentile', stats.p90], ['Slowest', stats.max]] as [string, number | null][]).map(([label, v]) => (
          <div key={label}>
            <dt className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</dt>
            <dd className="mt-1 text-[15px] font-semibold tabular-nums text-foreground">{fmtMin(v)}</dd>
          </div>
        ))}
      </dl>
      {footer && <div className="mt-4">{footer}</div>}
    </Panel>
  );
}

export function ResponseTab({ data }: { data: OperationalArea }) {
  const r = data.response;
  const tp = data.time_patterns;
  const o = data.outcomes;
  const rows = r.by_severity.filter(s => s.n > 0);
  const outcomes = Object.entries(o.counts).sort(([, a], [, b]) => b - a);

  return (
    <div className="flex flex-col gap-4">
      {/* ── The three clocks ─────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Clock3
          description="From the report arriving to a dispatcher sending a crew."
          footer={
            <div>
              <div className="mb-1.5 flex items-center justify-between text-[12px]">
                <span className="text-muted-foreground">Dispatched within the target</span>
                <strong className="tabular-nums text-foreground">{fmtPct(r.dispatch_compliance)}</strong>
              </div>
              <Meter ariaLabel="Dispatched within target" color={complianceColor(r.dispatch_compliance)} max={100} value={r.dispatch_compliance ?? 0} />
            </div>
          }
          icon={Zap}
          stats={r.dispatch}
          title="Time to dispatch"
          tone="var(--color-system-warning)"
        />
        <Clock3
          description="From the dispatch to the crew pressing Accept."
          icon={Timer}
          stats={r.ack}
          title="Time to accept"
          tone="var(--color-status-processing)"
        />
        <Clock3
          description="From the report arriving to it being marked resolved."
          icon={Clock}
          stats={r.resolution}
          title="Time to resolve"
          tone="var(--color-system-success)"
        />
      </div>

      {/* ── By severity, against the targets ─────────────────────────── */}
      <Panel
        description={`How ${periodLong(data.filters)} measured up to the dispatch targets and the crew acknowledgement deadlines. Reports still waiting count as “waiting”, not late — they have not been decided yet.`}
        flush
        title="Performance by severity"
      >
        {rows.length === 0 ? (
          <Empty icon={ShieldCheck} title="No reports to measure">Once reports are filed in this period, their response times are judged here.</Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[1040px] whitespace-nowrap text-[13px]">
              <thead>
                <tr className="border-y border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50 text-left text-[11.5px] uppercase tracking-wide text-muted-foreground">
                  <th className="px-5 py-2.5 font-semibold" scope="col">Severity</th>
                  <th className="px-3 py-2.5 text-right font-semibold" scope="col">Reports</th>
                  <th className="px-3 py-2.5 font-semibold" scope="col">Dispatch target</th>
                  <th className="px-3 py-2.5 font-semibold" scope="col">Median · 90th</th>
                  <th className="px-3 py-2.5 font-semibold" scope="col">On time · late · waiting</th>
                  <th className="w-[170px] px-3 py-2.5 font-semibold" scope="col">Within target</th>
                  <th className="px-3 py-2.5 font-semibold" scope="col">Accept deadline</th>
                  <th className="px-3 py-2.5 text-right font-semibold" scope="col">Accepted in time</th>
                  <th className="px-5 py-2.5 text-right font-semibold" scope="col">Median to resolve</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-surface-border)]">
                {rows.map(s => (
                  <tr className="hover:bg-[var(--color-surface-raised)]/40" key={s.severity}>
                    <td className="px-5 py-3"><SevChip severity={s.severity} /></td>
                    <td className="px-3 py-3 text-right font-semibold tabular-nums">{fmtInt(s.n)}</td>
                    <td className="px-3 py-3 tabular-nums text-[var(--color-text-secondary)]">{s.severity === 'untriaged' ? `${s.dispatch_target_min} min (strictest)` : `${s.dispatch_target_min} min`}</td>
                    <td className="px-3 py-3 tabular-nums text-[var(--color-text-secondary)]">{fmtMin(s.dispatch.p50)} · {fmtMin(s.dispatch.p90)}</td>
                    <td className="px-3 py-3 tabular-nums text-[var(--color-text-secondary)]">
                      {s.on_time} · {s.late} · {s.awaiting}
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-2.5">
                        <span className="w-10 shrink-0 text-right font-semibold tabular-nums text-foreground">{fmtPct(s.dispatch_compliance)}</span>
                        <Meter ariaLabel={`${SEVERITY_WORD[s.severity]} dispatched within target`} color={complianceColor(s.dispatch_compliance)} max={100} value={s.dispatch_compliance ?? 0} />
                      </div>
                    </td>
                    <td className="px-3 py-3 tabular-nums text-[var(--color-text-secondary)]">{fmtMin(s.ack_deadline_min)}</td>
                    <td className="px-3 py-3 text-right font-semibold tabular-nums" style={{ color: complianceColor(s.ack_compliance) }}>{fmtPct(s.ack_compliance)}</td>
                    <td className="px-5 py-3 text-right tabular-nums text-[var(--color-text-secondary)]">{fmtMin(s.resolution.p50)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="border-t border-[var(--color-surface-border)] px-5 py-3">
          <Note>
            The targets are the same ones Reports &amp; Export uses, so a figure here matches an exported report. They are provisional service targets, not yet agency policy. A negative or missing timestamp is left out of a time rather than counted as zero.
          </Note>
        </div>
      </Panel>

      {/* ── When ─────────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-5">
        <Panel
          className="xl:col-span-2"
          description={tp.peak_hour === null ? 'Reports by the hour they arrived.' : <>Busiest hour: <strong className="font-semibold text-foreground">{hourLabel(tp.peak_hour)}</strong>. Philippine time.</>}
          title="Time of day"
        >
          {tp.total === 0 ? <Empty icon={Clock} title="No reports in this period" /> : <HourChart patterns={tp} />}
        </Panel>
        <Panel
          className="xl:col-span-3"
          description={tp.peak_weekday === null ? 'Weekday and hour, together.' : <>Busiest day: <strong className="font-semibold text-foreground">{weekdayLong(tp.peak_weekday)}</strong>. Darker means more reports.</>}
          title="Week pattern"
        >
          {tp.total === 0 ? <Empty icon={Clock} title="No reports in this period" /> : <HeatGrid patterns={tp} />}
        </Panel>
      </div>

      {/* ── Outcomes ─────────────────────────────────────────────────── */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Panel
          className="lg:col-span-2"
          description={`What crews found and did, from the outcome they recorded. ${fmtInt(o.recorded)} of ${fmtInt(data.kpis.incidents)} report${data.kpis.incidents === 1 ? '' : 's'} have one.`}
          title="Outcomes"
        >
          <BarList
            color="var(--color-status-processing)"
            empty="No outcome has been recorded in this period yet — crews record it when they close a report."
            items={outcomes.map(([key, count]) => ({ key, label: outcomeLabel(key), count }))}
          />
        </Panel>
        <div className="grid grid-cols-1 content-start gap-3">
          <Kpi icon={Ambulance} label="People injured" sub="Recorded by crews at closure" tone="warning" value={fmtInt(o.casualties.injured)} />
          <Kpi icon={Ambulance} label="Transported to a facility" sub="Taken for treatment" tone="info" value={fmtInt(o.casualties.transported)} />
          <Kpi icon={Skull} label="Fatalities" sub="Recorded by crews at closure" tone="neutral" value={fmtInt(o.casualties.fatal)} />
        </div>
      </div>
    </div>
  );
}
