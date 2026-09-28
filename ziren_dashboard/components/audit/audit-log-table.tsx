'use client';

/**
 * AuditLogTable — the shared rendering for any list of AuditLogEntry rows.
 *
 * Used by both /audit-logs (the full Provincial Admin audit trail) and
 * /governance/configuration-history (the same data, filtered to
 * system_config.updated + rubric.activated). One table, two call sites —
 * governance/configuration-history/page.tsx built its own inline copy of
 * this markup before this component existed (Task 13); this is that markup,
 * extracted, with that page switched over to it.
 */

import { Fragment, useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import type { AuditLogEntry } from '@/lib/api/audit';

function formatValue(v: Record<string, unknown> | null): string {
  if (!v || Object.keys(v).length === 0) return '—';
  return Object.entries(v).map(([k, val]) => `${k}: ${JSON.stringify(val)}`).join(', ');
}

export function AuditLogTable({ entries }: { entries: AuditLogEntry[] }) {
  const [expanded, setExpanded] = useState<Set<string>>(new Set());

  function toggle(id: string) {
    setExpanded(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  if (entries.length === 0) {
    return (
      <p className="py-10 text-center text-[13px] text-muted-foreground">
        No matching audit log entries.
      </p>
    );
  }

  return (
    <div className="overflow-x-auto rounded-[var(--radius-card)] border border-[var(--color-surface-border)]">
      <table className="w-full text-[12.5px]">
        <thead className="bg-[var(--color-surface-raised)] text-left text-[11px] uppercase tracking-wide text-muted-foreground">
          <tr>
            <th className="w-8 px-2 py-2.5" />
            <th className="px-4 py-2.5">Date &amp; Time</th>
            <th className="px-4 py-2.5">User</th>
            <th className="px-4 py-2.5">Action</th>
            <th className="px-4 py-2.5">Target</th>
          </tr>
        </thead>
        <tbody>
          {entries.map((e, i) => {
            const isOpen = expanded.has(e.id);
            const hasDiff = e.previous_value || e.new_value;
            return (
              <Fragment key={e.id}>
                <tr
                  className={[
                    i > 0 ? 'border-t border-[var(--color-surface-border)]' : '',
                    hasDiff ? 'cursor-pointer hover:bg-[var(--color-surface-hover)]' : '',
                  ].join(' ')}
                  onClick={() => hasDiff && toggle(e.id)}
                >
                  <td className="px-2 py-2.5 text-muted-foreground">
                    {hasDiff && (isOpen ? <ChevronDown className="size-3.5" /> : <ChevronRight className="size-3.5" />)}
                  </td>
                  <td className="whitespace-nowrap px-4 py-2.5 text-muted-foreground">
                    {new Date(e.created_at).toLocaleString()}
                  </td>
                  <td className="px-4 py-2.5 text-foreground">
                    {e.actor_name ?? 'System'}
                    {e.actor_role && (
                      <span className="ml-1.5 text-[11px] text-muted-foreground">({e.actor_role})</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-foreground">{e.action.replace(/[._]/g, ' ')}</td>
                  <td className="px-4 py-2.5 text-foreground">
                    {e.target_label ?? e.target_id ?? e.target_type}
                    <span className="ml-1.5 text-[11px] text-muted-foreground">({e.target_type})</span>
                  </td>
                </tr>
                {isOpen && hasDiff && (
                  <tr className="border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]">
                    <td className="px-2 py-2.5" />
                    <td className="px-4 py-2.5 text-[11px] font-semibold uppercase text-muted-foreground" colSpan={1}>
                      Previous
                    </td>
                    <td className="px-4 py-2.5 text-muted-foreground" colSpan={3}>
                      {formatValue(e.previous_value)}
                    </td>
                  </tr>
                )}
                {isOpen && hasDiff && (
                  <tr className="bg-[var(--color-surface-raised)]">
                    <td className="px-2 py-2.5" />
                    <td className="px-4 py-2.5 text-[11px] font-semibold uppercase text-muted-foreground" colSpan={1}>
                      New
                    </td>
                    <td className="px-4 py-2.5 text-muted-foreground" colSpan={3}>
                      {formatValue(e.new_value)}
                    </td>
                  </tr>
                )}
              </Fragment>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
