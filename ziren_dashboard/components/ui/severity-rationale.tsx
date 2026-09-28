'use client';

/**
 * Severity rationale — why an incident carries the severity it carries.
 *
 * The severity on a Ziren incident is not a model opinion. It is the output of
 * a numbered rule (SR001–SR012) evaluated against signals read from the report
 * and from the resident's own wizard answers. This component exists so the
 * dispatcher — and the panel at the defense — sees the rule by name rather
 * than a bare severity word.
 *
 * Two surfaces:
 *   <SeverityRule />       one line, for a queue or history card
 *   <SeverityRationale />  full panel, for the incident detail view
 *
 * Design notes
 *   - The rule id is monospaced, matching the INC-XXXXXX treatment on cards.
 *     An identifier should look like an identifier; that is the whole point.
 *   - Colour is inherited from the severity the rule produced, so the red
 *     reserved for `critical` in globals.css stays reserved — this component
 *     never picks a colour of its own.
 *   - A missing rationale is stated, not hidden. `signals: null` means the
 *     model never ran, which is exactly when a human most needs to know.
 */

import {
  AlertTriangle,
  CircleHelp,
  Hash,
  ScrollText,
  Sparkles,
  UserCheck,
  UserRoundSearch,
} from 'lucide-react';

import {
  LOW_CONFIDENCE_THRESHOLD,
  type SeverityLevel,
  type TriageSignals,
} from '@/lib/api/dispatch';

const SEV_COLOR: Record<string, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

function severityColor(sev: SeverityLevel | null | undefined): string {
  return (sev && SEV_COLOR[sev]) || 'var(--color-text-muted)';
}

/**
 * How each verification outcome should read to a dispatcher.
 *
 * MISMATCH_FLAGGED is the one that changes what someone does next: the model
 * read the report as a different category than the resident selected. It is
 * surfaced, never auto-resolved — the resident is at the scene and the model
 * is not.
 */
const VERIFICATION: Record<
  string,
  { label: string; detail: string; tone: 'warn' | 'info' | 'ok'; Icon: typeof UserCheck }
> = {
  AGREE: {
    label: 'Model agrees',
    detail: 'The report text reads as the same category the resident selected.',
    tone: 'ok',
    Icon: UserCheck,
  },
  MISMATCH_FLAGGED: {
    label: 'Category mismatch',
    detail: 'The text reads as a different category than the resident chose. Confirm before dispatch.',
    tone: 'warn',
    Icon: AlertTriangle,
  },
  UNCERTAIN: {
    label: 'Model unsure',
    detail: 'Confidence fell below the flag threshold, so the resident’s selection stands.',
    tone: 'info',
    Icon: CircleHelp,
  },
  NO_SELECTION: {
    label: 'No category chosen',
    detail: 'The resident did not pick a category, so the model’s reading was used.',
    tone: 'info',
    Icon: CircleHelp,
  },
  NO_TEXT: {
    label: 'No report text',
    detail: 'Category and wizard answers were used as given.',
    tone: 'info',
    Icon: CircleHelp,
  },
};

const TONE_COLOR: Record<string, string> = {
  warn: 'var(--color-system-warning)',
  info: 'var(--color-text-muted)',
  ok:   'var(--color-system-success)',
};

/** Turn `hazard_spreading` into `hazard spreading` for display. */
function humanise(key: string): string {
  return key.replace(/_/g, ' ');
}

// ---------------------------------------------------------------------------
// Compact — one line under a card's report text
// ---------------------------------------------------------------------------

export function SeverityRule({
  signals,
  severity,
}: {
  signals: TriageSignals | null | undefined;
  severity: SeverityLevel | null | undefined;
}) {
  const rule = signals?.severity_rule;
  const reason = signals?.severity_reason;

  // No rule means the model never produced one for this report. Say so — a
  // blank space here reads as "nothing to see", which is the opposite of true.
  if (!rule) {
    return (
      <span
        className="inline-flex items-center gap-1.5 text-[11.5px] font-medium"
        style={{ color: 'var(--color-text-muted)' }}
        title="No automated triage ran for this report — a dispatcher sets the severity."
      >
        <CircleHelp size={11} strokeWidth={2} />
        Not triaged &middot; needs manual review
      </span>
    );
  }

  const color = severityColor(severity);

  return (
    <span
      className="inline-flex items-center gap-1.5 text-[11.5px] min-w-0"
      title={`Rule ${rule}: ${reason ?? ''}`}
    >
      <ScrollText size={11} strokeWidth={2} style={{ color, flexShrink: 0 }} />
      <span className="font-mono font-bold" style={{ color }}>
        {rule}
      </span>
      {reason && (
        <>
          <span style={{ color: 'var(--color-text-muted)' }}>&middot;</span>
          <span className="truncate font-medium" style={{ color: 'var(--color-text-secondary)' }}>
            {reason}
          </span>
        </>
      )}
      {/* The queue is where the dispatcher decides who to send, so an
          untrustworthy agency has to be visible before the card is opened. */}
      {signals?.needs_manual_agency && (
        <span
          className="inline-flex items-center gap-1 font-semibold shrink-0"
          style={{ color: 'var(--color-system-warning)' }}
          title={signals.agency_note ?? 'Agency came from a low-confidence reading — choose manually.'}
        >
          <UserRoundSearch size={11} strokeWidth={2} />
          pick agency
        </span>
      )}
    </span>
  );
}

// ---------------------------------------------------------------------------
// Full panel — incident detail view
// ---------------------------------------------------------------------------

export function SeverityRationale({
  signals,
  severity,
}: {
  signals: TriageSignals | null | undefined;
  severity: SeverityLevel | null | undefined;
}) {
  const color = severityColor(severity);

  if (!signals || !signals.severity_rule) {
    return (
      <div
        className="rounded-[var(--radius-xl)] border p-4"
        style={{
          backgroundColor: 'var(--color-surface-card)',
          borderColor: 'var(--color-surface-border)',
        }}
      >
        {/* Deliberately not .text-label-sm's own muted colour — see the
            identical note on _Section's heading in incident-detail-modal.tsx.
            This panel sits right after that modal's six section headings in
            the same reading flow, so it gets the same bold/foreground/ruled
            treatment rather than reverting to the quiet shared style. */}
        <p className="mb-3 border-b border-[var(--color-surface-border)] pb-1.5 text-[13.5px] font-bold uppercase tracking-wide text-foreground">
          WHY THIS SEVERITY
        </p>
        <div className="flex items-start gap-2.5">
          <CircleHelp
            size={16}
            strokeWidth={2}
            style={{ color: 'var(--color-text-muted)', marginTop: 2, flexShrink: 0 }}
          />
          <div>
            <p className="text-body font-semibold text-[var(--color-text-primary)]">
              No automated triage
            </p>
            <p className="text-[12.5px] mt-1 leading-relaxed" style={{ color: 'var(--color-text-secondary)' }}>
              The triage model did not run for this report, so no severity rule
              was applied. The report was saved regardless — a classifier being
              unavailable must never cost a resident their report. Set the
              severity manually when dispatching.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const verification = signals.verification_status
    ? VERIFICATION[signals.verification_status]
    : undefined;

  const fired = Object.entries(signals.signals ?? {});
  const fromWizard = new Set(signals.signals_from_wizard ?? []);
  const confidencePct =
    typeof signals.model_confidence === 'number'
      ? `${Math.round(signals.model_confidence * 100)}%`
      : null;

  // Only when a number exists. `model_confidence` is null for a report with no
  // text at all, and "low confidence" would be a lie about that — the model
  // was not unsure, it was never asked.
  const lowConfidence =
    typeof signals.model_confidence === 'number' &&
    signals.model_confidence < LOW_CONFIDENCE_THRESHOLD;

  return (
    <div
      className="rounded-[var(--radius-xl)] border p-4"
      style={{
        backgroundColor: 'var(--color-surface-card)',
        borderColor: 'var(--color-surface-border)',
      }}
    >
      <p className="text-label-sm text-[var(--color-text-muted)] mb-3">WHY THIS SEVERITY</p>

      {/* The headline: the rule that fired, by name. */}
      <div
        className="rounded-[var(--radius-lg)] border p-3 mb-3"
        style={{
          borderColor: `color-mix(in srgb, ${color} 35%, transparent)`,
          backgroundColor: `color-mix(in srgb, ${color} 7%, transparent)`,
        }}
      >
        <div className="flex items-start gap-2.5">
          <ScrollText size={16} strokeWidth={2} style={{ color, marginTop: 1, flexShrink: 0 }} />
          <div className="min-w-0">
            <div className="flex items-baseline gap-2 flex-wrap">
              <span className="font-mono text-[14px] font-bold" style={{ color }}>
                {signals.severity_rule}
              </span>
              {severity && (
                <span
                  className="text-[11px] font-bold uppercase tracking-wide"
                  style={{ color }}
                >
                  {severity}
                </span>
              )}
            </div>
            {signals.severity_reason && (
              <p
                className="text-body font-semibold mt-0.5"
                style={{ color: 'var(--color-text-primary)' }}
              >
                {signals.severity_reason}
              </p>
            )}
          </div>
        </div>
      </div>

      {/* What the model read, and whether it matched the resident. */}
      <div className="space-y-2.5">
        {signals.model_predicted && (
          <div className="flex items-start gap-2">
            <Sparkles
              size={13}
              strokeWidth={2}
              style={{ color: 'var(--color-ai-suggested)', marginTop: 2, flexShrink: 0 }}
            />
            <p className="text-[12.5px] leading-relaxed" style={{ color: 'var(--color-text-secondary)' }}>
              Model read this as{' '}
              <span className="font-semibold" style={{ color: 'var(--color-text-primary)' }}>
                {signals.model_predicted}
              </span>
              {confidencePct && ` at ${confidencePct} confidence`}
              {lowConfidence && (
                <span
                  className="ml-1.5 inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[11px] font-bold align-middle"
                  style={{
                    color: 'var(--color-system-warning)',
                    backgroundColor:
                      'color-mix(in srgb, var(--color-system-warning) 12%, transparent)',
                    border:
                      '1px solid color-mix(in srgb, var(--color-system-warning) 35%, transparent)',
                  }}
                >
                  <AlertTriangle size={10} strokeWidth={2.5} />
                  low confidence — please verify incident type
                </span>
              )}
              {signals.runner_up && (
                <span style={{ color: 'var(--color-text-muted)' }}>
                  {' '}(next: {signals.runner_up.category}{' '}
                  {Math.round(signals.runner_up.confidence * 100)}%)
                </span>
              )}
              {signals.user_selected && (
                <>
                  . Resident selected{' '}
                  <span className="font-semibold" style={{ color: 'var(--color-text-primary)' }}>
                    {humanise(signals.user_selected)}
                  </span>
                </>
              )}
              .
            </p>
          </div>
        )}

        {verification && (
          <div className="flex items-start gap-2">
            <verification.Icon
              size={13}
              strokeWidth={2}
              style={{ color: TONE_COLOR[verification.tone], marginTop: 2, flexShrink: 0 }}
            />
            <p className="text-[12.5px] leading-relaxed" style={{ color: 'var(--color-text-secondary)' }}>
              <span className="font-semibold" style={{ color: TONE_COLOR[verification.tone] }}>
                {verification.label}
              </span>
              {' — '}
              {verification.detail}
            </p>
          </div>
        )}
      </div>

      {/*
        The agency suggestion is scored separately from the severity, because
        they can fail independently: SR010 can park an unreadable report at a
        safe MODERATE while the agency beside it still came from a coin-flip
        reading. Boxed rather than listed so it cannot be skimmed past — this
        is the one line that asks the dispatcher to do something.
      */}
      {/* A number the recogniser ran into the next word. Boxed for the same
          reason as the agency warning: it asks the dispatcher to do something,
          and the count is the field they would otherwise trust without
          looking. */}
      {signals.count_uncertain && (
        <div
          className="mt-3 rounded-[var(--radius-lg)] border p-2.5 flex items-start gap-2.5"
          style={{
            borderColor: 'color-mix(in srgb, var(--color-system-warning) 35%, transparent)',
            backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 8%, transparent)',
          }}
        >
          <Hash
            size={15}
            strokeWidth={2}
            style={{ color: 'var(--color-system-warning)', marginTop: 1, flexShrink: 0 }}
          />
          <div className="min-w-0">
            <p
              className="text-[12.5px] font-bold"
              style={{ color: 'var(--color-system-warning)' }}
            >
              Confirm how many
            </p>
            <p
              className="text-[12.5px] leading-relaxed mt-0.5"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              {signals.count_note ??
                'The recogniser ran a number into the word after it, so any count here may be wrong.'}
              {' '}Play the recording rather than reading the number.
            </p>
          </div>
        </div>
      )}

      {signals.needs_manual_agency && (
        <div
          className="mt-3 rounded-[var(--radius-lg)] border p-2.5 flex items-start gap-2.5"
          style={{
            borderColor: 'color-mix(in srgb, var(--color-system-warning) 35%, transparent)',
            backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 8%, transparent)',
          }}
        >
          <UserRoundSearch
            size={15}
            strokeWidth={2}
            style={{ color: 'var(--color-system-warning)', marginTop: 1, flexShrink: 0 }}
          />
          <div className="min-w-0">
            <p
              className="text-[12.5px] font-bold"
              style={{ color: 'var(--color-system-warning)' }}
            >
              Choose the responder manually
            </p>
            <p
              className="text-[12.5px] leading-relaxed mt-0.5"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              {signals.agency_note ??
                'The suggested agency came from a low-confidence model reading.'}
              {signals.routing_agencies && signals.routing_agencies.length > 0 && (
                <>
                  {' '}Suggested:{' '}
                  <span className="font-semibold" style={{ color: 'var(--color-text-primary)' }}>
                    {signals.routing_agencies.join(', ')}
                  </span>
                  {' '}— treat this as a starting point, not a recommendation.
                </>
              )}
            </p>
          </div>
        </div>
      )}

      {/* The signals the rule was evaluated against. */}
      {fired.length > 0 && (
        <div className="mt-3 pt-3" style={{ borderTop: '1px solid var(--color-surface-border)' }}>
          <p className="text-[11px] text-[var(--color-text-muted)] mb-2">
            SIGNALS READ
            <span className="normal-case tracking-normal font-normal">
              {' '}— a dot marks one the resident answered themselves
            </span>
          </p>
          <div className="flex flex-wrap gap-1.5">
            {fired.map(([key, value]) => (
              <span
                key={key}
                className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-semibold"
                style={{
                  backgroundColor: 'var(--color-surface-raised)',
                  color: 'var(--color-text-secondary)',
                }}
                title={
                  fromWizard.has(key)
                    ? 'Answered by the resident in the report wizard'
                    : 'Read from the report text'
                }
              >
                {fromWizard.has(key) && (
                  <span
                    aria-hidden
                    style={{
                      width: 5,
                      height: 5,
                      borderRadius: '50%',
                      backgroundColor: 'var(--color-brand)',
                      flexShrink: 0,
                    }}
                  />
                )}
                {humanise(key)}
                {value !== true && (
                  <span style={{ color: 'var(--color-text-muted)' }}>: {String(value)}</span>
                )}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Provenance: which model release produced this. */}
      {signals.engine_version && (
        <p className="text-[11px] mt-3" style={{ color: 'var(--color-text-muted)' }}>
          {signals.engine ?? 'triage model'} v{signals.engine_version} &middot; advisory only —
          a responder must validate before dispatch
        </p>
      )}
    </div>
  );
}
