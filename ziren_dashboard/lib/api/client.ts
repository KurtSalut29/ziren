/**
 * Ziren API client — thin wrapper around fetch for the FastAPI backend.
 *
 * Base URL is read from the NEXT_PUBLIC_API_BASE_URL env variable.
 * Auth tokens are added per-request by the caller.
 */

const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8000';

interface RequestOptions extends RequestInit {
  token?: string;
}

/** Typed error so callers can distinguish auth failures from other errors. */
export class ApiError extends Error {
  constructor(
    message: string,
    public readonly status: number,
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

/**
 * Silently exchanges the stored refresh_token for a new access_token.
 *
 * WHY THIS EXISTS
 *
 * Login stored refresh_token in sessionStorage from day one (see
 * useAuth.ts's signOut, which has always cleared it) but nothing ever READ
 * it back. Access tokens expire — /auth/login documents 30 minutes — and
 * with no refresh path, the very next request after that made 401 the
 * dashboard's answer to everything, and every one of this client's callers
 * responds to a 401 by calling signOut(). The whole dashboard "just logs
 * out", found 2026-09-15 during a long testing session that was long
 * enough for a token to actually expire under it.
 *
 * THIS CALLS THE BACKEND'S OWN /auth/refresh, NOT SUPABASE DIRECTLY.
 *
 * The first version of this function called Supabase's own
 * /auth/v1/token?grant_type=refresh_token REST endpoint directly from the
 * browser, on the assumption that was the only way to refresh without
 * backend changes. It didn't need to guess: app/routers/auth.py already
 * has a working POST /auth/refresh (auth_service.refresh_session) that
 * does the exact same exchange server-side through code already exercised
 * by the rest of the app, and going through the proxy this app already
 * uses for everything else avoids relying on the Supabase URL/anon-key
 * pair being correctly present in NEXT_PUBLIC_* for a second, independent
 * code path. That first version never actually fixed the reported symptom
 * — this one calls the endpoint that was already built for it.
 *
 * MUST BE DEDUPLICATED ACROSS CONCURRENT CALLERS — THIS BROKE A FRESH LOGIN.
 *
 * The dashboard fires several authenticated requests in parallel on load
 * (users/me, dispatch/distress, dispatch/history, dispatch/queue, ...).
 * Live logs from 2026-09-15 showed all four 401 within milliseconds of a
 * SUCCESSFUL login, each independently calling this function, which fired
 * FOUR concurrent POST /auth/refresh using the same stored refresh_token.
 * Supabase refresh tokens are single-use and rotate on every exchange — of
 * four simultaneous attempts to spend the same one, exactly one can win.
 * The other three get a 401 from /auth/refresh itself, permanently (this
 * client only retries once per request), and each of THEIR callers has its
 * own signOut()-on-401 handling — so the session ended up killed by the
 * callers that lost the race, even though the one that won was sitting in
 * sessionStorage with a perfectly valid new session. A dashboard that had
 * never even finished loading looked like it "immediately signs back out."
 *
 * The fix is the module-level promise below: the FIRST 401 starts the one
 * refresh attempt and every other concurrent 401 awaits that SAME promise
 * instead of starting its own, so there is only ever one refresh_token
 * spent per expiry, however many requests discover the expiry at once.
 */
let refreshPromise: Promise<string | null> | null = null;

async function refreshAccessToken(): Promise<string | null> {
  if (refreshPromise) return refreshPromise;
  refreshPromise = doRefresh().finally(() => { refreshPromise = null; });
  return refreshPromise;
}

async function doRefresh(): Promise<string | null> {
  const refreshToken = sessionStorage.getItem('refresh_token');
  if (!refreshToken) return null;

  try {
    const res = await fetch(`${API_BASE_URL}/auth/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });
    if (!res.ok) return null;

    const data = await res.json() as { access_token?: string; refresh_token?: string };
    if (!data.access_token) return null;

    sessionStorage.setItem('access_token', data.access_token);
    // Supabase rotates the refresh token on every use — the old one stops
    // working once this succeeds, so the new one MUST replace it or the
    // very next expiry has nothing left to refresh with.
    if (data.refresh_token) sessionStorage.setItem('refresh_token', data.refresh_token);

    // useAuth reads sessionStorage exactly once, on mount — it has no way to
    // know a token was refreshed out from under it otherwise. Every mounted
    // instance of the hook picks this up and updates its own state, so the
    // NEXT call from anywhere in the app already carries the fresh token
    // instead of repeating this same refresh-then-retry dance per call.
    window.dispatchEvent(new CustomEvent('ziren:token-refreshed', { detail: data.access_token }));

    return data.access_token;
  } catch {
    return null;
  }
}

async function request<T>(path: string, options: RequestOptions = {}, isRetry = false): Promise<T> {
  const { token, ...fetchOptions } = options;

  const headers: HeadersInit = {
    'Content-Type': 'application/json',
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...(fetchOptions.headers ?? {}),
  };

  let response: Response;
  try {
    response = await fetch(`${API_BASE_URL}${path}`, {
      ...fetchOptions,
      headers,
    });
  } catch (cause) {
    // Network-level failure: the request never produced a response. This is a
    // genuinely different situation from a 4xx/5xx, and the distinction is
    // worth keeping — an HTTP error means the server answered.
    //
    // The bare `catch {}` that used to be here reported "Is the backend
    // running?" for every cause, including a CORS preflight rejection against
    // a perfectly healthy server. That sends whoever is debugging to restart a
    // process that was never the problem.
    const detail = cause instanceof Error ? cause.message : String(cause);
    throw new ApiError(
      `Could not reach ${API_BASE_URL}${path}. ` +
        'Check the backend is running and that this origin is allowed in ' +
        `CORS_ORIGINS_RAW. (${detail})`,
      0,
    );
  }

  if (!response.ok) {
    // A 401 on an authenticated call is, overwhelmingly, an expired access
    // token rather than a genuinely invalid one — try exactly once to
    // refresh and replay the request before giving up and letting the
    // caller's existing signOut()-on-401 handling take over. isRetry stops
    // this from looping if the refresh token itself is also dead.
    if (response.status === 401 && token && !isRetry) {
      const newToken = await refreshAccessToken();
      if (newToken) {
        return request<T>(path, { ...options, token: newToken }, true);
      }
    }
    const error = await response.json().catch(() => ({ detail: `HTTP ${response.status}` }));
    throw new ApiError(error.detail ?? `HTTP ${response.status}`, response.status);
  }

  return response.json() as Promise<T>;
}

export const apiClient = {
  get: <T>(path: string, token?: string) =>
    request<T>(path, { method: 'GET', token }),

  post: <T>(path: string, body: unknown, token?: string) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(body), token }),

  patch: <T>(path: string, body: unknown, token?: string) =>
    request<T>(path, { method: 'PATCH', body: JSON.stringify(body), token }),

  put: <T>(path: string, body: unknown, token?: string) =>
    request<T>(path, { method: 'PUT', body: JSON.stringify(body), token }),
};
