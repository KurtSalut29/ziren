'use client';

/**
 * Resolve design tokens to concrete colour strings, and follow the theme.
 *
 * Needed because Leaflet paints its vectors through SVG *presentation
 * attributes* (`fill="…"`, `stroke="…"`), and a presentation attribute is not
 * a CSS declaration — `var(--color-severity-critical)` in one is simply
 * invalid and the mark renders black. That is why the map component carried
 * two hard-coded hex tables, and why every marker on it stayed in the light
 * palette after the console gained a dark mode: the tokens had been copied
 * out of globals.css at authoring time instead of read from it at paint time.
 *
 * Reading them here keeps globals.css the single source of truth. `theme` is
 * in the dependency list so the values are re-read when the user switches,
 * which is what lets a caller repaint its marks.
 */

import { useEffect, useState } from 'react';
import { useTheme } from './use-theme';

export function useTokenColors<K extends string>(
  tokens: Record<K, string>,
): Record<K, string> {
  const { theme, mounted } = useTheme();

  // Seed with the token names themselves rather than with guessed hexes. A
  // caller that paints before the first effect gets a visibly wrong value it
  // cannot mistake for a real colour, instead of a plausible one that hides
  // the bug.
  const [resolved, setResolved] = useState<Record<K, string>>(tokens);

  useEffect(() => {
    if (!mounted) return;
    const style = getComputedStyle(document.documentElement);
    const next = {} as Record<K, string>;
    for (const key of Object.keys(tokens) as K[]) {
      next[key] = style.getPropertyValue(tokens[key]).trim() || tokens[key];
    }
    setResolved(next);
    // `tokens` is a literal at every call site, so a new object identity every
    // render — depending on it would re-read on every render forever. The
    // token NAMES are what matter and they are static; the theme is the only
    // thing that changes what they resolve to.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [theme, mounted]);

  return resolved;
}
