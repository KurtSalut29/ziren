'use client';

import { useEffect, useState } from 'react';

/**
 * False on the first client paint, true on the next frame.
 *
 * Entrance animations need a frame where the element is already in the DOM at
 * its starting value, otherwise the browser has nothing to transition from and
 * the element simply appears at its final size. Flipping this on a
 * requestAnimationFrame rather than directly in the effect guarantees that
 * first frame gets painted.
 *
 * Nothing here needs to be disabled for reduced motion: the global rule in
 * globals.css collapses transition-duration to 0.01ms, so the value snaps to
 * its target instead of sweeping to it.
 */
export function useMounted(): boolean {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  return mounted;
}
