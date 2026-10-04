'use client';

import { useEffect, useState } from 'react';
import {
  fetchResponderPosition,
  type IncidentDetail,
  type ResponderPosition,
} from '@/lib/api/dispatch';

/** Statuses where a crew is out and their position is worth watching. */
const MOVING = new Set(['dispatched', 'en_route', 'arrived']);

/** Matches the phone's reporting cadence while it has an active call. */
const POLL_MS = 30_000;

/**
 * The assigned responder's position for an open incident, kept current while
 * they are on the way (evaluator finding #2).
 *
 * Starts from what the incident detail already carried, so the dot is there
 * the moment the dialog opens, then re-reads the small position endpoint every
 * half minute while the incident is dispatched, en route or on scene. A failed
 * read keeps the last known position rather than blanking it.
 */
export function useResponderPosition(
  detail: IncidentDetail,
  token: string | null,
): ResponderPosition | null {
  const initial: ResponderPosition | null = detail.assigned_responder_id
    ? {
        responder_id: detail.assigned_responder_id,
        full_name: detail.responder?.full_name ?? null,
        lat: detail.responder_position?.lat ?? null,
        lng: detail.responder_position?.lng ?? null,
        updated_at: detail.responder_position?.updated_at ?? null,
      }
    : null;
  const [position, setPosition] = useState<ResponderPosition | null>(initial);

  // A different incident, or the detail re-read after an action (a new
  // assignment): start again from what it carries.
  const seedKey = `${detail.id}|${detail.assigned_responder_id ?? ''}|${detail.responder_position?.updated_at ?? ''}`;
  useEffect(() => {
    setPosition(initial);
    // `initial` is derived from the same fields as seedKey.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seedKey]);

  const watching = Boolean(token && detail.assigned_responder_id && MOVING.has(detail.status));

  useEffect(() => {
    if (!watching || !token) return;
    let cancelled = false;
    const read = () => {
      fetchResponderPosition(detail.id, token)
        .then((p) => { if (!cancelled) setPosition(p); })
        .catch(() => { /* keep the last known position */ });
    };
    const timer = window.setInterval(read, POLL_MS);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, [watching, token, detail.id]);

  return position;
}
