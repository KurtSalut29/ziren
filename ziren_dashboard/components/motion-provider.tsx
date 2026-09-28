'use client';

import { MotionConfig } from 'framer-motion';

/**
 * Makes Framer Motion honour the OS "reduce motion" setting.
 *
 * globals.css already collapses CSS animations and transitions under
 * `prefers-reduced-motion: reduce`, and does it carefully — `.animate-pulse`
 * and `.animate-spin` opt back in, because freezing a spinner makes a loading
 * screen look like a hung one.
 *
 * None of that reaches Framer Motion. Those animations are driven in
 * JavaScript off the Web Animations API, so a CSS media query cannot stop
 * them: the eight files using `motion.*` kept sliding rows in from `y: 6` and
 * popping the signup badge from `scale: 0.6` no matter what the operator had
 * asked their OS for. The gap was invisible because the CSS half looked
 * thorough.
 *
 * `reducedMotion="user"` defers to the media query and disables transform and
 * layout animations while leaving opacity alone — which is the right shape of
 * the fix. Reduced motion means fewer and gentler animations, not none: a
 * fade still tells a dispatcher that a row is new, without moving it.
 */
export function MotionProvider({ children }: { children: React.ReactNode }) {
  return <MotionConfig reducedMotion="user">{children}</MotionConfig>;
}
