'use client';

/**
 * useMapData — the /map/data poll, owned above the map component.
 *
 * It used to live inside ZirenMap, which meant the counts, the refresh state
 * and the error were all trapped behind a canvas the page could not read. The
 * page consequently had a hand-written legend that duplicated the map's own
 * floating badges, and the two could disagree — the legend listed four
 * severities whether or not any incident carried them.
 *
 * With the fetch up here the page owns the numbers and ZirenMap becomes a pure
 * renderer of whatever it is handed. No callback flows upward, so there is no
 * way for a data update to schedule a parent render from inside a child render.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchMapData, type MapData, type MapView } from '@/lib/api/map';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { mapPrefs } from '@/lib/prefs/definitions';

// The refresh interval is the operator's choice (Settings → Map & Location),
// 30 seconds unless they changed it.

export interface MapDataState {
  data: MapData | null;
  /** First load only. A poll does not blank the map that is already drawn. */
  loading: boolean;
  /** A poll in flight over data already on screen. */
  refreshing: boolean;
  /**
   * Set when the LAST attempt failed. `data` may still hold a good earlier
   * response, which is why the page reports this as staleness rather than as
   * an empty map — a dispatcher losing the network should keep seeing the
   * incidents they had, clearly marked as no longer live.
   */
  error: string | null;
  lastRefresh: Date | null;
  refresh: () => void;
}

export function useMapData(token: string | null, view: MapView = 'operational'): MapDataState {
  const [data, setData] = useState<MapData | null>(null);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);

  // Whether anything has ever landed. A ref, not `data !== null`, because the
  // very first response can legitimately be an empty island — no incidents,
  // no responders — and that must still count as "loaded" or the page shows a
  // loading spinner forever on a quiet night.
  //
  // Reset on a `view` change: switching Network <-> History is a different
  // question, not a refresh of the same one, so it should show its own
  // loading state rather than silently keeping the previous view's data on
  // screen while the new view's first response is in flight.
  const loadedOnce = useRef(false);

  const load = useCallback(async () => {
    if (!token) return;
    if (loadedOnce.current) setRefreshing(true);
    else setLoading(true);
    try {
      const next = await fetchMapData(token, view);
      setData(next);
      setLastRefresh(new Date());
      setError(null);
      loadedOnce.current = true;
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load map data.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [token, view]);

  const { refreshSeconds } = mapPrefs.use();

  useEffect(() => {
    loadedOnce.current = false;
    setData(null);
    void load();
    const id = setInterval(() => void load(), refreshSeconds * 1000);
    return () => clearInterval(id);
  }, [load, refreshSeconds]);

  return { data, loading, refreshing, error, lastRefresh, refresh: () => void load() };
}
