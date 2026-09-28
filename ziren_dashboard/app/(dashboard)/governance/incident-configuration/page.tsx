'use client';

/**
 * Incident Configuration — read-only. Categories and statuses are enforced
 * in code (app/models/incident.py), not editable rows — see the backend
 * endpoint's own docstring for why a second, editable copy here would be a
 * way for the two to silently drift.
 */

import { useEffect, useState } from 'react';
import { Info } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { fetchIncidentConfiguration, type IncidentConfiguration } from '@/lib/api/governance';
import { ApiError } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';

function Pill({ label }: { label: string }) {
  return (
    <span className="rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3 py-1 text-[12.5px] text-foreground">
      {label.replace(/_/g, ' ')}
    </span>
  );
}

export default function IncidentConfigurationPage() {
  const { token } = useAuth();
  const [config, setConfig] = useState<IncidentConfiguration | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    fetchIncidentConfiguration(token).then(setConfig).catch((e: unknown) => {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load.');
    });
  }, [token]);

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}
      <div className="flex items-start gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3">
        <Info className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
        <p className="text-meta leading-relaxed text-[var(--color-text-secondary)]">
          {config?.note ?? 'Defined in code — changing these requires a deployment, not a form.'}
        </p>
      </div>
      {!config ? (
        <Skeleton className="h-40 rounded-[var(--radius-card)]" />
      ) : (
        <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader className="gap-1">
              <CardTitle className="text-[15px]">Incident Categories</CardTitle>
              <CardDescription>What a resident can choose when filing a report</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex flex-wrap gap-2">
                {config.incident_categories.map(c => <Pill key={c} label={c} />)}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="gap-1">
              <CardTitle className="text-[15px]">Incident Statuses</CardTitle>
              <CardDescription>The lifecycle every report moves through</CardDescription>
            </CardHeader>
            <CardContent>
              <div className="flex flex-wrap gap-2">
                {config.incident_statuses.map(s => <Pill key={s} label={s} />)}
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
