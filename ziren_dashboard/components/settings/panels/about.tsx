'use client';

import { useEffect, useState } from 'react';
import {
  ArrowRight, Brain, ClipboardCheck, ClipboardCopy, Info, MapPinned, Mic,
  Send, ShieldCheck, Smartphone,
} from 'lucide-react';
import { DASHBOARD_VERSION, fetchHealth, type HealthResponse } from '@/lib/api/health';
import { buildDiagnostics } from '@/lib/utils/diagnostics';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, StatusDot,
} from '@/components/settings/kit';

const PIPELINE = [
  {
    icon: Smartphone,
    title: 'A resident reports',
    body: 'From the Ziren mobile app — a category, a few tap-through questions, their words or a voice recording, and where they are. When there is no internet at all, a text message to the gateway phone does the same job.',
  },
  {
    icon: Brain,
    title: 'The report is read and scored',
    body: 'A classifier reads what was written and a rule set for each agency turns the signals it finds into a suggested severity and the agency that should respond. A voice recording is transcribed and re-scored. A report the system cannot score is flagged for a person, never guessed at.',
  },
  {
    icon: ClipboardCheck,
    title: 'A dispatcher reviews it',
    body: 'Someone in the agency accepts, questions or rejects the report, confirms the severity — overriding the suggestion, with a reason, if they disagree — and assigns a responder who is on duty. The system suggests; a person decides.',
  },
  {
    icon: Send,
    title: 'A crew responds',
    body: 'The responder’s phone is alerted, they accept or refuse within a set time, and the incident moves through en route and arrived to resolved, with what the crew found recorded at the end.',
  },
  {
    icon: MapPinned,
    title: 'It becomes a record',
    body: 'Every incident is kept with its own record number, its full timeline and its outcome, for review, reporting and the comparison of what the system suggested against what turned out to be true.',
  },
];

/**
 * Things that changed, drawn from the project's own history. Each line is a
 * capability an administrator can use, not a commit message.
 */
const CHANGES: { date: string; title: string; body: string }[] = [
  {
    date: 'Sep 19, 2026',
    title: 'Incident Records and a rebuilt Settings',
    body: 'Incident History became Incident Records — a table with a citable record number (ZIR-2026-000123), a lookup by number and a full record panel. Settings was rebuilt with working alerts, map, incident, privacy and accessibility preferences, sign-in history and session control.',
  },
  {
    date: 'Sep 13, 2026',
    title: 'Notes, feedback and responder accountability',
    body: 'Dispatchers can add notes to an incident and see the resident’s feedback after it closes. Crews must accept or refuse an assignment in time, refusals carry a reason, and an unanswered assignment shows as overdue on the board.',
  },
  {
    date: 'Sep 9, 2026',
    title: 'Search, reports and announcements',
    body: 'One search across incidents, people and stations; Reports & Export to CSV, Excel and PDF across seven report types; and announcements that can be aimed at a role or an agency.',
  },
];

export function AboutPanel({
  token,
  role,
  agencyType,
}: {
  token: string;
  role: string | null;
  agencyType: string | null;
}) {
  const [health, setHealth] = useState<HealthResponse | null>(null);
  const [failed, setFailed] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    fetchHealth(token).then(setHealth).catch(() => setFailed(true));
  }, [token]);

  async function copyDiagnostics() {
    try {
      await navigator.clipboard.writeText(buildDiagnostics({ role, agencyType, health, healthFailed: failed }));
      setCopied(true);
      setTimeout(() => setCopied(false), 2200);
    } catch { /* clipboard blocked */ }
  }

  const tr = health?.transcription;

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Disaster reporting and response coordination for Biliran Province."
        icon={Info}
        title="About Ziren"
      />

      <Card>
        <div className="flex flex-col gap-3">
          <p className="text-[26px] font-black leading-none tracking-[0.18em] text-foreground">ZIREN</p>
          <p className="max-w-[64ch] text-[14px] leading-relaxed text-[var(--color-text-secondary)]">
            Ziren gets an emergency from a resident’s phone to the right agency’s screen — and a
            crew to the scene — faster and with less lost in translation. Residents report in
            English, Filipino, Bisaya or Waray, by typing, by voice or by text message, and the
            people who respond see one clear, ranked queue instead of a dozen phone calls.
          </p>
          <p className="text-[12.5px] text-muted-foreground">
            This dashboard is for Agency Admins and Provincial Admins. Residents and responders use
            the mobile app.
          </p>
        </div>
      </Card>

      <Card
        description="Read live from the server when you opened this page."
        flush
        title="This installation"
      >
        <RowList>
          <Row label="Dashboard version">
            <span className="font-mono text-[13px] text-foreground">v{DASHBOARD_VERSION}</span>
          </Row>
          <Row description="Whether this console can reach the Ziren server." label="Server">
            {failed ? (
              <StatusDot tone="danger">Unreachable</StatusDot>
            ) : health ? (
              <StatusDot tone={health.status === 'ok' ? 'success' : 'warning'}>
                {health.status === 'ok' ? 'Operational' : health.status}
              </StatusDot>
            ) : (
              <Skeleton className="h-4 w-24" />
            )}
          </Row>
          <Row description="The classifier that reads a report and suggests a category and severity." icon={Brain} label="Triage model">
            {health?.triage ? (
              <span className="flex items-center gap-3">
                <span className="font-mono text-[13px] text-foreground">v{health.triage.version}</span>
                <StatusDot tone={health.triage.model_loaded ? 'success' : 'danger'}>
                  {health.triage.model_loaded ? 'Loaded' : 'Not loaded'}
                </StatusDot>
              </span>
            ) : failed ? <span className="text-[13px] text-muted-foreground">—</span> : <Skeleton className="h-4 w-28" />}
          </Row>
          <Row
            description="Turns a resident’s voice recording into text. Without it, a voice report is still saved and playable — it is just scored on what was typed."
            icon={Mic}
            label="Speech recognition"
          >
            {tr ? (
              <span className="flex items-center gap-3">
                {tr.available && (
                  <span className="font-mono text-[13px] text-foreground">{[tr.engine, tr.version].filter(Boolean).join(' ')}</span>
                )}
                <StatusDot tone={tr.available ? 'success' : 'warning'}>{tr.available ? 'Available' : 'Not configured'}</StatusDot>
              </span>
            ) : failed ? <span className="text-[13px] text-muted-foreground">—</span> : <Skeleton className="h-4 w-28" />}
          </Row>
        </RowList>
      </Card>

      <Card
        description="Every incident follows the same five steps. Knowing them makes the rest of the console make sense."
        title="How Ziren works"
      >
        <ol className="flex flex-col">
          {PIPELINE.map((step, i) => {
            const Icon = step.icon;
            return (
              <li className="relative flex gap-4 pb-6 last:pb-0" key={step.title}>
                {i < PIPELINE.length - 1 && (
                  <span aria-hidden="true" className="absolute left-[17px] top-9 h-[calc(100%-2.25rem)] w-px bg-[var(--color-surface-border)]" />
                )}
                <span
                  aria-hidden="true"
                  className="flex size-9 shrink-0 items-center justify-center rounded-full"
                  style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
                >
                  <Icon className="size-[18px]" />
                </span>
                <span className="min-w-0">
                  <span className="block text-[13.5px] font-semibold text-foreground">
                    <span className="mr-2 font-mono text-[12px] text-muted-foreground">{i + 1}</span>
                    {step.title}
                  </span>
                  <span className="mt-0.5 block max-w-[66ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
                    {step.body}
                  </span>
                </span>
              </li>
            );
          })}
        </ol>
      </Card>

      <Callout icon={ShieldCheck} title="The system suggests. A person decides." tone="info">
        No severity, dispatch or closure is ever made by the software alone. A report the
        classifier is not confident about is flagged for a human, an override needs a stated
        reason, and every administrative change is written to the audit trail.
      </Callout>

      <Card flush title="What’s new">
        <ul className="divide-y divide-[var(--color-surface-border)]">
          {CHANGES.map(c => (
            <li className="flex flex-col gap-1 px-5 py-4 sm:flex-row sm:gap-6" key={c.date}>
              <span className="w-28 shrink-0 font-mono text-[12.5px] tabular-nums text-muted-foreground">{c.date}</span>
              <span className="min-w-0">
                <span className="block text-[13.5px] font-semibold text-foreground">{c.title}</span>
                <span className="mt-0.5 block max-w-[66ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">{c.body}</span>
              </span>
            </li>
          ))}
        </ul>
      </Card>

      <Card description="The parts Ziren is made of." title="Built with">
        <div className="grid gap-x-8 gap-y-4 sm:grid-cols-3">
          {[
            ['This dashboard', 'Next.js 15 and React 19, Tailwind CSS, Leaflet maps, Apache ECharts, Radix UI.'],
            ['The server', 'Python and FastAPI, with scikit-learn for the classifier, faster-whisper for speech recognition and structured logging.'],
            ['Data and sign-in', 'Supabase — a PostgreSQL database, authentication and file storage.'],
            ['The mobile app', 'Flutter, for both residents and responders, with an English and a Filipino interface.'],
            ['Maps', 'Esri World Imagery and CARTO / OpenStreetMap tiles, drawn with Leaflet.'],
            ['Reports', 'CSV, Excel (openpyxl) and PDF (ReportLab) exports generated on the server.'],
          ].map(([title, body]) => (
            <div key={title}>
              <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">{title}</p>
              <p className="mt-1 text-[13px] leading-relaxed text-[var(--color-text-secondary)]">{body}</p>
            </div>
          ))}
        </div>
      </Card>

      <Card
        description="Residents accept Ziren’s terms and privacy notice when they register in the mobile app; their acceptance and the version they accepted are recorded on their account."
        title="Terms and privacy"
      >
        <p className="text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
          This dashboard does not publish those documents itself. What a resident’s report exposes to
          you, and how to keep it private on your own screen, is set out under{' '}
          <span className="font-semibold text-foreground">Privacy</span>.
        </p>
      </Card>

      <Card
        description="A short, safe summary of this browser and this console — no passwords, no tokens, no report text. Paste it into a message when you ask for help."
        title="Diagnostics"
      >
        <Button onClick={copyDiagnostics} size="sm" variant="outline">
          <ClipboardCopy data-icon="inline-start" />
          {copied ? 'Copied to clipboard' : 'Copy diagnostics'}
          {!copied && <ArrowRight className="size-3.5" />}
        </Button>
      </Card>
    </div>
  );
}
