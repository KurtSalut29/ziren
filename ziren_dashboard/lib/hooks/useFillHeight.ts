'use client';

import { useEffect, useState, type RefObject } from 'react';

/**
 * The height a scroll box may take so that it ends at the bottom of the screen.
 *
 * A long table inside a page that scrolls as a whole loses its column names as
 * soon as the reader scrolls. Giving the table its own scroll box, sized to
 * what is left of the screen under the filters, keeps the header in view and
 * the rows scrolling under it. Same measurement IncidentRecordTable makes.
 *
 * Returns undefined until measured, so the first paint is never clipped.
 */
export function useFillHeight(
  ref: RefObject<HTMLElement | null>,
  /** Pixels to leave under the box: the page's bottom padding, plus a pager. */
  reserveBottom: number,
  /** Anything that moves the box: row count, which view is showing. */
  deps: readonly unknown[] = [],
): number | undefined {
  const [maxHeight, setMaxHeight] = useState<number | undefined>(undefined);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    // The nearest ancestor that scrolls vertically: the page's own scroller,
    // not the window, in this app's shell.
    let scroller: HTMLElement | null = el.parentElement;
    while (scroller) {
      const oy = getComputedStyle(scroller).overflowY;
      if (oy === 'auto' || oy === 'scroll') break;
      scroller = scroller.parentElement;
    }

    const measure = () => {
      // Where the box sits with the page scrolled to its very top, so the
      // answer does not depend on how far down the reader happens to be.
      const topAtRest = el.getBoundingClientRect().top + (scroller?.scrollTop ?? 0);
      setMaxHeight(Math.max(280, Math.floor(window.innerHeight - topAtRest - reserveBottom)));
    };
    measure();
    window.addEventListener('resize', measure);
    const ro = new ResizeObserver(measure);
    if (el.parentElement) ro.observe(el.parentElement);
    return () => {
      window.removeEventListener('resize', measure);
      ro.disconnect();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ref, reserveBottom, ...deps]);

  return maxHeight;
}
