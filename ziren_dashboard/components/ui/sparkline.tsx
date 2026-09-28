/**
 * Sparkline — the 14-day shape behind a stat tile's figure.
 *
 * A stat tile states where the console is right now. It cannot say whether
 * that is better or worse than yesterday, and on a dispatch queue that is the
 * question: three waiting is fine if it was nine on Monday and alarming if it
 * was zero.
 *
 * Deliberately not a chart. There are no axes, no gridlines and no value
 * labels, because none of those fit in the space and all of them would compete
 * with the figure the tile exists to show. The reader takes one thing from it
 * — the direction — and the exact numbers live in the hover readout and in the
 * full chart below.
 *
 * Restyled 2026-09-19 to match the shadcn-admin reference: the whole stroke
 * carries the tile's own accent colour (not just a grey line with a coloured
 * dot), smoothed through a monotone cubic so the shape reads as a single
 * confident wave rather than a jagged connect-the-dots line. `accent` is
 * still whatever colour rule the caller already applied — a muted tone for a
 * zero figure, a severity/agency colour where the tile genuinely is one —
 * this only changes how much of the line wears it.
 *
 * A flat series is drawn flat, on the baseline. Auto-scaling a series of
 * identical values would turn 0,0,0,0 into a dramatic full-height line, which
 * is the most common way a sparkline lies.
 */

'use client';

import { useMemo } from 'react';

export interface SparklineProps {
  values: number[];
  /** Colour for the whole line. Pass a muted token when the figure is zero. */
  accent: string;
  /** Accessible summary. The line itself is aria-hidden. */
  label: string;
  width?: number;
  height?: number;
}

/**
 * Monotone cubic through `points` (Fritsch–Butland tangents, the same curve
 * as d3.curveMonotoneX), as cubic-bezier segments.
 *
 * It passes through every real data point and, unlike a Catmull-Rom spline,
 * never overshoots between them — a step from 0 to 1 cannot dip below zero on
 * its way up. A dip under the baseline in a count is a value the data never
 * had. Assumes evenly spaced x, which the caller guarantees.
 */
function smoothPath(points: readonly (readonly [number, number])[]): string {
  const n = points.length;
  if (n < 2) return '';

  const dx: number[] = [];
  const slope: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    dx.push(points[i + 1][0] - points[i][0]);
    slope.push((points[i + 1][1] - points[i][1]) / dx[i]);
  }

  // Tangent at each point: the harmonic mean of the two neighbouring secants
  // where they agree in sign, flat where they disagree (a local extremum).
  const tangent: number[] = new Array(n);
  tangent[0] = slope[0];
  tangent[n - 1] = slope[n - 2];
  for (let i = 1; i < n - 1; i++) {
    tangent[i] =
      slope[i - 1] * slope[i] <= 0
        ? 0
        : (2 * slope[i - 1] * slope[i]) / (slope[i - 1] + slope[i]);
  }

  let d = `M${points[0][0]} ${points[0][1]}`;
  for (let i = 0; i < n - 1; i++) {
    const [x0, y0] = points[i];
    const [x1, y1] = points[i + 1];
    const h = dx[i] / 3;
    d += ` C${x0 + h} ${y0 + tangent[i] * h} ${x1 - h} ${y1 - tangent[i + 1] * h} ${x1} ${y1}`;
  }
  return d;
}

export function Sparkline({
  values,
  accent,
  label,
  width = 132,
  height = 28,
}: SparklineProps) {
  const geom = useMemo(() => {
    if (values.length < 2) return null;

    const max = Math.max(...values);
    const min = Math.min(...values);
    const span = max - min;

    // Padding keeps the ~2.5px stroke inside the box instead of clipping it
    // at the extremes of the series.
    const padY = 5;
    const usable = height - padY * 2;

    const x = (i: number) => (i / (values.length - 1)) * (width - 8) + 4;
    const y = (v: number) =>
      span === 0
        ? height - padY // flat series sits on the floor, not mid-box
        : height - padY - ((v - min) / span) * usable;

    const points = values.map((v, i) => [x(i), y(v)] as const);
    return { d: smoothPath(points) };
  }, [values, width, height]);

  if (!geom) {
    return <div aria-hidden="true" style={{ height }} />;
  }

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label={label}
      style={{ overflow: 'visible', display: 'block' }}
    >
      <path
        d={geom.d}
        fill="none"
        stroke={accent}
        strokeWidth={2.25}
        strokeLinejoin="round"
        strokeLinecap="round"
      />
    </svg>
  );
}
