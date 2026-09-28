'use client';

/**
 * Arrivals — one report has landed, tell whoever is showing reports.
 *
 * WHY THIS EXISTS
 *
 * The alert popup and the two lists that show reports (the live queue and
 * Incident Records) each fetch on their own clock. The popup polls every ten
 * seconds; the queue every fifteen or thirty; Incident Records fetched once,
 * when it opened, and never again. So a dispatcher could be told "New report
 * from a resident", open it, close it - and find the list behind it exactly as
 * it was before the report existed. The alert was right, the page said nothing,
 * and to the person looking it read as a report that had gone missing.
 *
 * The alert hook is the first to notice an arrival. It says so here, and any
 * list that is on screen fetches immediately instead of waiting for its own
 * next tick. It carries the ids only - a list re-reads the server rather than
 * trusting a payload of half a row.
 */

import { useEffect, useRef } from 'react';

const EVENT = 'ziren:incidents-arrived';

/** Called by whatever first learns that new reports exist. */
export function announceArrivals(ids: string[]): void {
  if (typeof window === 'undefined' || ids.length === 0) return;
  window.dispatchEvent(new CustomEvent<string[]>(EVENT, { detail: ids }));
}

/** Runs `onArrival` whenever new reports land, for as long as the caller is mounted. */
export function useArrivals(onArrival: (ids: string[]) => void): void {
  const ref = useRef(onArrival);
  ref.current = onArrival;
  useEffect(() => {
    const handler = (e: Event) => ref.current((e as CustomEvent<string[]>).detail ?? []);
    window.addEventListener(EVENT, handler);
    return () => window.removeEventListener(EVENT, handler);
  }, []);
}

// The reverse direction: a dialog on ANY page has opened a report. The alert
// hook lives in the layout and cannot see which page-owned dialog is open, so
// without this the alarm kept looping over the very report the dispatcher was
// already reading.
const OPENED = 'ziren:incident-opened';

export interface IncidentOpened {
  id: string;
  /** Opened from the alert itself (the layout's dialog), not a page's own table. */
  fromAlert: boolean;
}

export function announceOpened(detail: IncidentOpened): void {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(new CustomEvent<IncidentOpened>(OPENED, { detail }));
}

export function useOpened(onOpened: (detail: IncidentOpened) => void): void {
  const ref = useRef(onOpened);
  ref.current = onOpened;
  useEffect(() => {
    const handler = (e: Event) => {
      const d = (e as CustomEvent<IncidentOpened>).detail;
      if (d?.id) ref.current(d);
    };
    window.addEventListener(OPENED, handler);
    return () => window.removeEventListener(OPENED, handler);
  }, []);
}
