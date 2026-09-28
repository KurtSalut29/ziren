'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import {
  fetchNotifications,
  markAllNotificationsRead,
  markNotificationRead,
  type NotificationItem,
} from '@/lib/api/notifications';

/**
 * How often the bell asks for news while the tab is in front.
 *
 * It was thirty seconds, on the reasoning that nobody needs a badge within
 * seconds. That was true for "a station was created" and false for "another
 * agency is asking for your help" or "the resident answered your question",
 * both of which now arrive here and both of which someone is waiting on. Fifteen
 * seconds is still a light request - one indexed query on the caller's own rows.
 */
const POLL_MS = 15_000;

/** One page. The panel asks for more when the operator scrolls to the end. */
const PAGE = 30;

export interface UseNotifications {
  items: NotificationItem[];
  unreadCount: number;
  /** True only for the first load, when there is nothing yet to show. */
  loading: boolean;
  /** The last refresh failed and nothing from an earlier one is on screen. */
  error: boolean;
  hasMore: boolean;
  loadingMore: boolean;
  /** Ids that arrived on the most recent refresh, oldest first. Empty on the first load. */
  arrived: NotificationItem[];
  refresh: () => Promise<void>;
  loadMore: () => Promise<void>;
  markRead: (id: string) => Promise<void>;
  markAllRead: () => Promise<void>;
}

export function useNotifications(token: string | null): UseNotifications {
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [arrived, setArrived] = useState<NotificationItem[]>([]);

  // How many rows the operator has asked to see. A refresh re-reads that many,
  // so scrolling down to older items is not undone by the next poll.
  const wanted = useRef(PAGE);
  const seen = useRef<Set<string> | null>(null);

  const refresh = useCallback(async () => {
    if (!token) return;
    try {
      const result = await fetchNotifications(token, false, wanted.current);
      setItems(result.items);
      setUnreadCount(result.unread_count);
      setTotal(result.total);
      setError(false);

      // What is new since the last refresh. The very first load only seeds the
      // set: an operator opening the dashboard is not "notified" of everything
      // that arrived overnight, it is simply already in the list.
      const known = seen.current;
      if (known === null) {
        seen.current = new Set(result.items.map(n => n.id));
        setArrived([]);
      } else {
        const fresh = result.items.filter(n => !known.has(n.id) && !n.is_read);
        for (const n of result.items) known.add(n.id);
        setArrived(fresh.reverse());
      }
    } catch {
      // Transient: the next poll retries. Only show an error when there is
      // nothing on screen to fall back on.
      setError(prev => prev || items.length === 0);
    } finally {
      setLoading(false);
    }
    // `items.length` is read only to decide whether an error is worth showing.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  useEffect(() => {
    if (!token) return;
    refresh();

    // Poll while the tab is visible, and catch up the moment it becomes so - a
    // backgrounded tab throttles timers, and the operator coming back to it is
    // exactly when a stale badge matters.
    const tick = () => { if (document.visibilityState === 'visible') refresh(); };
    const id = setInterval(tick, POLL_MS);
    document.addEventListener('visibilitychange', tick);
    window.addEventListener('focus', tick);
    return () => {
      clearInterval(id);
      document.removeEventListener('visibilitychange', tick);
      window.removeEventListener('focus', tick);
    };
  }, [token, refresh]);

  const loadMore = useCallback(async () => {
    if (!token || loadingMore) return;
    setLoadingMore(true);
    wanted.current += PAGE;
    try {
      await refresh();
    } finally {
      setLoadingMore(false);
    }
  }, [token, loadingMore, refresh]);

  // Read from a ref, not from inside the state updater: an updater runs later,
  // during render, so a flag set in it is still false on the line after
  // setItems() - which is how the badge used to stay put after a row was read.
  const itemsRef = useRef<NotificationItem[]>(items);
  itemsRef.current = items;

  const markRead = useCallback(async (id: string) => {
    if (!token) return;
    const target = itemsRef.current.find(n => n.id === id);
    const wasUnread = !!target && !target.is_read;
    setItems(prev => prev.map(n => (n.id === id ? { ...n, is_read: true } : n)));
    if (wasUnread) setUnreadCount(c => Math.max(0, c - 1));
    try {
      await markNotificationRead(id, token);
    } catch {
      refresh(); // resync on failure rather than leave an optimistic lie on screen
    }
  }, [token, refresh]);

  const markAllRead = useCallback(async () => {
    if (!token) return;
    setItems(prev => prev.map(n => ({ ...n, is_read: true })));
    setUnreadCount(0);
    try {
      await markAllNotificationsRead(token);
    } catch {
      refresh();
    }
  }, [token, refresh]);

  return {
    items, unreadCount, loading, error, arrived, refresh, loadMore, markRead, markAllRead,
    hasMore: items.length < total,
    loadingMore,
  };
}
