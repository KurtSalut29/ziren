/**
 * A plain-text block describing this browser and this console, for someone
 * reporting a problem.
 *
 * "It doesn't work" cannot be acted on; "Chrome on Windows, 1366×768, backend
 * reachable, alert permission blocked, on the Incident Map at 3:48 PM" usually
 * can. This gathers those facts so the person asking for help does not have to
 * know which ones matter.
 *
 * DELIBERATELY NOT INCLUDED: the access token, the email address, any incident
 * text or record. The block is meant to be pasted into an email or a chat, and
 * nothing in it should be sensitive if it ends up somewhere it was not meant to.
 */

import type { HealthResponse } from '@/lib/api/health';
import { DASHBOARD_VERSION } from '@/lib/api/health';
import { describeDevice } from '@/lib/utils/device';
import { accessibilityPrefs, displayPrefs } from '@/lib/prefs/definitions';

export interface DiagnosticsInput {
  role: string | null;
  agencyType: string | null;
  health: HealthResponse | null;
  /** null when the health check itself failed, which is a finding on its own. */
  healthFailed: boolean;
}

export function buildDiagnostics({ role, agencyType, health, healthFailed }: DiagnosticsInput): string {
  const now = new Date();
  const device = describeDevice(navigator.userAgent);
  const notif = typeof Notification === 'undefined' ? 'unsupported' : Notification.permission;
  const display = displayPrefs.get();
  const a11y = accessibilityPrefs.get();

  const lines: (string | null)[] = [
    'ZIREN DIAGNOSTICS',
    `Generated      ${now.toISOString()}  (${now.toLocaleString()})`,
    `Page           ${window.location.pathname}`,
    `Dashboard      v${DASHBOARD_VERSION}`,
    `Signed in as   ${role ?? 'unknown role'}${agencyType ? ` · ${agencyType}` : ''}`,
    '',
    `Browser        ${device.label}`,
    `User agent     ${navigator.userAgent}`,
    `Window         ${window.innerWidth}×${window.innerHeight} @ ${window.devicePixelRatio}x`,
    `Language       ${navigator.language}`,
    `Time zone      ${Intl.DateTimeFormat().resolvedOptions().timeZone}`,
    `Online         ${navigator.onLine ? 'yes' : 'NO'}`,
    `Desktop alerts ${notif}`,
    `Display        density ${display.density}, ${display.timeFormat}, zone ${display.timeZone}`,
    `Accessibility  size ${a11y.fontScale}${a11y.highContrast ? ', high contrast' : ''}${a11y.reducedMotion ? ', reduced motion' : ''}`,
    '',
    healthFailed
      ? 'Backend        UNREACHABLE — the health check failed'
      : health
        ? `Backend        ${health.status}`
        : 'Backend        not checked',
    health?.triage
      ? `Triage model   v${health.triage.version} · ${health.triage.model_loaded ? 'loaded' : `NOT LOADED${health.triage.error ? ` (${health.triage.error})` : ''}`}`
      : null,
    health?.transcription
      ? `Transcription  ${health.transcription.available ? `${health.transcription.engine ?? 'engine'} ${health.transcription.version ?? ''}`.trim() : `unavailable${health.transcription.reason ? ` (${health.transcription.reason})` : ''}`}`
      : null,
  ];
  return lines.filter((l): l is string => l !== null).join('\n');
}
