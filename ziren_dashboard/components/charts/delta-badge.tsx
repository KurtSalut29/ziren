'use client';

/**
 * DeltaBadge — the reference's Delta, with this console's colour rule.
 *
 * @efferd/dashboard-3 ships `delta.tsx`, which paints a negative change
 * `bg-red-500/10 text-red-500`. Red is reserved on this console for critical
 * severity and nothing else: a red pixel means "critical incident" to a
 * dispatcher scanning under time pressure, and spending it on a KPI arrow
 * destroys that signal. Down is AMBER here, via --color-delta-down.
 *
 * Direction never depends on colour alone — the arrow glyph carries it, so the
 * badge still reads for a colourblind operator and in a greyscale printout.
 *
 * `riseIsBad` is stated per call site rather than assumed, because it is not
 * constant: more incidents arriving is bad, more incidents RESOLVED is good,
 * and a silent assumption would paint one of them the wrong colour the day
 * someone adds the second kind of tile.
 */

import { ArrowDown, ArrowUp, Minus } from 'lucide-react';

export function DeltaBadge({
  value,
  riseIsBad = true,
  suffix = '',
}: {
  value: number;
  riseIsBad?: boolean;
  suffix?: string;
}) {
  const flat = value === 0;
  const tone = flat
    ? 'var(--color-text-muted)'
    : (value > 0) === riseIsBad
      ? 'var(--color-delta-down)'
      : 'var(--color-delta-up)';
  const Icon = flat ? Minus : value > 0 ? ArrowUp : ArrowDown;

  return (
    <span
      className="inline-flex shrink-0 items-center gap-0.5 rounded-full px-1.5 py-0.5 text-[11px] font-medium tabular-nums"
      style={{
        color: tone,
        // Mixed from the same token that paints the glyph, so the pair can
        // never drift the way a hand-picked background would.
        backgroundColor: `color-mix(in srgb, ${tone} 12%, transparent)`,
      }}
    >
      <Icon aria-hidden="true" size={11} strokeWidth={2.4} />
      {value > 0 ? '+' : ''}
      {value}
      {suffix}
    </span>
  );
}
