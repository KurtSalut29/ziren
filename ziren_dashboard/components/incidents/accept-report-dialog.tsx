'use client';

/**
 * "Accept this report?" — the verification step before anyone is dispatched.
 *
 * It used to be two lines of grey text and two buttons (tester screenshot,
 * 2026-10-05: "sobrang pangit niya tignan"). Accepting is a decision about a
 * specific report, so the dialog now shows WHICH report — what it is, how
 * serious, where, who sent it — and spells out what the click changes, in the
 * order it happens: the reporter hears back, dispatch opens, and the two
 * review alternatives close for good.
 *
 * One component for both places the confirmation lives (the incident modal and
 * the full incident page), so the two cannot drift apart again.
 *
 * Colours keep their meanings: the action is orange because it is the primary
 * CTA, severity is colour AND icon AND word, and the one irreversible
 * consequence is amber (a warning), not red (red is critical severity only).
 */

import { Check, CircleCheck, Loader2, MapPin, MessageSquareOff, Send, ShieldCheck, Siren, UserRound } from 'lucide-react';
import type { IncidentDetail, SeverityLevel } from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { relativeTime } from '@/lib/format/relative-time';
import { CATEGORY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogMedia,
  AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { isIdVerified } from '@/lib/residents/trust';

export function AcceptReportDialog({
  open,
  incident,
  loading,
  dispatchable,
  onCancel,
  onConfirm,
}: {
  open: boolean;
  incident: IncidentDetail | null;
  loading: boolean;
  /** Whether this report can be dispatched once accepted (not an SOS that
   *  only needs a call back, not already closed). */
  dispatchable: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const category = incident?.incident_category ?? null;
  const categoryLabel = category && category !== 'other'
    ? CATEGORY_LABELS[category] ?? category
    : 'Uncategorised report';
  const CategoryIcon = (category && CATEGORY_ICON[category]) || Siren;
  const sev = (incident?.suggested_severity ?? incident?.severity ?? null) as SeverityLevel | null;
  const SevIcon = SEV_ICON[sev ?? 'untriaged'] ?? SEV_ICON.untriaged;
  const sevColor = sev ? SEV_COLOR[sev] : 'var(--color-text-muted)';
  const recordNo = incident?.record_number ?? (incident ? `INC-${incident.id.slice(0, 6).toUpperCase()}` : '');
  const place = incident?.location_address?.trim() || null;
  const reporter = incident?.users ?? null;

  const next: { icon: typeof Check; text: string; tone: 'ok' | 'warn' }[] = [
    { icon: Send, text: 'The reporter is told their report was accepted.', tone: 'ok' },
    ...(dispatchable
      ? [{ icon: CircleCheck, text: 'Dispatch opens: you can send a responder next.', tone: 'ok' as const }]
      : []),
    { icon: MessageSquareOff, text: 'Reject and Request clarification will no longer be available.', tone: 'warn' },
  ];

  return (
    <AlertDialog open={open} onOpenChange={o => { if (!o && !loading) onCancel(); }}>
      <AlertDialogContent className="data-[size=default]:sm:max-w-[460px]" data-testid="accept-report-dialog">
        <AlertDialogHeader>
          <AlertDialogMedia tone="brand"><ShieldCheck /></AlertDialogMedia>
          <AlertDialogTitle>Accept this report?</AlertDialogTitle>
          <AlertDialogDescription>
            You are confirming this is a real emergency for your station.
          </AlertDialogDescription>
        </AlertDialogHeader>

        {incident && (
          <div
            className="rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-3.5"
            style={{ borderLeft: `4px solid ${sevColor}` }}
          >
            <div className="flex items-start gap-3">
              <span
                className="flex size-10 shrink-0 items-center justify-center rounded-lg"
                style={{ background: `color-mix(in srgb, ${sevColor} 14%, transparent)`, color: sevColor }}
              >
                <CategoryIcon className="size-5" />
              </span>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                  <p className="truncate text-[15px] font-semibold text-[var(--color-text-primary)]">{categoryLabel}</p>
                  <span
                    className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide"
                    style={{ background: `color-mix(in srgb, ${sevColor} 14%, transparent)`, color: sevColor }}
                  >
                    <SevIcon className="size-3" /> {sev ?? 'Not ranked'}
                  </span>
                </div>
                <p className="mt-0.5 font-mono text-[12px] text-[var(--color-text-muted)]">
                  {recordNo} · reported {relativeTime(incident.created_at)}
                </p>
              </div>
            </div>

            {(place || reporter) && (
              <div className="mt-3 space-y-1.5 border-t border-[var(--color-surface-border)] pt-3 text-[13px] text-[var(--color-text-secondary)]">
                {place && (
                  <p className="flex items-start gap-2">
                    <MapPin className="mt-0.5 size-3.5 shrink-0 text-[var(--color-text-muted)]" />
                    <span className="line-clamp-2">{place}</span>
                  </p>
                )}
                {reporter && (
                  <p className="flex items-center gap-2">
                    <UserRound className="size-3.5 shrink-0 text-[var(--color-text-muted)]" />
                    <span className="truncate">{reporter.full_name}</span>
                    <span
                      className="shrink-0 rounded-full px-1.5 py-px text-[10.5px] font-semibold"
                      style={isIdVerified(reporter)
                        ? { background: 'var(--color-system-success-bg)', color: 'var(--color-system-success)' }
                        : { background: 'var(--color-system-warning-bg)', color: 'var(--color-system-warning)' }}
                    >
                      {isIdVerified(reporter) ? 'Verified' : 'Not verified'}
                    </span>
                  </p>
                )}
              </div>
            )}
          </div>
        )}

        <div>
          <p className="mb-2 text-[11px] font-bold uppercase tracking-wider text-[var(--color-text-muted)]">
            What happens next
          </p>
          <ul className="space-y-2">
            {next.map(({ icon: Icon, text, tone }) => (
              <li className="flex items-start gap-2.5 text-[13px] leading-snug" key={text}>
                <span
                  className="mt-px flex size-5 shrink-0 items-center justify-center rounded-full"
                  style={tone === 'ok'
                    ? { background: 'var(--color-system-success-bg)', color: 'var(--color-system-success)' }
                    : { background: 'var(--color-system-warning-bg)', color: 'var(--color-system-warning)' }}
                >
                  <Icon className="size-3" />
                </span>
                <span className={tone === 'ok' ? 'text-[var(--color-text-primary)]' : 'text-[var(--color-text-secondary)]'}>
                  {text}
                </span>
              </li>
            ))}
          </ul>
        </div>

        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>Back</AlertDialogCancel>
          <AlertDialogAction
            data-testid="accept-report-confirm"
            disabled={loading}
            onClick={e => { e.preventDefault(); onConfirm(); }}
          >
            {loading
              ? <><Loader2 className="size-4 animate-spin" /> Accepting…</>
              : <><Check className="size-4" /> Accept report</>}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
