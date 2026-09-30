'use client';

/**
 * IncidentRecordTable — Incident Records, one row per incident.
 *
 * Incident History used to be a list of monitoring cards: an elapsed-time
 * clock, a "View" button, a dispatch-latency readout. That is how you WATCH
 * work, and history is not work — it is the record of it. This is the record:
 * a flat table where every fact about an incident is its own column, read
 * across, the way an agency's own logbook is.
 *
 * WHAT EACH COLUMN IS FOR
 *
 *   Record no.   The citable identity, ZIR-2026-000123. A dispatcher reading a
 *                record out over the radio, or a station quoting it on a form,
 *                needs this and not a UUID.
 *   Type         What kind of emergency, plus an SOS marker — an SOS is a
 *                different kind of report, not a severity.
 *   Report       What the resident actually said, two lines of it. The full
 *                text is on hover and in the record panel.
 *   Location     The address the report was filed with, and the municipality
 *                of the station that answered. NOT a barangay: incidents do
 *                not store one, and a guessed barangay on an official record is
 *                worse than none.
 *   Agency /     Provincial Admin only. An Agency Admin's rows all share one
 *   Station      agency, so the column would repeat one value down the page.
 *   Reported     The date with the time under it, in one column. They were two
 *                columns, which pushed Status off the right edge of a laptop
 *                screen; stacked, the date still reads down the page by day and
 *                the hour still sits beside it for matching against a logbook.
 *   Severity     A word inside the chip as well as a colour. Never colour alone.
 *   Status       Dot plus word, for the same reason.
 *   Responder    Who was sent. A name, not an id.
 *   Outcome      What the crew found on closing. Empty until the incident is
 *                closed, and empty is correct: no other column can be filled
 *                in by inference.
 *
 * Dates and times are written the way a record is — 2026-01-25 and 04:30 —
 * not "3 months ago". A relative age is right for open work and meaningless in
 * an archive, where it goes stale the moment the page is read.
 *
 * Nothing here can dispatch or change an incident. Opening a row opens the
 * record panel, which is read-only in history mode.
 */

import { useEffect, useRef, useState } from 'react';
import { Building2, CheckCircle2, FilePenLine, FileText, MapPin, Mic } from 'lucide-react';
import { OUTCOME_LABEL, type HistoryIncident } from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { recordReportText, withoutVoicePlaceholder } from '@/lib/incidents/report-text';
import { formatDate, formatTime } from '@/lib/format/datetime';
import { DISPLAY_DEFAULTS, displayPrefs, type DisplayPrefs } from '@/lib/prefs/definitions';
import { AGENCY_ICON, AG_COLOR, sevOf, shortId, statusLabel } from './incident-vocabulary';
import {
  CategoryTile, SeverityChip, SosChip, StatusPill, TABLE_HEAD_CELL,
} from './incident-table-parts';

/**
 * Everything a row shows, as one lower-case string to search.
 *
 * The search box used to match only the stored report text, the address, the
 * reporter's name and the UUID — so it could not find a record by the number in
 * the first column, or by a responder, a station, a status or a type, all of
 * which are plainly on screen. And because it read the RAW report text, typing
 * "voice recording" matched every voice report through words the table no
 * longer shows. A search should find what the reader can see, so this is built
 * from the same pieces the row renders.
 *
 * For a voice report both readings are included — what was heard and the
 * corrected spelling — so a dispatcher who types "sunoog" or "sunog" finds it.
 */
export function recordSearchText(i: HistoryIncident, display: DisplayPrefs = displayPrefs.get()): string {
  const report = recordReportText(i.report_text, i.signals);
  const category = i.incident_category;
  return [
    i.record_number,
    `INC-${shortId(i.id)}`,
    i.id.replace(/-/g, ''),
    report.text,
    // The transcript as heard, alongside the corrected reading shown above.
    withoutVoicePlaceholder(i.report_text),
    i.signals?.transcript?.text,
    i.location_address,
    i.stations?.agencies?.municipality,
    i.stations?.name,
    i.stations?.agencies?.agency_type,
    category && category !== 'other' ? CATEGORY_LABELS[category] : 'uncategorised',
    i.sos_flagged ? 'sos' : null,
    sevOf(i) ?? 'untriaged',
    statusLabel(i.status),
    i.responder?.full_name,
    i.users?.full_name,
    i.outcome ? OUTCOME_LABEL[i.outcome] : null,
    formatDate(i.created_at, display),
    formatTime(i.created_at, display),
  ]
    .filter((part): part is string => typeof part === 'string' && part !== '')
    .join('\n')
    .toLowerCase();
}

interface Column {
  key: string;
  label: string;
  /** Width in px. The table's minimum width is their sum, so nothing is ever
   *  squeezed below it — see the note on the wrapper below. */
  width: number;
  /** Shown only to Provincial Admin. */
  provincialOnly?: boolean;
}

/**
 * Widths are a budget, not a suggestion. The table area is only about 1,120px
 * at a 1440px screen (the sidebar takes the rest), and eleven columns do not
 * fit in it. The first draft gave every column but Report a fixed width and let
 * Report take "whatever is left", which was almost nothing: the one column that
 * carries what the resident actually said was cut to two words, and Outcome fell
 * off the right edge entirely. Report now has a real width (300px, about sixty
 * characters over its two lines) and the table scrolls sideways for the rest.
 *
 * 2026-09-30: everything up to and including Status now fits a 1440px screen
 * without scrolling (1,080px of the 1,118 available). Before, Status was cut
 * in half by the right edge, so the one column that says how a report ended
 * needed a sideways scroll to read.
 */
const COLUMNS: Column[] = [
  { key: 'record',    label: 'Record no.',       width: 148 },
  { key: 'type',      label: 'Type',             width: 150 },
  { key: 'report',    label: 'Report',           width: 270 },
  { key: 'location',  label: 'Location',         width: 180 },
  { key: 'agency',    label: 'Agency / Station', width: 168, provincialOnly: true },
  { key: 'reported',  label: 'Reported',         width: 104 },
  { key: 'severity',  label: 'Severity',         width: 112 },
  { key: 'status',    label: 'Status',           width: 116 },
  { key: 'responder', label: 'Responder',        width: 132 },
  { key: 'outcome',   label: 'Outcome',          width: 150 },
  // Resolved rows only — see _Row. The PNP-blotter-style prose account an
  // Agency Admin files after the fact, distinct from Outcome's brief tally.
  // Headed "Narrative report" so the short button labels under it ("Write",
  // "Draft", "Filed") cannot be mistaken for the resident's own Report column.
  { key: 'narrative', label: 'Narrative report', width: 136 },
];

/** The first column stays put while the rest scroll under it, so a row is
 *  still identified by its record number however far right the reader is. The
 *  hover fill is repeated on the cell because a sticky cell paints over the
 *  row's own background.
 *
 *  This cell's row rule is drawn along its TOP edge as an inset shadow, not as
 *  the bottom border every other cell has. A pinned cell sits on its own
 *  compositing layer and paints over what is beneath it, and the cell of the
 *  next row starts a fraction of a pixel early on any row whose height is not a
 *  whole number of pixels — enough to paint over the last pixel of the cell
 *  above and take the rule with it. That showed as a break in the divider under
 *  this one column, on some rows only. A cell always paints its own top edge, so
 *  a rule there cannot be covered by its neighbour. The first row has none: the
 *  header's own border is already directly above it. */
const STICKY_CELL =
  'sticky left-0 z-[1] bg-card border-b-0! ' +
  'shadow-[1px_0_0_var(--color-surface-border),inset_0_1px_0_var(--color-surface-border)] ' +
  'group-first:shadow-[1px_0_0_var(--color-surface-border)] ' +
  'group-hover:bg-[var(--color-surface-hover)]';

export function IncidentRecordTable({
  rows,
  isProvincialAdmin,
  onOpen,
  onNarrative,
  display = DISPLAY_DEFAULTS,
  reserveBottom = 32,
}: {
  rows: HistoryIncident[];
  isProvincialAdmin: boolean;
  onOpen: (id: string) => void;
  /** Opens the Narrative Report directly — see the column's own note. */
  onNarrative: (id: string) => void;
  /** Date and time preferences. Passed down once rather than subscribed to by
   *  every row. */
  display?: DisplayPrefs;
  /** Pixels to leave under the table — the page's bottom padding, plus the
   *  pager when there is one. */
  reserveBottom?: number;
}) {
  const columns = COLUMNS.filter(c => !c.provincialOnly || isProvincialAdmin);
  const tableWidth = columns.reduce((sum, c) => sum + c.width, 0);

  // Two things are measured off the scroll box, both in the one place that
  // already watches it:
  //
  //  1. Whether there is more table off the right edge. A thin scrollbar alone
  //     is not enough of a cue: on a 1440px screen Status, Responder and Outcome
  //     sit past the edge, and nothing else says so. The fade below is drawn
  //     only while there is something to scroll to, so it never lies about a
  //     table that fits.
  //
  //  2. How tall the box may be. See `maxHeight` below.
  const scrollRef = useRef<HTMLDivElement>(null);
  const [moreToRight, setMoreToRight] = useState(false);
  const [maxHeight, setMaxHeight] = useState<number | undefined>(undefined);
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    /** The nearest ancestor that scrolls vertically — the page's own scroller,
     *  not the window, in this app's shell. */
    let scroller: HTMLElement | null = el.parentElement;
    while (scroller) {
      const oy = getComputedStyle(scroller).overflowY;
      if (oy === 'auto' || oy === 'scroll') break;
      scroller = scroller.parentElement;
    }

    const measure = () => {
      setMoreToRight(el.scrollLeft + el.clientWidth < el.scrollWidth - 1);
      // Where the box sits with the page scrolled to its very top, so the
      // answer does not depend on how far down the reader happens to be when a
      // resize fires.
      const topAtRest = el.getBoundingClientRect().top + (scroller?.scrollTop ?? 0);
      setMaxHeight(Math.max(280, Math.floor(window.innerHeight - topAtRest - reserveBottom)));
    };
    measure();
    el.addEventListener('scroll', measure, { passive: true });
    window.addEventListener('resize', measure);
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    if (el.parentElement) ro.observe(el.parentElement);
    return () => {
      el.removeEventListener('scroll', measure);
      window.removeEventListener('resize', measure);
      ro.disconnect();
    };
  }, [rows.length, tableWidth, reserveBottom]);

  return (
    // Wider than a laptop screen once eleven columns are in it. It scrolls
    // sideways inside its own frame rather than wrapping cells into tall rows —
    // a record table whose rows are different heights cannot be read across.
    // The frame is the outer div so the fade stays fixed to the edge while the
    // table scrolls under it.
    <div
      className="relative overflow-hidden rounded-[var(--radius-card)] border bg-card shadow-[var(--shadow-card)]"
      style={{ borderColor: 'var(--color-surface-border)' }}
    >
      {/* THE HEADER STAYS PUT, so this box is also the vertical scroll area.
          A sticky header sticks to its nearest scrolling ancestor, and a box
          that only scrolls sideways is still, per the CSS overflow rules, a
          scroll container on the other axis too — so a header inside it sticks
          to THE BOX, which never scrolls vertically, and rides away with the
          page. (The live queue's table hit exactly this and gave up on a sticky
          header.) The fix is to let this box scroll vertically as well, and to
          size it to the screen: its height is whatever is left under the filter
          bar and summary, so the rows scroll in here and the column names stay
          above them, with the sticky first column pinned in the corner. */}
      <div
        className="scroll-slim overflow-auto"
        ref={scrollRef}
        style={{ maxHeight }}
      >
        <table
          className="w-full border-separate border-spacing-0 text-left"
          style={{ minWidth: tableWidth }}
        >
          <colgroup>
            {columns.map(c => (
              <col key={c.key} style={{ width: c.width }} />
            ))}
          </colgroup>
          <thead>
            <tr className="[&>th]:border-b [&>th]:border-[var(--color-border-strong)]">
              {columns.map((c, i) => (
                <th
                  className={[
                    // Opaque, or rows would show through as they scroll under.
                    // Above the body's sticky first column (z-1); the corner cell
                    // is above both, since it is the one that pins on both axes.
                    'sticky top-0', TABLE_HEAD_CELL,
                    i === 0
                      ? 'left-0 z-[4] shadow-[1px_0_0_var(--color-surface-border)]'
                      : 'z-[3]',
                  ].join(' ')}
                  key={c.key}
                  scope="col"
                >
                  {c.label}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map(inc => (
              <_Row
                display={display}
                incident={inc}
                isProvincialAdmin={isProvincialAdmin}
                key={inc.id}
                onNarrative={onNarrative}
                onOpen={onOpen}
              />
            ))}
          </tbody>
        </table>
      </div>
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-y-0 right-0 w-12 transition-opacity duration-200"
        style={{
          background: 'linear-gradient(to left, var(--color-surface-card), transparent)',
          opacity: moreToRight ? 1 : 0,
        }}
      />
    </div>
  );
}

function _Row({
  incident,
  isProvincialAdmin,
  onOpen,
  onNarrative,
  display,
}: {
  incident: HistoryIncident;
  isProvincialAdmin: boolean;
  onOpen: (id: string) => void;
  onNarrative: (id: string) => void;
  display: DisplayPrefs;
}) {
  const sev = sevOf(incident);

  const category = incident.incident_category;
  const categoryLabel =
    category && category !== 'other' ? (CATEGORY_LABELS[category] ?? null) : null;

  const agType = incident.stations?.agencies?.agency_type ?? null;
  const agColor = agType ? (AG_COLOR[agType] ?? 'var(--color-brand)') : 'var(--color-text-muted)';
  const AgencyIcon = agType ? (AGENCY_ICON[agType] ?? Building2) : Building2;
  const stationName = incident.stations?.name ?? null;
  const municipality = incident.stations?.agencies?.municipality ?? null;

  // A backend that predates migration 035 has no record_number. Fall back to
  // the short id rather than render "undefined" in the first column.
  const recordNo = incident.record_number ?? `INC-${shortId(incident.id)}`;

  const responderName =
    incident.responder?.full_name ??
    (incident.assigned_responder_id ? 'Assigned' : null);

  const injured = incident.casualties_injured ?? 0;
  const fatal = incident.casualties_fatal ?? 0;

  const report = recordReportText(incident.report_text, incident.signals);

  return (
    // The row rules are on the CELLS, not the row: the table is border-separate
    // (a sticky header loses its border under border-collapse, because the
    // border belongs to the table and does not travel with the cell), and a
    // <tr> border does nothing in that mode.
    <tr
      className="group cursor-pointer align-middle transition-colors hover:bg-[var(--color-surface-hover)] [&>td]:border-b [&>td]:border-[var(--color-surface-border)] last:[&>td]:border-b-0"
      onClick={() => onOpen(incident.id)}
    >
      {/* The record number is the row's real button. The <tr> click above is a
          convenience for the mouse; this is what a keyboard and a screen
          reader reach, so opening a record never depends on the pointer. */}
      <td className={`px-3 py-2.5 ${STICKY_CELL}`}>
        <button
          className="font-mono text-[12.5px] font-semibold tabular-nums whitespace-nowrap text-foreground hover:underline focus-visible:underline focus-visible:outline-none"
          onClick={e => { e.stopPropagation(); onOpen(incident.id); }}
          type="button"
        >
          {recordNo}
        </button>
      </td>

      <td className="px-3 py-2.5">
        <div className="flex items-center gap-2.5">
          <CategoryTile category={category} />
          <div className="flex min-w-0 flex-col items-start gap-1">
            <span className="text-[13px] leading-tight font-medium text-foreground">
              {categoryLabel ?? 'Uncategorised'}
            </span>
            {incident.sos_flagged && <SosChip />}
          </div>
        </div>
      </td>

      <td className="px-3 py-2.5">
        {/* Two lines of what the resident said; hover for all of it. The full
            text is one click away in the record panel, so this column only has
            to be enough to recognise the report by.
            A voice report is stored as "<Category> — reported by voice
            recording — <what was heard>": the app's own scaffolding, then the
            transcript. Only what was said belongs in this column (the corrected
            reading where the spelling pass changed something), so the prefix is
            dropped and a small microphone says how it was reported instead. */}
        {report.kind === 'voice-untranscribed' ? (
          <p
            className="flex items-center gap-1.5 text-[13px] italic leading-snug text-muted-foreground"
            title="A voice recording was filed with this report but it has no transcript."
          >
            <Mic aria-hidden="true" className="shrink-0" size={13} />
            Voice report — no transcript
          </p>
        ) : (
          <p
            className="line-clamp-2 text-[13px] leading-snug text-foreground"
            title={report.text}
          >
            {report.kind === 'voice' && (
              <Mic
                aria-label="Reported by voice recording"
                className="mr-1.5 inline-block align-[-2px] text-muted-foreground"
                role="img"
                size={13}
              />
            )}
            {report.text}
          </p>
        )}
      </td>

      <td className="px-3 py-2.5">
        <div className="flex flex-col gap-0.5 text-[12.5px] leading-snug">
          <span className="flex items-start gap-1.5 text-foreground">
            <MapPin aria-hidden="true" className="mt-0.5 shrink-0 text-muted-foreground" size={12} />
            {/* Stated, not blank: a record with no location is a fact about the
                record, and an empty cell reads as a rendering fault. */}
            <span className="line-clamp-2" title={incident.location_address ?? undefined}>
              {incident.location_address ?? 'No location given'}
            </span>
          </span>
          {municipality && (
            <span className="pl-[18px] text-muted-foreground">{municipality}</span>
          )}
        </div>
      </td>

      {isProvincialAdmin && (
        <td className="px-3 py-2.5">
          <span
            className="flex items-center gap-1.5 text-[12.5px] font-semibold"
            style={{ color: agColor }}
            title={agType && stationName ? `${agType} · ${stationName}` : undefined}
          >
            <AgencyIcon aria-hidden="true" className="shrink-0" size={14} />
            <span className="truncate">{stationName ?? 'Unassigned'}</span>
          </span>
        </td>
      )}

      <td className="px-3 py-2.5 font-mono tabular-nums whitespace-nowrap">
        <span className="block text-[12.5px] leading-tight text-foreground">
          {formatDate(incident.created_at, display)}
        </span>
        <span className="mt-0.5 block text-[11.5px] leading-tight text-muted-foreground">
          {formatTime(incident.created_at, display)}
        </span>
      </td>

      <td className="px-3 py-2.5">
        {/* Icon and word inside the chip — severity is never colour alone. */}
        <SeverityChip severity={sev} />
      </td>

      <td className="px-3 py-2.5">
        {/* Dot plus word, for the same reason. */}
        <StatusPill status={incident.status} />
      </td>

      <td className="px-3 py-2.5 text-[12.5px]">
        {responderName ? (
          <span className="line-clamp-2 text-foreground">{responderName}</span>
        ) : (
          <span className="text-muted-foreground">—</span>
        )}
      </td>

      <td className="px-3 py-2.5 text-[12.5px]">
        {incident.outcome ? (
          <div className="flex flex-col gap-0.5">
            {/* An outcome this build has no label for is shown as stored. The
                cell used to render empty, which reads as "no outcome". */}
            <span className="text-foreground">{OUTCOME_LABEL[incident.outcome] ?? incident.outcome.replace(/_/g, ' ')}</span>
            {(injured > 0 || fatal > 0) && (
              <span className="font-mono text-[11.5px] tabular-nums whitespace-nowrap text-muted-foreground">
                {injured > 0 && `${injured} injured`}
                {injured > 0 && fatal > 0 && ' · '}
                {fatal > 0 && (
                  <span
                    className="font-bold"
                    style={{ color: 'var(--color-severity-critical)' }}
                  >
                    {fatal} fatal
                  </span>
                )}
              </span>
            )}
          </div>
        ) : (
          <span className="text-muted-foreground">—</span>
        )}
      </td>

      <td className="px-3 py-2.5">
        {/* Resolved only — a narrative report describes what happened, and
            nothing has happened in the past tense on a report still open.
            incident_narrative_service.save_narrative_report enforces the
            same rule with a 409, this just never offers the dead end.

            The label and colour name which of three states this row is in
            — not just "open the thing" every time — so a reader scanning
            the column can tell which resolved incidents still need a
            report written up without opening each one. Colours match the
            same DRAFT/FINALIZED badge the report's own page shows once
            it's open, so the two never disagree about what a state means. */}
        {incident.status === 'resolved' ? (
          <_NarrativeButton
            onClick={() => onNarrative(incident.id)}
            status={incident.narrative_report_status ?? null}
          />
        ) : (
          <span className="text-muted-foreground">—</span>
        )}
      </td>
    </tr>
  );
}

/** null = not started, 'draft' = written but not signed off, 'finalized' =
 *  signed off (still editable — see NarrativeEditor's own comment on
 *  why finalizing doesn't lock the form). */
function _NarrativeButton({
  status,
  onClick,
}: {
  status: 'draft' | 'finalized' | null;
  onClick: () => void;
}) {
  const { label, hint, icon: Icon, color } =
    status === 'finalized'
      ? { label: 'Filed', hint: 'View the finalized narrative report', icon: CheckCircle2, color: 'var(--color-system-success)' }
      : status === 'draft'
        ? { label: 'Draft', hint: 'Continue the draft narrative report', icon: FilePenLine, color: 'var(--color-system-warning)' }
        : { label: 'Write', hint: 'Create the narrative report', icon: FileText, color: 'var(--color-brand)' };

  return (
    <button
      aria-label={hint}
      className="inline-flex items-center gap-1.5 rounded-[8px] border px-2.5 py-1.5 text-[11.5px] leading-none font-semibold whitespace-nowrap transition-colors hover:brightness-105"
      onClick={e => { e.stopPropagation(); onClick(); }}
      title={hint}
      style={{
        color,
        borderColor: `color-mix(in srgb, ${color} 40%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${color} 8%, transparent)`,
      }}
      type="button"
    >
      <Icon aria-hidden="true" size={13} />
      {label}
    </button>
  );
}
