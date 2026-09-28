'use client';

/**
 * QueueOverview — the shape of the queue, beside the queue.
 *
 * The table answers "who is next" for whatever set is on screen. This answers
 * the question that comes before it: what is on this console at all, and which
 * part of it am I looking at.
 *
 * WHY THE PREVIEW IS HERE AND NOT ONLY IN THE TABLE
 *
 * A dispatcher who has filtered to one agency, sorted by newest and paged to
 * page four can no longer see the top of the working order — and that is
 * exactly the moment a radio call asks them what they are working next. The
 * two rows pinned under the waiting band are always the true head of the line,
 * whatever the table has been arranged to show. They are read-only reminders,
 * and clicking one opens it.
 *
 * The bands are FILTERS, not headings. Selecting one narrows the table; the
 * counts stay whole either way, because a count that shrank to match its own
 * filter would be answering a question nobody asked.
 */

import { ChevronRight, Wifi, WifiOff } from 'lucide-react';
import type { QueueIncident } from '@/lib/api/dispatch';
import { sevOf, SEV_COLOR, timeShort } from './incident-vocabulary';

export interface QueueBand {
  key: string;
  label: string;
  count: number;
  /** Dot colour. A severity token only where the band really is a severity. */
  color: string;
  /** One line under the label — usually the longest wait in the band. */
  hint?: string | null;
}

export function QueueOverview({
  bands,
  active,
  onSelect,
  next,
  onOpen,
  connection,
  showSync = true,
}: {
  bands: QueueBand[];
  active: string;
  onSelect: (key: string) => void;
  /** The true head of the working line — at most two rows, with positions. */
  next: { incident: QueueIncident; position: number }[];
  onOpen: (id: string) => void;
  connection: { live: boolean; lastSync: Date | null; stale: boolean };
  /**
   * Whether to draw the "Queue sync" card. Off for a Provincial Admin: the
   * card exists so a dispatcher can tell a paused or failing poll from a live
   * one, and a role that cannot pause it and has no timestamp to read has
   * nothing for it to report.
   */
  showSync?: boolean;
}) {
  return (
    /* NOT sticky/clamped any more. The idea was right — keep the NEXT rows
       visible while the reader scrolls a long table — but pinning this rail
       (position: sticky) taller than the remaining viewport needs SOME way
       to reach whatever falls below the fold, which is what the
       max-h + overflow-y-auto pair was for: cap this rail's own height and
       let IT scroll internally once stuck.
       That created a scroll-inside-a-scroll: this rail sits inside a page
       that already scrolls, and reported 2026-09-15, the inner box simply
       would not scroll on its own — the wheel kept moving the outer page
       instead, permanently hiding every band past whatever fit in the cap
       (High, Medium/low/untriaged, Assigned/en route, On scene, All open —
       gone, not just off-screen). A rail a reader cannot fully see loses to
       a rail that scrolls away with the page but is never missing anything;
       this always shows every band now, at the cost of the pin. */
    <aside className="flex w-full shrink-0 flex-col gap-3 lg:w-[268px] lg:self-start">
      {/* ── The bands ─────────────────────────────────────────── */}
      <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
        <div className="flex items-center justify-between border-b border-[var(--color-surface-border)] px-4 py-2.5">
          <span
            className="text-section-label"
            style={{ color: 'var(--color-text-tertiary)' }}
          >
            Queue overview
          </span>
          <ChevronRight aria-hidden="true" className="text-muted-foreground" size={14} />
        </div>

        <ul>
          {bands.map(band => {
            const on = band.key === active;
            return (
              <li key={band.key}>
                <button
                  aria-pressed={on}
                  className="relative flex w-full items-center gap-2.5 border-b border-[var(--color-surface-border)] px-4 py-2.5 text-left transition-colors last:border-b-0 hover:bg-[var(--color-surface-hover)]"
                  onClick={() => onSelect(band.key)}
                  style={
                    on
                      ? {
                          backgroundColor: `color-mix(in srgb, ${band.color} 8%, transparent)`,
                        }
                      : undefined
                  }
                  type="button"
                >
                  {/* The selected band wears a bar in its own colour, so which
                      band you are in is legible without reading the label. */}
                  {on && (
                    <span
                      aria-hidden="true"
                      className="absolute top-0 bottom-0 left-0 w-[3px]"
                      style={{ backgroundColor: band.color }}
                    />
                  )}
                  <span
                    aria-hidden="true"
                    className="size-2 shrink-0 rounded-full"
                    style={{ backgroundColor: band.color }}
                  />
                  <span className="min-w-0 flex-1">
                    <span
                      className="block truncate text-[11.5px] font-bold tracking-wide uppercase"
                      style={{ color: on ? band.color : 'var(--color-text-secondary)' }}
                    >
                      {band.label}
                    </span>
                  </span>
                  <span
                    className="shrink-0 font-mono text-[13px] font-bold tabular-nums"
                    style={{
                      color:
                        band.count === 0
                          ? 'var(--color-text-muted)'
                          : 'var(--color-text-primary)',
                    }}
                  >
                    {band.count}
                  </span>
                </button>

                {/* Pinned under the waiting band: the head of the line, always
                    true, whatever the table is currently showing. */}
                {band.key === 'awaiting' && next.length > 0 && (
                  <ul className="border-b border-[var(--color-surface-border)] px-3 pt-1 pb-2.5">
                    {next.map(({ incident, position }) => {
                      const color =
                        SEV_COLOR[sevOf(incident) ?? ''] ?? 'var(--color-text-muted)';
                      return (
                        <li key={incident.id}>
                          <button
                            className="flex w-full gap-2 rounded-[var(--radius-sm)] px-2 py-1.5 text-left transition-colors hover:bg-[var(--color-surface-hover)]"
                            onClick={() => onOpen(incident.id)}
                            type="button"
                          >
                            <span
                              aria-hidden="true"
                              className="mt-0.5 w-[2px] shrink-0 self-stretch rounded-full"
                              style={{ backgroundColor: color }}
                            />
                            <span className="min-w-0 flex-1">
                              <span className="flex items-center gap-1.5">
                                <span
                                  className="font-mono text-[10px] font-bold"
                                  style={{
                                    color:
                                      position === 1
                                        ? 'var(--color-brand)'
                                        : 'var(--color-text-muted)',
                                  }}
                                >
                                  {position === 1 ? 'NEXT' : `#${position}`}
                                </span>
                                <span className="ml-auto shrink-0 font-mono text-[10.5px] text-muted-foreground">
                                  {timeShort(incident.created_at)}
                                </span>
                              </span>
                              <span className="block truncate text-[12px] text-foreground">
                                {incident.report_text}
                              </span>
                            </span>
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </li>
            );
          })}
        </ul>
      </div>

      {/* ── Is this screen still true? ────────────────────────── */}
      {/*
        The most dangerous state on a dispatch console is a stale queue that
        looks live. A dispatcher reading a screen that stopped updating four
        minutes ago has no way to tell from the rows themselves — every one of
        them still looks perfectly current.

        Deliberately NOT called "Connection": the sidebar already carries a
        card by that name, and it answers a different question — whether the
        BROWSER is online. This one is about whether the QUEUE is current, and
        the two disagree exactly when it matters, when the machine is online
        and the poll is failing.
      */}
      {showSync && (
      <div
        className="flex items-center gap-2 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-2.5"
        title={
          connection.stale
            ? 'The last refresh failed - these rows may be out of date.'
            : connection.live
              ? 'The queue refreshes on its own.'
              : 'Auto refresh is off. Rows will not change on their own.'
        }
      >
        {connection.stale ? (
          <WifiOff size={13} style={{ color: 'var(--color-system-warning)' }} />
        ) : (
          <Wifi size={13} style={{ color: 'var(--color-system-success)' }} />
        )}
        <span
          className="text-[12.5px] font-semibold"
          style={{
            color: connection.stale
              ? 'var(--color-system-warning)'
              : 'var(--color-system-success)',
          }}
        >
          {connection.stale ? 'Not updating' : connection.live ? 'Live' : 'Paused'}
        </span>
        {connection.lastSync && (
          <span className="ml-auto font-mono text-[11px] text-muted-foreground">
            {connection.lastSync.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </span>
        )}
      </div>
      )}
    </aside>
  );
}
