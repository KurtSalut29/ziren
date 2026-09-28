'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { ArrowRight, Building2, MapPin, MapPinOff, UserCheck, UserCog, UserMinus, Users } from 'lucide-react';
import type { OperationalArea, ResponderRow, StationRow } from '@/lib/api/operational-area';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { formatDate } from '@/lib/format/datetime';
import { formatCoordinates } from '@/lib/format/geo';
import { displayPrefs, mapPrefs } from '@/lib/prefs/definitions';
import { periodLong } from './period';
import { AgencyChip, Empty, Kpi, Note, Panel, ago, fmtInt, fmtMin } from './kit';

export function CrewTab({ data, onTab }: { data: OperationalArea; onTab: (t: string) => void }) {
  const router = useRouter();
  const display = displayPrefs.use();
  const geo = mapPrefs.use();
  const st = data.stations;
  const r = data.responders;
  const stations = st.items;
  const mapped = stations.filter(s => s.lat !== null && s.is_active).length;

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Kpi icon={Building2} label="Stations in this area" sub={`${mapped} on the map · all agencies`} tone="neutral" value={fmtInt(stations.length)} />
        <Kpi icon={UserCheck} label="On duty now" sub={`Of ${fmtInt(r.approved)} approved responder${r.approved === 1 ? '' : 's'}`} tone="success" value={fmtInt(r.on_duty)} />
        <Kpi icon={UserMinus} label="Off duty" sub="Approved, not on shift" tone="neutral" value={fmtInt(r.off_duty)} />
        <Kpi
          icon={UserCog}
          label="Awaiting approval"
          onClick={r.pending ? () => router.push('/responders') : undefined}
          sub={r.pending ? 'Cannot receive dispatches yet' : 'Nobody waiting'}
          tone={r.pending ? 'warning' : 'success'}
          value={fmtInt(r.pending)}
        />
      </div>

      {/* ── Stations ─────────────────────────────────────────────────── */}
      <Panel
        action={
          <button className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" onClick={() => onTab('map')} type="button">
            See them on the map <ArrowRight className="size-3.5" />
          </button>
        }
        description={`Every station of every agency in ${data.area.municipality}. Report figures are shown only for your own — another agency’s data stays theirs.`}
        title="Stations"
      >
        {stations.length === 0 ? (
          <Empty icon={Building2} title="No station on file for this area">An agency admin or provincial admin can add one under Agencies.</Empty>
        ) : (
          <ul className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-3">
            {stations.map(s => <StationCard display={display} geo={geo} key={s.id} station={s} />)}
          </ul>
        )}
        {st.unassigned_incidents > 0 && (
          <div className="mt-4">
            <Note tone="warning">
              <strong className="font-semibold">{st.unassigned_incidents} report{st.unassigned_incidents === 1 ? ' has' : 's have'} no station assigned</strong> in {periodLong(data.filters)} — the reporter’s location did not resolve to a nearest station.
            </Note>
          </div>
        )}
      </Panel>

      {/* ── Crew ─────────────────────────────────────────────────────── */}
      <Panel
        action={
          <Link className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" href="/responders">
            Manage responders <ArrowRight className="size-3.5" />
          </Link>
        }
        description={`Your responders, and what each handled in ${periodLong(data.filters)}.`}
        flush
        title="Crew roster"
      >
        {r.roster.length === 0 ? (
          <Empty icon={Users} title="No responders yet">Responders register from the mobile app and appear here once approved.</Empty>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-[13px]">
              <thead>
                <tr className="border-y border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50 text-left text-[11.5px] uppercase tracking-wide text-muted-foreground">
                  <th className="px-5 py-2.5 font-semibold" scope="col">Responder</th>
                  <th className="px-3 py-2.5 font-semibold" scope="col">Status</th>
                  <th className="px-3 py-2.5 text-right font-semibold" scope="col">Handled</th>
                  <th className="px-3 py-2.5 text-right font-semibold" scope="col">Resolved</th>
                  <th className="px-3 py-2.5 text-right font-semibold" scope="col">Avg accept time</th>
                  <th className="px-5 py-2.5 text-right font-semibold" scope="col">Location</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-surface-border)]">
                {r.roster.map(u => <CrewRow key={u.id} u={u} />)}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      {data.area.agency === null && (
        <p className="px-1 text-[12px] text-muted-foreground">Crew figures cover your agency type across this municipality.</p>
      )}
    </div>
  );
}

function StationCard({
  station: s,
  display,
  geo,
}: {
  station: StationRow;
  display: Parameters<typeof formatDate>[1];
  geo: Parameters<typeof formatCoordinates>[2];
}) {
  const hue = AG_COLOR[s.agency_type ?? ''] ?? 'var(--color-text-muted)';
  return (
    <li className="flex flex-col rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4" style={{ borderTopColor: hue, borderTopWidth: 3 }}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="flex items-center gap-2 text-[11.5px] text-muted-foreground"><AgencyChip type={s.agency_type} />{s.agency_name}</p>
          <h3 className="mt-1.5 text-[14.5px] font-semibold leading-snug text-foreground">{s.name}</h3>
        </div>
        {s.is_own && <span className="shrink-0 rounded-full bg-[var(--color-brand-subtle)] px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wide text-[var(--color-brand)]">Yours</span>}
      </div>
      <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">{s.address ?? 'No address on file'}</p>

      <p className="mt-3 flex items-center gap-1.5 text-[12px]">
        {s.lat !== null && s.lng !== null ? (
          <>
            <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-system-success)]" />
            <span className="font-mono text-[11.5px] tabular-nums text-[var(--color-text-secondary)]">{formatCoordinates(s.lat, s.lng, geo)}</span>
          </>
        ) : (
          <>
            <MapPinOff aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-system-warning)]" />
            <span className="font-medium text-[var(--color-system-warning)]">No coordinates — cannot be pinned or picked as nearest</span>
          </>
        )}
      </p>
      {!s.is_active && <p className="mt-1 text-[12px] font-medium text-muted-foreground">Inactive</p>}

      {s.is_own && s.incidents !== null ? (
        <dl className="mt-4 grid grid-cols-3 gap-2 border-t border-[var(--color-surface-border)] pt-3 text-center">
          <div>
            <dt className="text-[10.5px] font-semibold uppercase tracking-wide text-muted-foreground">Reports</dt>
            <dd className="mt-0.5 text-[16px] font-bold tabular-nums text-foreground">{fmtInt(s.incidents)}</dd>
          </div>
          <div>
            <dt className="text-[10.5px] font-semibold uppercase tracking-wide text-muted-foreground">Avg dispatch</dt>
            <dd className="mt-0.5 text-[16px] font-bold tabular-nums text-foreground">{fmtMin(s.dispatch?.avg ?? null)}</dd>
          </div>
          <div>
            <dt className="text-[10.5px] font-semibold uppercase tracking-wide text-muted-foreground">Last report</dt>
            <dd className="mt-0.5 text-[13px] font-semibold tabular-nums text-foreground">{s.last_incident_at ? formatDate(s.last_incident_at, display) : '—'}</dd>
          </div>
        </dl>
      ) : (
        <p className="mt-4 border-t border-[var(--color-surface-border)] pt-3 text-[12px] text-muted-foreground">Another agency’s station — its report figures are not shown to you.</p>
      )}
    </li>
  );
}

function CrewRow({ u }: { u: ResponderRow }) {
  const pending = u.approval_status === 'pending';
  const rejected = u.approval_status === 'rejected';
  const onDuty = u.approval_status === 'approved' && u.availability === 'on_duty';
  const label = pending ? 'Awaiting approval' : rejected ? 'Rejected' : onDuty ? 'On duty' : 'Off duty';
  const color = pending ? 'var(--color-system-warning)' : onDuty ? 'var(--color-system-success)' : 'var(--color-text-muted)';
  return (
    <tr className="hover:bg-[var(--color-surface-raised)]/40">
      <td className="px-5 py-3">
        <p className="font-medium text-foreground">{u.full_name ?? 'Unnamed responder'}</p>
        <p className="text-[12px] text-muted-foreground">{u.badge_id ? `Badge ${u.badge_id}` : 'No badge on file'}{u.agency_type && <> · {u.agency_type}</>}</p>
      </td>
      <td className="px-3 py-3">
        <span className="inline-flex items-center gap-1.5 text-[12.5px] font-medium" style={{ color }}>
          <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: color }} />
          {label}
        </span>
      </td>
      <td className="px-3 py-3 text-right font-semibold tabular-nums">{fmtInt(u.incidents)}</td>
      <td className="px-3 py-3 text-right tabular-nums text-[var(--color-text-secondary)]">{fmtInt(u.resolved)}</td>
      <td className="px-3 py-3 text-right tabular-nums text-[var(--color-text-secondary)]">{u.ack.n ? fmtMin(u.ack.avg) : '—'}</td>
      <td className="whitespace-nowrap px-5 py-3 text-right text-[12.5px]">
        {u.has_location ? (
          <span className="text-[var(--color-text-secondary)]">Seen {ago(u.location_updated_at)}</span>
        ) : (
          <span className="text-muted-foreground">No location shared</span>
        )}
      </td>
    </tr>
  );
}
