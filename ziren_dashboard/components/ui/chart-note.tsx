/**
 * ChartNote — the sentence that tells an admin how to read the chart above it.
 *
 * Every chart on this console encodes a decision that is invisible in the
 * picture: whether closed incidents are counted, whether today is a full day,
 * what the line is measured against. An admin who guesses wrong reads the
 * chart backwards and is confident about it, which is worse than not having
 * the chart.
 *
 * So the note states the rule, not the reassurance. "Counts every report that
 * arrived that day, including ones already resolved" is a note. "Track your
 * incident volume at a glance" is decoration with a full stop.
 *
 * It sits below the chart deliberately. Above the chart it becomes a preamble
 * people scroll past to reach the picture; below it, it is where the eye lands
 * when the picture raises a question.
 */

import type { ReactNode } from 'react';

export function ChartNote({ children }: { children: ReactNode }) {
  return (
    <p
      className="mt-3 border-t pt-2.5 text-meta leading-relaxed"
      style={{
        borderColor: 'var(--color-surface-border)',
        color: 'var(--color-text-muted)',
      }}
    >
      {children}
    </p>
  );
}
