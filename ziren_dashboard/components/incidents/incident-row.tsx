'use client';

/**
 * IncidentRow — one report, as a card.
 *
 * Now used only by the Overview's "Needs attention" list. Incident History
 * used to render this too, until it became Incident Records and moved to a
 * flat table (incident-record-table.tsx). The live queue moved to a table
 * earlier still (incident-table.tsx) once it needed grouping and mixed sort
 * orders this card layout doesn't do.
 *
 * There is no "still active" exception here: a list that isn't a live queue
 * has no business dispatching, because acting on a page that isn't
 * refreshing is acting on a snapshot that may already be stale. Assigning a
 * responder is the live queue's job — this always offers View + a read-only
 * "More" menu instead, whatever the incident's status.
 */

import Link from 'next/link';
import {
  AlertTriangle, Building2, ClipboardCheck, Clock, Eye, Flame,
  MapPin, MoreHorizontal, Paperclip, Siren, Sparkles, Tag, UserRound, Users,
} from 'lucide-react';
import type { QueueIncident } from '@/lib/api/dispatch';
import { Button } from '@/components/efferd/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/efferd/ui/dropdown-menu';
import { SeverityRule } from '@/components/ui/severity-rationale';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { AckBadge, isAckOverdue } from './ack-badge';
import {
  AGENCY_ICON, AG_COLOR, CATEGORY_ICON, CLOSED_STATUSES, SEV_COLOR,
  STATUS_STYLE, durationBetween, sevOf, statusLabel, timeShort,
  urgencyTimeColor,
} from './incident-vocabulary';
import { OUTCOME_LABEL, type IncidentOutcome } from '@/lib/api/dispatch';

/**
 * Three panes, divided by rules: WHEN it came in, WHAT it says, and WHO owns
 * it plus what to do about it.
 *
 * The panes are separated by actual vertical rules rather than whitespace,
 * because each answers a different question and a dispatcher reads them in
 * that order. Everything inside a pane is the answer to one question, which
 * is what lets the eye stop scanning once it has what it came for.
 */

export function IncidentRow({
  incident,
  onOpen,
  queuePosition,
  isNew = false,
  isProvincialAdmin = false,
}: {
  /**
   * `resolved_at` rides in from the history endpoint only. Queue rows never
   * carry it — they cannot, since /dispatch/queue excludes closed incidents —
   * so it is optional rather than a second component.
   */
  incident: QueueIncident & {
    resolved_at?: string | null;
    /** Phase 6D after-action, present on closed incidents only. */
    outcome?: IncidentOutcome | null;
    casualties_injured?: number | null;
    casualties_fatal?: number | null;
  };
  onOpen: (id: string) => void;
  /**
   * 1-based place in the waiting line, when this row is in one.
   *
   * Absent on history rows and on incidents already with a crew — neither is
   * waiting for anything, so a position would be a number about nothing.
   */
  queuePosition?: number;
  /** Arrived since this console last polled. Wears a marker for ~90s. */
  isNew?: boolean;
  /**
   * Every row an Agency Admin sees already shares their own one agency —
   * the WHO badge naming it below is only informative for Provincial Admin,
   * whose History spans several. For them it names the STATION instead:
   * the agency type is already implied by who's signed in (same call
   * incident-table.tsx already made for the live queue's "Whose" column),
   * so repeating it on every row of Provincial Admin's history would answer
   * a question they never asked while leaving the one they did — which
   * station — unanswered.
   */
  isProvincialAdmin?: boolean;
}) {
  const sev = sevOf(incident);
  const sevColor = sev ? (SEV_COLOR[sev] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)';
  const agType   = incident.stations?.agencies?.agency_type ?? null;
  const agColor  = agType ? (AG_COLOR[agType] ?? 'var(--color-brand)') : 'var(--color-text-muted)';
  const sc       = STATUS_STYLE[incident.status] ?? STATUS_STYLE.received;
  const shortId  = incident.id.replace(/-/g, '').toUpperCase().slice(-6);
  const timeColor = urgencyTimeColor(incident.created_at, incident.status);
  const category = incident.incident_category;
  const categoryLabel =
    category && category !== 'other' ? (CATEGORY_LABELS[category] ?? null) : null;
  const CategoryIcon = category ? (CATEGORY_ICON[category] ?? Tag) : Tag;
  const AgencyIcon = agType ? (AGENCY_ICON[agType] ?? Building2) : UserRound;
  const stationName = incident.stations?.name ?? null;
  /** What the WHO badge actually names — see `isProvincialAdmin`'s doc above. */
  const whoLabel = isProvincialAdmin ? (stationName ?? 'Unassigned') : (agType ?? 'Unassigned');
  const whoTitle = isProvincialAdmin && agType && stationName ? `${agType} · ${stationName}` : undefined;
  const status = statusLabel(incident.status);
  const untrusted =
    incident.users && (!incident.users.is_verified || incident.users.sos_warning_count > 0);
  const clock = new Date(incident.created_at).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
  });

  /**
   * What actually happened, for a closed incident.
   *
   * Null while the incident is still open — the row then keeps its urgency
   * clock, which is the right figure for work somebody is still waiting on.
   *
   * `resolved_at` can be missing on a row whose status says resolved: the
   * column is nullable and older rows predate it being written. That is why
   * the total falls back to the status word instead of rendering a computed
   * dash — a blank where a duration belongs reads as a broken component.
   */
  const outcome = (() => {
    if (!CLOSED_STATUSES.includes(incident.status)) return null;
    const end = incident.resolved_at;
    return {
      total: end ? durationBetween(incident.created_at, end) : '—',
      totalLabel: end
        ? incident.status === 'cancelled' ? 'to cancel' : 'to resolve'
        : incident.status === 'cancelled'
          ? 'Cancelled — no closure time recorded'
          : 'Closure time unavailable',
    };
  })();

  /**
   * How long it took to reach a crew.
   *
   * Deliberately NOT part of `outcome`: the moment dispatched_at exists this
   * is a finished fact, whether or not the incident has since closed. An
   * en-route incident dispatched six minutes after the call is worth seeing on
   * the live queue too — it says the handoff already happened, and when.
   */
  const dispatchLatency = incident.dispatched_at
    ? durationBetween(incident.created_at, incident.dispatched_at)
    : null;

  return (
    <div
      className="relative overflow-hidden rounded-[var(--radius-card)] border bg-card shadow-[var(--shadow-card)]"
      style={{
        // A new arrival gets a brand-coloured edge for its first ninety
        // seconds. The queue is ordered by danger and then by age, which is
        // correct and which makes a new report land in the MIDDLE of the list
        // — the one thing a dispatcher watching the screen cannot spot by
        // position. The border says "this was not here a moment ago" without
        // moving it out of the order it belongs in.
        // An overdue or handed-back assignment outranks a new arrival for
        // the border. A new report has at least been SEEN by this console;
        // an unanswered one has been seen by nobody at all, and it is the
        // only state on this board where the system is waiting on a person
        // who may not know they are being waited on.
        borderColor: isAckOverdue(incident.ack)
          ? 'var(--color-severity-critical, #dc2626)'
          : isNew
            ? 'var(--color-brand)'
            : 'var(--color-surface-border)',
      }}
    >
      {/* No severity rail. The bordered chip in the first pane already carries
          severity as a WORD, so the rail was a second encoding of the same
          fact — and the accessibility rule this console works to is that
          severity is never colour alone, not that it is colour twice. */}
      <div className="grid min-w-0 grid-cols-1 lg:grid-cols-[168px_minmax(0,1fr)_300px]">
        {/* ── WHEN ───────────────────────────────────────────── */}
        <div className="flex flex-col gap-2 px-4 py-4">
          {/* Place in line, above the clock. The clock says how long this has
              waited; this says how many people are ahead of it. A dispatcher
              opening a hundred-row queue needs the second number to know where
              to start, and it is the only thing on the row that answers
              "what do I do next" rather than "what is this". */}
          {(queuePosition !== undefined || isNew) && (
            <div className="flex items-center gap-2">
              {queuePosition !== undefined && (
                <span
                  className="font-mono text-[12px] font-bold tabular-nums"
                  style={{
                    color:
                      queuePosition === 1
                        ? 'var(--color-brand)'
                        : 'var(--color-text-muted)',
                  }}
                >
                  {queuePosition === 1 ? 'NEXT' : `#${queuePosition}`}
                </span>
              )}
              {isNew && (
                <span
                  className="rounded-[var(--radius-sm)] px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide"
                  style={{
                    backgroundColor: 'var(--color-brand)',
                    color: 'var(--color-text-inverse)',
                  }}
                >
                  New
                </span>
              )}
            </div>
          )}
          {outcome ? (
            /* A CLOSED incident. The headline is how long the whole thing
               took, not how long ago it started.

               "92d ago" is the right figure for open work — it is the wait
               somebody is still sitting in. On a resolved report it is noise:
               nobody reviewing last quarter cares that a fire was reported 92
               days ago, they care that it took four minutes to reach a crew
               and three hours to close. Both timestamps were already on the
               row and neither was ever drawn. */
            <div>
              <span className="font-mono text-[19px] leading-none font-semibold tabular-nums text-foreground">
                {outcome.total}
              </span>
              <span className="ml-1 text-[13px] text-muted-foreground">
                {outcome.totalLabel}
              </span>
            </div>
          ) : (
            <div>
              <span
                className="font-mono text-[19px] leading-none font-semibold tabular-nums"
                style={{ color: timeColor }}
              >
                {timeShort(incident.created_at)}
              </span>
              <span className="ml-1 text-[13px] text-muted-foreground">ago</span>
            </div>
          )}

          {/* A bordered chip, not bare text. Severity is the single most
              consequential word on the row and a chip gives it an edge the
              eye catches at a glance. */}
          <span
            className="w-fit rounded-[var(--radius-sm)] border px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide"
            style={{
              color: sevColor,
              borderColor: `color-mix(in srgb, ${sevColor} 45%, transparent)`,
              backgroundColor: `color-mix(in srgb, ${sevColor} 10%, transparent)`,
            }}
          >
            {sev ?? 'untriaged'}
          </span>

          <div className="mt-auto flex flex-col gap-0.5 border-t border-[var(--color-surface-border)] pt-2 text-[12px] text-muted-foreground">
            <span className="flex items-center gap-1.5">
              <Clock className="shrink-0" size={12} />
              {status}
            </span>
            {/* Time to dispatch — the number an after-action review is
                actually looking for, and the one figure on this row the
                agency is judged on. Shown for anything that reached a crew,
                open or closed; absent when nothing was ever dispatched, where
                its absence is itself the finding.
                Label and value are their own line each — this pane is only
                168px wide, and "Dispatched in 10h 58m" packed into one flex
                row wrapped mid-phrase into "Dispatched in" / "10h 58m" on
                separate lines with no visual link to each other, sitting
                directly under the status word "Dispatched" above and reading
                as four disconnected fragments instead of two facts. The
                indent lines the value up under the label's text, not the
                icon, so the pair still reads as one unit. */}
            {dispatchLatency && (
              <span className="flex flex-col gap-0.5">
                <span className="flex items-center gap-1.5">
                  <Siren className="shrink-0" size={12} />
                  Dispatched in
                </span>
                <span className="pl-[18px] font-mono text-[12.5px] font-semibold tabular-nums text-foreground">
                  {dispatchLatency}
                </span>
              </span>
            )}

            {/* Whether a crew has actually ANSWERED. Sits next to the
                dispatch latency because the two are halves of one fact:
                how long it took to reach a crew, and whether that crew
                said anything back. Until this existed only the first half
                was visible, and "dispatched in 40s" read as success even
                when nobody had seen it. */}
            <AckBadge ack={incident.ack} />

            {/* WHAT THE CREW FOUND.

                The single most valuable field this console gained, and not
                for the dispatcher reading one row — for the comparison it
                finally makes possible across all of them. Severity is what
                the rubric GUESSED from a civilian's account; outcome is
                what was TRUE. An incident scored `critical` that closes
                `false_alarm` is a measurable rubric miss, and before this
                column existed that comparison could not be made at all. */}
            {incident.outcome && (
              <span
                className="flex items-center gap-1.5"
                style={{
                  color:
                    incident.outcome === 'false_alarm' ||
                    incident.outcome === 'nobody_found'
                      ? 'var(--color-text-muted)'
                      : 'var(--color-text-secondary)',
                }}
              >
                <ClipboardCheck className="shrink-0" size={12} />
                {OUTCOME_LABEL[incident.outcome]}
                {typeof incident.casualties_injured === 'number' &&
                  incident.casualties_injured > 0 && (
                    <span className="font-mono tabular-nums">
                      · {incident.casualties_injured} injured
                    </span>
                  )}
                {typeof incident.casualties_fatal === 'number' &&
                  incident.casualties_fatal > 0 && (
                    <span
                      className="font-mono font-bold tabular-nums"
                      style={{ color: 'var(--color-severity-critical)' }}
                    >
                      · {incident.casualties_fatal} fatal
                    </span>
                  )}
              </span>
            )}

            {/* Raised by a crew already on another incident. Worth a chip
                because it changes how the row should be read: this is not
                a second emergency, it is the same one needing a second
                agency — and until now that coordination happened on the
                radio and left no record at all. */}
            {incident.backup_of_incident_id && (
              <span
                className="flex items-center gap-1.5 font-semibold"
                style={{ color: 'var(--color-system-info, #0ea5e9)' }}
                title={incident.backup_reason ?? undefined}
              >
                <Users className="shrink-0" size={12} />
                Mutual aid request
              </span>
            )}
            {/* Only worth saying once the incident is CLOSED. On open work a
                missing dispatch is the normal state of something still being
                triaged; on a closed one it means nobody was ever sent. */}
            {outcome && !dispatchLatency && (
              <span className="text-[var(--color-system-warning)]">
                Never dispatched
              </span>
            )}
            {/* The wall-clock time, not only the elapsed one. "1d ago" cannot
                be matched against a radio log or a caller's account of when
                they rang; a timestamp can. */}
            <span className="font-mono tabular-nums">
              {clock}
              {outcome && (
                <span className="ml-1.5 font-sans">
                  {new Date(incident.created_at).toLocaleDateString([], {
                    day: 'numeric', month: 'short',
                  })}
                </span>
              )}
            </span>
          </div>
        </div>

        {/* ── WHAT ───────────────────────────────────────────── */}
        <div className="flex min-w-0 flex-col gap-2 border-t border-[var(--color-surface-border)] px-4 py-4 lg:border-l lg:border-t-0">
          {/* A button, not a link. It opens the detail dialog over the queue
              rather than navigating, so the dispatcher keeps their scroll
              position, their filters and their place in the band. */}
          <button
            className="text-left text-[16px] font-semibold leading-snug text-foreground hover:underline focus-visible:underline focus-visible:outline-none"
            onClick={() => onOpen(incident.id)}
            type="button"
          >
            {incident.report_text}
          </button>

          <span className="flex min-w-0 items-center gap-1.5 text-[13px] text-muted-foreground">
            <MapPin className="shrink-0" size={13} />
            {/* Stated, not blank. An incident with no location is a fact a
                dispatcher must see, and an empty slot reads as a rendering
                fault rather than missing data. */}
            <span className="truncate">
              {incident.location_address ?? 'No location given'}
            </span>
          </span>

          <div className="flex flex-wrap items-center gap-2">
            <span className="inline-flex max-w-full items-center gap-1.5 rounded-full border border-[var(--color-surface-border)] px-2.5 py-1 text-[12px]">
              <SeverityRule signals={incident.signals} severity={sev} />
            </span>

            {incident.sos_flagged && (
              <_Chip color="var(--color-severity-critical)" icon={Siren} label="SOS report" />
            )}
            {/* Evidence, not a severity or AI signal — surfaced so a
                dispatcher scanning history knows it's there. */}
            {!!incident.media_count && incident.media_count > 0 && (
              <_Chip
                color="var(--color-system-info)"
                icon={Paperclip}
                label={`${incident.media_count} attachment${incident.media_count === 1 ? '' : 's'}`}
              />
            )}
            {incident.nlp_review_needed && (
              <_Chip color="var(--color-ai-suggested)" icon={Eye} label="Needs NLP review" />
            )}
            {incident.suggested_severity && !incident.severity && (
              <_Chip color="var(--color-ai-suggested)" icon={Sparkles} label="AI suggested" />
            )}
            {untrusted && !incident.users!.is_verified && (
              <_Chip color="var(--color-system-warning)" icon={UserRound} label="Unverified reporter" />
            )}
            {untrusted && incident.users!.sos_warning_count > 0 && (
              <_Chip
                color="var(--color-severity-critical)"
                icon={AlertTriangle}
                label={`${incident.users!.sos_warning_count} prior false SOS`}
              />
            )}
          </div>
        </div>

        {/* ── WHO, AND WHAT NEXT ─────────────────────────────── */}
        <div className="flex flex-col gap-2 border-t border-[var(--color-surface-border)] px-4 py-4 lg:border-l lg:border-t-0">
          <div className="flex items-center justify-between gap-2">
            <span className="flex min-w-0 items-center gap-2">
              <span
                aria-hidden="true"
                className="flex size-7 shrink-0 items-center justify-center rounded-[var(--radius-sm)]"
                style={{
                  color: agColor,
                  backgroundColor: `color-mix(in srgb, ${agColor} 12%, transparent)`,
                }}
              >
                <AgencyIcon size={15} strokeWidth={2} />
              </span>
              <span
                className="truncate text-[13px] font-bold"
                style={{ color: agColor }}
                title={whoTitle}
              >
                {whoLabel}
              </span>
            </span>

            {/* Dot plus word: status must never depend on colour alone. */}
            <span
              className="flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full px-2 py-1 text-[10.5px] font-bold uppercase tracking-wide"
              style={{ backgroundColor: sc.bg, color: sc.text }}
            >
              <span
                aria-hidden="true"
                className="size-1.5 rounded-full"
                style={{ backgroundColor: sc.text }}
              />
              {status}
            </span>
          </div>

          <span className="flex items-center gap-2 text-[13px] text-muted-foreground">
            <CategoryIcon className="shrink-0" size={14} />
            {categoryLabel ?? 'Uncategorised'}
          </span>
          <span className="flex items-center gap-2 font-mono text-[13px] text-muted-foreground">
            <Tag className="shrink-0" size={14} />
            INC-{shortId}
          </span>

          <div className="mt-auto flex gap-2 border-t border-[var(--color-surface-border)] pt-3">
            <Button className="flex-1" onClick={() => onOpen(incident.id)} size="sm" variant="outline">
              <Eye data-icon="inline-start" />
              {/* An untriaged report is not being "viewed", it is being
                  adjudicated. The verb should say which. */}
              {sev ? 'View' : 'Review'}
            </Button>
            {/* No Assign here, ever — see the header comment. Dispatching
                belongs to the live queue; this card only ever appears on
                Incident History, which has no live poll behind it, closed
                incident or not. */}
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button className="flex-1" size="sm" variant="outline">
                  <MoreHorizontal data-icon="inline-start" />
                  More
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end">
                <DropdownMenuItem onClick={() => onOpen(incident.id)}>
                  <Eye data-icon="inline-start" />
                  View details
                </DropdownMenuItem>
                <DropdownMenuItem asChild>
                  <Link href={`/map?incident=${incident.id}`}>
                    <MapPin data-icon="inline-start" />
                    View on map
                  </Link>
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </div>
    </div>
  );
}

/** A bordered pill. Icon carries the tint, text stays legible on the card. */
function _Chip({
  icon: Icon,
  label,
  color,
}: {
  icon: typeof Flame;
  label: string;
  color: string;
}) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[12px] font-medium"
      style={{
        color,
        borderColor: `color-mix(in srgb, ${color} 40%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${color} 8%, transparent)`,
      }}
    >
      <Icon className="shrink-0" size={12} strokeWidth={2} />
      {label}
    </span>
  );
}

