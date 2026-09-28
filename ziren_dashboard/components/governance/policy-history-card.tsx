'use client';

/**
 * PolicyHistoryCard — "what changed and who changed it" beside a policy
 * form. Both Account Policies and Notification Policies used to be a single
 * narrow card floating alone on an otherwise empty page — this reuses the
 * audit trail every system_config.updated write already creates (see
 * governance_service.update_policy) rather than inventing new content, so
 * the page fills its space with something true instead of padding.
 */

import { useEffect, useState } from 'react';
import { fetchAuditLogs, type AuditLogEntry } from '@/lib/api/audit';
import { AuditLogTable } from '@/components/audit/audit-log-table';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';

export function PolicyHistoryCard({ token, policyKey }: { token: string | null; policyKey: string }) {
  const [entries, setEntries] = useState<AuditLogEntry[] | null>(null);

  useEffect(() => {
    if (!token) return;
    fetchAuditLogs(token, { target_type: 'system_config', limit: 50 })
      .then(res => setEntries(res.items.filter(e => e.target_id === policyKey).slice(0, 10)))
      .catch(() => setEntries([]));
  }, [token, policyKey]);

  return (
    <Card>
      <CardHeader className="gap-1">
        <CardTitle className="text-[15px]">Recent changes</CardTitle>
        <CardDescription>The last times this policy was updated, and by whom</CardDescription>
      </CardHeader>
      <CardContent>
        {entries === null ? (
          <Skeleton className="h-32 rounded-[var(--radius-card)]" />
        ) : (
          <AuditLogTable entries={entries} />
        )}
      </CardContent>
    </Card>
  );
}
