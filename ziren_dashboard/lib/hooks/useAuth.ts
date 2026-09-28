'use client';

import { useEffect, useState } from 'react';

/**
 * Reactive hook that reads the session from sessionStorage.
 *
 * `hydrated` starts false and becomes true after the first read.
 * Consumers must wait for `hydrated === true` before making any
 * "is the user logged in?" decision — token is null both when the
 * user is genuinely unauthenticated AND during the brief window
 * before the effect fires.
 *
 * Phase 6A stores tokens in sessionStorage after login.
 * Phase 12 (security hardening) should move to httpOnly cookies.
 */
export function useAuth() {
  const [token,      setToken]      = useState<string | null>(null);
  const [role,       setRole]       = useState<string | null>(null);
  const [email,      setEmail]      = useState<string | null>(null);
  const [agencyType, setAgencyType] = useState<string | null>(null);
  const [hydrated,   setHydrated]   = useState(false);

  useEffect(() => {
    setToken(sessionStorage.getItem('access_token'));
    setRole(sessionStorage.getItem('user_role'));
    setEmail(sessionStorage.getItem('user_email'));
    setAgencyType(sessionStorage.getItem('user_agency_type'));
    setHydrated(true);

    // client.ts silently refreshes an expired access token and replaces it
    // in sessionStorage — but that write alone doesn't touch this hook's
    // React state, read once above on mount. Without this listener, every
    // OTHER call site relying on `token` from this hook would keep handing
    // out the stale value and 401 again, forcing its own refresh, forever
    // one step behind. This is what lets the app settle on the fresh token
    // after the first silent refresh instead of repeating it per call.
    const onRefresh = (e: Event) => {
      setToken((e as CustomEvent<string>).detail);
    };
    window.addEventListener('ziren:token-refreshed', onRefresh);
    return () => window.removeEventListener('ziren:token-refreshed', onRefresh);
  }, []);

  return {
    token,
    role,
    email,
    agencyType,
    hydrated,
    isAdmin:           role === 'agency_admin' || role === 'provincial_admin',
    isAgencyAdmin:     role === 'agency_admin',
    isProvincialAdmin: role === 'provincial_admin',
  };
}

/** Imperative read for use outside React components (e.g. API helpers). */
export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return sessionStorage.getItem('access_token');
}

export function signOut() {
  if (typeof window === 'undefined') return;
  sessionStorage.removeItem('access_token');
  sessionStorage.removeItem('refresh_token');
  sessionStorage.removeItem('user_role');
  sessionStorage.removeItem('user_email');
  sessionStorage.removeItem('user_agency_type');
  window.location.href = '/login';
}
