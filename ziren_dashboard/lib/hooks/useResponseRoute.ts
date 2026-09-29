'use client';

/**
 * useResponseRoute — the drive from the responding station to the incident.
 *
 * Owned above the map surface, for the same reason useMapData is: the
 * panel around the map has to state the distance and the ETA in words, and a
 * number trapped inside a canvas is a number the panel has to invent a second
 * copy of. Two copies of a distance is two distances that can disagree.
 *
 * Re-fetches only when the coordinates actually move, not on every render of
 * the modal that holds it — the endpoints are read out of a fetched incident,
 * so their array identity changes even when the numbers do not.
 */

import { useEffect, useState } from 'react';
import {
  fetchResponseRoute,
  type LatLng,
  type ResponseRoute,
} from '@/lib/incidents/response-route';

export interface ResponseRouteState {
  route: ResponseRoute | null;
  loading: boolean;
}

export function useResponseRoute(
  from: LatLng | null,
  to: LatLng | null,
): ResponseRouteState {
  const [route, setRoute] = useState<ResponseRoute | null>(null);
  const [loading, setLoading] = useState(false);

  // Primitives, so the effect compares the COORDINATES rather than the tuples
  // they arrive in. Without this the effect re-runs on every parent render and
  // hammers a public routing service from an open dialog.
  const fromLat = from?.[0] ?? null;
  const fromLng = from?.[1] ?? null;
  const toLat = to?.[0] ?? null;
  const toLng = to?.[1] ?? null;

  useEffect(() => {
    if (fromLat === null || fromLng === null || toLat === null || toLng === null) {
      setRoute(null);
      setLoading(false);
      return;
    }

    const controller = new AbortController();
    let cancelled = false;

    // Clear first. A route left over from the previously opened incident would
    // otherwise sit under a new report's address as if it belonged to it.
    setRoute(null);
    setLoading(true);

    fetchResponseRoute([fromLat, fromLng], [toLat, toLng], controller.signal)
      .then(r => { if (!cancelled) setRoute(r); })
      .finally(() => { if (!cancelled) setLoading(false); });

    return () => {
      cancelled = true;
      controller.abort();
    };
  }, [fromLat, fromLng, toLat, toLng]);

  return { route, loading };
}
