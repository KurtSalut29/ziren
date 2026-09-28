'use client';

/**
 * Configuration History — every critical config change: system_config
 * policy updates and rubric activations, both already landing in the
 * general audit_logs table (see audit_service + Task 5's rubric.py wiring).
 *
 * Renders via the shared AuditLogTable (extracted in Task 14's Audit Logs
 * page) rather than a second copy of the same table markup.
 */

import { useEffect, useState } from 'react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { fetchConfigurationHistory } from '@/lib/api/governance';
import { ApiError } from '@/lib/api/client';
import type { AuditLogEntry } from '@/lib/api/audit';
import { AuditLogTable } from '@/components/audit/audit-log-table';
import { Alert } from '@/components/ui/alert';
import { Skeleton } from '@/components/efferd/ui/skeleton';

export default function ConfigurationHistoryPage() {
  const { token } = useAuth();
  const [entries, setEntries] = useState<AuditLogEntry[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    fetchConfigurationHistory(token)
      .then(r => setEntries(r.items))
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setError(e instanceof Error ? e.message : 'Failed to load.');
      });
  }, [token]);

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}
      {!entries ? <Skeleton className="h-64 rounded-[var(--radius-card)]" /> : <AuditLogTable entries={entries} />}
    </div>
  );
}
