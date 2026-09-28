/**
 * CSV export of the Operational Area — the summary, the response measures, the
 * barangay table, the stations and the crew, in one file an admin can open in a
 * spreadsheet or hand to a superior.
 *
 * Built in the browser from the payload already on screen, so the file always
 * matches what the reader was looking at, filters and all.
 */

import type { OperationalArea } from '@/lib/api/operational-area';
import { periodLong } from './period';
import { SEVERITY_WORD, categoryLabel, outcomeLabel } from './kit';

/**
 * One CSV cell. Quotes are doubled, and a cell that begins with = + - or @ is
 * prefixed so a spreadsheet reads it as text: station and responder names are
 * typed by people, and a name that starts with "=" would otherwise run as a formula.
 */
export function csvCell(value: unknown): string {
  if (value === null || value === undefined) return '';
  let s = String(value);
  if (/^[=+\-@\t\r]/.test(s) && Number.isNaN(Number(s))) s = `'${s}`;
  return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

const row = (cells: unknown[]) => cells.map(csvCell).join(',');
const min = (m: number | null) => (m === null ? '' : m);

export function buildAreaCsv(d: OperationalArea): string {
  const k = d.kpis;
  const out: string[] = [];
  const section = (title: string, header: string[], rows: unknown[][]) => {
    out.push('', row([title.toUpperCase()]), row(header), ...rows.map(row));
  };

  out.push(row(['Ziren — Operational Area']));
  out.push(row(['Municipality', [d.area.municipality, d.area.province].filter(Boolean).join(', ')]));
  if (d.area.agency) out.push(row(['Agency', d.area.agency.name, d.area.agency.agency_type]));
  out.push(row(['Showing', d.filters.barangay ?? 'Whole municipality']));
  out.push(row(['Period', periodLong(d.filters)]));
  // A chosen range also goes in as two real dates, which a spreadsheet can filter and sort on.
  if (d.filters.date_from && d.filters.date_to) {
    out.push(row(['From', d.filters.date_from]));
    out.push(row(['To', d.filters.date_to]));
  }
  out.push(row(['Generated', d.generated_at]));

  section('Summary', ['Measure', 'Value'], [
    ['Reports', k.incidents],
    ['Reports in the previous period', k.previous_incidents ?? 'n/a (all time)'],
    ['Active now', k.active_now],
    ['Waiting for dispatch', k.awaiting_dispatch],
    ['Critical', k.critical],
    ['SOS', k.sos],
    ['Resolved', k.resolved],
    ['Cancelled', k.cancelled],
    ['Resolved share of closed (%)', k.resolved_rate ?? ''],
    ['False alarms', k.false_alarms],
    ['Dispatched within target (%)', k.dispatch_compliance ?? ''],
    ['Registered residents', k.residents],
    ['Verified residents', k.verified_residents],
    ['PWD residents', k.pwd_residents],
    ['Residents aged 60 or over', k.senior_residents],
    ['Children under 12', k.child_residents],
    ['Vulnerable residents (PWD, 60+ or under 12; each counted once)', k.vulnerable_residents],
    ['People injured', d.outcomes.casualties.injured],
    ['Transported', d.outcomes.casualties.transported],
    ['Fatalities', d.outcomes.casualties.fatal],
  ]);

  section('Response time (minutes)', ['Measure', 'Reports', 'Average', 'Median', '90th percentile', 'Slowest'], [
    ['Time to dispatch', k.dispatch.n, min(k.dispatch.avg), min(k.dispatch.p50), min(k.dispatch.p90), min(k.dispatch.max)],
    ['Time to accept', k.ack.n, min(k.ack.avg), min(k.ack.p50), min(k.ack.p90), min(k.ack.max)],
    ['Time to resolve', k.resolution.n, min(k.resolution.avg), min(k.resolution.p50), min(k.resolution.p90), min(k.resolution.max)],
  ]);

  section('Performance by severity', [
    'Severity', 'Reports', 'Dispatch target (min)', 'Median dispatch (min)', 'On time', 'Late', 'Waiting',
    'Within target (%)', 'Accept deadline (min)', 'Accepted in time (%)', 'Median resolve (min)',
  ], d.response.by_severity.filter(s => s.n > 0).map(s => [
    SEVERITY_WORD[s.severity], s.n, s.dispatch_target_min, min(s.dispatch.p50), s.on_time, s.late, s.awaiting,
    s.dispatch_compliance ?? '', s.ack_deadline_min, s.ack_compliance ?? '', min(s.resolution.p50),
  ]));

  section('Reports by type', ['Type', 'Reports'], Object.entries(d.mix.categories).sort(([, a], [, b]) => b - a).map(([c, n]) => [categoryLabel(c), n]));
  section('Outcomes', ['Outcome', 'Reports'], Object.entries(d.outcomes.counts).sort(([, a], [, b]) => b - a).map(([o, n]) => [outcomeLabel(o), n]));

  section('Barangays', ['Barangay', 'Residents', 'Verified', 'PWD', 'Aged 60+', 'Under 12', 'Vulnerable', 'Reports', 'Critical', 'Active', 'Last report'],
    d.barangays.items.map(b => [b.name, b.residents, b.verified, b.pwd, b.seniors, b.children, b.vulnerable, b.incidents, b.critical, b.active, b.last_incident_at ?? '']));
  out.push(row([
    'Note', `${d.barangays.unmatched_incidents} report(s) name no barangay and ${d.barangays.unlocated_incidents} have no address; they are in the totals but not in a barangay row.`,
  ]));

  section('Repeat locations', ['Place', 'Barangay', 'Reports', 'Critical', 'Mostly', 'Last report'],
    d.hotspots.map(h => [h.place, h.barangay ?? '', h.count, h.critical, categoryLabel(h.top_category), h.last_at ?? '']));

  section('Stations', ['Station', 'Agency', 'Type', 'Address', 'Latitude', 'Longitude', 'Reports', 'Average dispatch (min)'],
    d.stations.items.map(s => [s.name, s.agency_name, s.agency_type, s.address, s.lat, s.lng, s.incidents ?? '(not shown)', min(s.dispatch?.avg ?? null)]));

  section('Crew', ['Responder', 'Badge', 'Status', 'Reports handled', 'Resolved', 'Average accept time (min)'],
    d.responders.roster.map(u => [
      u.full_name, u.badge_id,
      u.approval_status === 'approved' ? (u.availability === 'on_duty' ? 'On duty' : 'Off duty') : u.approval_status,
      u.incidents, u.resolved, min(u.ack.avg),
    ]));

  section('Agencies here', ['Agency', 'Type', 'Contact number', 'Email', 'Stations'],
    d.agencies.map(a => [a.name, a.agency_type, a.contact_number, a.email, a.stations]));

  if (d.comparison) {
    section('Municipalities compared', ['Municipality', 'Barangays', 'Residents', 'Stations', 'Responders', 'On duty', 'Reports', 'Critical', 'Active'],
      d.comparison.map(c => [c.municipality, c.barangays, c.residents, c.stations, c.responders, c.on_duty, c.incidents, c.critical, c.active]));
  }
  return out.join('\r\n');
}

/** A filename an admin can sort a folder by: area, window, date. */
export function areaCsvName(d: OperationalArea, now = new Date()): string {
  const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  const window = d.filters.date_from && d.filters.date_to
    ? `${d.filters.date_from}_to_${d.filters.date_to}`
    : d.filters.days === 0 ? 'all-time' : `${d.filters.days}d`;
  const parts = ['operational-area', slug(d.area.municipality), d.filters.barangay ? slug(d.filters.barangay) : null, window, now.toISOString().slice(0, 10)];
  return `${parts.filter(Boolean).join('-')}.csv`;
}

export function downloadCsv(filename: string, csv: string): void {
  // The BOM makes Excel read the file as UTF-8, which the Filipino place names need.
  const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
