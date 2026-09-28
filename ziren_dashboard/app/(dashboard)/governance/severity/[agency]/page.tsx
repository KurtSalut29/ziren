'use client';

/**
 * One agency's severity rubric — its rules, its versions, and its audit log.
 *
 * This page changes what the triage engine does to every incoming report for
 * an agency, so two things get more ceremony than elsewhere on the console:
 * activation goes through a real modal dialog rather than a hand-drawn overlay,
 * and the difference between "previewing" and "live" is stated on screen the
 * whole time it is true.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import {
  AlertTriangle, ArrowLeft, CheckCircle2, ChevronDown, Clock, Eye, FileJson,
  FlaskConical, History, Upload, Zap,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import {
  activateConfig, getActiveConfig, getAuditLog, getConfig, listConfigs,
  uploadConfig,
  type AgencyType, type RubricAuditEntry, type RubricConfigDetail,
  type RubricConfigSummary, type RubricRule, type SeverityLevel,
} from '@/lib/api/rubric';
import { Alert } from '@/components/ui/alert';
import { Fig } from '@/components/ui/fig';
import { Button } from '@/components/efferd/ui/button';
import { Input } from '@/components/efferd/ui/input';
import { Label } from '@/components/efferd/ui/label';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { Card, CardContent } from '@/components/efferd/ui/card';
import {
  Tabs, TabsContent, TabsList, TabsTrigger,
} from '@/components/efferd/ui/tabs';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { useNotice } from '@/lib/toast';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDateTime } from '@/lib/format/datetime';

// ── Constants ─────────────────────────────────────────────────

const VALID_AGENCIES: AgencyType[] = ['BFP', 'PNP', 'MDRRMO'];

const AGENCY_LABELS: Record<AgencyType, string> = {
  BFP: 'Bureau of Fire Protection',
  PNP: 'Philippine National Police',
  MDRRMO: 'Municipal DRRMO',
};

/**
 * Tokens with no hex fallback, deliberately.
 *
 * These maps used to read `var(--color-agency-bfp, #E53E3E)`. Every fallback
 * was a DIFFERENT colour from the token it backed — #E53E3E against the real
 * #EF4444, #3182CE against #0EA5E9, #38A169 against #10B981, and the same
 * story across all four severities. A fallback that silently substitutes a
 * hue the design system does not contain is worse than no fallback: the page
 * keeps rendering and nobody finds out the token went missing.
 */
const AGENCY_COLOR: Record<AgencyType, string> = {
  BFP:    'var(--color-agency-bfp)',
  PNP:    'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

const SEVERITY_COLOR: Record<SeverityLevel, string> = {
  critical: 'var(--color-severity-critical)',
  high:     'var(--color-severity-high)',
  medium:   'var(--color-severity-medium)',
  low:      'var(--color-severity-low)',
};

/** Worst first. Never sorted at render — see the note in map-legend. */
const SEVERITY_ORDER: SeverityLevel[] = ['critical', 'high', 'medium', 'low'];

/**
 * Upload ceiling.
 *
 * A rubric config is a few hundred rules of JSON — tens of kilobytes. The
 * handler reads the whole file into memory with `file.text()` before parsing,
 * so without a cap, picking the wrong file in the dialog freezes the tab
 * rather than showing an error.
 */
const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;

type TabKey = 'rules' | 'versions' | 'audit';

// ── Main page ─────────────────────────────────────────────────

export default function RubricAgencyPage() {
  const params = useParams();
  const { token, isAgencyAdmin } = useAuth();
  const agencyType = (params?.agency as string)?.toUpperCase() as AgencyType;
  const isValidAgency = VALID_AGENCIES.includes(agencyType);

  const [activeConfig, setActiveConfig] = useState<RubricConfigDetail | null>(null);
  const [configs, setConfigs]           = useState<RubricConfigSummary[]>([]);
  const [auditLog, setAuditLog]         = useState<RubricAuditEntry[]>([]);
  const [loading, setLoading]           = useState(true);
  const [error, setError]               = useState<string | null>(null);
  const setNotice = useNotice();
  const [tab, setTab]                   = useState<TabKey>('rules');

  const [uploading, setUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [activating, setActivating] = useState(false);
  const [activateReason, setActivateReason] = useState('');
  const [confirmActivate, setConfirmActivate] = useState<RubricConfigSummary | null>(null);

  const [previewConfig, setPreviewConfig] = useState<RubricConfigDetail | null>(null);
  const [previewLoading, setPreviewLoading] = useState<string | null>(null);

  const load = useCallback(async () => {
    // Bail on an unknown slug rather than firing three requests that are
    // guaranteed to 404 — the render below already reports it.
    if (!token || !isValidAgency) return;
    setLoading(true);
    setError(null);
    try {
      const [active, all, log] = await Promise.all([
        getActiveConfig(agencyType, token),
        listConfigs(agencyType, token),
        getAuditLog(agencyType, token),
      ]);
      setActiveConfig(active);
      setConfigs(all);
      setAuditLog(log);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load rubric config.');
    } finally {
      setLoading(false);
    }
  }, [token, agencyType, isValidAgency]);

  useEffect(() => { void load(); }, [load]);

  // ── Handlers ──────────────────────────────────────────────

  async function handleFileUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !token) return;
    setUploading(true);
    setNotice(null);
    try {
      if (file.size > MAX_UPLOAD_BYTES) {
        throw new Error(
          `That file is ${(file.size / 1024 / 1024).toFixed(1)} MB. A rubric ` +
          'config is normally under 100 KB — check you picked the right file.',
        );
      }
      const text = await file.text();
      let parsed: { version?: string; rules?: RubricRule[] };
      try {
        parsed = JSON.parse(text);
      } catch {
        throw new Error('That file is not valid JSON.');
      }
      if (typeof parsed.version !== 'string' || !parsed.version.trim()) {
        throw new Error('The file needs a "version" string at the top level.');
      }
      if (!Array.isArray(parsed.rules) || parsed.rules.length === 0) {
        throw new Error('The file needs a non-empty "rules" array.');
      }
      // A shape check on the first rule, so an obviously wrong file is named
      // as such here instead of coming back as a validation error from the API
      // after a round trip.
      const first = parsed.rules[0];
      if (!first || typeof first.rule_id !== 'string' || !first.severity_contribution) {
        throw new Error(
          'The first entry in "rules" has no rule_id or severity_contribution — ' +
          'this does not look like a rubric config.',
        );
      }

      const result = await uploadConfig(
        agencyType,
        { version: parsed.version, rules: parsed.rules },
        token,
      );
      setNotice({
        type: 'success',
        text: `Version "${result.version}" uploaded. It is NOT live yet — activate it from the Versions tab.`,
      });
      await load();
      setTab('versions');
    } catch (e: unknown) {
      setNotice({ type: 'error', text: e instanceof Error ? e.message : 'Upload failed.' });
    } finally {
      setUploading(false);
      // Clearing the input matters: without it, picking the SAME file again
      // fires no change event and the upload silently does nothing.
      if (fileInputRef.current) fileInputRef.current.value = '';
    }
  }

  async function handleActivate() {
    if (!confirmActivate || !token) return;
    setActivating(true);
    setNotice(null);
    try {
      const result = await activateConfig(
        agencyType, confirmActivate.id, activateReason || null, token,
      );
      setNotice({
        type: 'success',
        text: `Version "${result.version}" is now the live rubric for ${agencyType}.`,
      });
      setConfirmActivate(null);
      setActivateReason('');
      setPreviewConfig(null);   // the thing being previewed is the live one now
      await load();
      setTab('rules');
    } catch (e: unknown) {
      setNotice({ type: 'error', text: e instanceof Error ? e.message : 'Activation failed.' });
    } finally {
      setActivating(false);
    }
  }

  async function handlePreview(config: RubricConfigSummary) {
    if (!token) return;
    if (previewConfig?.id === config.id) { setPreviewConfig(null); return; }
    setPreviewLoading(config.id);
    try {
      const detail = await getConfig(agencyType, config.id, token);
      setPreviewConfig(detail);
      setTab('rules');
    } catch (e: unknown) {
      setNotice({ type: 'error', text: e instanceof Error ? e.message : 'Failed to load that version.' });
    } finally {
      setPreviewLoading(null);
    }
  }

  // ── Render ────────────────────────────────────────────────

  if (!isValidAgency) {
    return (
      <div className="px-6 py-5 md:px-7">
        <Alert
          variant="error"
          message={`Unknown agency type: "${params?.agency}". Valid values are BFP, PNP and MDRRMO.`}
        />
      </div>
    );
  }

  const displayConfig = previewConfig ?? activeConfig;

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {/* Back to the selector — Provincial Admin only. For an Agency Admin
          /governance/severity redirects straight back here, so the link
          would be a round trip to the page they were already on. */}
      {!isAgencyAdmin && (
        <Link
          className="inline-flex w-fit items-center gap-1.5 text-meta text-muted-foreground transition-colors hover:text-foreground"
          href="/governance/severity"
        >
          <ArrowLeft className="size-3.5" /> All agencies
        </Link>
      )}

      {/* ── Identity + upload ───────────────────────────── */}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
        <span className="text-[15px] font-bold" style={{ color: AGENCY_COLOR[agencyType] }}>
          {agencyType}
        </span>
        <span className="text-[15px] font-semibold text-foreground">
          {AGENCY_LABELS[agencyType]}
        </span>
        {activeConfig ? (
          <span
            className="flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold"
            style={{
              backgroundColor: 'color-mix(in srgb, var(--color-system-success) 12%, transparent)',
              color: 'var(--color-system-success)',
            }}
          >
            <CheckCircle2 className="size-3.5" />
            v{activeConfig.version} live
          </span>
        ) : !loading ? (
          <span
            className="flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-bold"
            style={{
              backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 12%, transparent)',
              color: 'var(--color-system-warning)',
            }}
          >
            <AlertTriangle className="size-3.5" />
            Bundled seed
          </span>
        ) : null}

        <input
          accept=".json,application/json"
          className="hidden"
          onChange={handleFileUpload}
          ref={fileInputRef}
          type="file"
        />
        {/* No Refresh button. Nothing changes this data except this page, and
            it reloads itself after every upload and activation. */}
        <Button
          className="ml-auto"
          disabled={uploading}
          onClick={() => fileInputRef.current?.click()}
          size="sm"
          variant="outline"
        >
          <Upload data-icon="inline-start" />
          {uploading ? 'Uploading…' : 'Upload config'}
        </Button>
      </div>

      {error && <Alert variant="error" message={error} />}

      {!loading && !activeConfig && (
        <Alert
          variant="warning"
          message={
            `${agencyType} has no config in the database, so the engine is scoring ` +
            'its reports from the bundled seed file. Uploading a config and ' +
            'activating it makes that config authoritative instead.'
          }
        />
      )}

      {previewConfig && (
        <div className="flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] border border-[color-mix(in_srgb,var(--color-brand)_25%,transparent)] bg-[color-mix(in_srgb,var(--color-brand)_8%,transparent)] px-4 py-3">
          <FlaskConical className="size-4 shrink-0 text-[var(--color-brand)]" />
          <p className="flex-1 text-meta leading-relaxed text-[var(--color-text-secondary)]">
            <span className="font-semibold">
              You are reading version {previewConfig.version}, which is not live.
            </span>{' '}
            Nothing below is affecting incoming reports.
          </p>
          <Button onClick={() => setPreviewConfig(null)} size="sm" variant="outline">
            <Eye data-icon="inline-start" />
            Show the live rubric
          </Button>
        </div>
      )}

      {/* ── Tabs ─────────────────────────────────────────
          Radix, not the hand-rolled row of buttons this page had. Those had
          no role="tablist", no aria-selected and no arrow-key movement, so a
          keyboard user had to Tab through all three to reach the last one and
          a screen reader announced them as unrelated buttons. */}
      <Tabs onValueChange={v => setTab(v as TabKey)} value={tab}>
        <TabsList variant="line">
          <TabsTrigger value="rules">
            <Zap data-icon="inline-start" />
            Rules
          </TabsTrigger>
          <TabsTrigger value="versions">
            <History data-icon="inline-start" />
            Versions ({configs.length})
          </TabsTrigger>
          <TabsTrigger value="audit">
            <Clock data-icon="inline-start" />
            Audit log
          </TabsTrigger>
        </TabsList>

        {loading ? (
          <div className="flex flex-col gap-2 pt-2">
            {Array.from({ length: 4 }).map((_, i) => (
              <Skeleton className="h-16 rounded-[var(--radius-card)]" key={i} />
            ))}
          </div>
        ) : (
          <>
            <TabsContent value="rules">
              <RulesTab config={displayConfig} />
            </TabsContent>
            <TabsContent value="versions">
              <VersionsTab
                activeConfigId={activeConfig?.id ?? null}
                configs={configs}
                onActivate={c => { setConfirmActivate(c); setActivateReason(''); }}
                onPreview={handlePreview}
                previewConfigId={previewConfig?.id ?? null}
                previewLoading={previewLoading}
              />
            </TabsContent>
            <TabsContent value="audit">
              <AuditTab entries={auditLog} />
            </TabsContent>
          </>
        )}
      </Tabs>

      <ActivateDialog
        agencyType={agencyType}
        config={confirmActivate}
        currentVersion={activeConfig?.version ?? null}
        loading={activating}
        onCancel={() => { setConfirmActivate(null); setActivateReason(''); }}
        onConfirm={handleActivate}
        onReasonChange={setActivateReason}
        reason={activateReason}
      />
    </div>
  );
}

// ── Rules tab ─────────────────────────────────────────────────

function RulesTab({ config }: { config: RubricConfigDetail | null }) {
  if (!config) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-14 text-center">
          <FileJson className="size-8 text-muted-foreground" />
          <p className="text-[15px] font-semibold text-foreground">
            Nothing to show — the seed file is in charge
          </p>
          <p className="max-w-sm text-meta text-muted-foreground">
            The rules currently scoring this agency&apos;s reports live in the
            bundled seed file, not in the database, so they cannot be listed
            here. Upload a config and activate it to see and manage them.
          </p>
        </CardContent>
      </Card>
    );
  }

  const active = config.rules.filter(r => r.active);
  const inactive = config.rules.filter(r => !r.active);
  const unsourced = active.filter(r => r.provenance.toUpperCase().startsWith('TODO'));

  // Grouped worst-first rather than listed in file order. A rubric is read to
  // answer "what makes something critical here", and file order buries that.
  const byTier = SEVERITY_ORDER
    .map(tier => ({ tier, rules: active.filter(r => r.severity_contribution === tier) }))
    .filter(g => g.rules.length > 0);

  return (
    <div className="flex flex-col gap-4">
      {unsourced.length > 0 && (
        /* This warning used to read "Fill in field interview citations before
           the defense". That is a note to the developer, rendered in the
           product, to an agency administrator who has no idea what defence is
           being referred to. What it means to THEM is below. */
        <Alert
          variant="warning"
          message={
            unsourced.length === 1
              ? 'One active rule records no source for its severity. It still ' +
                'fires, but nothing on file says who decided the threshold or ' +
                'why, so a disputed dispatch cannot be defended from this ' +
                'record. The engine logs a warning at startup for it.'
              : `${unsourced.length} active rules record no source for their ` +
                'severity. They still fire, but nothing on file says who decided ' +
                'the thresholds or why, so a disputed dispatch cannot be ' +
                'defended from this record. The engine logs a warning at ' +
                'startup for each one.'
          }
        />
      )}

      {byTier.map(({ tier, rules }) => (
        <section className="flex flex-col gap-2" key={tier}>
          <div className="flex items-center gap-2">
            <span
              aria-hidden="true"
              className="size-2 shrink-0 rounded-full"
              style={{ backgroundColor: SEVERITY_COLOR[tier] }}
            />
            <h2
              className="text-[11px] font-bold tracking-wide uppercase"
              style={{ color: SEVERITY_COLOR[tier] }}
            >
              {tier}
            </h2>
            <span className="text-meta text-muted-foreground">
              <Fig className="text-[12px] font-semibold">{rules.length}</Fig> rule
              {rules.length === 1 ? '' : 's'}
            </span>
            <div className="h-px flex-1 bg-[var(--color-surface-border)]" />
          </div>
          {rules.map(rule => (
            <RuleCard key={rule.rule_id} rule={rule} />
          ))}
        </section>
      ))}

      {inactive.length > 0 && (
        <section className="flex flex-col gap-2">
          <div className="flex items-center gap-2">
            <h2 className="text-[11px] font-bold tracking-wide text-muted-foreground uppercase">
              Retired
            </h2>
            <span className="text-meta text-muted-foreground">
              <Fig className="text-[12px] font-semibold">{inactive.length}</Fig> kept
              for the audit trail · not evaluated
            </span>
            <div className="h-px flex-1 bg-[var(--color-surface-border)]" />
          </div>
          {inactive.map(rule => (
            <RuleCard dimmed key={rule.rule_id} rule={rule} />
          ))}
        </section>
      )}
    </div>
  );
}

// ── Rule card ─────────────────────────────────────────────────

function RuleCard({ rule, dimmed = false }: { rule: RubricRule; dimmed?: boolean }) {
  const [expanded, setExpanded] = useState(false);
  const severityColor = SEVERITY_COLOR[rule.severity_contribution];
  const unsourced = rule.provenance.toUpperCase().startsWith('TODO');

  return (
    <div
      className={[
        'overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] transition-colors',
        dimmed ? 'opacity-60' : 'hover:border-[var(--color-brand-subtle)]',
      ].join(' ')}
    >
      <button
        aria-expanded={expanded}
        className="flex w-full items-center gap-3 p-4 text-left"
        onClick={() => setExpanded(e => !e)}
      >
        <span
          className="min-w-[60px] shrink-0 rounded-full px-2 py-1 text-center text-[11px] font-bold tracking-wide uppercase"
          style={{
            backgroundColor: `color-mix(in srgb, ${severityColor} 15%, transparent)`,
            color: severityColor,
          }}
        >
          {rule.severity_contribution}
        </span>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="font-mono text-[11px] text-muted-foreground">
              {rule.rule_id}
            </span>
            {unsourced && (
              <span className="rounded bg-[color-mix(in_srgb,var(--color-system-warning)_12%,transparent)] px-1.5 py-0.5 text-[11px] font-semibold text-[var(--color-system-warning)]">
                No source recorded
              </span>
            )}
            {!rule.active && (
              <span className="rounded bg-[var(--color-surface-raised)] px-1.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
                Retired
              </span>
            )}
          </div>
          <p className="mt-0.5 truncate text-[13px] font-semibold text-foreground">
            {rule.description}
          </p>
        </div>

        <div className="flex shrink-0 items-center gap-3">
          {rule.recommended_agency && (
            <span
              className="text-[11px] font-semibold"
              style={{ color: AGENCY_COLOR[rule.recommended_agency] }}
            >
              → {rule.recommended_agency}
            </span>
          )}
          <ChevronDown
            className={[
              'size-4 text-muted-foreground transition-transform',
              expanded ? 'rotate-180' : '',
            ].join(' ')}
          />
        </div>
      </button>

      {expanded && (
        <div className="flex flex-col gap-3 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-base)] px-4 pt-3 pb-4">
          <ConditionTable conditions={rule.conditions} />
          <div>
            <p className="mb-1 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
              Where this threshold came from
            </p>
            <p
              className={[
                'text-[12px] leading-relaxed',
                unsourced
                  ? 'text-[var(--color-system-warning)]'
                  : 'text-[var(--color-text-secondary)]',
              ].join(' ')}
            >
              {rule.provenance}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Condition table ───────────────────────────────────────────

function ConditionTable({
  conditions,
}: {
  conditions: import('@/lib/api/rubric').RubricCondition;
}) {
  type Row = { signal: string; operator: string; value: string };
  const rows: Row[] = [];

  function push(signal: string, operator: string, value: unknown) {
    if (value === null || value === undefined) return;
    rows.push({
      signal,
      operator,
      value: Array.isArray(value) ? value.join(', ') : String(value),
    });
  }

  push('incident_type', 'is', conditions.incident_type);
  push('incident_type', 'is one of', conditions.incident_type_in);
  push('fire_type', 'is', conditions.fire_type);
  push('fire_type', 'is one of', conditions.fire_type_in);
  push('casualty_mentioned', 'is', conditions.casualty_mentioned);
  push('injured_count', '≥', conditions.injured_count_gte);
  push('injured_count', '≤', conditions.injured_count_lte);
  push('dead_count', '≥', conditions.dead_count_gte);
  push('weapon_mentioned', 'is', conditions.weapon_mentioned);
  push('weapon_type', 'is one of', conditions.weapon_type_in);
  push('children_involved', 'is', conditions.children_involved);
  push('urgency_level', 'is one of', conditions.urgency_level_in);
  push('structure_type', 'is one of', conditions.structure_type_in);
  push('multi_agency_needed', 'is', conditions.multi_agency_needed);
  push('why_category', 'is one of', conditions.why_category_in);
  push('how_category', 'is one of', conditions.how_category_in);
  push('incident_category', 'is one of', conditions.incident_category_in);

  if (rows.length === 0) {
    return (
      <p className="text-meta text-[var(--color-system-warning)]">
        This rule has no conditions, so it matches every report of its type.
      </p>
    );
  }

  return (
    <div>
      <p className="mb-2 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
        Fires when all of these are true
      </p>
      {/* Own scroll container: a long `is one of` list must not widen the page.
          Every table on this console that can hold arbitrary values needs this
          or the whole layout gains a horizontal scrollbar. */}
      <div className="scroll-slim overflow-x-auto rounded-[var(--radius-md)] border border-[var(--color-surface-border)]">
        <table className="w-full min-w-[420px] text-[12px]">
          <tbody>
            {rows.map((row, i) => (
              <tr
                className={i % 2 === 0 ? 'bg-[var(--color-surface-base)]' : 'bg-[var(--color-surface-card)]'}
                key={`${row.signal}-${row.operator}-${i}`}
              >
                <td className="w-44 px-3 py-2 font-mono whitespace-nowrap text-[var(--color-brand)]">
                  {row.signal}
                </td>
                <td className="w-24 px-3 py-2 text-center whitespace-nowrap text-muted-foreground">
                  {row.operator}
                </td>
                <td className="px-3 py-2 font-medium text-foreground">{row.value}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ── Versions tab ──────────────────────────────────────────────

function VersionsTab({
  configs, activeConfigId, previewConfigId, previewLoading, onPreview, onActivate,
}: {
  configs: RubricConfigSummary[];
  activeConfigId: string | null;
  previewConfigId: string | null;
  previewLoading: string | null;
  onPreview: (c: RubricConfigSummary) => void;
  onActivate: (c: RubricConfigSummary) => void;
}) {
  const display = displayPrefs.use();
  if (configs.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-14 text-center">
          <History className="size-8 text-muted-foreground" />
          <p className="text-[15px] font-semibold text-foreground">No uploaded versions</p>
          <p className="max-w-sm text-meta text-muted-foreground">
            Upload a JSON config to start a version history. Uploading never
            changes what the engine is doing — activation is a separate step.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {configs.map(config => {
        const isActive = config.id === activeConfigId;
        const isPreviewing = config.id === previewConfigId;
        return (
          <Card
            className={isActive ? 'border-[var(--color-system-success)]' : undefined}
            key={config.id}
          >
            <CardContent className="flex flex-wrap items-center justify-between gap-3 py-4">
              <div className="min-w-0">
                <div className="mb-1 flex flex-wrap items-center gap-2">
                  <span className="text-[14px] font-bold text-foreground">
                    v{config.version}
                  </span>
                  {isActive && (
                    <span className="flex items-center gap-1 text-[11px] font-semibold text-[var(--color-system-success)]">
                      <CheckCircle2 className="size-3.5" /> Live
                    </span>
                  )}
                  {isPreviewing && !isActive && (
                    <span className="rounded bg-[color-mix(in_srgb,var(--color-brand)_10%,transparent)] px-1.5 py-0.5 text-[11px] font-semibold text-[var(--color-brand)]">
                      Previewing
                    </span>
                  )}
                </div>
                <p className="text-meta text-muted-foreground">
                  Uploaded {formatDateTime(config.created_at, display)}
                  {config.activated_at && ` · last activated ${formatDateTime(config.activated_at, display)}`}
                </p>
              </div>

              <div className="flex shrink-0 items-center gap-2">
                <Button
                  disabled={previewLoading === config.id}
                  onClick={() => onPreview(config)}
                  size="sm"
                  variant="outline"
                >
                  {previewLoading === config.id
                    ? 'Loading…'
                    : isPreviewing ? 'Hide rules' : 'Preview rules'}
                </Button>
                {!isActive && (
                  <Button onClick={() => onActivate(config)} size="sm">
                    <CheckCircle2 data-icon="inline-start" />
                    Make live
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
}

// ── Audit tab ─────────────────────────────────────────────────

const AUDIT_EVENT_LABEL: Record<string, string> = {
  config_created:     'Uploaded',
  config_activated:   'Made live',
  config_deactivated: 'Retired',
  rule_updated:       'Rule updated',
  fallback_to_seed:   'Fell back to seed',
};

const AUDIT_EVENT_COLOR: Record<string, string> = {
  config_created:     'var(--color-brand)',
  config_activated:   'var(--color-system-success)',
  config_deactivated: 'var(--color-system-warning)',
  rule_updated:       'var(--color-text-muted)',
  fallback_to_seed:   'var(--color-system-error)',
};

function AuditTab({ entries }: { entries: RubricAuditEntry[] }) {
  const display = displayPrefs.use();
  if (entries.length === 0) {
    return (
      <Card>
        <CardContent className="flex flex-col items-center gap-2 py-14 text-center">
          <Clock className="size-8 text-muted-foreground" />
          <p className="text-[15px] font-semibold text-foreground">Nothing logged yet</p>
          <p className="max-w-sm text-meta text-muted-foreground">
            Every upload and activation is recorded here with who did it and
            why, so a change to how reports are scored can always be traced
            back to a decision.
          </p>
        </CardContent>
      </Card>
    );
  }

  return (
    <div className="flex flex-col gap-2">
      {entries.map(entry => {
        const color = AUDIT_EVENT_COLOR[entry.event_type] ?? 'var(--color-text-muted)';
        return (
          <div
            className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-3"
            key={entry.id}
          >
            <div className="flex items-start gap-3">
              <span
                className="mt-0.5 shrink-0 rounded-full px-2 py-0.5 text-[11px] font-bold tracking-wide uppercase"
                style={{
                  backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`,
                  color,
                }}
              >
                {AUDIT_EVENT_LABEL[entry.event_type] ?? entry.event_type}
              </span>
              <div className="min-w-0 flex-1">
                {entry.config_version && (
                  <span className="text-[13px] font-semibold text-foreground">
                    v{entry.config_version}
                  </span>
                )}
                {entry.notes && (
                  <p className="mt-0.5 text-[12px] leading-relaxed text-[var(--color-text-secondary)]">
                    {entry.notes}
                  </p>
                )}
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {formatDateTime(entry.created_at, display)}
                  {entry.actor_id && ` · by ${entry.actor_id.slice(0, 8)}…`}
                </p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ── Activation dialog ─────────────────────────────────────────

/**
 * Radix, not the fixed-position div this page used to draw.
 *
 * That one had no role, no focus trap, no Escape handler and no scroll lock —
 * Tab walked straight out of it into the page behind, and the reason field
 * could be left focused while the page underneath scrolled. This dialog
 * changes how every incoming report for an entire agency is scored; it is the
 * last control on the console that should be improvised.
 */
function ActivateDialog({
  config, agencyType, currentVersion, reason, onReasonChange, onConfirm, onCancel, loading,
}: {
  config: RubricConfigSummary | null;
  agencyType: AgencyType;
  currentVersion: string | null;
  reason: string;
  onReasonChange: (v: string) => void;
  onConfirm: () => void;
  onCancel: () => void;
  loading: boolean;
}) {
  return (
    <AlertDialog onOpenChange={open => { if (!open) onCancel(); }} open={config !== null}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Make v{config?.version} the live rubric for {agencyType}?
          </AlertDialogTitle>
          <AlertDialogDescription>
            From the moment you confirm, every new {agencyType} report is scored
            against this version&apos;s rules.{' '}
            {currentVersion
              ? `v${currentVersion} is retired but kept, so you can switch back.`
              : 'The bundled seed file stops being used.'}{' '}
            Reports already in the queue keep the severity they were given.
          </AlertDialogDescription>
        </AlertDialogHeader>

        <div className="flex flex-col gap-1.5">
          <Label htmlFor="activate-reason">Why (optional — saved to the audit log)</Label>
          <Input
            id="activate-reason"
            onChange={e => onReasonChange(e.target.value)}
            placeholder="e.g. Raised the injury threshold after the BFP field interview"
            value={reason}
          />
        </div>

        <AlertDialogFooter>
          <AlertDialogCancel disabled={loading}>Cancel</AlertDialogCancel>
          <AlertDialogAction
            disabled={loading}
            onClick={e => { e.preventDefault(); onConfirm(); }}
          >
            {loading ? 'Activating…' : `Make v${config?.version} live`}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

// ── Helpers ───────────────────────────────────────────────────
