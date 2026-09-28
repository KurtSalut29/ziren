'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import {
  Activity, ArrowRight, BellRing, Database, FileSpreadsheet, Gauge, HardDrive,
  KeyRound, Server, ShieldAlert, SlidersHorizontal, Smartphone,
} from 'lucide-react';
import { apiClient } from '@/lib/api/client';
import { useShellAlerts } from '@/components/shell/app-shell';
import { DISPATCH_TARGET_MINUTES, DEFAULT_TARGET_MINUTES } from '@/components/incidents/incident-vocabulary';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, StatusDot,
} from '@/components/settings/kit';

interface SystemConfig {
  environment: string;
  limits: { live_queue_max: number; records_page_max: number; voice_recording_max_mb: number };
  rate_limits: { login: string; incident_submit: string; sos_submit: string };
  triage: { confidence_flag_threshold: number };
  ack_deadline_seconds: Record<string, number>;
  password_policy: { min_length: number; requires_uppercase: boolean; requires_digit: boolean };
}

const fmtRate = (r: string) => r.replace('/', ' per ').replace('minute', 'minute').replace('hour', 'hour');
const fmtSeconds = (s: number) => (s % 60 === 0 ? `${s / 60} min` : `${s} s`);
const SEVERITY_LABEL: Record<string, string> = {
  critical: 'Critical', high: 'High', medium: 'Medium', low: 'Low', unscored: 'Not yet scored',
};

// ── System Configuration ─────────────────────────────────────────────────

export function SystemConfigPanel({ token }: { token: string }) {
  const [cfg, setCfg] = useState<SystemConfig | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    apiClient.get<SystemConfig>('/system-status/config', token).then(setCfg).catch(() => setFailed(true));
  }, [token]);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="The limits and thresholds this deployment actually runs on, read live from the code and environment that enforce them."
        icon={SlidersHorizontal}
        scope="province"
        title="System Configuration"
      />

      <Callout title="Read-only, on purpose" tone="info">
        These are set in the server’s code or environment, not in a database table. Changing one is
        a deployment decision that needs a restart, so there is no switch here to promise one. What you
        can do is see exactly what applies — to answer “why was I blocked?” or “how long a recording will be accepted?”
        without reading the source.
      </Callout>

      {failed ? (
        <Callout title="Could not read the configuration" tone="danger" />
      ) : !cfg ? (
        <div className="flex flex-col gap-4"><Skeleton className="h-44 rounded-[var(--radius-card)]" /><Skeleton className="h-44 rounded-[var(--radius-card)]" /></div>
      ) : (
        <>
          <Card flush title="Response clocks">
            <div className="overflow-x-auto">
              <table className="w-full border-collapse text-left text-[13px]">
                <thead>
                  <tr className="border-b border-[var(--color-surface-border)] text-[11.5px] font-semibold uppercase tracking-wide text-muted-foreground">
                    <th className="px-5 py-2.5 font-semibold" scope="col">Severity</th>
                    <th className="px-3 py-2.5 font-semibold" scope="col">Dispatch within</th>
                    <th className="px-5 py-2.5 font-semibold" scope="col">Crew must accept within</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(cfg.ack_deadline_seconds).map(([sev, secs]) => (
                    <tr className="border-b border-[var(--color-surface-border)] last:border-b-0" key={sev}>
                      <td className="px-5 py-3 font-semibold text-foreground">{SEVERITY_LABEL[sev] ?? sev}</td>
                      <td className="px-3 py-3 font-mono tabular-nums text-foreground">
                        {sev === 'unscored' ? DEFAULT_TARGET_MINUTES : (DISPATCH_TARGET_MINUTES[sev] ?? DEFAULT_TARGET_MINUTES)} min
                      </td>
                      <td className="px-5 py-3 font-mono tabular-nums text-foreground">{fmtSeconds(secs)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </Card>

          <Card flush title="Reporting and workflow">
            <RowList>
              <Row description="Classifier suggestions below this confidence are flagged for a human instead of being trusted." icon={Gauge} label="Confidence bar">
                <span className="font-mono text-[13px] text-foreground">{Math.round(cfg.triage.confidence_flag_threshold * 100)}%</span>
              </Row>
              <Row description="The most open incidents the live queue will load at once." icon={Database} label="Live queue ceiling">
                <span className="font-mono text-[13px] text-foreground">{cfg.limits.live_queue_max}</span>
              </Row>
              <Row description="Records are paged, never capped; this is the most one page asks for." icon={Database} label="Records per page (maximum)">
                <span className="font-mono text-[13px] text-foreground">{cfg.limits.records_page_max}</span>
              </Row>
              <Row description="A voice recording larger than this is saved and playable but not transcribed." icon={Server} label="Largest recording transcribed">
                <span className="font-mono text-[13px] text-foreground">{cfg.limits.voice_recording_max_mb} MB</span>
              </Row>
            </RowList>
          </Card>

          <Card description="How many times a caller can try before being told to wait. Guards against guessing and against floods." flush title="Rate limits">
            <RowList>
              <Row label="Sign-in attempts"><Mono>{fmtRate(cfg.rate_limits.login)}</Mono></Row>
              <Row label="Incident reports"><Mono>{fmtRate(cfg.rate_limits.incident_submit)}</Mono></Row>
              <Row label="SOS reports"><Mono>{fmtRate(cfg.rate_limits.sos_submit)}</Mono></Row>
            </RowList>
          </Card>

          <Card flush title="Security">
            <RowList>
              <Row
                description={`At least ${cfg.password_policy.min_length} characters${cfg.password_policy.requires_uppercase ? ', one uppercase letter' : ''}${cfg.password_policy.requires_digit ? ' and one digit' : ''}. The same rule for signing up and changing a password.`}
                icon={KeyRound}
                label="Password policy"
              />
              <Row description="Whether this server is running as a development or a production deployment." icon={ShieldAlert} label="Environment">
                <StatusDot tone={cfg.environment === 'production' ? 'success' : 'warning'}>{cfg.environment}</StatusDot>
              </Row>
            </RowList>
          </Card>
        </>
      )}
    </div>
  );
}

// ── Push Notifications ───────────────────────────────────────────────────

export function PushPanel({ onOpen }: { onOpen: (key: string) => void }) {
  const shell = useShellAlerts();
  const permission = shell?.permission ?? 'default';
  const label = {
    granted: ['success', 'Allowed'], default: ['warning', 'Not asked yet'],
    denied: ['danger', 'Blocked'], unsupported: ['neutral', 'Not supported'],
  }[permission] as ['success' | 'warning' | 'danger' | 'neutral', string];

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="How alerts leave the server and reach a person’s device."
        icon={Smartphone}
        title="Push Notifications"
      />

      <Callout title="Ziren does not run a push server" tone="info">
        There is no central service sending notifications, so there is no delivery rate or failure
        count to report. The dashboard alerts through the browser’s own notification system while a
        tab is open, and the mobile app’s alerts are raised on the phone itself and stop when the app is
        force-closed.
      </Callout>

      <Card flush title="On this browser">
        <RowList>
          <Row description="Whether this browser lets the dashboard raise desktop pop-ups for new incidents." icon={BellRing} label="Desktop notifications">
            <span className="flex items-center gap-3">
              <StatusDot tone={label[0]}>{label[1]}</StatusDot>
              {permission === 'default' && shell && (
                <Button onClick={shell.requestPermission} size="sm">
                  <BellRing data-icon="inline-start" />
                  Turn on
                </Button>
              )}
            </span>
          </Row>
          <Row description="Volume, sound mode, pop-up and tab flash for this screen." label="Delivery settings">
            <Button onClick={() => onOpen('notifications')} size="sm" variant="outline">
              Open Notifications <ArrowRight className="size-3.5" />
            </Button>
          </Row>
        </RowList>
      </Card>
    </div>
  );
}

// ── Backup & Recovery ────────────────────────────────────────────────────

export function BackupPanel() {
  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="What protects the data if something goes wrong, and what you can do about it from here."
        icon={HardDrive}
        title="Backup & Recovery"
      />

      <Callout title="Ziren does not schedule backups itself" tone="warning">
        The database lives in Supabase, and its own backup and point-in-time recovery are the safety
        net. They are configured in the Supabase project, outside this console, so there is no “last
        backup” time or restore button here to show. Confirm with whoever owns the Supabase project
        that recovery is switched on and how far back it reaches.
      </Callout>

      <Card flush title="What you can do from here">
        <RowList>
          <Row description="Export incidents, responders, accounts and more as CSV, Excel or PDF — a copy you hold yourself." icon={FileSpreadsheet} label="Export your agency’s data">
            <Button asChild size="sm" variant="outline">
              <Link href="/reports">Open Reports & Export <ArrowRight className="size-3.5" /></Link>
            </Button>
          </Row>
          <Row description="Live health of the server, database and classifier — the first thing to check before and after any recovery." icon={Activity} label="Check system health">
            <Button asChild size="sm" variant="outline">
              <Link href="/system-status">Open System Status <ArrowRight className="size-3.5" /></Link>
            </Button>
          </Row>
          <Row description="Every administrative change is recorded, so a bad edit can be traced to who made it and what it was before." icon={ShieldAlert} label="Trace a change">
            <Button asChild size="sm" variant="outline">
              <Link href="/audit-logs">Open Audit Logs <ArrowRight className="size-3.5" /></Link>
            </Button>
          </Row>
        </RowList>
      </Card>
    </div>
  );
}

function Mono({ children }: { children: React.ReactNode }) {
  return <span className="font-mono text-[13px] text-foreground">{children}</span>;
}
