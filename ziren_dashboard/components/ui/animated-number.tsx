'use client';

/**
 * AnimatedNumber — a stat that counts up to its value instead of just
 * appearing. Framer Motion can render a MotionValue directly as a text
 * child (it patches the DOM node imperatively, no React re-render per
 * frame), which is what makes a smooth 60fps count-up cheap enough to put
 * on every stat card on a page without it costing a set of layout thrashes.
 *
 * Respects reduced-motion explicitly rather than relying on MotionProvider
 * alone: MotionConfig's `reducedMotion="user"` (see motion-provider.tsx)
 * disables transform/layout animations, but this drives a NUMBER through
 * `animate()`, not a transform — the safer, explicit read is to check
 * useReducedMotion() ourselves and skip straight to the final value.
 */

import { useEffect, useRef } from 'react';
import {
  animate, motion, useMotionValue, useReducedMotion, useTransform,
} from 'framer-motion';

export function AnimatedNumber({
  value,
  format,
  duration = 1,
  className,
}: {
  value: number;
  /** e.g. (n) => `${n}%` or (n) => n.toLocaleString(). Defaults to plain integer text. */
  format?: (n: number) => string;
  duration?: number;
  className?: string;
}) {
  const reducedMotion = useReducedMotion();
  const count = useMotionValue(reducedMotion ? value : 0);
  const rounded = useTransform(count, latest =>
    format ? format(Math.round(latest)) : Math.round(latest).toLocaleString(),
  );
  // Only the FIRST mount should count up from zero — a poll refreshing this
  // same card thirty seconds later should ease from the OLD value to the
  // new one, not restart the whole animation from 0 every time.
  const mounted = useRef(false);

  useEffect(() => {
    if (reducedMotion) {
      count.set(value);
      return;
    }
    const controls = animate(count, value, {
      duration: mounted.current ? duration * 0.6 : duration,
      ease: [0.16, 1, 0.3, 1],
    });
    mounted.current = true;
    return controls.stop;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value, reducedMotion]);

  return <motion.span className={className}>{rounded}</motion.span>;
}
