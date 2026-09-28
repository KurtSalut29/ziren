/**
 * StatStrip / StatCell — the headline metric band shared by every admin page.
 *
 * Redesigned 2026-09-19 to match the reference the product owner supplied
 * (the "Active sales / Product revenue" cards): separate cards on a gap, a
 * leading icon tile with a plain sentence-case label beside it, the figure as
 * the loudest thing in the card, a coloured delta with its context beside it,
 * and one trend line on the trailing edge.
 *
 *     [icon] Label
 *     FIGURE ........................... trend line
 *     delta · context line
 *
 * The trailing graphic is a Sparkline, and only when the tile has a real daily
 * series behind its figure. It is drawn in the delta's own tone — good, bad or
 * quiet — so the line says the same thing as the number under it, exactly as
 * the reference's green and maroon lines do.
 *
 * A tile with no such series draws nothing on the right. Inventing a shape to
 * fill the space would be a fabricated series, and the console never does that.
 * There are no progress or "health" bars either: a bar against a denominator
 * is a gauge, not a trend, and it made the tiles that had one look like a
 * different kind of card from the ones that had a line. A figure that is a
 * part of a named whole says so in words instead — see `whole`.
 *
 * What deliberately did NOT come across from the reference:
 *
 *   - Its delta paints negatives red. Red is reserved on this console for
 *     critical severity and nothing else, so "bad" is AMBER here via
 *     --color-delta-down. A red pixel means "critical incident" to a
 *     dispatcher under time pressure.
 *   - Its delta has no arrow. Ours does, so direction never depends on colour
 *     alone.
 *   - Its icon tiles are all one neutral grey. Ours carry a hue on every card,
 *     zero or not, so the row reads as one family — but the hue is still
 *     chosen by the caller, not decorated: red only on the Critical tile,
 *     amber where something needs a person, green where it is clear.
 */

'use client';

import { Children, ReactNode } from 'react';
import { ArrowDown, ArrowUp, Minus } from 'lucide-react';
import { Sparkline } from './sparkline';

const LG_COLS: Record<number, string> = {
  1: 'lg:grid-cols-1',
  2: 'lg:grid-cols-2',
  3: 'lg:grid-cols-3',
  4: 'lg:grid-cols-4',
  5: 'lg:grid-cols-5',
  // One row of six, not two rows of three. Three columns across the same
  // width as a 5-card strip nearly doubles each card's size against its
  // sibling pages (Incident History reads very differently for Agency
  // Admin's 5 cards vs. Provincial Admin's 6) — six stays a single row at
  // a size much closer to the rest of the app, and still divides evenly
  // with no leftover slot, which is the actual property that avoids the
  // ragged 4+2 wrap this map exists to prevent.
  6: 'lg:grid-cols-6',
};

export function StatStrip({ children }: { children: ReactNode }) {
  /**
   * NOT Children.count(children). A conditional card written as
   * `{cond && <StatCell .../>}` — e.g. Incident History's Provincial-only
   * "Stations with Incidents" tile — still occupies one slot in the
   * children array when `cond` is false: React's own traversal invokes
   * the count callback for that `false` the same as for a real element.
   * That inflated an Agency Admin's real 5 cards to a counted 6, which has
   * no LG_COLS entry, so the strip fell back to 4 columns and wrapped a
   * lone 5th card onto its own half-empty row — the layout bug this fixes.
   * Children.toArray() still surfaces that same `null` placeholder, so it
   * has to be filtered out explicitly rather than just deduped/keyed.
   */
  const count = Children.toArray(children).filter(Boolean).length;
  return (
    <div
      // Five or six cards share one row at desktop width, which leaves each
      // about 170–210px. StatCell reads `data-dense` to tighten its padding
      // and header so a label is not cut short. Keep labels in a dense strip
      // to about 16 characters.
      data-dense={count >= 5}
      className={[
        'group/strip grid grid-cols-1 gap-3 sm:grid-cols-2',
        LG_COLS[count] ?? 'lg:grid-cols-4',
      ].join(' ')}
    >
      {children}
    </div>
  );
}

export interface StatCellProps {
  icon: ReactNode;
  label: string;
  value: string | number;
  /** One line of context beside the delta, e.g. "38% of active queue". */
  trend?: string;
  /** Icon glyph colour, and the tint of a `whole` percentage. Every tile
   *  carries one, zero or not. Use a severity token only when the figure
   *  genuinely is that severity — see the colour rules in globals.css. */
  color: string;
  /** Icon tile fill. Pair with `color`. */
  bg: string;
  /**
   * Daily values ending today, drawn as the trend line.
   *
   * The figure alone cannot answer the question an admin opens this page
   * with — three waiting is fine if Monday was nine and alarming if Monday
   * was zero. Omit when no honest series exists; a tile without one is
   * correct, and inventing a shape to fill the space is not.
   */
  spark?: number[];
  /**
   * Signed change across the series window, with the value it started from.
   * Omitted when the endpoints match or there is no series, where a change
   * would be noise.
   */
  delta?: { change: number; from: number; display?: string } | null;
  /**
   * Does a rising number mean things are getting worse? True for every tile
   * on this console — but stated per tile rather than assumed, because the
   * day someone adds "resolved today" this becomes false and a silent
   * assumption would paint it the wrong colour.
   */
  riseIsBad?: boolean;
  /**
   * The whole this figure is a part of, and the words for it — stated in the
   * context line as "29% of 17 incidents".
   *
   * Supply it ONLY when the figure is genuinely a subset of that whole. A
   * part larger than its whole is not drawn at all rather than shown as
   * "150%", and an elapsed duration has no whole and must never be given one.
   */
  whole?: number;
  wholeLabel?: string;
}

/**
 * Tone answers "is this good?", not "which way did it move?" — so a falling
 * critical count still reads as good news rather than a warning. Shared by
 * the delta text and the trend line so the two can never disagree.
 */
function deltaTone(change: number, riseIsBad: boolean): string {
  if (change === 0) return 'var(--color-text-muted)';
  return (change > 0) === riseIsBad
    ? 'var(--color-delta-down)'
    : 'var(--color-delta-up)';
}

/** Plain arrow + value, coloured — not a filled pill. */
function DeltaChip({
  change,
  display,
  riseIsBad,
}: {
  change: number;
  display?: string;
  riseIsBad: boolean;
}) {
  const Icon = change === 0 ? Minus : change > 0 ? ArrowUp : ArrowDown;

  return (
    <span
      className="inline-flex shrink-0 items-center gap-0.5 text-meta font-semibold tabular-nums"
      style={{ color: deltaTone(change, riseIsBad) }}
    >
      <Icon aria-hidden="true" size={11} strokeWidth={2.4} />
      {display ?? `${change > 0 ? '+' : ''}${change}`}
    </span>
  );
}

export function StatCell({
  icon,
  label,
  value,
  trend,
  color,
  bg,
  spark,
  delta,
  riseIsBad = true,
  whole,
  wholeLabel,
}: StatCellProps) {
  /**
   * A ratio needs a number to divide, a whole to divide it by, and the part
   * must actually fit inside the whole. That last check is not paranoia: this
   * card shipped showing "Active 3 … of 2" at a full 100% gauge, because the
   * whole was "received in the last 14 days" while the figure counted every
   * open incident including ones older than the window. It clamped and read
   * as a complete gauge instead of an impossible fraction.
   */
  const hasWhole =
    whole !== undefined &&
    typeof value === 'number' &&
    whole > 0 &&
    value <= whole;

  const hasSpark = !!spark && spark.length > 1;

  /**
   * A zero recedes — the FIGURE does. On a quiet console most cells read
   * "Critical 0", and a zero at figure size in full ink was the loudest mark
   * on the screen while carrying the least information. It stays legible,
   * because "no critical incidents" is a fact a dispatcher needs to read and
   * not one to hide; it just stops competing. The icon tile is a different
   * matter: it is the card's identity, not its reading, so it keeps its hue
   * at zero and the row reads as one family.
   */
  const isZero = value === 0 || value === '0';
  const figureTone = isZero
    ? 'var(--color-text-muted)'
    : 'var(--color-text-primary)';

  // The trend line says one thing: is the trend good, bad, or neither. It
  // takes the delta's tone when there is a delta. With none (the window ended
  // where it began) it is neutral grey — lighter still when the figure is
  // zero, so a quiet metric stays quiet all the way through. It never borrows
  // the tile's own hue: a red line on a Critical tile would read as "critical
  // is rising" whether or not it was.
  const sparkTone = delta
    ? deltaTone(delta.change, riseIsBad)
    : isZero
      ? 'var(--color-chart-line)'
      : 'var(--color-text-muted)';

  return (
    <div
      className="flex flex-col gap-4 rounded-[var(--radius-card)] border p-5 group-data-[dense=true]/strip:gap-3.5 group-data-[dense=true]/strip:p-4"
      style={{
        borderColor: 'var(--color-surface-border)',
        backgroundColor: 'var(--color-surface-card)',
        // Soft lift, matching the reference's cards — see --shadow-card's
        // note in globals.css for why this replaced the old flat-bordered
        // rule rather than sitting alongside it as an option.
        boxShadow: 'var(--shadow-card)',
      }}
    >
      {/* Header — the icon tile leads, the label follows on the same line.
          The label recedes so the figure below is the loudest thing in the
          card. The hairline is drawn from the glyph's own colour, so each
          tile gets an outline that matches its hue without a token per
          tile. */}
      <div className="flex items-center gap-2.5 group-data-[dense=true]/strip:gap-2">
        <span
          aria-hidden="true"
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-md)] group-data-[dense=true]/strip:h-6 group-data-[dense=true]/strip:w-6 [&>svg]:h-[14px] [&>svg]:w-[14px]"
          style={{
            backgroundColor: bg,
            color,
            boxShadow:
              'inset 0 0 0 1px color-mix(in srgb, currentColor 14%, transparent)',
          }}
        >
          {icon}
        </span>
        <span
          className="truncate text-[13.5px] font-medium group-data-[dense=true]/strip:text-[13px]"
          style={{ color: 'var(--color-text-secondary)' }}
          title={label}
        >
          {label}
        </span>
      </div>

      <div className="flex flex-col gap-2">
        {/* Figure and its one graphic. min-h holds the row steady so a card
            with no graphic still lines its figure up with the rest of the
            strip. */}
        <div className="flex min-h-[44px] items-center justify-between gap-3">
          <span
            className="text-stat block min-w-0 tabular-nums"
            style={{ color: figureTone }}
          >
            {value}
          </span>

          {hasSpark ? (
            <Sparkline
              accent={sparkTone}
              height={40}
              label={`${label}: ${spark!.length}-day trend, ending at ${value}`}
              values={spark!}
              width={96}
            />
          ) : null}
        </div>

        {/* Delta, ratio and context share the card's full width on their own
            line. Squeezed into the figure's column they wrapped on some cards
            and not others, and a line that breaks in two of four tiles breaks
            the row. */}
        <div className="flex min-h-[20px] flex-wrap items-center gap-x-1.5 gap-y-0.5">
          {delta ? (
            <DeltaChip
              change={delta.change}
              display={delta.display}
              riseIsBad={riseIsBad}
            />
          ) : null}
          {hasWhole ? (
            // States the pair the percentage came from, so the reader never
            // has to reverse-engineer it.
            <span className="shrink-0 text-meta">
              <span
                className="font-semibold tabular-nums"
                style={{ color: isZero ? 'var(--color-text-muted)' : color }}
              >
                {Math.round(((value as number) / (whole as number)) * 100)}%
              </span>{' '}
              <span style={{ color: 'var(--color-text-muted)' }}>
                of {whole}
                {wholeLabel ? ` ${wholeLabel}` : ''}
              </span>
            </span>
          ) : null}
          {trend ? (
            // Wraps to a second line instead of truncating: the context line
            // often carries the window ("last 30 days"), and an ellipsis
            // that eats it leaves a figure with no stated basis.
            <span
              className="line-clamp-2 min-w-0 text-meta"
              style={{ color: 'var(--color-text-muted)' }}
            >
              {hasWhole ? '· ' : ''}
              {trend}
            </span>
          ) : null}
        </div>
      </div>
    </div>
  );
}
