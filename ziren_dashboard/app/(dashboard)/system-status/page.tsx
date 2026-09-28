'use client';

/**
 * System Status — spec Section 13. The least time-sensitive page in the
 * whole plan: nobody needs a health badge within seconds, hence the
 * 60-second poll (every other poll in this app is 10-30s).
 */

import { useEffect, useState } from 'react';
import { CheckCircle2, XCircle } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import { fetchSystemStatus, type SystemStatus } from '@/lib/api/system-status';
import { Alert } from '@/components/ui/alert';
import {
  Card, CardContent, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';

const POLL_MS = 60_000;

/**
 * What each check actually probes, per system_status_service.check_all() —
 * so this reads as a monitor of real components instead of eight identical
 * "Operational" cards with no way to tell what any of them cover.
 */
const CHECK_DESCRIPTIONS: Record<string, string> = {
  'Authentication': 'Supabase Auth — sign-in and account lookups for every role.',
  'Database': 'Postgres reachability for the users table, the base every other check builds on.',
  'Incident Service': 'The incidents table that reports and dispatch queues read from.',
  'Notification Service': 'The notifications table the bell icon and in-app alerts read from.',
  'Map Service': 'The stations table the Incident Map and Geographic Overview depend on.',
  'AI/NLP Service': 'The triage model that scores incoming reports for severity.',
  'File Storage': 'Supabase Storage — ID photos, incident media, and other uploads.',
  'Realtime Services': 'Approximated via the database check — no live socket probe exists yet.',
};

export default function SystemStatusPage() {
  const { token } = useAuth();
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [lastChecked, setLastChecked] = useState<Date | null>(null);

  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    const load = () => {
      fetchSystemStatus(token)
        .then(s => { if (!cancelled) { setStatus(s); setLastChecked(new Date()); setError(null); } })
        .catch((e: unknown) => {
          if (cancelled) return;
          if (e instanceof ApiError && e.status === 401) { signOut(); return; }
          setError(e instanceof Error ? e.message : 'Failed to load status.');
        });
    };
    load();
    const id = setInterval(load, POLL_MS);
    return () => { cancelled = true; clearInterval(id); };
  }, [token]);

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}

      {status && (
        <div className="flex items-center gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3">
          {status.all_operational ? (
            <CheckCircle2 className="size-5 shrink-0 text-[var(--color-system-success)]" />
          ) : (
            <XCircle className="size-5 shrink-0 text-[var(--color-severity-critical)]" />
          )}
          <p className="text-[13.5px] font-semibold text-foreground">
            {status.all_operational ? 'All systems operational' : 'One or more services are down'}
          </p>
          {lastChecked && (
            <span className="ml-auto text-meta text-muted-foreground">
              Checked {lastChecked.toLocaleTimeString()}
            </span>
          )}
        </div>
      )}

      {!status ? (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <Skeleton className="h-20 rounded-[var(--radius-card)]" key={i} />
          ))}
        </div>
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {status.checks.map(c => (
            <Card key={c.name}>
              <CardHeader className="gap-1 pb-2">
                <CardTitle className="flex items-center gap-2 text-[13.5px]">
                  {c.status === 'operational' ? (
                    <CheckCircle2 className="size-4 shrink-0 text-[var(--color-system-success)]" />
                  ) : (
                    <XCircle className="size-4 shrink-0 text-[var(--color-severity-critical)]" />
                  )}
                  {c.name}
                </CardTitle>
              </CardHeader>
              <CardContent>
                <p
                  className="text-[12.5px] font-semibold"
                  style={{
                    color: c.status === 'operational'
                      ? 'var(--color-system-success)' : 'var(--color-severity-critical)',
                  }}
                >
                  {c.status === 'operational' ? 'Operational' : 'Down'}
                </p>
                {CHECK_DESCRIPTIONS[c.name] && (
                  <p className="mt-1.5 text-[11.5px] leading-snug text-muted-foreground">
                    {CHECK_DESCRIPTIONS[c.name]}
                  </p>
                )}
                {c.detail && (
                  <>
                    {/* Plain-language lead line first — c.detail below is a raw
                        backend exception string (str(exc)[:200] in
                        system_status_service.py), the exact "Error 500"-style
                        text an admin shouldn't have to parse to know what to do:
                        wait and check again, or contact whoever owns the service. */}
                    <p className="mt-1.5 text-[11.5px] font-medium text-[var(--color-severity-critical)]">
                      This service could not be reached. If it stays down, contact your system administrator.
                    </p>
                    <p
                      className="mt-1 truncate text-[11px] text-muted-foreground"
                      title={c.detail}
                    >
                      Technical detail: {c.detail}
                    </p>
                  </>
                )}
                <p className="mt-1.5 text-[11px] text-muted-foreground">Checked in {c.latency_ms}ms</p>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
