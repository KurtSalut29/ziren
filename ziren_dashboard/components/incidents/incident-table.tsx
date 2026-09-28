'use client';

/**
 * IncidentTable — the queue as three short lines instead of one long one.
 *
 * WHAT WENT WRONG WITH THE FIRST TWO ATTEMPTS
 *
 * The card list was unreadable past a dozen reports, so it became one table
 * ranked #1…#26 by severity and then by age. That fixed the scrolling and
 * introduced a worse problem: the ranking did not match how the people using
 * it think. Asked what order the queue is worked in, the dispatcher answered
 * "kung sino ang nauna" — whoever arrived first. The console's #1 was often
 * NOT the earliest report, because severity outranked age, and nothing on the
 * screen said so. A number that contradicts the reader's own rule, set in the
 * typeface of a fact, is worse than no number at all.
 *
 * WHAT THIS DOES INSTEAD
 *
 *   1. THREE GROUPS, in the order they are worked: critical, then high, then
 *      everything else. Three is a number a person can hold. Twenty-six ranks
 *      is not, and nobody ever worked #17 as #17.
 *
 *   2. INSIDE A GROUP, STRICTLY FIRST COME FIRST SERVED. #1 is the oldest
 *      report in that group, every time, with no exceptions to explain. The
 *      rule the dispatcher already believes is the rule the screen follows.
 *
 * Severity no longer re-ranks anything, because it no longer has to: it
 * decides which GROUP a report is in, and the groups are worked in order. The
 * one comparison that used to need explaining — why a three-minute critical
 * sits above a three-hour high — is answered by a heading rather than by
 * arithmetic the reader has to redo on every row.
 *
 * The dispatch target survives, demoted to what it is actually good at: a
 * WARNING. It paints the waiting clock and adds a LATE flag. It sorts nothing,
 * so it can never contradict the headings above it.
 *
 * Severity stays a WORD as well as a colour, per the console's colour rules.
 */

import Link from 'next/link';
import {
  Building2, MapPin, MoreHorizontal, Siren, Tag,
  UserPlus, UserRound,
} from 'lucide-react';
import type { QueueIncident } from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { AckBadge, isAckOverdue } from './ack-badge';
import {
  AGENCY_ICON, AG_COLOR, AWAITING_STATUSES, CATEGORY_ICON, SEV_COLOR,
  STATUS_STYLE, dueState, longestWait, sevOf, shortId, statusLabel, timeShort,
  urgencyTimeColor,
} from './incident-vocabulary';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/efferd/ui/dropdown-menu';

/**
 * The columns, with the question each one answers.
 *
 * The `title` is not decoration: a dispatcher meeting this table for the first
 * time has to learn what "#" means before the number is worth anything, and a
 * legend under the table is a legend nobody reads.
 *
 * The "agency" column is a function of role, not a fixed label. Every row an
 * Agency Admin ever sees belongs to their own one agency — the column earns
 * its place there. Every row a Provincial Admin sees shares their own one
 * agency_type instead (that's the whole scope), so the genuinely
 * distinguishing fact for THEM is which of their agency's stations handled
 * it — see incident-vocabulary.ts's stationOf. Same column position, same
 * icon/colour, different fact in the cell.
 */
function columnsFor(
  isProvincialAdmin: boolean,
): { key: string; label: string; help: string; align?: 'right' }[] {
  return [
    // Dropped for Provincial Admin, not just relabelled — matches the same
    // conditional in the <colgroup> above and the row's own pos <td> below.
    // All three MUST agree on column count, or every header past this one
    // silently shifts left of the data cell it's supposed to sit over.
    ...(isProvincialAdmin
      ? []
      : [{ key: 'pos', label: '#', help: 'Place within this group, oldest first. #1 arrived before every other report in the same group.' }]),
    { key: 'incident', label: 'Incident', help: 'What was reported, and the rule that set its severity.' },
    { key: 'location', label: 'Location', help: 'The address resolved from the coordinates the report carried.' },
    // Only for a Provincial Admin. Every row an Agency Admin sees belongs to
    // their own agency, so a column repeating it on every line is noise.
    ...(isProvincialAdmin
      ? [{ key: 'agency', label: 'Station', help: 'Which of your agency’s stations this report was routed to.' }]
      : []),
    { key: 'status',   label: 'Status',   help: 'Where the report is in the workflow — separate from how severe it is.' },
    { key: 'waiting',  label: 'Waiting',  help: 'How long the reporter has been waiting since it landed. Amber near this severity’s dispatch target, red past it.' },
    { key: 'actions',  label: '',         help: 'Actions', align: 'right' },
  ];
}

/** The three lines the queue is worked in, worst first. */
export type GroupKey = 'critical' | 'high' | 'other';

export const GROUP_META: Record<
  GroupKey,
  {
    label: string;
    instruction: string;
    /**
     * A Provincial Admin never dispatches, so "Dispatch these first" reads
     * as an instruction to someone who has no dispatch action on this page
     * at all — see the role branch a few lines below in _Row. Same fact,
     * stated as what should already be happening rather than what to do.
     */
    provincialAdminInstruction: string;
    color: string;
  }
> = {
  critical: {
    label: 'Critical',
    instruction: 'Dispatch these first',
    provincialAdminInstruction: 'Should be dispatched first',
    color: 'var(--color-severity-critical)',
  },
  high: {
    label: 'High',
    instruction: 'After the critical ones',
    provincialAdminInstruction: 'Should follow the critical ones',
    color: 'var(--color-severity-high)',
  },
  other: {
    // The severity WORDS are kept. They are the vocabulary the rubric, the
    // mobile app and the printed reports all share, and renaming them here to
    // something friendlier would leave two names for one thing.
    label: 'Medium, low & untriaged',
    instruction: 'When a crew frees up',
    provincialAdminInstruction: 'Lower priority',
    color: 'var(--color-text-muted)',
  },
};

export function groupOf(incident: QueueIncident): GroupKey {
  const s = sevOf(incident);
  return s === 'critical' ? 'critical' : s === 'high' ? 'high' : 'other';
}

export function IncidentTable({
  rows,
  position,
  nextId,
  newIds,
  grouped,
  isProvincialAdmin,
  onOpen,
}: {
  rows: QueueIncident[];
  /** id → place within its own group, oldest first. Absent once dispatched. */
  position: Map<string, number>;
  /**
   * The one report to take next: first in the first group that has anything.
   *
   * Every group starts at #1, so without this there would be two or three
   * rows wearing a #1 and no way to tell which of them is the actual next
   * job. Only this row is tinted. The other #1s keep their number, because
   * within their own group that is still exactly what they are.
   */
  nextId: string | null;
  newIds: Set<string>;
  /**
   * Draw the group headings.
   *
   * Off when the reader has asked for newest-first, where the groups
   * interleave and a heading would appear every second row — a heading that
   * repeats is not a heading.
   */
  grouped: boolean;
  isProvincialAdmin: boolean;
  onOpen: (id: string) => void;
}) {
  // ALWAYS overflow-x-auto, not lg:overflow-x-visible. That toggle assumed
  // "lg and up" meant "wide enough that the 900px table always fits" — it
  // does not. This page's own chrome already spends most of a 1024px (lg)
  // viewport before the table gets a pixel: the shell nav (236px expanded)
  // + this page's own padding (2×28px) + the QueueOverview rail (268px)
  // + its gap (16px) is ~584px gone before the table starts, leaving ~440px
  // for something that needs 900. The table was overflowing its own rounded
  // card with no scrollbar to reach the rest — reported 2026-09-15 as
  // content "cannot be seen" at ordinary laptop widths, and worse at any
  // browser zoom above 100% (zooming in shrinks the effective CSS viewport
  // the same way a narrower window would). True fit without scrolling only
  // starts around a ~1536px+ viewport with the nav expanded — there is no
  // sane breakpoint below that where turning the scrollbar off is safe.
  //
  // The risk being traded away: the comment this replaced warned that an
  // always-on overflow-x-auto turns this div into a scroll container, which
  // can change what a `position: sticky` descendant sticks relative to. In
  // practice this div is never height-constrained — it is always exactly as
  // tall as the table, so its own scrollport never has an independent
  // vertical offset to stick against, and the header should keep tracking
  // page scroll as before. Worth confirming the sticky header still follows
  // correctly on a long table now that this is live; that regression would
  // be far more recoverable than the reported one (content with no way to
  // reach it at all).
  return (
    <div className="scroll-slim overflow-x-auto">
      <table className="w-full min-w-[760px] border-collapse text-left">
        <colgroup>
          {/* Provincial Admin drops the # column — there's no working order
              to have a place in when nothing here is ever dispatched. */}
          {!isProvincialAdmin && <col className="w-[64px]" />}
          <col />
          <col className="w-[200px]" />
          {isProvincialAdmin && <col className="w-[132px]" />}
          <col className="w-[148px]" />
          <col className="w-[96px]" />
          <col className="w-[48px]" />
        </colgroup>
        <thead>
          <tr className="[&>th]:border-b [&>th]:border-[var(--color-surface-border)]">
            {columnsFor(isProvincialAdmin).map(c => (
              <th
                /* NOT sticky any more. This wrapper is now unconditionally
                   overflow-x-auto (see the div below) so the table is never
                   silently unreachable when it doesn't fit — but a sticky
                   descendant sticks relative to its nearest scroll-container
                   ancestor, and overflow-x-auto makes THIS div that ancestor
                   (per the CSS overflow spec, setting only one axis forces
                   the other to compute as auto too), not the page. The
                   result, seen live 2026-09-15: the header re-anchored
                   105px below the top of a container that never itself
                   scrolls, rendering stuck in the middle of the table on top
                   of row content instead of floating above it. A header
                   that scrolls normally with the page is a smaller loss than
                   one that renders in the wrong place. */
                className={[
                  'bg-[var(--color-surface-card)] px-3 py-2.5',
                  'text-section-label font-semibold whitespace-nowrap',
                  c.align === 'right' ? 'text-right' : 'text-left',
                ].join(' ')}
                key={c.key}
                scope="col"
                style={{ color: 'var(--color-text-tertiary)' }}
                title={c.help}
              >
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((inc, i) => {
            const group = groupOf(inc);
            // A heading whenever the group changes, which on a page in working
            // order means at most three times. `rows` arrives ordered, so this
            // is a comparison with the row above rather than a second grouping
            // pass that could disagree with the first.
            const startsGroup =
              grouped && (i === 0 || groupOf(rows[i - 1]) !== group);

            return (
              <_Fragment key={inc.id}>
                {startsGroup && (
                  <_GroupHeading
                    group={group}
                    isProvincialAdmin={isProvincialAdmin}
                    rows={rows.filter(r => groupOf(r) === group)}
                  />
                )}
                <_Row
                  incident={inc}
                  isNew={newIds.has(inc.id)}
                  isNext={inc.id === nextId}
                  isProvincialAdmin={isProvincialAdmin}
                  onOpen={onOpen}
                  position={position.get(inc.id)}
                />
              </_Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

/** A keyed fragment, so a heading and its row can share one key. */
function _Fragment({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}

/**
 * The heading that answers "why is this one above that one".
 *
 * It carries the instruction, not only the label. "Critical" is a
 * classification; "Dispatch these first" is what to do about it, and the
 * second is what a dispatcher under pressure is actually reading for.
 */
function _GroupHeading({
  group,
  rows,
  isProvincialAdmin,
}: {
  group: GroupKey;
  rows: QueueIncident[];
  isProvincialAdmin: boolean;
}) {
  const meta = GROUP_META[group];
  const instruction = isProvincialAdmin ? meta.provincialAdminInstruction : meta.instruction;
  const waited = longestWait(rows);
  return (
    <tr>
      <th
        className="border-y border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3 py-1.5 text-left"
        colSpan={columnsFor(isProvincialAdmin).length}
        scope="colgroup"
      >
        <span className="flex flex-wrap items-center gap-x-2.5 gap-y-1">
          <span
            aria-hidden="true"
            className="size-2 shrink-0 rounded-full"
            style={{ backgroundColor: meta.color }}
          />
          <span
            className="text-[11.5px] font-bold tracking-wide uppercase"
            style={{ color: meta.color }}
          >
            {meta.label}
          </span>
          <span className="text-meta text-muted-foreground" title={instruction}>
            {rows.length} waiting
            {waited && ` · longest ${waited}`}
          </span>
        </span>
      </th>
    </tr>
  );
}

function _Row({
  incident,
  position,
  isNext,
  isNew,
  isProvincialAdmin,
  onOpen,
}: {
  incident: QueueIncident;
  position?: number;
  isNext: boolean;
  isNew: boolean;
  isProvincialAdmin: boolean;
  onOpen: (id: string) => void;
}) {
  const sev = sevOf(incident);
  const sevColor = sev ? (SEV_COLOR[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
  const agType = incident.stations?.agencies?.agency_type ?? null;
  const agColor = agType ? (AG_COLOR[agType] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
  const AgencyIcon = agType ? (AGENCY_ICON[agType] ?? Building2) : UserRound;
  // Every row a Provincial Admin sees already shares their own agency_type —
  // the station is the fact that actually varies row to row for them.
  const stationName = incident.stations?.name ?? null;
  const wholeLabel = isProvincialAdmin ? (stationName ?? 'Unrouted') : (agType ?? 'Unrouted');
  const sc = STATUS_STYLE[incident.status] ?? STATUS_STYLE.received;
  const category = incident.incident_category;
  const CategoryIcon = category ? (CATEGORY_ICON[category] ?? Tag) : Tag;
  const categoryLabel =
    category && category !== 'other' ? (CATEGORY_LABELS[category] ?? null) : null;
  const overdue = isAckOverdue(incident.ack);
  const waiting = AWAITING_STATUSES.includes(incident.status);
  const due = dueState(incident);
  const late = waiting && due.bucket === 'late';

  // Time alone reads as "this morning" no matter how old the report actually
  // is — a report 13 days late still just said "09:34", indistinguishable
  // from one that landed nine minutes ago. The date only earns its place
  // once it's not today; today's reports stay exactly as compact as before.
  const createdAt = new Date(incident.created_at);
  const receivedToday = createdAt.toDateString() === new Date().toDateString();
  const received = receivedToday
    ? createdAt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
    : `${createdAt.toLocaleDateString([], { month: 'short', day: 'numeric' })}, ${
        createdAt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      }`;

  return (
    <tr
      className="group border-b border-[var(--color-surface-border)] align-top transition-colors last:border-b-0 hover:bg-[var(--color-surface-hover)]"
      // What "Show in list" scrolls to - see ActiveIncidentsView.
      data-incident-id={incident.id}
      data-new={isNew ? '' : undefined}
      style={{
        // The row at the head of a group is tinted in THAT group's colour, not
        // in red. On a quiet shift the only thing waiting may be a medium one,
        // and painting it critical-red would be the console shouting a
        // severity the incident does not have. A report that has just arrived
        // gets a soft brand wash instead, so it can be found in a long list.
        backgroundColor: isNext
          ? `color-mix(in srgb, ${sevColor} 7%, transparent)`
          : isNew
            ? 'color-mix(in srgb, var(--color-brand) 8%, transparent)'
            : undefined,
      }}
    >
      {/* ── Place in this group ─────────────────────────────────
          Provincial Admin drops this cell entirely, not just its content —
          there's no working order to have a place in when nothing on this
          page is ever dispatched. The overdue signal this cell's accent bar
          used to also carry isn't lost: the Waiting column already renders
          its own independent LATE flag off the same `overdue`/`late` state,
          colour AND text, not just this bar. */}
      {!isProvincialAdmin && (
        <td className="relative px-3 py-3">
          {/* The accent bar sits on the first cell rather than on the row: a
              border-left on a <tr> is not painted by every engine at
              border-collapse, which is how this stripe silently disappeared in
              the first draft. */}
          {(isNext || overdue) && (
            <span
              aria-hidden="true"
              className="absolute top-0 bottom-0 left-0 w-[3px]"
              style={{
                backgroundColor: overdue ? 'var(--color-severity-critical)' : sevColor,
              }}
            />
          )}
          {position === undefined ? (
            <span
              className="text-meta text-muted-foreground"
              title="Already with a crew — not waiting on a decision."
            >
              —
            </span>
          ) : (
            <>
              <span
                className="font-mono text-[13px] font-bold tabular-nums"
                style={{
                  color: isNext ? 'var(--color-brand)' : 'var(--color-text-muted)',
                }}
                title={
                  isNext
                    ? 'Take this one next: the oldest report in the most urgent group that has anything waiting.'
                    : `Number ${position} in this group, counting from the oldest.`
                }
              >
                #{position}
              </span>
              {/* Only ONE row on the whole page wears this. Each group restarts
                  at #1, so the word is what separates "first in its group" from
                  "the job to pick up right now". */}
              {isNext && (
                <span
                  className="mt-1 block font-mono text-[9.5px] font-bold tracking-wide"
                  style={{ color: 'var(--color-brand)' }}
                >
                  NEXT
                </span>
              )}
            </>
          )}
        </td>
      )}

      {/* ── The report ────────────────────────────────────────── */}
      <td className="px-3 py-3">
        <div className="flex items-start gap-2">
          {/* The category, as an icon with its name on hover. It was a word
              here too, which pushed the meta line onto a second row and made
              every row in the table taller than the fact deserved. */}
          <CategoryIcon
            className="mt-0.5 shrink-0"
            size={14}
            style={{ color: sevColor }}
          >
            <title>{categoryLabel ?? 'Category not chosen by the reporter'}</title>
          </CategoryIcon>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
              {/* A button, not a link: the detail opens OVER the queue so the
                  dispatcher keeps their filters, their page and their place. */}
              <button
                className="line-clamp-2 max-w-full text-left text-[13.5px] leading-snug font-semibold text-foreground hover:underline"
                onClick={() => onOpen(incident.id)}
                type="button"
              >
                {incident.report_text}
              </button>
              {incident.sos_flagged && (
                <span
                  className="inline-flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold"
                  style={{
                    backgroundColor: 'var(--color-severity-critical-bg)',
                    color: 'var(--color-severity-critical)',
                  }}
                >
                  <Siren size={10} /> SOS
                </span>
              )}
              {isNew && (
                <span
                  className="shrink-0 rounded-[var(--radius-sm)] px-1.5 py-0.5 text-[10px] font-bold uppercase"
                  style={{
                    backgroundColor: 'var(--color-brand)',
                    color: 'var(--color-text-inverse)',
                  }}
                >
                  New
                </span>
              )}
            </div>

            <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[11.5px]">
              {/* Severity as a word. Never the row tint alone — the console's
                  colour rules put a label beside every severity hue. */}
              <span
                className="rounded-[var(--radius-sm)] border px-1.5 py-px text-[10px] font-bold tracking-wide uppercase"
                style={{
                  color: sevColor,
                  borderColor: `color-mix(in srgb, ${sevColor} 45%, transparent)`,
                }}
              >
                {sev ?? 'untriaged'}
              </span>
            </div>
          </div>
        </div>
      </td>

      {/* ── Where ─────────────────────────────────────────────── */}
      <td className="px-3 py-3 text-[12.5px] leading-tight text-muted-foreground">
        {incident.location_address ? (
          <span className="line-clamp-2">{incident.location_address}</span>
        ) : (
          <span
            className="inline-flex items-center gap-1"
            style={{ color: 'var(--color-system-warning)' }}
            title="No address resolved for this report."
          >
            <MapPin size={11} /> No address
          </span>
        )}
      </td>

      {/* ── Which station (Provincial Admin only) ─────────────── */}
      {isProvincialAdmin && (
      <td className="px-3 py-3">
        <span
          className="inline-flex items-center gap-1.5 text-[12.5px] font-semibold whitespace-nowrap"
          style={{ color: agColor }}
          title={isProvincialAdmin && stationName ? `${agType} · ${stationName}` : undefined}
        >
          <AgencyIcon aria-hidden="true" size={13} />
          {wholeLabel}
        </span>
      </td>
      )}

      {/* ── Where in the workflow ─────────────────────────────── */}
      <td className="px-3 py-3">
        <div className="flex flex-col items-start gap-1">
          <span
            className="rounded-full px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap"
            style={{ backgroundColor: sc.bg, color: sc.text }}
          >
            {statusLabel(incident.status)}
          </span>
          {/* Whether the crew has answered. Only ever present on rows that
              have been dispatched, which is where the question exists.

              The size is set HERE, not in the badge: it sizes to its context,
              and a table cell inherits the document's 14px where the card gave
              it 12. Unwrapped, "NO ANSWER FROM CREW" wrapped onto two lines
              and made every dispatched row taller than the ones above it. */}
          <span className="text-[11px] leading-tight">
            <AckBadge ack={incident.ack} />
          </span>
        </div>
      </td>

      {/* ── How long the reporter has been waiting ────────────── */}
      {/* Coloured against THIS severity's target, not one threshold for the
          whole console. The flag is the only thing the target is used for now;
          it changes no order, so it can never contradict the headings. */}
      <td className="px-3 py-3">
        <span
          className="font-mono text-[14px] font-bold tabular-nums"
          style={{ color: urgencyTimeColor(incident.created_at, incident.status, sev) }}
          title={`Received ${received}. Target for ${sev ?? 'untriaged'} reports is ${due.targetMinutes} minutes.`}
        >
          {timeShort(incident.created_at)}
        </span>
        {late && (
          <span
            className="mt-0.5 block text-[10px] font-bold tracking-wide uppercase"
            style={{ color: 'var(--color-severity-critical)' }}
            title={`Past the ${due.targetMinutes}-minute dispatch target for ${sev ?? 'untriaged'} reports by ${Math.abs(due.minutesLeft)} minutes.`}
          >
            Late
          </span>
        )}
      </td>


      {/* ── What to do about it ───────────────────────────────── */}
      <td className="px-2 py-3 text-right">
        <DropdownMenu>
          <DropdownMenuTrigger
            aria-label={`Actions for incident INC-${shortId(incident.id)}`}
            className="inline-flex size-7 items-center justify-center rounded-[var(--radius-sm)] text-muted-foreground transition-colors hover:bg-[var(--color-surface-raised)] hover:text-foreground"
          >
            <MoreHorizontal size={15} />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => onOpen(incident.id)}>
              <MapPin data-icon="inline-start" />
              Open detail
            </DropdownMenuItem>
            {/* A Provincial Admin oversees every station of their agency_type
                and dispatches for none of them, so Assign is an action they
                can never take. */}
            {isProvincialAdmin ? (
              <DropdownMenuItem asChild>
                <Link href={`/map?incident=${incident.id}`}>
                  <MapPin data-icon="inline-start" />
                  View on map
                </Link>
              </DropdownMenuItem>
            ) : (
              // Opens the detail modal (Dispatch lives in its action bar
              // now) instead of navigating to the full page's #assign
              // anchor — a dispatcher deciding who to send should not have
              // to leave the queue to do it.
              <DropdownMenuItem onClick={() => onOpen(incident.id)}>
                <UserPlus data-icon="inline-start" />
                Assign a responder
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </td>
    </tr>
  );
}
