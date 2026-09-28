/**
 * DailyVolumeChart — trailing daily report counts, hand-rolled SVG.
 *
 * Columns, not a smoothed area. The previous version drew quadratic curves
 * through seven daily totals, which implies values between the days and
 * overshoots above the highest one — a chart of 7 integers was rendering as a
 * continuous signal that rose to numbers no day actually recorded. Daily
 * counts are discrete events; each gets its own column and nothing is drawn
 * between them.
 *
 * Colour: the neutral chart tokens, per the rule in globals.css that bars
 * carry no semantic meaning and are emphasised by value rather than hue. The
 * only emphasised column is today's, and it is emphasised by darkness.
 *
 * Motion: the columns grow from the baseline once, left to right, which is the
 * direction the axis is read in. Hover is a separate, instant register — a
 * highlight band and a readout — so exploring the chart never waits on an
 * animation. Reduced motion is handled globally (see useMounted).
 */

'use client';

import { useState } from 'react';
import { useMounted } from '@/lib/hooks/useMounted';
import { Fig } from './fig';

export interface ChartPoint {
  label: string;
  value: number;
}

function niceMax(max: number): number {
  if (max <= 0) return 4;
  const pow = Math.pow(10, Math.floor(Math.log10(max)));
  const scaled = max / pow;
  const step = scaled <= 1 ? 1 : scaled <= 2 ? 2 : scaled <= 5 ? 5 : 10;
  return step * pow;
}

/**
 * Fractions of `max` to draw a gridline at.
 *
 * A fixed [0, .25, .5, .75, 1] breaks whenever the axis tops out below 4: at
 * max = 2 the five lines are labelled 0, 1, 1, 2, 2, so two gridlines at
 * different heights claim the same value and a column can no longer be read
 * off the axis. It surfaces exactly when the numbers are small, which for a
 * provincial dispatch queue is most of the time.
 *
 * niceMax only ever returns 1, 2, 5 or 10 times a power of ten, so choosing
 * the largest divisor of `max` from 5..1 always yields whole-number labels
 * with no repeats.
 */
function tickFractions(max: number): number[] {
  const divisions = [5, 4, 3, 2, 1].find(d => max % d === 0) ?? 1;
  return Array.from({ length: divisions + 1 }, (_, i) => i / divisions);
}

export function DailyVolumeChart({
  data,
  height = 200,
  /** Milliseconds before the entrance begins, for sequencing against the
   *  blocks above this one on the page. */
  delay = 0,
}: {
  data: ChartPoint[];
  height?: number;
  delay?: number;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const mounted = useMounted();

  const W = 640;
  const H = height;
  const padL = 34;
  const padR = 8;
  const padT = 14;
  const padB = 26;

  const max = niceMax(Math.max(...data.map(d => d.value), 0));
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const slot = innerW / data.length;
  const barW = Math.min(34, slot * 0.44);

  const y = (v: number) => padT + innerH - (v / max) * innerH;
  const ticks = tickFractions(max);

  const sum = data.reduce((s, d) => s + d.value, 0);
  const avg = data.length > 0 ? sum / data.length : 0;
  const shown = hover !== null ? data[hover] : null;

  return (
    <div>
      <svg
        viewBox={`0 0 ${W} ${H}`}
        className="w-full"
        role="img"
        aria-label={`Reports per day: ${data.map(d => `${d.label} ${d.value}`).join(', ')}`}
        onMouseLeave={() => setHover(null)}
      >
        {ticks.map(t => {
          const gy = padT + innerH - t * innerH;
          return (
            <g key={t}>
              <line
                x1={padL} y1={gy} x2={W - padR} y2={gy}
                stroke="var(--color-surface-border)" strokeWidth={1}
              />
              <text
                x={padL - 8} y={gy + 3} textAnchor="end"
                fontSize={11} fill="var(--color-text-muted)" fontWeight={500}
              >
                {Math.round(t * max)}
              </text>
            </g>
          );
        })}

        {/* Seven-day average. --color-chart-baseline exists in the token set
            for exactly this line and had no consumer; without it a column is
            only comparable to the other six by eye. */}
        {avg > 0 && (
          <line
            x1={padL} y1={y(avg)} x2={W - padR} y2={y(avg)}
            stroke="var(--color-chart-baseline)" strokeWidth={1}
            style={{
              opacity: mounted ? 1 : 0,
              transition: `opacity 400ms ease ${delay + data.length * 55}ms`,
            }}
          />
        )}

        {data.map((d, i) => {
          const isToday = i === data.length - 1;
          const bx = padL + i * slot + (slot - barW) / 2;
          const barH = max === 0 ? 0 : (d.value / max) * innerH;
          const by = padT + innerH - barH;
          const active = isToday || hover === i;

          return (
            <g key={d.label + i} onMouseEnter={() => setHover(i)}>
              {/* Hover band, drawn under the column so the column stays crisp. */}
              <rect
                x={padL + i * slot} y={padT}
                width={slot} height={innerH}
                rx={6}
                fill="var(--color-surface-hover)"
                style={{ opacity: hover === i ? 1 : 0, transition: 'opacity 140ms ease' }}
              />
              {/* Full-height hit area: a 0-count day has no column to aim at. */}
              <rect
                x={padL + i * slot} y={padT}
                width={slot} height={innerH}
                fill="transparent"
              />
              <rect
                x={bx}
                y={d.value === 0 ? padT + innerH - 2 : by}
                width={barW}
                height={d.value === 0 ? 2 : Math.max(barH, 2)}
                rx={4}
                fill={active ? 'var(--color-chart-bar-active)' : 'var(--color-chart-bar)'}
                style={{
                  // scaleY from the column's own baseline. Geometry attributes
                  // (y/height) are not animatable everywhere; a transform on
                  // the element's fill-box is.
                  transformBox: 'fill-box',
                  transformOrigin: 'bottom',
                  transform: mounted ? 'scaleY(1)' : 'scaleY(0)',
                  transition:
                    `transform 620ms cubic-bezier(0.16, 1, 0.3, 1) ${delay + i * 55}ms, ` +
                    'fill 150ms ease',
                }}
              />
              <text
                x={bx + barW / 2} y={H - 8} textAnchor="middle"
                fontSize={11} fontWeight={active ? 600 : 500}
                fill={active ? 'var(--color-text-secondary)' : 'var(--color-text-muted)'}
                style={{ transition: 'fill 150ms ease' }}
              >
                {d.label}
              </text>
            </g>
          );
        })}
      </svg>

      {/* The readout replaces the floating tooltip. A tooltip that follows the
          cursor covers the columns beside the one being read, which is the
          comparison the reader is in the middle of making; a fixed line under
          the axis never occludes the data and holds the same slot whether or
          not anything is hovered. */}
      <p className="mt-1 min-h-[18px] text-meta text-[var(--color-text-muted)]">
        {shown ? (
          <>
            <Fig className="text-[var(--color-text-primary)]">{shown.value}</Fig>{' '}
            {shown.value === 1 ? 'report' : 'reports'} on{' '}
            <span className="text-[var(--color-text-secondary)]">{shown.label.toLowerCase()}</span>
          </>
        ) : (
          <>
            <Fig>{sum}</Fig> reports over <Fig>{data.length}</Fig> days · daily average <Fig>{avg.toFixed(1)}</Fig>
          </>
        )}
      </p>
    </div>
  );
}
