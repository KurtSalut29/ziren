'use client';

/**
 * Settings.
 *
 * A grouped rail of sections on the left with a search box on top, and the
 * selected section on the right. Each section is its own file under
 * components/settings/panels/ — this page only decides which sections a role
 * gets, in what order, and shows the one selected.
 *
 * WHERE EACH SETTING IS SAVED is the organising idea, and every panel says so in
 * its header (a "scope" chip): THIS BROWSER (appearance, alerts delivery, map,
 * incident display, privacy, accessibility — applied instantly, never leaves
 * the machine), YOUR ACCOUNT (profile, password, sessions), YOUR AGENCY (its
 * record, alert rules, responder approvals — shared by everyone in it) and
 * PROVINCE-WIDE. Confusing those is how a shared terminal ends up with someone
 * else's font size, or one admin switches off an agency's alert believing it was
 * only theirs.
 *
 * The two admin roles do not get one rail with items hidden. A Provincial Admin
 * configures their agency type's whole footprint and gets three whole groups
 * (System Management, Integrations, Audit & System) an Agency Admin never sees.
 *
 * Deep links: /settings?tab=notifications opens that section, and choosing one
 * updates the address, so a section can be linked to from anywhere — including
 * from the alert that says "check your notification settings".
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Accessibility, Activity, Bell, BellRing, BrainCircuit, Building2,
  ClipboardList, Globe, HardDrive, Info, KeyRound, LandPlot, LifeBuoy,
  ListChecks, MapPin, MonitorSmartphone, Palette, Plug, Scale,
  ScrollText, Server, ShieldCheck, SlidersHorizontal, Smartphone, Tags, User, UserCog, Users,
} from 'lucide-react';
import { useAuth } from '@/lib/hooks/useAuth';
import { Alert } from '@/components/ui/alert';
import { Check } from 'lucide-react';
import { SaveSlotContext, SettingsSearch, SettingsTabs, type RailGroup } from '@/components/settings/kit';
import { LinkOutPanel } from '@/components/settings/settings-kit';
import { AgencySection } from '@/components/settings/panels/agency';
import { RespondersPanel } from '@/components/settings/panels/responders';
import { ProfilePanel } from '@/components/settings/panels/profile';
import { SecurityPanel } from '@/components/settings/panels/security';
import { LoginDevicesPanel } from '@/components/settings/panels/login-devices';
import { PrivacyPanel } from '@/components/settings/panels/privacy';
import { AppearancePanel } from '@/components/settings/panels/appearance';
import { NotificationsPanel } from '@/components/settings/panels/notifications';
import { MapLocationPanel } from '@/components/settings/panels/map-location';
import { IncidentPreferencesPanel } from '@/components/settings/panels/incident-preferences';
import { AccessibilityPanel } from '@/components/settings/panels/accessibility';
import { LanguagePanel } from '@/components/settings/panels/language';
import { SupportPanel } from '@/components/settings/panels/support';
import { AboutPanel } from '@/components/settings/panels/about';
import { BackupPanel, PushPanel, SystemConfigPanel } from '@/components/settings/panels/system';
import { AiNlpPanel, IncidentCategoriesPanel } from '@/components/settings/extra-panels';

type SettingsTab =
  | 'agency' | 'alerts' | 'responders'
  | 'profile' | 'security' | 'login-devices' | 'privacy'
  | 'appearance' | 'notifications' | 'map-location' | 'incident-prefs' | 'accessibility' | 'language'
  | 'agencies-link' | 'users-roles-link' | 'incident-categories' | 'system-config'
  | 'push-notifications' | 'ai-nlp' | 'severity-rules-link'
  | 'audit-logs-link' | 'system-status-link' | 'backup-recovery'
  | 'support' | 'about';

/**
 * The rail, per role. `keywords` are the words a person might type to find a
 * section without knowing its name — the search box matches them as well as the
 * label, so "sound", "password" or "font" all lead somewhere.
 */
function railGroupsFor(isProvincialAdmin: boolean): RailGroup[] {
  const profile: RailGroup = {
    label: 'Profile',
    icon: User,
    items: [
      { key: 'profile', label: 'Profile', icon: User, keywords: ['name', 'phone', 'email', 'account id', 'avatar', 'photo'] },
      { key: 'security', label: 'Account & Security', icon: KeyRound, keywords: ['password', 'change password', 'two-factor', '2fa', 'strength', 'check-up'] },
      { key: 'login-devices', label: 'Login & Devices', icon: MonitorSmartphone, keywords: ['sessions', 'sign out', 'devices', 'history', 'idle', 'timeout', 'log out'] },
      { key: 'privacy', label: 'Privacy', icon: ShieldCheck, keywords: ['mask', 'phone numbers', 'data', 'download', 'export', 'reset', 'backup', 'activity', 'gdpr'] },
    ],
  };
  const preferences: RailGroup = {
    label: 'Preferences',
    icon: SlidersHorizontal,
    items: [
      { key: 'appearance', label: 'Appearance', icon: Palette, keywords: ['theme', 'dark', 'light', 'density', 'compact', 'date', 'time', '12-hour', '24-hour', 'time zone'] },
      { key: 'notifications', label: 'Notifications', icon: Bell, keywords: ['sound', 'alarm', 'volume', 'alert', 'desktop', 'pop-up', 'flash', 'mute', 'inbox', 'poll'] },
      { key: 'map-location', label: 'Map & Location', icon: MapPin, keywords: ['basemap', 'satellite', 'street', 'layers', 'units', 'miles', 'kilometres', 'coordinates', 'labels'] },
      { key: 'incident-prefs', label: 'Incident Preferences', icon: ListChecks, keywords: ['queue', 'refresh', 'records', 'per page', 'window', 'record panel', 'sections'] },
      { key: 'accessibility', label: 'Accessibility', icon: Accessibility, keywords: ['font', 'text size', 'zoom', 'contrast', 'motion', 'focus', 'underline', 'spacing', 'larger'] },
      { key: 'language', label: 'Language & Region', icon: Globe, keywords: ['english', 'filipino', 'bisaya', 'waray', 'locale', 'format', 'translate'] },
    ],
  };
  const agency: RailGroup = {
    label: isProvincialAdmin ? 'Agency Tools' : 'Agency',
    icon: Building2,
    items: [
      { key: 'agency', label: isProvincialAdmin ? 'Edit an agency' : 'Agency Information', icon: Building2, keywords: ['contact', 'municipality', 'stations', 'name', 'email', 'phone'] },
      { key: 'alerts', label: 'Alerts', icon: BellRing, keywords: ['severity', 'interrupt', 'rules', 'critical', 'response', 'targets', 'deadline'] },
      ...(isProvincialAdmin ? [] : [{ key: 'responders', label: 'Responders', icon: Users, keywords: ['approve', 'roster', 'on duty', 'pending', 'crew'] }]),
    ],
  };
  const support: RailGroup = {
    label: 'Support',
    icon: LifeBuoy,
    items: [
      { key: 'support', label: 'Help & Support', icon: LifeBuoy, keywords: ['help', 'faq', 'contact', 'shortcuts', 'keyboard', 'report a problem', 'diagnostics', 'guide'] },
      { key: 'about', label: 'About Ziren', icon: Info, keywords: ['version', 'what is new', 'changelog', 'health', 'built with', 'legal'] },
    ],
  };

  if (!isProvincialAdmin) return [agency, profile, preferences, support];

  return [
    profile,
    agency,
    {
      label: 'System Management',
      icon: Server,
      items: [
        { key: 'agencies-link', label: 'Agencies', icon: LandPlot, keywords: ['stations', 'coverage'] },
        { key: 'users-roles-link', label: 'Users & Roles', icon: UserCog, keywords: ['accounts', 'admins', 'residents'] },
        { key: 'incident-categories', label: 'Incident Categories', icon: Tags, keywords: ['fire', 'medical', 'routing'] },
        { key: 'system-config', label: 'System Configuration', icon: SlidersHorizontal, keywords: ['limits', 'rate limit', 'threshold', 'password policy', 'deadline'] },
      ],
    },
    preferences,
    {
      label: 'Integrations',
      icon: Plug,
      items: [
        { key: 'push-notifications', label: 'Push Notifications', icon: Smartphone, keywords: ['mobile', 'permission'] },
        { key: 'ai-nlp', label: 'AI & NLP', icon: BrainCircuit, keywords: ['classifier', 'model', 'triage', 'waray'] },
        { key: 'severity-rules-link', label: 'Severity Rules', icon: Scale, keywords: ['rubric', 'rules'] },
      ],
    },
    {
      label: 'Audit & System',
      icon: ScrollText,
      items: [
        { key: 'audit-logs-link', label: 'Audit Logs', icon: ClipboardList, keywords: ['history', 'trail'] },
        { key: 'system-status-link', label: 'System Status', icon: Activity, keywords: ['health', 'uptime'] },
        { key: 'backup-recovery', label: 'Backup & Recovery', icon: HardDrive, keywords: ['restore', 'export'] },
      ],
    },
    support,
  ];
}

export default function SettingsPage() {
  const { token, role, agencyType, isProvincialAdmin, isAgencyAdmin } = useAuth();
  const groups = useMemo(() => railGroupsFor(isProvincialAdmin), [isProvincialAdmin]);
  const validKeys = useMemo(() => new Set(groups.flatMap(g => g.items.map(i => i.key))), [groups]);
  const defaultTab: SettingsTab = isProvincialAdmin ? 'profile' : 'agency';

  const [tab, setTab] = useState<SettingsTab | null>(null);
  // Where a panel's SaveBar puts its buttons: the page's top-right corner.
  const [saveSlot, setSaveSlot] = useState<HTMLElement | null>(null);
  // The heading row is only pinned from tablet width up. On a phone it would eat
  // a fifth of the screen, so there the unsaved-changes bar floats at the bottom
  // instead — the SaveBar's own fallback when it is handed no slot.
  const [wide, setWide] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 768px)');
    const update = () => setWide(mq.matches);
    update();
    mq.addEventListener('change', update);
    return () => mq.removeEventListener('change', update);
  }, []);

  // Deep link: /settings?tab=notifications. Read once on arrival.
  useEffect(() => {
    const wanted = new URLSearchParams(window.location.search).get('tab');
    if (wanted && validKeys.has(wanted)) setTab(wanted as SettingsTab);
  }, [validKeys]);

  const select = useCallback((key: string) => {
    setTab(key as SettingsTab);
    // Address bar follows the selection so a section can be linked to and
    // survives a reload. replaceState, not pushState: browsing sections is not
    // history a person wants to Back through.
    try {
      window.history.replaceState(null, '', `${window.location.pathname}?tab=${key}`);
    } catch { /* an embedded or sandboxed context — the state still works */ }
    // The panel is taller than the screen; land at its top, not wherever the
    // previous one was scrolled to.
    document.getElementById('main-content')?.scrollTo({ top: 0 });
  }, []);

  if (!token || (!isProvincialAdmin && !isAgencyAdmin)) {
    return (
      <div className="px-6 py-5 md:px-7">
        <Alert variant="error" message="Settings are only available to Agency Admins and Provincial Admins." />
      </div>
    );
  }

  const active: SettingsTab = tab && validKeys.has(tab) ? tab : defaultTab;

  return (
    <SaveSlotContext.Provider value={wide ? saveSlot : null}>
    <div className="min-h-full">
      <div className="mx-auto w-full max-w-[1120px] pb-16">
        {/* The page's own heading row: the title, a way to find a section, and —
            always in this corner — the action for whatever is unsaved. Sticky, so
            Save is never a scroll away from a long form. */}
        <div className="z-20 bg-[var(--color-frame)] px-6 pb-3 pt-7 md:sticky md:top-0 md:px-8">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-3">
            <h1 className="text-[30px] font-bold leading-none tracking-tight text-foreground">Settings</h1>
            <div className="flex w-full flex-wrap items-center gap-3 sm:ml-auto sm:w-auto">
              <SettingsSearch groups={groups} onSelect={select} />
              <div className="contents peer" ref={setSaveSlot} />
              <span className="hidden items-center gap-1.5 text-[13px] font-medium text-muted-foreground md:inline-flex peer-has-[[data-save-active]]:hidden">
                <Check aria-hidden="true" className="size-4 text-[var(--color-system-success)]" strokeWidth={2.5} />
                No unsaved changes
              </span>
            </div>
          </div>
        </div>

        <div className="px-6 md:px-8">
          <SettingsTabs activeKey={active} groups={groups} onSelect={select} />
        </div>

        <div className="min-w-0 px-6 pt-4 md:px-8" key={active}>
          {/* ── Agency ─────────────────────────────────────────── */}
          {active === 'agency' && (
            <AgencySection isProvincialAdmin={isProvincialAdmin} onOpen={select} section="record" token={token} />
          )}
          {active === 'alerts' && (
            <AgencySection isProvincialAdmin={isProvincialAdmin} onOpen={select} section="alerts" token={token} />
          )}
          {active === 'responders' && !isProvincialAdmin && <RespondersPanel token={token} />}

          {/* ── Profile ────────────────────────────────────────── */}
          {active === 'profile' && <ProfilePanel token={token} />}
          {active === 'security' && <SecurityPanel token={token} />}
          {active === 'login-devices' && <LoginDevicesPanel token={token} />}
          {active === 'privacy' && <PrivacyPanel isProvincialAdmin={isProvincialAdmin} token={token} />}

          {/* ── Preferences ────────────────────────────────────── */}
          {active === 'appearance' && <AppearancePanel />}
          {active === 'notifications' && <NotificationsPanel isProvincialAdmin={isProvincialAdmin} onOpen={select} token={token} />}
          {active === 'map-location' && <MapLocationPanel />}
          {active === 'incident-prefs' && <IncidentPreferencesPanel />}
          {active === 'accessibility' && <AccessibilityPanel />}
          {active === 'language' && <LanguagePanel token={token} />}

          {/* ── Support ────────────────────────────────────────── */}
          {active === 'support' && (
            <SupportPanel agencyType={agencyType} isProvincialAdmin={isProvincialAdmin} role={role} token={token} />
          )}
          {active === 'about' && <AboutPanel agencyType={agencyType} role={role} token={token} />}

          {/* ── Provincial Admin: real panels ──────────────────── */}
          {isProvincialAdmin && active === 'system-config' && <SystemConfigPanel token={token} />}
          {isProvincialAdmin && active === 'push-notifications' && <PushPanel onOpen={select} />}
          {isProvincialAdmin && active === 'backup-recovery' && <BackupPanel />}
          {isProvincialAdmin && active === 'ai-nlp' && <AiNlpPanel token={token} />}
          {isProvincialAdmin && active === 'incident-categories' && <IncidentCategoriesPanel />}

          {/* ── Provincial Admin: a real page already owns these ── */}
          {isProvincialAdmin && active === 'agencies-link' && (
            <LinkOutPanel cta="Open Agencies" description="Every agency registered in Ziren — add one, deactivate one, or manage its stations and administrators." href="/agencies" icon={LandPlot} title="Agencies" />
          )}
          {isProvincialAdmin && active === 'users-roles-link' && (
            <LinkOutPanel cta="Open Accounts" description="Every Ziren account across every role — residents, responders and admins — and the role each one holds." href="/accounts" icon={UserCog} title="Users & Roles" />
          )}
          {isProvincialAdmin && active === 'severity-rules-link' && (
            <LinkOutPanel cta="Open Severity Rules" description="The per-agency rules that turn a report’s extracted signals into a suggested severity." href="/governance/severity" icon={Scale} title="Severity Rules" />
          )}
          {isProvincialAdmin && active === 'audit-logs-link' && (
            <LinkOutPanel cta="Open Audit Logs" description="Every recorded administrative action, in order — including admin sign-ins and password changes." href="/audit-logs" icon={ClipboardList} title="Audit Logs" />
          )}
          {isProvincialAdmin && active === 'system-status-link' && (
            <LinkOutPanel cta="Open System Status" description="Live health of the server, database and classifier." href="/system-status" icon={Activity} title="System Status" />
          )}
        </div>
      </div>
    </div>
    </SaveSlotContext.Provider>
  );
}
