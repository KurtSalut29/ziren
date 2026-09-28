/**
 * Fig — an operational figure.
 *
 * Wraps a number that a dispatcher reads as data: a count, a share, a clock
 * value. Renders in the mono face with tabular figures (see `.fig` in
 * globals.css) so digits line up across rows and do not jitter when a value
 * ticks over on refresh.
 *
 * `tone` accepts a CSS color — pass a severity token when the figure IS that
 * severity (a critical count coloured with --color-severity-critical is the
 * intended use). Leave it unset for a neutral figure. Never pass a colour to
 * make a number look important; on this dashboard hue is reserved, and a red
 * figure claims "critical incident" whether or not that was meant.
 */

import type { CSSProperties, ReactNode } from 'react';

export function Fig({
  children,
  tone,
  className = '',
  style,
}: {
  children: ReactNode;
  tone?: string;
  className?: string;
  style?: CSSProperties;
}) {
  return (
    <span
      className={`fig ${className}`}
      style={tone ? { color: tone, ...style } : style}
    >
      {children}
    </span>
  );
}
