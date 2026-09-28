'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { fetchQueue, type QueueIncident, type SeverityLevel } from '@/lib/api/dispatch';
import { relativeTime } from '@/lib/format/relative-time';

const SEV_DOT: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

export function SidebarRecentIncidents({ token }: { token: string }) {
  const [incidents, setIncidents] = useState<QueueIncident[]>([]);
  const [loading, setLoading]     = useState(true);

  useEffect(() => {
    let cancelled = false;
    fetchQueue(token)
      .then(data => {
        if (cancelled) return;
        const sorted = [...data].sort(
          (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
        );
        setIncidents(sorted.slice(0, 5));
      })
      .catch(() => {})
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [token]);

  return (
    <>
      <p className="px-3 pb-2 text-[11px] font-bold uppercase tracking-wider text-[var(--color-text-muted)]">
        Recent incidents
      </p>

      {loading ? (
        <div className="flex flex-col gap-1">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="h-10 animate-pulse rounded-lg bg-[var(--color-surface-raised)]" />
          ))}
        </div>
      ) : incidents.length === 0 ? (
        <p className="px-3 pb-2 text-[12px] text-[var(--color-text-muted)]">
          No active incidents.
        </p>
      ) : (
        <div className="flex flex-col gap-0.5">
          {incidents.map(inc => {
            const sev    = (inc.suggested_severity ?? inc.severity) as SeverityLevel | null;
            const dot    = sev ? SEV_DOT[sev] : 'var(--color-text-muted)';
            const agency = inc.stations?.agencies?.agency_type ?? '';

            return (
              <Link
                key={inc.id}
                href={`/incidents/${inc.id}`}
                className="flex items-start gap-2.5 rounded-lg px-3 py-2 no-underline transition-colors hover:bg-[var(--color-surface-raised)]"
              >
                <span
                  className="mt-1 h-[7px] w-[7px] shrink-0 rounded-full"
                  style={{ backgroundColor: dot }}
                  aria-hidden="true"
                />
                <span className="flex min-w-0 flex-col gap-0.5">
                  <span className="block truncate text-[12.5px] font-semibold text-[var(--color-text-primary)]">
                    {inc.report_text}
                  </span>
                  <span className="text-[11px] text-[var(--color-text-muted)]">
                    {agency ? `${agency} · ` : ''}{relativeTime(inc.created_at)}
                  </span>
                </span>
              </Link>
            );
          })}
        </div>
      )}
    </>
  );
}
