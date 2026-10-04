'use client';

import { useEffect, useState } from 'react';
import { ChevronDown, History } from 'lucide-react';
import { fetchNarrativeVersions, type NarrativeVersion } from '@/lib/api/dispatch';

const FIELD_LABELS: Record<string, string> = {
  narrative: 'narrative',
  reporting_person_name: 'reporting person',
  incident_occurred_at: 'date and time',
  place_of_incident: 'place',
  prepared_by_name: 'prepared by',
  investigator_name: 'investigator',
  reference_no: 'reference no.',
  details: 'detailed sections',
};

/**
 * Earlier versions of a finalized narrative report (evaluator finding #8).
 *
 * Each entry is the report as it read before someone changed it, with who,
 * when, what and why. Read-only: the versions themselves cannot be edited or
 * deleted, by the database's own rule (migration 044).
 */
export function NarrativeVersions({
  incidentId,
  token,
  refreshKey,
}: {
  incidentId: string;
  token: string;
  refreshKey: number;
}) {
  const [versions, setVersions] = useState<NarrativeVersion[] | null>(null);
  const [open, setOpen] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchNarrativeVersions(incidentId, token)
      .then(v => { if (!cancelled) setVersions(v); })
      .catch(() => { if (!cancelled) setVersions([]); });
    return () => { cancelled = true; };
  }, [incidentId, token, refreshKey]);

  if (!versions) return null;

  return (
    <section
      className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-5 py-4"
      data-testid="narrative-versions"
    >
      <h3 className="mb-2 flex items-center gap-2 text-[14px] font-semibold text-[var(--color-text-primary)]">
        <History size={15} /> Changes after finalizing
      </h3>
      {versions.length === 0 ? (
        <p className="text-[12.5px] text-[var(--color-text-secondary)]">
          Not changed since it was finalized.
        </p>
      ) : (
        <ol className="flex flex-col gap-2">
          {versions.map(v => {
            const expanded = open === v.id;
            return (
              <li className="rounded-[var(--radius-md)] border border-[var(--color-surface-border)]" key={v.id}>
                <button
                  aria-expanded={expanded}
                  className="flex w-full items-start gap-3 px-3 py-2 text-left"
                  onClick={() => setOpen(expanded ? null : v.id)}
                  type="button"
                >
                  <span className="mt-0.5 shrink-0 rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 font-mono text-[11px] text-[var(--color-text-secondary)]">
                    v{v.version_no}
                  </span>
                  <span className="min-w-0 flex-1 text-[12.5px] leading-snug">
                    <span className="font-semibold text-[var(--color-text-primary)]">
                      {v.changed_by_name ?? 'An administrator'}
                    </span>
                    <span className="text-[var(--color-text-secondary)]">
                      {' changed the '}
                      {v.changed_fields.map(f => FIELD_LABELS[f] ?? f).join(', ') || 'report'}
                      {' · '}
                      {new Date(v.changed_at).toLocaleString()}
                    </span>
                    <span className="mt-0.5 block text-[var(--color-text-primary)]">“{v.change_reason}”</span>
                  </span>
                  <ChevronDown
                    className={`mt-1 shrink-0 text-[var(--color-text-muted)] transition-transform ${expanded ? 'rotate-180' : ''}`}
                    size={15}
                  />
                </button>
                {expanded && (
                  <div className="border-t border-[var(--color-surface-border)] px-3 py-2">
                    <p className="mb-1 text-[11.5px] font-semibold uppercase tracking-wide text-[var(--color-text-muted)]">
                      Narrative before this change
                    </p>
                    <p className="whitespace-pre-wrap text-[13px] text-[var(--color-text-primary)]">
                      {v.snapshot.narrative || '(empty)'}
                    </p>
                  </div>
                )}
              </li>
            );
          })}
        </ol>
      )}
    </section>
  );
}
