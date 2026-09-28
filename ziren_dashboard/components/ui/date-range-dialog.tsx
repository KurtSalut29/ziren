'use client';

/**
 * Choosing the days a period covers — a dialog with two separate containers,
 * FROM and TO, each with its own calendar. Shared by every date-range filter
 * in the dashboard (Operational Area, Incident Records, Audit Logs, Reports
 * & Export) — see period-picker.tsx for the pill row that opens it.
 *
 * The rules that keep it hard to get wrong:
 *   - Both days are included: 1 March to 15 March is fifteen days. The footer says
 *     so in a number, and — when `showComparison` is on — says what the figures
 *     would be compared with (the fifteen days before), because a comparison the
 *     reader cannot see is a comparison they cannot trust. Off by default: most
 *     callers here don't compute a previous-period comparison at all, and stating
 *     one anyway would promise something the screen never delivers.
 *   - There is no invalid state to fall into. Picking a start after the end moves
 *     the end to match; picking an end before the start moves the start. Days after
 *     today, and days beyond the longest range the caller accepts, cannot be picked.
 *   - Quick picks (today, yesterday, this month, last month, this year) are the
 *     ranges people actually ask for, one click each.
 *   - Dates are Philippine calendar days throughout (see period.ts), so "today"
 *     is the same day for everyone regardless of where their device thinks it is.
 *
 * Keyboard, in a calendar: arrows move by a day or a week, Home/End go to the
 * start/end of the week, PageUp/PageDown by a month (with Shift, a year), Enter
 * or Space picks. Esc leaves without changing anything.
 */

import { useEffect, useRef, useState } from 'react';
import { CalendarRange, Check, ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight, X } from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { Button } from '@/components/efferd/ui/button';
import { cn } from '@/lib/utils';
import {
  WEEKDAYS, WEEKDAY_NAMES, addDays, addMonths, clampYmd, fmtLong, fmtMedium, formatRange, monthGrid, monthLabel,
  monthOf, parseYmd, previousRange, quickRanges, rangeLength, sameRange, startOfMonth, toYmd, weekdayOf,
  type Range, type Ymd,
} from './period';

export function DateRangeDialog({
  open,
  onOpenChange,
  initial,
  today,
  earliest,
  onApply,
  triggerRef,
  showComparison = false,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Where the pickers start: the range on screen, or the preset it stands for. */
  initial: Range;
  today: Ymd;
  /** The oldest day that can be picked. */
  earliest: Ymd;
  onApply: (range: Range) => void;
  /** The field that opens this dialog — focus returns to it on close, however closing happened. */
  triggerRef: React.RefObject<HTMLButtonElement | null>;
  /** Whether the footer states what the chosen range would be compared with (a previous period of the same length). */
  showComparison?: boolean;
}) {
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[700px]"
        onCloseAutoFocus={e => {
          // Radix's implicit "restore whatever was focused before" does not reliably land
          // back on a plain trigger button that isn't a <Dialog.Trigger>, so it is named
          // explicitly instead — confirmed by hand: without this, closing this dialog
          // (Escape, an outside click, or making a choice) dropped focus to <body>.
          e.preventDefault();
          triggerRef.current?.focus();
        }}
        onOpenAutoFocus={e => {
          // Start on the FROM calendar's day, so the keyboard is already where the first choice is.
          e.preventDefault();
          (e.target as HTMLElement).querySelector<HTMLElement>('[data-range-panel="from"] [data-ymd][tabindex="0"]')?.focus();
        }}
        showCloseButton={false}
      >
        {/* Mounted only while open, so every visit starts from `initial` and a cancelled edit leaves no trace. */}
        <RangeForm
          earliest={earliest}
          initial={initial}
          onApply={r => { onApply(r); onOpenChange(false); }}
          showComparison={showComparison}
          today={today}
        />
      </DialogContent>
    </Dialog>
  );
}

function RangeForm({
  initial,
  today,
  earliest,
  onApply,
  showComparison,
}: {
  initial: Range;
  today: Ymd;
  earliest: Ymd;
  onApply: (range: Range) => void;
  showComparison: boolean;
}) {
  const [from, setFrom] = useState(initial.from);
  const [to, setTo] = useState(initial.to);
  const [fromView, setFromView] = useState(monthOf(initial.from));
  const [toView, setToView] = useState(monthOf(initial.to));

  const pickFrom = (d: Ymd) => {
    setFrom(d);
    if (d > to) { setTo(d); setToView(monthOf(d)); }
  };
  const pickTo = (d: Ymd) => {
    setTo(d);
    if (d < from) { setFrom(d); setFromView(monthOf(d)); }
  };
  const pickRange = (r: Range) => {
    setFrom(r.from); setTo(r.to);
    setFromView(monthOf(r.from)); setToView(monthOf(r.to));
  };

  const draft = { from, to };
  const n = rangeLength(draft);
  const before = previousRange(draft);

  return (
    <>
      <div className="flex items-start gap-3.5 px-5 pb-4 pt-5 sm:px-6">
        <span
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-brand-subtle)] text-[var(--color-brand)]"
        >
          <CalendarRange className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <DialogTitle className="text-[18px] font-bold leading-tight tracking-tight text-foreground">
            Choose a date range
          </DialogTitle>
          <DialogDescription className="mt-1 text-[13px] leading-snug">
            Show figures for the reports created between two days. Both days are included.
          </DialogDescription>
        </div>
        <DialogClose
          aria-label="Close"
          className="-mr-1 -mt-1 flex size-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
        >
          <X aria-hidden="true" className="size-4" />
        </DialogClose>
      </div>

      <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-5 sm:px-6">
        <div className="grid gap-3 sm:grid-cols-2">
          <CalendarPanel
            from={from}
            kind="from"
            label="From"
            max={today}
            min={earliest}
            onPick={pickFrom}
            onView={setFromView}
            to={to}
            today={today}
            value={from}
            view={fromView}
          />
          <CalendarPanel
            from={from}
            kind="to"
            label="To"
            max={today}
            min={earliest}
            onPick={pickTo}
            onView={setToView}
            to={to}
            today={today}
            value={to}
            view={toView}
          />
        </div>

        <div className="mt-4 flex flex-wrap items-center gap-2" role="group" aria-label="Quick picks">
          <span className="mr-1 text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">Quick picks</span>
          {quickRanges(today).map(q => {
            const on = sameRange(q.range, draft);
            return (
              <button
                aria-pressed={on}
                className={cn(
                  'h-8 rounded-full border px-3 text-[12.5px] font-semibold transition-colors',
                  on
                    ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] text-foreground'
                    : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
                )}
                key={q.key}
                onClick={() => pickRange(q.range)}
                type="button"
              >
                {q.label}
              </button>
            );
          })}
        </div>
      </div>

      <div className="flex flex-col gap-3 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/45 px-5 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-6">
        <div aria-live="polite" className="min-w-0">
          <p className="text-[14px] text-foreground" data-range-summary>
            <strong className="font-bold">{n} day{n === 1 ? '' : 's'}</strong>
            <span className="text-[var(--color-text-secondary)]"> · {formatRange(from, to)}</span>
          </p>
          {showComparison && (
            <p className="mt-0.5 text-[12.5px] text-muted-foreground">
              Compared with {n === 1 ? 'the day' : `the ${n} days`} before ({formatRange(before.from, before.to)}).
            </p>
          )}
        </div>
        <div className="flex shrink-0 items-center justify-end gap-2.5">
          <DialogClose asChild>
            <Button className="h-9 rounded-[var(--radius-control)] px-4" type="button" variant="outline">Cancel</Button>
          </DialogClose>
          <Button className="h-9 rounded-[var(--radius-control)] px-5" onClick={() => onApply(draft)} type="button">
            <Check data-icon="inline-start" />
            Apply
          </Button>
        </div>
      </div>
    </>
  );
}

// ── One calendar ─────────────────────────────────────────────────────────

function CalendarPanel({
  kind,
  label,
  value,
  from,
  to,
  view,
  onView,
  onPick,
  min,
  max,
  today,
}: {
  kind: 'from' | 'to';
  label: string;
  /** The day this calendar chooses. */
  value: Ymd;
  from: Ymd;
  to: Ymd;
  view: { y: number; m: number };
  onView: (v: { y: number; m: number }) => void;
  onPick: (d: Ymd) => void;
  min: Ymd;
  max: Ymd;
  today: Ymd;
}) {
  const grid = useRef<HTMLDivElement>(null);
  const pending = useRef<Ymd | null>(null);
  const cells = monthGrid(view.y, view.m);
  const weeks = Array.from({ length: 6 }, (_, w) => cells.slice(w * 7, w * 7 + 7));
  const viewFirst = toYmd(view.y, view.m, 1);
  const minMonth = startOfMonth(min);
  const maxMonth = startOfMonth(max);

  const inView = (d: Ymd) => d.slice(0, 7) === viewFirst.slice(0, 7);
  // The panel's one tab stop: its own day when it is on screen, else the first day that can be picked.
  const stop = inView(value) ? value : clampYmd(viewFirst, min, max);

  const focusDay = (d: Ymd) => grid.current?.querySelector<HTMLElement>(`[data-ymd="${d}"]`)?.focus();

  // A key press that crosses into another month changes the view first; focus follows once the days exist.
  useEffect(() => {
    if (pending.current) {
      focusDay(pending.current);
      pending.current = null;
    }
  }, [view.y, view.m]);

  const goMonths = (delta: number) => onView(monthOf(clampYmd(addMonths(viewFirst, delta), minMonth, maxMonth)));

  function onKeyDown(e: React.KeyboardEvent<HTMLDivElement>) {
    const here = (e.target as HTMLElement).closest<HTMLElement>('[data-ymd]')?.dataset.ymd;
    if (!here) return;
    const next =
      e.key === 'ArrowLeft' ? addDays(here, -1)
      : e.key === 'ArrowRight' ? addDays(here, 1)
      : e.key === 'ArrowUp' ? addDays(here, -7)
      : e.key === 'ArrowDown' ? addDays(here, 7)
      : e.key === 'Home' ? addDays(here, -weekdayOf(here))
      : e.key === 'End' ? addDays(here, 6 - weekdayOf(here))
      : e.key === 'PageUp' ? addMonths(here, e.shiftKey ? -12 : -1)
      : e.key === 'PageDown' ? addMonths(here, e.shiftKey ? 12 : 1)
      : null;
    if (!next) return;
    e.preventDefault();
    const target = clampYmd(next, min, max);
    if (target === here) return;
    const p = parseYmd(target)!;
    if (p.y !== view.y || p.m !== view.m) {
      pending.current = target;
      onView({ y: p.y, m: p.m });
    } else {
      focusDay(target);
    }
  }

  const other = kind === 'from' ? to : from;
  const navButton = 'flex size-8 items-center justify-center rounded-lg text-[var(--color-text-secondary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground disabled:cursor-not-allowed disabled:opacity-35 disabled:hover:bg-transparent';

  return (
    <section
      aria-label={`${label} date`}
      className="rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4"
      data-range-panel={kind}
    >
      <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">{label}</p>
      <p className="mt-0.5 text-[20px] font-bold leading-tight tracking-tight text-foreground" data-range-value>{fmtMedium(value)}</p>

      <div className="mb-2 mt-3 flex items-center justify-between">
        <div className="flex">
          <button aria-label="Previous year" className={navButton} disabled={viewFirst <= minMonth} onClick={() => goMonths(-12)} type="button">
            <ChevronsLeft aria-hidden="true" className="size-4" />
          </button>
          <button aria-label="Previous month" className={navButton} disabled={viewFirst <= minMonth} onClick={() => goMonths(-1)} type="button">
            <ChevronLeft aria-hidden="true" className="size-4" />
          </button>
        </div>
        <p aria-live="polite" className="text-[14px] font-semibold text-foreground">{monthLabel(view.y, view.m)}</p>
        <div className="flex">
          <button aria-label="Next month" className={navButton} disabled={viewFirst >= maxMonth} onClick={() => goMonths(1)} type="button">
            <ChevronRight aria-hidden="true" className="size-4" />
          </button>
          <button aria-label="Next year" className={navButton} disabled={viewFirst >= maxMonth} onClick={() => goMonths(12)} type="button">
            <ChevronsRight aria-hidden="true" className="size-4" />
          </button>
        </div>
      </div>

      <div aria-label={monthLabel(view.y, view.m)} onKeyDown={onKeyDown} ref={grid} role="grid">
        <div className="grid grid-cols-7" role="row">
          {WEEKDAYS.map((w, i) => (
            <div
              aria-label={WEEKDAY_NAMES[i]}
              className="flex h-8 items-center justify-center text-[11.5px] font-semibold text-[var(--color-text-tertiary)]"
              key={w}
              role="columnheader"
            >
              {w}
            </div>
          ))}
        </div>

        {weeks.map((week, w) => (
          <div className="grid grid-cols-7" key={w} role="row">
            {week.map((d, c) => {
              if (!d) return <div className="h-9" key={`blank-${w}-${c}`} role="gridcell" />;
              const disabled = d < min || d > max;
              const selected = d === value;
              const inBand = d >= from && d <= to;
              const isOtherEnd = d === other && !selected;
              return (
                <div
                  aria-selected={selected}
                  className={cn(
                    'h-9',
                    // The band between the two ends, softened to a pill at each end and at the edge of a week.
                    inBand && 'bg-[var(--color-brand-subtle)]',
                    inBand && (d === from || c === 0) && 'rounded-l-full',
                    inBand && (d === to || c === 6) && 'rounded-r-full',
                  )}
                  key={d}
                  role="gridcell"
                >
                  <button
                    aria-current={d === today ? 'date' : undefined}
                    aria-label={fmtLong(d)}
                    className={cn(
                      'mx-auto flex size-9 items-center justify-center rounded-full text-[13px] tabular-nums transition-colors focus-visible:rounded-full',
                      disabled
                        ? 'cursor-not-allowed text-[var(--color-text-disabled)]'
                        : 'text-foreground hover:bg-[var(--color-surface-hover)]',
                      d === today && !selected && 'font-semibold ring-1 ring-inset ring-[var(--color-border-strong)]',
                      isOtherEnd && 'font-semibold ring-2 ring-inset ring-[var(--color-brand-active)]',
                      selected && 'bg-[var(--color-brand-active)] font-semibold text-white hover:bg-[var(--color-brand-active)]',
                    )}
                    data-ymd={d}
                    disabled={disabled}
                    onClick={() => onPick(d)}
                    tabIndex={d === stop ? 0 : -1}
                    type="button"
                  >
                    {Number(d.slice(8))}
                  </button>
                </div>
              );
            })}
          </div>
        ))}
      </div>
    </section>
  );
}
