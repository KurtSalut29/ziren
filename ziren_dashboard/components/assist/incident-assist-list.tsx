'use client';

/**
 * "Stations we asked" — inside the incident detail view, under the Request
 * help button: every station this incident has asked, whether they answered,
 * and the last thing they said, one click from the full conversation.
 *
 * Before this, a request left the incident the moment it was sent; the only
 * way to see whether anyone was coming was to go and find the Agencies tab.
 */

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { ArrowRight, MessageSquare } from 'lucide-react';
import { listAssistRequests, type AssistRequestSummary } from '@/lib/api/assist-requests';
import { AG_COLOR, AGENCY_ICON } from '@/components/incidents/incident-vocabulary';
import { ASSIST_STATUS, ago } from './assist-vocabulary';

export function IncidentAssistList({
  incidentId,
  token,
  version,
}: {
  incidentId: string;
  token: string;
  /** Bumped by the caller after a send, to re-read immediately. */
  version: number;
}) {
  const [rows, setRows] = useState<AssistRequestSummary[] | null>(null);

  useEffect(() => {
    let live = true;
    const load = () => listAssistRequests('sent', token, incidentId)
      .then(r => { if (live) setRows(r); })
      .catch(() => { if (live) setRows(prev => prev ?? []); });
    void load();
    const t = window.setInterval(() => { if (document.visibilityState === 'visible') void load(); }, 15_000);
    return () => { live = false; window.clearInterval(t); };
  }, [incidentId, token, version]);

  if (!rows || rows.length === 0) return null;

  return (
    <ul className="mt-3 flex flex-col gap-2">
      {rows.map(r => {
        const st = ASSIST_STATUS[r.status];
        const Icon = r.requested_agency_type ? AGENCY_ICON[r.requested_agency_type] : undefined;
        const hue = r.requested_agency_type ? AG_COLOR[r.requested_agency_type] : 'var(--color-text-tertiary)';
        return (
          <li key={r.id}>
            <Link
              className="group flex items-center gap-3 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2.5 transition-colors hover:border-[var(--color-brand)]"
              href={`/assist-requests?id=${r.id}`}
            >
              {Icon && (
                <span
                  aria-hidden="true"
                  className="flex size-8 shrink-0 items-center justify-center rounded-lg"
                  style={{ backgroundColor: `color-mix(in srgb, ${hue} 14%, transparent)`, color: hue }}
                >
                  <Icon className="size-4" />
                </span>
              )}
              <span className="min-w-0 flex-1">
                <span className="flex items-center gap-2">
                  <span className="truncate text-[13px] font-semibold text-foreground">{r.requested_agency_name ?? 'Station'}</span>
                  <span className="inline-flex shrink-0 items-center gap-1 rounded-full px-2 py-0.5 text-[10.5px] font-bold" style={{ backgroundColor: st.bg, color: st.fg }}>
                    <st.icon aria-hidden="true" className="size-3" />{st.outgoing}
                  </span>
                </span>
                {r.last_message_preview && (
                  <span className="mt-0.5 flex items-center gap-1.5 text-[12px] text-muted-foreground">
                    <MessageSquare aria-hidden="true" className="size-3 shrink-0" />
                    <span className="truncate">{r.last_message_preview}</span>
                    <span className="shrink-0">· {ago(r.last_message_at)}</span>
                  </span>
                )}
              </span>
              <ArrowRight aria-hidden="true" className="size-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
            </Link>
          </li>
        );
      })}
    </ul>
  );
}
