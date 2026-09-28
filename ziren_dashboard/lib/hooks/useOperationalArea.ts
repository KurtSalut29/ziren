'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import {
  fetchOperationalArea,
  type OperationalArea,
  type OperationalAreaQuery,
} from '@/lib/api/operational-area';

export interface OperationalAreaState {
  data: OperationalArea | null;
  /** True while a request the reader asked for is in flight — a period change, a refresh click. Not for background polls. */
  loading: boolean;
  /** A load failed and there is nothing on screen to fall back on. */
  error: string | null;
  /** A background refresh failed: what is on screen is older than it looks. */
  stale: boolean;
  refresh: () => void;
}

/**
 * Loads the Operational Area payload, reloads it when the query changes, and
 * (with `pollMs`) keeps it fresh while the tab is in view.
 *
 * Behaviours worth naming:
 *  - The previous payload STAYS on screen while the next one loads. Switching the
 *    period from 30 days to 90 with the whole page blanking to skeletons reads as
 *    a crash; dimming what is there and swapping it reads as a change of mind.
 *  - Responses are matched to the request that asked for them. Two quick period
 *    changes can resolve out of order, and the slower first answer must not
 *    overwrite the newer one.
 *  - A background poll is SILENT: it never dims the screen, and if it fails the
 *    last good figures stay put and `stale` says so. An alarm room whose figures
 *    flash grey every minute, or vanish when the wifi blinks, is worse than one
 *    that is a minute old.
 *  - Polling pauses while the tab is hidden and catches up the moment it is shown
 *    again, so a screen left open overnight is not asking the server all night
 *    yet is never stale when someone comes back to it.
 */
export function useOperationalArea(
  token: string | null,
  query: OperationalAreaQuery | null,
  options: { pollMs?: number } = {},
): OperationalAreaState {
  const { pollMs = 0 } = options;
  const [data, setData] = useState<OperationalArea | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [stale, setStale] = useState(false);
  const latest = useRef(0);
  const loadedAt = useRef(0);

  const municipality = query?.municipality;
  const barangay = query?.barangay ?? null;
  const days = query?.days;
  // Primitives, so a new object with the same dates does not look like a new question.
  const from = query?.range?.from ?? null;
  const to = query?.range?.to ?? null;
  const ready = Boolean(token && query);

  const load = useCallback((silent = false) => {
    if (!token || days === undefined) return;
    const ticket = ++latest.current;
    if (!silent) setLoading(true);
    fetchOperationalArea(token, { municipality, barangay, days, range: from && to ? { from, to } : null })
      .then(res => {
        if (ticket !== latest.current) return;
        loadedAt.current = Date.now();
        setData(res);
        setError(null);
        setStale(false);
      })
      .catch((e: unknown) => {
        if (ticket !== latest.current) return;
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        if (silent) { setStale(true); return; }
        setError(e instanceof Error ? e.message : 'Could not load the operational area.');
      })
      .finally(() => { if (ticket === latest.current && !silent) setLoading(false); });
  }, [token, municipality, barangay, days, from, to]);

  useEffect(() => {
    if (ready) load(false);
  }, [ready, load]);

  useEffect(() => {
    if (!ready || !pollMs) return;
    const tick = () => { if (document.visibilityState === 'visible') load(true); };
    const id = setInterval(tick, pollMs);
    const onVisible = () => {
      if (document.visibilityState === 'visible' && Date.now() - loadedAt.current >= pollMs) load(true);
    };
    document.addEventListener('visibilitychange', onVisible);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', onVisible); };
  }, [ready, pollMs, load]);

  return { data, loading, error, stale, refresh: () => load(false) };
}
