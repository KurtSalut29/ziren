'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  ArrowRight, Bell, BellRing, Building2, CalendarDays, Copy, MapPinned, Siren,
  Timer,
} from 'lucide-react';
import { ApiError, apiClient } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDateTime } from '@/lib/format/datetime';
import { DISPATCH_TARGET_MINUTES, DEFAULT_TARGET_MINUTES } from '@/components/incidents/incident-vocabulary';
import { Input } from '@/components/efferd/ui/input';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Select, SelectContent, SelectGroup, SelectItem, SelectTrigger, SelectValue,
} from '@/components/efferd/ui/select';
import {
  Callout, Card, PanelHeader, Row, RowList, SaveBar, Stat, StatGrid, StatusDot,
  ToggleRow,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';
import { hotlineProblem } from '@/lib/format/hotlines';

// ── Types ────────────────────────────────────────────────────────────────

interface NotificationRules { critical: boolean; high: boolean; medium: boolean; low: boolean }

interface AgencyProfile {
  id: string;
  name: string;
  agency_type: string;
  municipality: string;
  province: string;
  region: string;
  contact_number: string | null;
  email: string | null;
  is_active: boolean;
  notification_rules: NotificationRules | null;
  created_at: string;
  updated_at: string;
}

interface AgencyOption { id: string; name: string; agency_type: string; municipality: string }

interface Overview { stations: number; responders: number; active_incidents: number; resolved_today: number }

interface StationRow {
  id: string;
  name: string;
  address: string | null;
  location: { coordinates?: number[] } | null;
  is_active: boolean;
  agency_id: string;
  has_coverage: boolean;
}

const AGENCY_COLOR: Record<string, string> = {
  BFP: 'var(--color-agency-bfp)',
  PNP: 'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

/**
 * What the database does when notification_rules is null. Mirrors the column
 * default in migration 041 and the fallback in useIncidentAlerts — all three
 * must agree, or the switches here describe alerting that is not happening.
 * These four cover SCORED reports only; an unscored one always interrupts.
 * Every severity is on: critical + high only meant PNP, whose everyday reports
 * score low/medium, was never alerted at all.
 */
const DEFAULT_RULES: NotificationRules = { critical: true, high: true, medium: true, low: true };

// ── Which agency (both roles) ────────────────────────────────────────────

type Section = 'record' | 'alerts';

/**
 * Resolves WHICH agency the two panels below are about.
 *
 * An Agency Admin has exactly one, on their account. A Provincial Admin owns
 * none and picks among the agencies of their type; the panels are remounted
 * when that choice changes (key={agencyId}) because re-fetching into a live
 * form would leave the previous agency's typed-but-unsaved values sitting under
 * the new agency's name, and Save would write them to the wrong record.
 */
export function AgencySection({
  token,
  section,
  isProvincialAdmin,
  onOpen,
}: {
  token: string;
  section: Section;
  isProvincialAdmin: boolean;
  onOpen: (key: string) => void;
}) {
  const [agencies, setAgencies] = useState<AgencyOption[]>([]);
  const [agencyId, setAgencyId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    const load = isProvincialAdmin
      ? apiClient.get<AgencyOption[]>('/users/agencies-list', token).then(list => {
          if (cancelled) return;
          setAgencies(list);
          if (list.length > 0) setAgencyId(list[0].id);
        })
      : apiClient.get<{ agency_id: string | null }>('/users/me', token).then(me => {
          if (!cancelled) setAgencyId(me.agency_id);
        });
    load
      .catch((e: unknown) => {
        if (cancelled) return;
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setError(e instanceof Error ? e.message : 'Could not load your agency.');
      })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [token, isProvincialAdmin]);

  const title = section === 'record' ? (isProvincialAdmin ? 'Edit an agency' : 'Agency Information') : 'Alerts';

  if (loading) {
    return (
      <div className="flex flex-col gap-6">
        <PanelHeader icon={section === 'record' ? Building2 : BellRing} scope="agency" title={title} />
        <Skeleton className="h-52 rounded-[var(--radius-card)]" />
        <Skeleton className="h-64 rounded-[var(--radius-card)]" />
      </div>
    );
  }
  if (error) {
    return (
      <div className="flex flex-col gap-6">
        <PanelHeader icon={Building2} scope="agency" title={title} />
        <Callout title="Could not load the agency" tone="danger">{error}</Callout>
      </div>
    );
  }
  if (!agencyId) {
    return (
      <div className="flex flex-col gap-6">
        <PanelHeader icon={Building2} scope="agency" title={title} />
        <Callout title="No agency is assigned to your account" tone="warning">
          There is nothing here to edit until a Provincial Admin sets it. Ask them to assign your agency.
        </Callout>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      {isProvincialAdmin && (
        <Card
          description="The record and alert rules below belong to whichever agency is selected. You are the only role that can switch it."
          title="Which agency"
        >
          <Select onValueChange={setAgencyId} value={agencyId}>
            <SelectTrigger aria-label="Agency" className="w-full max-w-md">
              <SelectValue placeholder="Select an agency" />
            </SelectTrigger>
            <SelectContent>
              <SelectGroup>
                {agencies.map(a => (
                  <SelectItem key={a.id} value={a.id}>
                    {a.agency_type} — {a.name} ({a.municipality})
                  </SelectItem>
                ))}
              </SelectGroup>
            </SelectContent>
          </Select>
        </Card>
      )}
      <AgencyPanels
        agencyId={agencyId}
        isProvincialAdmin={isProvincialAdmin}
        key={agencyId}
        onOpen={onOpen}
        section={section}
        token={token}
      />
    </div>
  );
}

function AgencyPanels({
  agencyId, token, section, isProvincialAdmin, onOpen,
}: {
  agencyId: string;
  token: string;
  section: Section;
  isProvincialAdmin: boolean;
  onOpen: (key: string) => void;
}) {
  // ONE fetch shared by both panels. They used to each call the same endpoint
  // for the same record on every load.
  const [profile, setProfile] = useState<AgencyProfile | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      setProfile(await apiClient.get<AgencyProfile>(`/stations/agencies/${agencyId}`, token));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load the agency profile.');
    }
  }, [agencyId, token]);

  useEffect(() => { void load(); }, [load]);

  if (error && !profile) return <Callout title="Could not load the agency" tone="danger">{error}</Callout>;
  if (!profile) {
    return (
      <div className="flex flex-col gap-6">
        <Skeleton className="h-40 rounded-[var(--radius-card)]" />
        <Skeleton className="h-72 rounded-[var(--radius-card)]" />
      </div>
    );
  }

  return section === 'record'
    ? <AgencyInformation isProvincialAdmin={isProvincialAdmin} onSaved={load} profile={profile} token={token} />
    : <AlertsPanel onOpen={onOpen} onSaved={load} profile={profile} token={token} />;
}

// ── Agency Information ───────────────────────────────────────────────────

/** Plausible phone digits, or empty. */
// A station may list several lines — see lib/format/hotlines.ts. The mobile
// app shows each one as its own Call button, online and offline.
const phoneProblem = hotlineProblem;

function emailProblem(raw: string): string | null {
  const v = raw.trim();
  if (v === '') return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v) ? null : 'That does not look like an email address.';
}

function AgencyInformation({
  profile, token, onSaved, isProvincialAdmin,
}: {
  profile: AgencyProfile;
  token: string;
  onSaved: () => void;
  isProvincialAdmin: boolean;
}) {
  const display = displayPrefs.use();
  const [form, setForm] = useState({
    name: profile.name,
    municipality: profile.municipality,
    contact_number: profile.contact_number ?? '',
    email: profile.email ?? '',
  });
  const [saving, setSaving] = useState(false);
  const setNotice = useNotice();
  const [stats, setStats] = useState<Overview | null>(null);
  const [stations, setStations] = useState<StationRow[] | null>(null);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let cancelled = false;
    apiClient.get<Overview>(`/stations/agencies/${profile.id}/overview`, token)
      .then(s => { if (!cancelled) setStats(s); })
      .catch(() => { /* a bonus — the form below works without it */ });
    apiClient.get<StationRow[]>('/stations/', token)
      .then(rows => { if (!cancelled) setStations(rows.filter(r => r.agency_id === profile.id)); })
      .catch(() => { if (!cancelled) setStations([]); });
    return () => { cancelled = true; };
  }, [profile.id, token]);

  const problems = useMemo(() => ({
    name: form.name.trim() === '' ? 'The agency needs a name.' : null,
    municipality: form.municipality.trim() === '' ? 'The agency needs a municipality.' : null,
    contact_number: phoneProblem(form.contact_number),
    email: emailProblem(form.email),
  }), [form]);
  const valid = !Object.values(problems).some(Boolean);

  const dirty =
    form.name.trim() !== profile.name ||
    form.municipality.trim() !== profile.municipality ||
    form.contact_number.trim() !== (profile.contact_number ?? '') ||
    form.email.trim() !== (profile.email ?? '');

  function set<K extends keyof typeof form>(key: K, value: string) {
    setForm(f => ({ ...f, [key]: value }));
    setNotice(null);
  }

  async function save() {
    if (!valid) return;
    setSaving(true);
    setNotice(null);
    try {
      await apiClient.patch(
        `/stations/agencies/${profile.id}`,
        {
          name: form.name.trim(),
          municipality: form.municipality.trim(),
          contact_number: form.contact_number.trim() || null,
          email: form.email.trim() || null,
        },
        token,
      );
      setNotice({ tone: 'success', text: 'The agency record was updated.' });
      onSaved();
    } catch (e) {
      setNotice({ tone: 'danger', text: e instanceof Error ? e.message : 'Save failed.' });
    } finally {
      setSaving(false);
    }
  }

  function discard() {
    setForm({
      name: profile.name,
      municipality: profile.municipality,
      contact_number: profile.contact_number ?? '',
      email: profile.email ?? '',
    });
    setNotice(null);
  }

  async function copyId() {
    try {
      await navigator.clipboard.writeText(profile.id);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch { /* clipboard blocked */ }
  }

  const color = AGENCY_COLOR[profile.agency_type] ?? 'var(--color-brand)';

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description={
          isProvincialAdmin
            ? 'The record for the agency selected above: who residents and other agencies are given to contact.'
            : 'Your agency’s record: the name, place and contact details residents and other agencies are given.'
        }
        icon={Building2}
        scope={isProvincialAdmin ? ['agency', 'province'] : 'agency'}
        title={isProvincialAdmin ? 'Edit an agency' : 'Agency Information'}
      />

      <Card>
        <div className="flex flex-wrap items-center gap-5">
          <span
            aria-hidden="true"
            className="flex size-14 shrink-0 items-center justify-center rounded-[16px] text-[15px] font-black tracking-wide"
            style={{ color, backgroundColor: `color-mix(in srgb, ${color} 13%, transparent)` }}
          >
            {profile.agency_type}
          </span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[18px] font-bold leading-tight text-foreground">{profile.name}</p>
            <p className="mt-0.5 text-[13px] text-muted-foreground">
              {profile.municipality} · {profile.province} · {profile.region}
            </p>
            <div className="mt-2">
              <StatusDot tone={profile.is_active ? 'success' : 'neutral'}>
                {profile.is_active ? 'Active' : 'Inactive'}
              </StatusDot>
            </div>
          </div>
        </div>
      </Card>

      {stats && (
        <StatGrid>
          <Stat hint="Physical locations" label="Stations" value={stats.stations} />
          <Stat hint="On the roster" label="Responders" value={stats.responders} />
          <Stat hint="Not yet closed" label="Active incidents" value={stats.active_incidents} />
          <Stat hint="Since midnight" label="Resolved today" tone="success" value={stats.resolved_today} />
        </StatGrid>
      )}


      <Card
        description="What residents and other agencies see when they need to reach this agency. Changes apply to everyone in it."
        title="Name and contact"
      >
        <RowList>
          <Field error={problems.name} id="agency-name" label="Agency name">
            <Input aria-invalid={!!problems.name} className="max-w-[380px]" id="agency-name" onChange={e => set('name', e.target.value)} value={form.name} />
          </Field>
          <Field error={problems.municipality} id="agency-municipality" label="Municipality">
            <Input aria-invalid={!!problems.municipality} className="max-w-[380px]" id="agency-municipality" onChange={e => set('municipality', e.target.value)} value={form.municipality} />
          </Field>
          <Field error={problems.contact_number} id="agency-contact" label="Hotline numbers">
            <Input aria-invalid={!!problems.contact_number} className="max-w-[460px]" id="agency-contact" inputMode="tel" onChange={e => set('contact_number', e.target.value)} placeholder="Globe: 0955-723-6300; Smart: 0948-024-3466" value={form.contact_number} />
            {/* Residents see these in the app, and can call them with no
                internet — so every number here has to be dialable. */}
            {!problems.contact_number && (
              <span className="mt-1.5 block text-[12px] text-muted-foreground">
                Shown to residents in the app as Call buttons, even offline. Separate several numbers with “;”, and add a label if you like — “Globe:”, “Smart:”, “Landline:”.
              </span>
            )}
          </Field>
          <Field error={problems.email} id="agency-email" label="Email address">
            <Input aria-invalid={!!problems.email} className="max-w-[380px]" id="agency-email" onChange={e => set('email', e.target.value)} placeholder="agency@biliran.gov.ph" type="email" value={form.email} />
          </Field>
        </RowList>
      </Card>

      <Card
        action={
          <Link className="inline-flex items-center gap-1 text-[13px] font-semibold text-[var(--color-brand)] hover:underline" href="/agencies">
            Manage stations <ArrowRight className="size-3.5" />
          </Link>
        }
        description="Where this agency’s crews are based. Adding a station, moving its pin and drawing its coverage area is done under Agencies."
        flush
        title="Stations"
      >
        {stations === null ? (
          <div className="flex flex-col gap-2 px-5 py-4"><Skeleton className="h-10 rounded-lg" /><Skeleton className="h-10 rounded-lg" /></div>
        ) : stations.length === 0 ? (
          <p className="px-5 py-6 text-[13px] text-muted-foreground">This agency has no active stations yet.</p>
        ) : (
          <ul className="divide-y divide-[var(--color-surface-border)]">
            {stations.map(st => (
              <li className="flex flex-wrap items-center gap-x-4 gap-y-1 px-5 py-3" key={st.id}>
                <MapPinned aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1">
                  <span className="block text-[13.5px] font-medium text-foreground">{st.name}</span>
                  <span className="block text-[12px] text-muted-foreground">{st.address ?? 'No address recorded'}</span>
                </span>
                <span className="flex items-center gap-3 text-[12px]">
                  <StatusDot tone={st.location?.coordinates ? 'success' : 'warning'}>
                    {st.location?.coordinates ? 'Pin placed' : 'No pin'}
                  </StatusDot>
                  <StatusDot tone={st.has_coverage ? 'success' : 'neutral'}>
                    {st.has_coverage ? 'Coverage set' : 'No coverage'}
                  </StatusDot>
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card flush title="Record">
        <RowList>
          <Row icon={CalendarDays} label="Created">
            <span className="font-mono text-[13px] text-foreground">{formatDateTime(profile.created_at, display)}</span>
          </Row>
          <Row icon={CalendarDays} label="Last changed">
            <span className="font-mono text-[13px] text-foreground">{formatDateTime(profile.updated_at, display)}</span>
          </Row>
          <Row description="Quote this if you need help with this agency’s record." label="Agency ID">
            <span className="flex items-center gap-2">
              <code className="rounded-md bg-[var(--color-surface-raised)] px-2 py-1 font-mono text-[12px] text-foreground">{profile.id}</code>
              <Button onClick={copyId} size="sm" variant="outline">
                <Copy data-icon="inline-start" />
                {copied ? 'Copied' : 'Copy'}
              </Button>
            </span>
          </Row>
        </RowList>
      </Card>

      <SaveBar dirty={dirty && valid} onDiscard={discard} onSave={save} saving={saving} />
    </div>
  );
}

function Field({
  id, label, error, children,
}: {
  id: string; label: string; error: string | null; children: React.ReactNode;
}) {
  return (
    <Row htmlFor={id} label={label}>
      {children}
      {error && <span className="mt-1.5 block text-[12px]" style={{ color: 'var(--color-severity-critical)' }}>{error}</span>}
    </Row>
  );
}

// ── Alerts ───────────────────────────────────────────────────────────────

const SEVERITY_LEVELS: { key: keyof NotificationRules; label: string; color: string; desc: string }[] = [
  { key: 'critical', label: 'Critical', color: 'var(--color-severity-critical)', desc: 'Fire with fatalities, mass casualty, hazardous materials.' },
  { key: 'high', label: 'High', color: 'var(--color-severity-high)', desc: 'Confirmed injuries, armed incidents.' },
  { key: 'medium', label: 'Medium', color: 'var(--color-severity-medium)', desc: 'Property damage, minor disputes.' },
  { key: 'low', label: 'Low', color: 'var(--color-severity-low)', desc: 'Informational reports with no immediate threat.' },
];

/**
 * Crew acknowledgement deadlines, seconds. MIRRORS `_ACK_DEADLINE_SECONDS` in
 * ziren_backend/app/services/responder_ack.py — that is where the board and the
 * responder's phone both read it, so it is the source of truth. Shown here so an
 * admin can see what "overdue" means; not editable, because it is policy in
 * code, not a per-agency setting.
 */
const ACK_SECONDS: Record<string, number> = { critical: 60, high: 120, medium: 180, low: 180 };
const ACK_DEFAULT_SECONDS = 60;

function AlertsPanel({
  profile, token, onSaved, onOpen,
}: {
  profile: AgencyProfile;
  token: string;
  onSaved: () => void;
  onOpen: (key: string) => void;
}) {
  const stored = useMemo(() => profile.notification_rules ?? DEFAULT_RULES, [profile.notification_rules]);
  const [rules, setRules] = useState<NotificationRules>(stored);
  const [saving, setSaving] = useState(false);
  const setNotice = useNotice();

  const dirty = SEVERITY_LEVELS.some(({ key }) => rules[key] !== stored[key]);
  const noneOn = SEVERITY_LEVELS.every(({ key }) => !rules[key]);
  const onCount = SEVERITY_LEVELS.filter(({ key }) => rules[key]).length;

  async function save() {
    setSaving(true);
    setNotice(null);
    try {
      await apiClient.patch(`/stations/agencies/${profile.id}`, { notification_rules: rules }, token);
      setNotice({ tone: 'success', text: 'Alert rules saved. They apply to every dispatcher in this agency within seconds.' });
      onSaved();
    } catch (e) {
      setNotice({ tone: 'danger', text: e instanceof Error ? e.message : 'Save failed.' });
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Which reports break into your dispatchers’ attention. Everything still reaches the live queue; these rules only decide what interrupts."
        icon={BellRing}
        scope="agency"
        title="Alerts"
      />


      <Card
        description={
          profile.notification_rules === null
            ? 'This agency has never set these, so the defaults are shown: every severity.'
            : `${onCount} of 4 severities interrupt.`
        }
        flush
        title="Which severities interrupt"
      >
        <RowList>
          {SEVERITY_LEVELS.map(({ key, label, color, desc }) => (
            <ToggleRow
              checked={rules[key]}
              description={desc}
              id={`notify-${key}`}
              key={key}
              label={label}
              badge={<span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: color }} />}
              onChange={v => { setRules(r => ({ ...r, [key]: v })); setNotice(null); }}
            />
          ))}
          <Row
            description="A report the rules could not score has no severity to switch off, so it always interrupts — it is the one most in need of a person."
            label="Not yet scored"
          >
            <StatusDot tone="success">Always alerts</StatusDot>
          </Row>
        </RowList>
      </Card>

      {noneOn && (
        <Callout title="No scored report will interrupt anyone" tone="warning">
          With every severity off, not even a critical report breaks in. Reports still arrive in
          the live queue, but only someone looking at it will see them.
        </Callout>
      )}

      <Card
        description="These rules are the agency’s. How each dispatcher’s own screen delivers an alert — sound, volume, desktop pop-up — is set per browser."
        title="How an alert reaches a person"
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <p className="max-w-[54ch] text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
            An alert shows on screen, can flash the tab, play an alarm and raise a desktop
            pop-up, depending on the browser’s settings.
          </p>
          <Button onClick={() => onOpen('notifications')} size="sm" variant="outline">
            <Bell data-icon="inline-start" />
            Open notification settings
          </Button>
        </div>
      </Card>

      <Card
        description="The clocks the console runs against each report. They are set in code — provisional, pending each agency confirming its own — and shown here so “late” and “overdue” have a meaning you can check."
        flush
        title="Response targets"
      >
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-left text-[13px]">
            <thead>
              <tr className="border-b border-[var(--color-surface-border)] text-[11.5px] font-semibold uppercase tracking-wide text-muted-foreground">
                <th className="px-5 py-2.5 font-semibold" scope="col">Severity</th>
                <th className="px-3 py-2.5 font-semibold" scope="col">
                  <span className="inline-flex items-center gap-1.5"><Siren aria-hidden="true" className="size-3.5" />Dispatch within</span>
                </th>
                <th className="px-5 py-2.5 font-semibold" scope="col">
                  <span className="inline-flex items-center gap-1.5"><Timer aria-hidden="true" className="size-3.5" />Crew must accept within</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {[...SEVERITY_LEVELS.map(s => s.key as string), 'untriaged'].map(sev => {
                const meta = SEVERITY_LEVELS.find(s => s.key === sev);
                const dispatch = DISPATCH_TARGET_MINUTES[sev] ?? DEFAULT_TARGET_MINUTES;
                const ack = ACK_SECONDS[sev] ?? ACK_DEFAULT_SECONDS;
                return (
                  <tr className="border-b border-[var(--color-surface-border)] last:border-b-0" key={sev}>
                    <td className="px-5 py-3">
                      <span className="inline-flex items-center gap-2 font-semibold text-foreground">
                        <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: meta?.color ?? 'var(--color-text-muted)' }} />
                        {meta?.label ?? 'Not yet scored'}
                      </span>
                    </td>
                    <td className="px-3 py-3 font-mono tabular-nums text-foreground">{dispatch} min</td>
                    <td className="px-5 py-3 font-mono tabular-nums text-foreground">
                      {ack >= 60 && ack % 60 === 0 ? `${ack / 60} min` : `${ack} s`}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <p className="border-t border-[var(--color-surface-border)] px-5 py-3 text-[12.5px] leading-relaxed text-muted-foreground">
          A report is flagged <span className="font-semibold text-foreground">due</span> in the last quarter of its
          dispatch window and <span className="font-semibold text-foreground">late</span> after it. An assignment a
          crew has not accepted in time is shown <span className="font-semibold text-foreground">overdue</span> on the
          board and reads the same on the responder’s phone. A report not yet scored gets the strictest clock, not
          the most forgiving.
        </p>
      </Card>

      <SaveBar
        dirty={dirty}
        label="Save alert rules"
        message="You have unsaved alert rules."
        onDiscard={() => { setRules(stored); setNotice(null); }}
        onSave={save}
        saving={saving}
      />
    </div>
  );
}
