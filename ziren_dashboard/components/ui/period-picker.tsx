'use client';

/**
 * A period control: a row of preset pills (7 days / 30 days / 90 days / 1
 * year / All time) plus a Custom pill that opens a two-calendar dialog —
 * the pattern built for the Operational Area header and, since, reused by
 * every other date-range filter in the dashboard (Incident Records, Audit
 * Logs, Reports & Export) so a "from – to" filter looks and behaves the
 * same wherever it appears.
 *
 * State is a (days, range) pair, not a single value: `days` is a rolling
 * preset (0 = all time) and `range`, when set, overrides it — the same
 * shape Operational Area's backend already takes, so a caller whose backend
 * understands a rolling `days` window can pass it straight through instead
 * of resolving to concrete dates itself. A caller whose backend only
 * understands concrete dates resolves the pair with `resolvePeriod` from
 * ./period before sending a request; either way, this component never
 * needs to know which.
 */

import { useRef, useState } from 'react';
import { CalendarRange } from 'lucide-react';
import { cn } from '@/lib/utils';
import { DateRangeDialog } from './date-range-dialog';
import {
  MAX_RANGE_DAYS, PERIODS, addDays, presetRange, type Range, type Ymd,
} from './period';

// flex + items-center + justify-center, not text-align:center alone: a plain block
// button centers its text horizontally but NOT vertically.
//
// The pill has NO fixed height of its own: it stretches to fill the track's row. It was
// h-7 (28px) inside the 'sm' track's 24px of content (32px - 2px border - 6px padding),
// so it hung 4px below the top edge and sat flush on the bottom border — the "space above
// the active pill" that read as off-centre. Filling the row keeps the gap identical on
// every side at either track size.
const PILL = 'flex items-center justify-center rounded-[calc(var(--radius-control)-3px)] px-1 text-[12.5px] font-semibold whitespace-nowrap transition-colors sm:px-2';
const PILL_ON = 'bg-[var(--color-surface-card)] text-foreground shadow-[0_1px_2px_rgba(0,0,0,0.1),0_0_0_1px_var(--color-surface-border)]';
const PILL_OFF = 'text-muted-foreground hover:text-foreground';

export function PeriodPicker({
  days,
  onDays,
  range,
  onRange,
  today,
  earliest,
  size = 'sm',
  showComparison = false,
  className,
}: {
  /** The rolling preset, in days (0 = all time). Ignored while `range` is set. */
  days: number;
  onDays: (d: number) => void;
  /** A range the reader chose in the Custom dialog; when set it overrides `days`. */
  range: Range | null;
  onRange: (r: Range) => void;
  today: Ymd;
  /** The oldest day the Custom dialog's calendars will open to. Defaults to ~10 years back. */
  earliest?: Ymd;
  /** 'md' (36px) matches the Operational Area header; 'sm' (32px) fits a denser filter bar. */
  size?: 'sm' | 'md';
  /** Whether the Custom dialog's footer states what the chosen range would be compared with. Off by default — most callers don't compute a previous-period comparison. */
  showComparison?: boolean;
  className?: string;
}) {
  const [rangeOpen, setRangeOpen] = useState(false);
  // Hands focus back to this pill when the dialog closes, however it closed — see the
  // matching note on DateRangeDialog's onCloseAutoFocus.
  const rangeTriggerRef = useRef<HTMLButtonElement>(null);
  const custom = range !== null;

  /**
   * Arrow keys move along the period options, as they do in any radio group. A preset is
   * chosen as focus lands on it; "Custom" only takes focus — it opens a dialog, and a
   * dialog should not pop up because someone was on their way past it.
   */
  function onPeriodKey(e: React.KeyboardEvent<HTMLDivElement>) {
    const step = e.key === 'ArrowRight' || e.key === 'ArrowDown' ? 1 : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? -1 : 0;
    if (!step) return;
    const radios = Array.from(e.currentTarget.querySelectorAll<HTMLButtonElement>('[role="radio"]'));
    const at = radios.indexOf(document.activeElement as HTMLButtonElement);
    if (at < 0) return;
    e.preventDefault();
    const to = (at + step + radios.length) % radios.length;
    radios[to]?.focus();
    if (to < PERIODS.length) onDays(PERIODS[to].days);
  }

  return (
    <>
      <div
        aria-label="Period"
        className={cn(
          'grid w-full grid-cols-[repeat(5,minmax(0,1fr))_minmax(0,1.3fr)] gap-0.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-[3px]',
          size === 'md' ? 'h-9' : 'h-8',
          className,
        )}
        onKeyDown={onPeriodKey}
        role="radiogroup"
      >
        {PERIODS.map(p => {
          const active = !custom && p.days === days;
          return (
            <button
              aria-checked={active}
              aria-label={p.label}
              className={cn(PILL, active ? PILL_ON : PILL_OFF)}
              key={p.days}
              onClick={() => onDays(p.days)}
              role="radio"
              tabIndex={active ? 0 : -1}
              type="button"
            >
              <span className="sm:hidden">{p.short}</span>
              <span className="max-sm:hidden">{p.label}</span>
            </button>
          );
        })}
        <button
          aria-checked={custom}
          aria-label="Custom range"
          className={cn(PILL, 'gap-1', custom ? PILL_ON : PILL_OFF)}
          onClick={() => setRangeOpen(true)}
          ref={rangeTriggerRef}
          role="radio"
          tabIndex={custom ? 0 : -1}
          title="Pick a start and an end date"
          type="button"
        >
          <CalendarRange aria-hidden="true" className="size-3.5 shrink-0" />
          <span className="max-sm:hidden">Custom</span>
        </button>
      </div>

      {/* Renders into a portal, so where it sits here does not matter; nothing is drawn while closed. */}
      <DateRangeDialog
        earliest={earliest ?? addDays(today, -(MAX_RANGE_DAYS - 1))}
        initial={range ?? presetRange(days, today)}
        onApply={onRange}
        onOpenChange={setRangeOpen}
        open={rangeOpen}
        showComparison={showComparison}
        today={today}
        triggerRef={rangeTriggerRef}
      />
    </>
  );
}
