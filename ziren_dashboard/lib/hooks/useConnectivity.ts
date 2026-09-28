'use client';

/**
 * useConnectivity — is the operator looking at live data or a stale cache.
 *
 * Extracted out of the old sidebar ConnectivityCard so the same state can
 * drive a compact dot on the account avatar instead of a permanent text
 * card. The state machine itself is unchanged: 'syncing' is held briefly
 * after the browser fires 'online' so pages behind it have a moment to
 * re-fetch, rather than claiming the data is current a couple of seconds
 * before it actually is.
 */

import { useEffect, useState } from 'react';

export type ConnectivityState = 'online' | 'offline' | 'syncing';

export interface ConnectivityInfo {
  state: ConnectivityState;
  label: string;
  detail: string;
  color: string;
}

const CONFIG: Record<ConnectivityState, Omit<ConnectivityInfo, 'state'>> = {
  online: {
    label: 'Live',
    detail: 'Queue is current',
    color: 'var(--color-connectivity-online)',
  },
  offline: {
    label: 'Offline',
    detail: 'Showing cached data',
    color: 'var(--color-connectivity-offline)',
  },
  syncing: {
    label: 'Syncing',
    detail: 'Re-fetching the queue',
    color: 'var(--color-connectivity-sms)',
  },
};

export function useConnectivity(): ConnectivityInfo {
  const [state, setState] = useState<ConnectivityState>('online');

  useEffect(() => {
    setState(navigator.onLine ? 'online' : 'offline');

    let syncTimer: ReturnType<typeof setTimeout> | null = null;

    const handleOnline = () => {
      setState('syncing');
      syncTimer = setTimeout(() => setState('online'), 2000);
    };
    const handleOffline = () => {
      if (syncTimer) clearTimeout(syncTimer);
      setState('offline');
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
      if (syncTimer) clearTimeout(syncTimer);
    };
  }, []);

  return { state, ...CONFIG[state] };
}
