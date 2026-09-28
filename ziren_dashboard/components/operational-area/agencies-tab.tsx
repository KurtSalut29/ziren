'use client';

import Link from 'next/link';
import { ArrowRight, Building2, Handshake, Mail, MapPin, Phone, ShieldAlert } from 'lucide-react';
import type { AgencyPresence, AreaFilters, OperationalArea } from '@/lib/api/operational-area';
import { useAssistInboxContext } from '@/components/assist/assist-context';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { periodLong } from './period';
import { AgencyChip, BarList, Empty, Note, Panel, SIGNAL_LABEL, fmtInt } from './kit';

// `token` is still passed by the page but no longer read here: the assist
// requests this tab used to fetch come from the layout's shared inbox now.
export function AgenciesTab({ data }: { data: OperationalArea; token: string }) {
  const signals = Object.entries(data.mix.multi_agency_signals).sort(([, a], [, b]) => b - a);
  const others = data.agencies.filter(a => !a.is_own && a.is_active);

  return (
    <div className="flex flex-col gap-4">
      <AssistRequestsLink />

      <Panel
        description={`Every agency with a presence in ${data.area.municipality}. When a report needs more than one of you, this is who to call.`}
        title="Agencies here"
      >
        {data.agencies.length === 0 ? (
          <Empty icon={Building2} title="No agency registered in this municipality" />
        ) : (
          <ul className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
            {data.agencies.map(a => <AgencyCard agency={a} filters={data.filters} key={a.id} />)}
          </ul>
        )}
      </Panel>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <Panel
          description={`What reporters flagged on the reports in ${periodLong(data.filters)}. A flag is the reporter’s own answer on the report form — a hint that another agency may be needed, not a dispatch decision.`}
          title="Overlapping hazards"
        >
          <BarList
            color="var(--color-text-secondary)"
            empty="No report in this period was flagged with an overlapping hazard."
            items={signals.map(([key, count]) => ({ key, label: SIGNAL_LABEL[key] ?? key, count }))}
          />
        </Panel>

        <Panel description="Numbers to reach the other agencies in your area, one tap from a phone." title="Quick contacts">
          {others.length === 0 ? (
            <Empty icon={Phone} title="No other agency here">Nobody else is registered in this municipality yet.</Empty>
          ) : (
            <ul className="flex flex-col divide-y divide-[var(--color-surface-border)]">
              {others.map(a => (
                <li className="flex flex-wrap items-center justify-between gap-3 py-3 first:pt-0 last:pb-0" key={a.id}>
                  <div className="min-w-0">
                    <p className="flex items-center gap-2 text-[13.5px] font-medium text-foreground"><AgencyChip type={a.agency_type} />{a.name}</p>
                    <p className="mt-0.5 text-[12px] text-muted-foreground">{a.email ?? 'No email on file'}</p>
                  </div>
                  {a.contact_number ? (
                    <a className="inline-flex items-center gap-1.5 rounded-lg border border-[var(--color-surface-border)] px-3 py-1.5 text-[13px] font-semibold tabular-nums text-foreground hover:bg-[var(--color-surface-raised)]" href={`tel:${a.contact_number.replace(/[^\d+]/g, '')}`}>
                      <Phone aria-hidden="true" className="size-3.5" />
                      {a.contact_number}
                    </a>
                  ) : (
                    <span className="text-[12.5px] text-muted-foreground">No number on file</span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>

      <Note>
        <ShieldAlert aria-hidden="true" className="mr-1.5 inline size-3.5 align-[-2px]" />
        Ziren shows you only your own agency’s reports. Another agency’s incident figures are theirs, and are not visible here.
      </Note>
    </div>
  );
}

function AgencyCard({ agency: a, filters }: { agency: AgencyPresence; filters: AreaFilters }) {
  const hue = AG_COLOR[a.agency_type ?? ''] ?? 'var(--color-text-muted)';
  return (
    <li className="flex flex-col rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4" style={{ borderTopColor: hue, borderTopWidth: 3 }}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="flex items-center gap-2"><AgencyChip type={a.agency_type} />{!a.is_active && <span className="text-[11px] font-semibold text-muted-foreground">Inactive</span>}</p>
          <h3 className="mt-1.5 text-[15px] font-semibold leading-snug text-foreground">{a.name}</h3>
        </div>
        {a.is_own && <span className="shrink-0 rounded-full bg-[var(--color-brand-subtle)] px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide text-[var(--color-brand)]">Yours</span>}
      </div>

      <ul className="mt-3 flex flex-col gap-1.5 text-[13px]">
        <li className="flex items-center gap-2 text-[var(--color-text-secondary)]">
          <Phone aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          {a.contact_number ? <a className="tabular-nums hover:underline" href={`tel:${a.contact_number.replace(/[^\d+]/g, '')}`}>{a.contact_number}</a> : <span className="text-muted-foreground">No contact number on file</span>}
        </li>
        <li className="flex items-center gap-2 text-[var(--color-text-secondary)]">
          <Mail aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          {a.email ? <a className="truncate hover:underline" href={`mailto:${a.email}`}>{a.email}</a> : <span className="text-muted-foreground">No email on file</span>}
        </li>
        <li className="flex items-center gap-2 text-[var(--color-text-secondary)]">
          <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          {a.stations} station{a.stations === 1 ? '' : 's'}
          {a.stations > 0 && a.mapped_stations < a.stations && <span className="text-[var(--color-system-warning)]">· {a.stations - a.mapped_stations} not on the map</span>}
        </li>
      </ul>

      {a.is_own ? (
        <div className="mt-4 flex items-center justify-between gap-2 border-t border-[var(--color-surface-border)] pt-3 text-[12.5px]">
          <span className="text-muted-foreground">Reports {filters.date_from ? `· ${periodLong(filters)}` : filters.days === 0 ? 'all time' : `· ${filters.days} days`}</span>
          <span className="flex items-center gap-3">
            <strong className="text-[16px] tabular-nums text-foreground">{fmtInt(a.incidents)}</strong>
            {(!a.contact_number || !a.email) && (
              <Link className="text-[12px] font-semibold text-[var(--color-brand)] hover:underline" href="/settings?tab=agency">Complete details</Link>
            )}
          </span>
        </div>
      ) : (
        <p className="mt-4 border-t border-[var(--color-surface-border)] pt-3 text-[12px] text-muted-foreground">Report figures for this agency are not shown to you.</p>
      )}
    </li>
  );
}

/**
 * Assist requests used to live in a panel here. They have their own page now
 * (see app/(dashboard)/assist-requests) — this card only points there, since
 * this is still where a station looks when it thinks "who else is around".
 */
function AssistRequestsLink() {
  const inbox = useAssistInboxContext();
  const waiting = inbox?.pendingIncoming ?? 0;
  return (
    <Link
      className="group flex items-center gap-4 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-5 py-4 transition-colors hover:border-[var(--color-brand)]"
      href="/assist-requests"
    >
      <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-[var(--color-system-info-bg)] text-[var(--color-system-info)]">
        <Handshake aria-hidden="true" className="size-5" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[14px] font-bold text-foreground">Assist Requests</span>
        <span className="block text-[12.5px] text-muted-foreground">
          {waiting > 0
            ? `${waiting} station${waiting === 1 ? ' is' : 's are'} waiting for your answer.`
            : 'Ask any station in Biliran for help, and talk it through with them.'}
        </span>
      </span>
      <ArrowRight aria-hidden="true" className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
    </Link>
  );
}
