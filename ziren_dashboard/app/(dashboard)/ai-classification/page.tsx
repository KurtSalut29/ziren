'use client';

/**
 * AI & Classification Monitoring — spec Section 12.
 *
 * Read-only. Every number here comes from the `signals` JSONB column the
 * triage pipeline already writes to each incident (see TriageSignals in
 * app/models/incident.py on the backend) — this page adds no new
 * instrumentation, it's a window onto data that already exists. There is
 * deliberately no control here that touches the trained model itself.
 */

import { useEffect, useState } from 'react';
import { BrainCircuit, CheckCircle2, HelpCircle, XCircle } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { fetchAiMonitoringStats, type AiMonitoringStats } from '@/lib/api/ai-monitoring';
import { ApiError } from '@/lib/api/client';
import { Alert } from '@/components/ui/alert';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
} from '@/components/efferd/ui/card';
import { Skeleton } from '@/components/efferd/ui/skeleton';

const RESULT_STYLE: Record<string, { color: string; icon: typeof CheckCircle2; label: string }> = {
  AGREE:             { color: 'var(--color-system-success)', icon: CheckCircle2, label: 'Agreed with resident' },
  MISMATCH_FLAGGED:  { color: 'var(--color-severity-critical)', icon: XCircle, label: 'Mismatch flagged' },
  UNCERTAIN:         { color: 'var(--color-system-warning)', icon: HelpCircle, label: 'Uncertain' },
  NO_SELECTION:      { color: 'var(--color-text-muted)', icon: HelpCircle, label: 'Resident chose no category' },
  NO_TEXT:           { color: 'var(--color-text-muted)', icon: HelpCircle, label: 'No text to classify' },
};

export default function AiClassificationPage() {
  const { token } = useAuth();
  const [stats, setStats] = useState<AiMonitoringStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) return;
    fetchAiMonitoringStats(token).then(setStats).catch((e: unknown) => {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load.');
    });
  }, [token]);

  if (error) return <div className="px-6 py-5 md:px-7"><Alert variant="error" message={error} /></div>;
  if (!stats) {
    return (
      <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
        <Skeleton className="h-24 rounded-[var(--radius-card)]" />
        <Skeleton className="h-64 rounded-[var(--radius-card)]" />
      </div>
    );
  }

  const maxConfidence = Math.max(1, ...Object.values(stats.confidence_distribution));

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      <StatStrip>
        <StatCell
          bg="var(--color-brand-subtle)" color="var(--color-brand)"
          icon={<BrainCircuit size={12} strokeWidth={2} />}
          label="Model version" value={stats.model_version}
          trend={stats.model_status === 'active' ? 'Active' : 'Unavailable'}
        />
        <StatCell
          bg="var(--color-system-success-bg)" color="var(--color-system-success)"
          icon={<CheckCircle2 size={12} strokeWidth={2} />}
          label="AI-assisted classifications" value={stats.total_classifications}
          trend="Total incidents scored"
        />
        <StatCell
          bg="var(--color-status-dispatched-bg)" color="var(--color-status-dispatched)"
          icon={<CheckCircle2 size={12} strokeWidth={2} />}
          label="Agreement rate"
          value={
            stats.total_classifications > 0
              ? `${Math.round(((stats.verification_breakdown.AGREE ?? 0) / stats.total_classifications) * 100)}%`
              : '—'
          }
          trend="Model matched resident's own choice"
        />
      </StatStrip>

      {/* items-start: without it, the taller card stretches its shorter
          sibling to match, leaving dead space below its last row. */}
      <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="gap-1">
            <CardTitle className="text-[15px]">Confidence distribution</CardTitle>
            <CardDescription>How sure the model was, across every classification</CardDescription>
          </CardHeader>
          <CardContent>
            {Object.keys(stats.confidence_distribution).length === 0 ? (
              <p className="py-6 text-center text-meta text-muted-foreground">No classifications yet.</p>
            ) : (
              <ul className="flex flex-col gap-2.5">
                {Object.entries(stats.confidence_distribution).map(([bucket, count]) => (
                  <li className="flex items-center gap-3" key={bucket}>
                    <span className="w-16 shrink-0 text-[12.5px] text-foreground">{bucket}</span>
                    <div className="h-2 flex-1 overflow-hidden rounded-full bg-[var(--color-surface-raised)]">
                      <div
                        className="h-full rounded-full"
                        style={{ width: `${(count / maxConfidence) * 100}%`, backgroundColor: 'var(--color-brand)' }}
                      />
                    </div>
                    <span className="w-8 shrink-0 text-right text-[12.5px] font-semibold text-foreground">{count}</span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="gap-1">
            <CardTitle className="text-[15px]">Human verification</CardTitle>
            <CardDescription>How the model&apos;s guess compared to what the resident chose</CardDescription>
          </CardHeader>
          <CardContent>
            {Object.keys(stats.verification_breakdown).length === 0 ? (
              <p className="py-6 text-center text-meta text-muted-foreground">No data yet.</p>
            ) : (
              <ul className="flex flex-col gap-2.5">
                {Object.entries(stats.verification_breakdown).map(([status, count]) => {
                  const style = RESULT_STYLE[status] ?? RESULT_STYLE.NO_SELECTION;
                  const Icon = style.icon;
                  return (
                    <li className="flex items-center gap-2" key={status}>
                      <Icon className="size-3.5 shrink-0" style={{ color: style.color }} />
                      <span className="flex-1 text-[12.5px] text-foreground">{style.label}</span>
                      <span className="text-[12.5px] font-semibold text-foreground">{count}</span>
                    </li>
                  );
                })}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="gap-1">
          <CardTitle className="text-[15px]">Recent classifications</CardTitle>
          <CardDescription>Model prediction vs. what the resident selected</CardDescription>
        </CardHeader>
        <CardContent>
          {stats.sample_corrections.length === 0 ? (
            <p className="py-6 text-center text-meta text-muted-foreground">Nothing to show yet.</p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-[12.5px]">
                <thead className="text-left text-[11px] uppercase tracking-wide text-muted-foreground">
                  <tr>
                    <th className="py-2 pr-4">Date</th>
                    <th className="py-2 pr-4">AI Prediction</th>
                    <th className="py-2 pr-4">Resident Selection</th>
                    <th className="py-2 pr-4">Result</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.sample_corrections.map((c, i) => {
                    const style = c.result ? RESULT_STYLE[c.result] ?? RESULT_STYLE.NO_SELECTION : RESULT_STYLE.NO_SELECTION;
                    return (
                      <tr className={i > 0 ? 'border-t border-[var(--color-surface-border)]' : ''} key={c.incident_id}>
                        <td className="py-2 pr-4 text-muted-foreground">{new Date(c.created_at).toLocaleDateString()}</td>
                        <td className="py-2 pr-4 text-foreground">{c.predicted ?? '—'}</td>
                        <td className="py-2 pr-4 text-foreground">{c.selected ?? '—'}</td>
                        <td className="py-2 pr-4" style={{ color: style.color }}>{style.label}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
