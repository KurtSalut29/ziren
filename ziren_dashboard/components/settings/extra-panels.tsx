'use client';

/**
 * Provincial-Admin panels that fetch or derive something real: AI & NLP and
 * the incident categories. (About Ziren has its own file now, panels/about.tsx.)
 */

import { useEffect, useState } from 'react';
import {
  Activity, BrainCircuit, Flame, ShieldAlert, Tags,
} from 'lucide-react';
import { apiClient } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { CATEGORY_LABELS, REAL_CATEGORIES } from '@/lib/charts/queue-series';
import { SettingsPanel, SettingsRow, SettingsRowGroup } from '@/components/settings/settings-kit';

// ── AI & NLP (Provincial Admin) ─────────────────────────────────

interface TriageStatus {
  model_loaded: boolean;
  version: string;
  flag_threshold: number | null;
  error: string | null;
  stt_corrections: number;
}

export function AiNlpPanel({ token }: { token: string }) {
  const [triage, setTriage] = useState<TriageStatus | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiClient.get<TriageStatus>('/triage/status', token)
      .then(setTriage)
      .catch((e: unknown) => setError(e instanceof Error ? e.message : 'Failed to load.'));
  }, [token]);

  return (
    <SettingsPanel
      description="How incoming reports are classified and scored before a dispatcher ever sees them."
      icon={BrainCircuit}
      title="AI & NLP"
    >
      <div
        className="flex items-start gap-3 rounded-[var(--radius-card)] border px-4 py-3"
        style={{
          borderColor: 'color-mix(in srgb, var(--color-system-warning) 40%, transparent)',
          backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 8%, transparent)',
        }}
      >
        <ShieldAlert className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-system-warning)' }} />
        <p className="text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
          <span className="font-semibold text-foreground">AI does not make the final dispatch decision.</span>{' '}
          It suggests a severity and category from the report text; a dispatcher always confirms
          before a crew is sent. Severity Rules (under Integrations) governs how those suggestions
          are computed, not this panel.
        </p>
      </div>

      {error && <Alert message={error} variant="error" />}

      <SettingsRowGroup>
        <SettingsRow label="Model status">
          {triage ? (
            <span className="flex items-center gap-1.5 text-[13px] font-medium" style={{
              color: triage.model_loaded ? 'var(--color-system-success)' : 'var(--color-severity-critical)',
            }}>
              <span
                aria-hidden
                className="size-1.5 rounded-full"
                style={{ backgroundColor: triage.model_loaded ? 'var(--color-system-success)' : 'var(--color-severity-critical)' }}
              />
              {triage.model_loaded ? 'Loaded' : triage.error ?? 'Not loaded'}
            </span>
          ) : (
            <Skeleton className="h-4 w-20" />
          )}
        </SettingsRow>
        {triage && (
          <>
            <SettingsRow label="Model version">
              <span className="font-mono text-[13px] text-muted-foreground">v{triage.version}</span>
            </SettingsRow>
            <SettingsRow
              description="Speech-to-text corrections loaded for Waray/Bisaya/Tagalog dialect handling."
              label="Correction entries"
            >
              <span className="text-[13px] text-muted-foreground">{triage.stt_corrections}</span>
            </SettingsRow>
          </>
        )}
        <SettingsRow description="A report the model cannot confidently score is always flagged for a human, never guessed at silently." label="Human validation">
          <span className="text-[13px] font-medium text-foreground">Required</span>
        </SettingsRow>
        <SettingsRow description="Words are read in whichever of these the reporter used — nothing is translated before scoring." label="Languages handled">
          <span className="text-[13px] text-muted-foreground">English, Filipino, Waray, Cebuano/Bisaya</span>
        </SettingsRow>
      </SettingsRowGroup>
    </SettingsPanel>
  );
}

// ── Incident Categories (Provincial Admin) ───────────────────────

const CATEGORY_AGENCY: Record<string, string> = {
  fire: 'BFP',
  domestic_dispute_crime: 'PNP',
  medical_trauma: 'MDRRMO',
  vehicular: 'MDRRMO',
  flood_landslide_calamity: 'MDRRMO',
};

export function IncidentCategoriesPanel() {
  return (
    <SettingsPanel
      description="The categories a resident can choose when filing a report, and which agency each routes to by default."
      icon={Tags}
      title="Incident Categories"
    >
      <p className="text-[12.5px] text-muted-foreground">
        These are fixed in the triage model&apos;s code, not a database table — adding or renaming
        one means retraining the classifier, so there is no add/edit control here to promise one.
      </p>
      <SettingsRowGroup>
        {REAL_CATEGORIES.map(key => (
          <SettingsRow icon={Flame} key={key} label={CATEGORY_LABELS[key]}>
            <span className="rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] font-bold text-muted-foreground">
              Routes to {CATEGORY_AGENCY[key]}
            </span>
          </SettingsRow>
        ))}
        <SettingsRow description="A resident who doesn't fit any category above, or didn't choose one." icon={Activity} label="Other">
          <span className="rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] font-bold text-muted-foreground">
            Nearest station, any agency
          </span>
        </SettingsRow>
      </SettingsRowGroup>
    </SettingsPanel>
  );
}
