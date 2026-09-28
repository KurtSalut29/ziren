'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { fetchAssistThread, type AssistThread } from '@/lib/api/assist-requests';

export interface AssistThreadState {
  thread: AssistThread | null;
  loading: boolean;
  error: string | null;
  refresh: () => void;
}

/**
 * Loads one assist-request thread and polls it every `pollMs` while mounted
 * and the tab is visible — the "fast polling while open" delivery mechanism
 * the design spec chose over giving the dashboard its first-ever direct
 * Supabase Realtime subscription (see the spec's Global Constraints).
 * Stops the moment the panel unmounts; there is no background poll.
 */
export function useAssistThread(
  requestId: string | null,
  token: string | null,
  pollMs = 6000,
): AssistThreadState {
  const [thread, setThread] = useState<AssistThread | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const latest = useRef(0);

  const load = useCallback((silent = false) => {
    if (!requestId || !token) return;
    const ticket = ++latest.current;
    if (!silent) setLoading(true);
    fetchAssistThread(requestId, token)
      .then(res => {
        if (ticket !== latest.current) return;
        setThread(res);
        setError(null);
      })
      .catch((e: unknown) => {
        if (ticket !== latest.current) return;
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        if (!silent) setError(e instanceof Error ? e.message : 'Could not load this conversation.');
      })
      .finally(() => { if (ticket === latest.current) setLoading(false); });
  }, [requestId, token]);

  useEffect(() => {
    setThread(null);
    load(false);
  }, [load]);

  useEffect(() => {
    if (!requestId || !token) return;
    const id = setInterval(() => {
      if (document.visibilityState === 'visible') load(true);
    }, pollMs);
    return () => clearInterval(id);
  }, [requestId, token, pollMs, load]);

  return { thread, loading, error, refresh: () => load(false) };
}
