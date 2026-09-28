'use client';

/**
 * Audit Logs — spec Section 10. Every administrative action for the
 * Provincial Admin's own agency_type, plus platform-wide ones.
 * Read-only, provincial_admin only (enforced server-side by GET /audit-logs/).
 */

import { useEffect, useState } from 'react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import { fetchAuditLogs, type AuditLogEntry } from '@/lib/api/audit';
import { AuditLogTable } from '@/components/audit/audit-log-table';
import { Alert } from '@/components/ui/alert';
import { Pagination } from '@/components/ui/pagination';
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { FilterField } from '@/components/ui/filter-field';
import { PeriodPicker } from '@/components/ui/period-picker';
import { phToday, resolvePeriod, type Range } from '@/components/ui/period';

const PAGE_SIZE = 50;

const TARGET_TYPES = ['user', 'station', 'rubric_config', 'system_config', 'announcement'];

export default function AuditLogsPage() {
  const { token } = useAuth();
  const [entries, setEntries] = useState<AuditLogEntry[] | null>(null);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [targetType, setTargetType] = useState('all');
  // All time by default — matches this filter's behaviour before it had a
  // Period control at all (nothing set meant every entry). /audit-logs only
  // ever understood exact dates, not a rolling "last N days" window, so a
  // chosen preset is resolved to concrete dates below rather than sent as
  // `days` — the same two-calendar Custom dialog as Operational Area's own
  // Period filter, just wired to a backend with no rolling-window concept.
  const [days, setDays] = useState(0);
  const [range, setRange] = useState<Range | null>(null);
  const [today] = useState(() => phToday());
  const [error, setError] = useState<string | null>(null);

  const resolved = resolvePeriod(days, range, today);

  useEffect(() => {
    if (!token) return;
    setEntries(null);
    fetchAuditLogs(token, {
      target_type: targetType === 'all' ? undefined : targetType,
      date_from: resolved?.from,
      date_to: resolved?.to,
      limit: PAGE_SIZE,
      offset: (page - 1) * PAGE_SIZE,
    })
      .then(r => { setEntries(r.items); setTotal(r.total); })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setError(e instanceof Error ? e.message : 'Failed to load audit logs.');
      });
  }, [token, targetType, resolved?.from, resolved?.to, page]);

  useEffect(() => { setPage(1); }, [targetType, resolved?.from, resolved?.to]);

  const pageCount = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error && <Alert variant="error" message={error} />}

      {/* Captioned fields that fill the row — the same pattern as Operational
          Area's own filter tier, rather than two narrow controls sitting left
          with the rest of the row going unused. */}
      <div className="flex flex-wrap items-end gap-x-5 gap-y-3.5">
        <FilterField className="max-sm:w-full sm:flex-[1_1_200px]" label="Target type">
          <Select onValueChange={setTargetType} value={targetType}>
            <SelectTrigger className="w-full" id="target-type">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All targets</SelectItem>
              {TARGET_TYPES.map(t => (
                <SelectItem key={t} value={t}>{t.replace('_', ' ')}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FilterField>

        <FilterField className="max-sm:w-full sm:flex-[2.4_1_420px]" label="Period">
          <PeriodPicker days={days} onDays={setDays} onRange={setRange} range={range} size="sm" today={today} />
        </FilterField>

        <span className="ml-auto shrink-0 self-end pb-1.5 text-meta text-muted-foreground">
          {total} entr{total === 1 ? 'y' : 'ies'}
        </span>
      </div>

      {entries === null ? (
        <Skeleton className="h-64 rounded-[var(--radius-card)]" />
      ) : (
        <>
          <AuditLogTable entries={entries} />
          <Pagination
            align="center"
            onNext={() => setPage(p => p + 1)}
            onPrevious={() => setPage(p => p - 1)}
            page={page}
            pageCount={pageCount}
          />
        </>
      )}
    </div>
  );
}
