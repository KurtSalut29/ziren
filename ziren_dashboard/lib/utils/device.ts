/**
 * Small helpers for describing a session: what device it is, and when it began
 * and ends. Used by Settings → Login & Devices.
 */

export interface DeviceInfo {
  browser: string;
  os: string;
  /** "Chrome on Windows" — what a person recognises their own machine by. */
  label: string;
  mobile: boolean;
}

/**
 * A recognisable name for a device from its user-agent string.
 *
 * Deliberately coarse. A user-agent is whatever the browser chose to send, and
 * a person reading their sign-in history needs "Chrome on Windows", not a
 * version number to compare. Order matters: Edge and Opera both contain
 * "Chrome", and Chrome contains "Safari", so the more specific name is tested
 * first.
 */
export function describeDevice(userAgent: string | null | undefined): DeviceInfo {
  const ua = userAgent ?? '';
  if (!ua) return { browser: 'Unknown browser', os: 'Unknown system', label: 'Unknown device', mobile: false };

  const browser =
    /Edg(e|A|iOS)?\//.test(ua) ? 'Edge'
    : /OPR\/|Opera/.test(ua) ? 'Opera'
    : /Firefox\/|FxiOS\//.test(ua) ? 'Firefox'
    : /Chrome\/|CriOS\//.test(ua) ? 'Chrome'
    : /Safari\//.test(ua) ? 'Safari'
    : 'Another browser';

  const os =
    /Windows NT/.test(ua) ? 'Windows'
    : /Android/.test(ua) ? 'Android'
    : /iPhone|iPad|iPod/.test(ua) ? 'iOS'
    : /Mac OS X|Macintosh/.test(ua) ? 'macOS'
    : /CrOS/.test(ua) ? 'ChromeOS'
    : /Linux/.test(ua) ? 'Linux'
    : 'Another system';

  return { browser, os, label: `${browser} on ${os}`, mobile: /Android|iPhone|iPad|iPod|Mobile/.test(ua) };
}

export interface SessionTiming {
  /** When this access token was issued (ms since epoch), or null. */
  issuedAt: number | null;
  /** When it stops being valid (ms since epoch), or null. */
  expiresAt: number | null;
}

/**
 * The issue and expiry times inside a JWT access token.
 *
 * Read only — the token's signature is NOT checked here (the browser has no
 * key to check it with, and does not need to: the server checks it on every
 * request). This is for showing the operator when their session began and when
 * it will next renew, never for deciding anything.
 */
export function readSessionTiming(token: string | null): SessionTiming {
  if (!token) return { issuedAt: null, expiresAt: null };
  try {
    const payload = token.split('.')[1];
    if (!payload) return { issuedAt: null, expiresAt: null };
    const json = JSON.parse(
      decodeURIComponent(
        atob(payload.replace(/-/g, '+').replace(/_/g, '/'))
          .split('')
          .map(c => '%' + c.charCodeAt(0).toString(16).padStart(2, '0'))
          .join(''),
      ),
    ) as { iat?: number; exp?: number };
    return {
      issuedAt: typeof json.iat === 'number' ? json.iat * 1000 : null,
      expiresAt: typeof json.exp === 'number' ? json.exp * 1000 : null,
    };
  } catch {
    return { issuedAt: null, expiresAt: null };
  }
}

/** "3 min ago", "2 h ago", "yesterday" — for a moment in the recent past. */
export function timeAgo(ms: number, now = Date.now()): string {
  const s = Math.max(0, Math.round((now - ms) / 1000));
  if (s < 45) return 'just now';
  const m = Math.round(s / 60);
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} h ago`;
  const d = Math.round(h / 24);
  return d === 1 ? 'yesterday' : `${d} days ago`;
}
