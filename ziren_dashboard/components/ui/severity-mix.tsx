/**
 * SeverityMix — the composition of the active queue as one bar.
 *
 * Replaces the four-bar severity chart. Four ordered tiers that sum to the
 * whole queue are a composition, not a comparison: a grouped bar chart made
 * the reader add the bars up themselves to see the shape of the shift, and
 * spent a full panel doing it. One segmented bar states the proportion
 * directly and leaves the panel for something the page did not have room for.
 *
 * Colour never travels alone here — every segment is repeated in the legend
 * with its tier name and count, per the severity rule in globals.css.
 *
 * Motion: segments open from the left in severity order, so the bar assembles
 * worst-first. That is the order the reader cares about, and it means the
 * critical share is the first thing on the page to finish moving.
 */

'use client';

import { useMounted } from '@/lib/hooks/useMounted';
import { Fig } from './fig';

export interface SeverityCounts {
  critical: number;
  high: number;
  medium: number;
  low: number;
}

const TIERS = [
  { key: 'critical', label: 'Critical', color: 'var(--color-severity-critical)' },
  { key: 'high',     label: 'High',     color: 'var(--color-severity-high)' },
  { key: 'medium',   label: 'Medium',   color: 'var(--color-severity-medium)' },
  { key: 'low',      label: 'Low',      color: 'var(--color-severity-low)' },
] as const;

/**
 * Below this many incidents, the bar is suppressed and the legend carries the
 * figures alone.
 *
 * A proportion needs a population. With one medium incident in the queue the
 * segment was mathematically correct at 100% and read as a gauge pinned to
 * full — the console appeared to be saturated with medium severity when it
 * held a single report. Rounding made it worse further up: two of three
 * incidents drew two thirds of the width whatever the absolute numbers were.
 *
 * The same reasoning retired the semicircle dials this file's sibling
 * describes. Inventing a denominator to make the bar look reasonable at low n
 * would be that mistake again, so nothing is drawn instead.
 */
const MIN_FOR_PROPORTION = 5;

export function SeverityMix({
  counts,
  delay = 0,
}: {
  counts: SeverityCounts;
  /** Milliseconds before the entrance begins, for page-load sequencing. */
  delay?: number;
}) {
  const mounted = useMounted();
  const total = TIERS.reduce((sum, t) => sum + counts[t.key], 0);

  if (total === 0) {
    return (
      <p className="text-ui text-[var(--color-text-muted)]">
        Nothing in the active queue to rank.
      </p>
    );
  }

  const showProportion = total >= MIN_FOR_PROPORTION;

  return (
    <div>
      {showProportion ? (
      <div
        className="flex h-2.5 w-full gap-0.5 overflow-hidden rounded-full"
        role="img"
        aria-label={
          'Active queue by severity: ' +
          TIERS.filter(t => counts[t.key] > 0)
            .map(t => `${counts[t.key]} ${t.label.toLowerCase()}`)
            .join(', ')
        }
      >
        {TIERS.map((t, i) =>
          counts[t.key] > 0 ? (
            <span
              key={t.key}
              className="h-full first:rounded-l-full last:rounded-r-full"
              style={{
                width: mounted ? `${(counts[t.key] / total) * 100}%` : '0%',
                backgroundColor: t.color,
                transition: `width 560ms cubic-bezier(0.16, 1, 0.3, 1) ${delay + i * 70}ms`,
              }}
            />
          ) : null,
        )}
      </div>
      ) : (
        <p className="text-meta" style={{ color: 'var(--color-text-muted)' }}>
          {total === 1
            ? 'One incident in the active queue.'
            : `${total} incidents in the active queue — too few to show a mix.`}
        </p>
      )}

      <ul className="mt-3.5 flex flex-wrap gap-x-5 gap-y-2">
        {TIERS.map((t, i) => {
          const n = counts[t.key];
          return (
            <li
              key={t.key}
              className="flex items-baseline gap-1.5"
              style={{
                opacity: mounted ? 1 : 0,
                transition: `opacity 300ms ease ${delay + 160 + i * 70}ms`,
              }}
            >
              <span
                aria-hidden="true"
                className="h-1.5 w-1.5 shrink-0 translate-y-[-1px] rounded-full"
                style={{ backgroundColor: t.color, opacity: n > 0 ? 1 : 0.35 }}
              />
              <span
                className="text-meta"
                style={{ color: n > 0 ? 'var(--color-text-secondary)' : 'var(--color-text-muted)' }}
              >
                {t.label}
              </span>
              <Fig
                className="text-[12.5px] font-semibold"
                tone={n > 0 ? 'var(--color-text-primary)' : 'var(--color-text-muted)'}
              >
                {n}
              </Fig>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
