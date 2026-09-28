'use client';

/**
 * useIncidentThread — the conversation on one incident, kept fresh.
 *
 * The thread used to be drawn inside the report itself, so it polled for as
 * long as the report was open. It is a modal now, opened on demand — which
 * would have meant nothing was listening while it was closed and a resident's
 * reply could sit unseen. This hook is owned by the report (the incident dialog
 * or the full page), not by the chat window, so the thread keeps loading
 * whether or not the window is open, and can say "1 new reply" on the Chat
 * button.
 *
 * `unread` is what the agency has not yet had a chance to read: resident
 * messages newer than both the last time the chat window was open and the
 * agency's own last message. The first is obvious; the second covers a reply
 * the agency has clearly already seen and answered.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { fetchIncidentNotes, type IncidentNote } from '@/lib/api/dispatch';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { toast } from '@/lib/toast';

/** How often the thread is re-read while the report is on screen. */
export const THREAD_POLL_MS = 15_000;

export function useIncidentThread({
  incidentId,
  token,
  chatOpen,
}: {
  incidentId: string | null;
  token: string | null;
  /** While the chat window is open a reply appears in it; no toast is needed. */
  chatOpen: boolean;
}) {
  const [notes, setNotes] = useState<IncidentNote[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [seenAt, setSeenAt] = useState<number>(0);

  const newestResidentNote = useRef<string | null>(null);
  const firstLoad = useRef(true);
  const chatOpenRef = useRef(chatOpen);
  chatOpenRef.current = chatOpen;

  const load = useCallback(async () => {
    if (!incidentId || !token) return;
    try {
      const data = await fetchIncidentNotes(incidentId, token);
      setNotes(data);
      setError(null);

      // A reply that lands while the report is open is announced once. The
      // very first load only seeds the marker: a reply that was already there
      // when the report was opened is not news.
      const latest = [...data].reverse().find(n => n.author_role === 'resident');
      if (
        !firstLoad.current &&
        latest &&
        latest.id !== newestResidentNote.current &&
        !chatOpenRef.current
      ) {
        toast.info('The resident replied', { detail: latest.body.slice(0, 140) });
      }
      newestResidentNote.current = latest?.id ?? null;
      firstLoad.current = false;
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Could not load the messages.');
    }
  }, [incidentId, token]);

  useEffect(() => {
    firstLoad.current = true;
    newestResidentNote.current = null;
    setNotes(null);
    setSeenAt(0);
    if (!incidentId) return;
    void load();
    const id = setInterval(() => { if (document.visibilityState === 'visible') void load(); }, THREAD_POLL_MS);
    return () => clearInterval(id);
  }, [incidentId, load]);

  /** The agency has the window open on the latest message. */
  const markSeen = useCallback(() => setSeenAt(Date.now()), []);

  const lastAgencyAt = (notes ?? [])
    .filter(n => n.author_role !== 'resident')
    .reduce((max, n) => Math.max(max, new Date(n.created_at).getTime()), 0);

  const unread = (notes ?? []).filter(n =>
    n.author_role === 'resident' &&
    new Date(n.created_at).getTime() > Math.max(seenAt, lastAgencyAt),
  ).length;

  return { notes, error, reload: load, unread, markSeen, setError };
}

export type IncidentThread = ReturnType<typeof useIncidentThread>;
