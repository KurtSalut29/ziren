'use client';

import { useEffect, useRef, useState } from 'react';
import {
  Download, EyeOff, FileJson, History, Phone, RotateCcw, ShieldCheck, Upload, UserRound,
} from 'lucide-react';
import { apiClient, ApiError } from '@/lib/api/client';
import {
  describeAction, fetchAccountSecurity, fetchMyActivity, type ActivityItem,
} from '@/lib/api/account';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs, privacyPrefs } from '@/lib/prefs/definitions';
import { formatDate, formatDateTime } from '@/lib/format/datetime';
import {
  downloadJson, exportPreferences, importPreferences, resetAllPreferences,
} from '@/lib/prefs/backup';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Card, PanelHeader, Row, RowList, SavedFlash, ToggleRow,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';

interface MyProfile {
  full_name: string;
  email: string;
  phone_number: string | null;
  role: string;
  agency_type: string | null;
  agency_name: string | null;
  badge_id: string | null;
  is_verified: boolean;
  created_at: string;
}

const ROLE_LABEL: Record<string, string> = {
  agency_admin: 'Agency Admin',
  provincial_admin: 'Provincial Admin',
};

export function PrivacyPanel({ token, isProvincialAdmin }: { token: string; isProvincialAdmin: boolean }) {
  const display = displayPrefs.use();
  const privacy = privacyPrefs.use();

  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [activity, setActivity] = useState<ActivityItem[] | null>(null);
  const [showActivity, setShowActivity] = useState(false);
  const setNotice = useNotice();
  const [exporting, setExporting] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    apiClient.get<MyProfile>('/users/me', token)
      .then(setProfile)
      .catch((e: unknown) => { if (e instanceof ApiError && e.status === 401) signOut(); });
    fetchMyActivity(token, { kind: 'all', limit: 100 })
      .then(r => setActivity(r.items))
      .catch(() => setActivity([]));
  }, [token]);

  /**
   * Everything Ziren holds about THIS account, as a file the person keeps.
   *
   * Assembled from the same endpoints the rest of Settings reads, so it can
   * never claim to hold something the console does not, nor omit something it
   * shows. The preferences are this browser's, included because they are also
   * "data about you", even though they never leave the machine.
   */
  async function downloadMyData() {
    setExporting(true);
    setNotice(null);
    try {
      const [account, security, trail] = await Promise.all([
        apiClient.get<MyProfile>('/users/me', token),
        fetchAccountSecurity(token).catch(() => null),
        fetchMyActivity(token, { kind: 'all', limit: 100 }).catch(() => ({ items: [] as ActivityItem[] })),
      ]);
      downloadJson(`ziren-my-data-${new Date().toISOString().slice(0, 10)}.json`, {
        generated_at: new Date().toISOString(),
        about: 'Everything the Ziren console holds about your own account. Activity is your most recent 100 recorded actions.',
        account,
        security,
        recorded_activity: trail.items,
        preferences_on_this_browser: exportPreferences(),
      });
      setNotice({ tone: 'success', text: 'Your data was downloaded as a JSON file.' });
    } catch {
      setNotice({ tone: 'danger', text: 'Could not assemble your data. Try again in a moment.' });
    } finally {
      setExporting(false);
    }
  }

  function saveBackup() {
    downloadJson(`ziren-settings-${new Date().toISOString().slice(0, 10)}.json`, exportPreferences());
    setNotice({ tone: 'success', text: 'Your settings for this browser were saved to a file.' });
  }

  async function loadBackup(file: File) {
    setNotice(null);
    try {
      const result = importPreferences(JSON.parse(await file.text()));
      if (result.ok) {
        setNotice({ tone: 'success', text: `Restored ${result.applied} groups of settings. Reloading to apply the theme…` });
        setTimeout(() => window.location.reload(), 900);
      } else {
        setNotice({ tone: 'danger', text: result.reason });
      }
    } catch {
      setNotice({ tone: 'danger', text: 'That file could not be read as a settings backup.' });
    }
  }

  function resetEverything() {
    if (!window.confirm('Reset every setting on this browser to how it shipped? Your account and agency settings are not affected.')) return;
    resetAllPreferences();
    setNotice({ tone: 'success', text: 'This browser’s settings were reset. Reloading…' });
    setTimeout(() => window.location.reload(), 700);
  }

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="What Ziren holds about you, who can see a resident’s details on your screen, and how to take your data with you or wipe this browser clean."
        icon={ShieldCheck}
        meta={<SavedFlash signal={privacy.maskContacts} />}
        scope={['account', 'browser']}
        title="Privacy"
      />


      <Card
        description="Residents’ phone numbers and emergency contacts appear in the record panel. If other people can see your screen — a shared display, a screen share, a projected demo — hide them until you ask."
        title="Residents’ contact details on screen"
      >
        <RowList>
          <ToggleRow
            checked={privacy.maskContacts}
            description="Shows a number as 0917•••••67 with a Reveal button beside it. This hides the display only; the number is still in the page, so it protects against a glance over your shoulder, not against someone with access to this computer."
            icon={EyeOff}
            id="privacy-mask"
            label="Mask contact numbers until clicked"
            onChange={v => privacyPrefs.set({ maskContacts: v })}
          />
        </RowList>
      </Card>

      <Card
        description="Read straight from your account — nothing here is filled in from anywhere else."
        title="What Ziren holds about your account"
      >
        {!profile ? (
          <Skeleton className="h-40 rounded-[12px]" />
        ) : (
          <RowList>
              <Row icon={UserRound} label="Name"><Value>{profile.full_name}</Value></Row>
              <Row label="Email"><Value>{profile.email}</Value></Row>
              <Row icon={Phone} label="Phone number">
                <Value>{profile.phone_number ?? 'None on file'}</Value>
              </Row>
              <Row label="Role"><Value>{ROLE_LABEL[profile.role] ?? profile.role}</Value></Row>
              <Row label={isProvincialAdmin ? 'Agency type' : 'Agency'}>
                <Value>
                  {profile.agency_name
                    ? `${profile.agency_type ? profile.agency_type + ' — ' : ''}${profile.agency_name}`
                    : (profile.agency_type ?? '—')}
                </Value>
              </Row>
              <Row label="Member since"><Value>{formatDate(profile.created_at, display)}</Value></Row>
            </RowList>
        )}
      </Card>

      <Card
        description="The rows the audit trail keeps under your name: your sign-ins, and the administrative changes you make (stations, accounts, announcements and so on). This page shows them to you; a Provincial Admin can also see them in Audit Logs, which is what an audit trail is for."
        title="Activity recorded about you"
        action={
          <Button onClick={() => setShowActivity(v => !v)} size="sm" variant="outline">
            <History data-icon="inline-start" />
            {showActivity ? 'Hide' : 'Show'} {activity ? `(${activity.length}${activity.length === 100 ? '+' : ''})` : ''}
          </Button>
        }
        flush={showActivity}
      >
        {!showActivity ? (
          <p className="text-[13px] text-muted-foreground">
            {activity === null
              ? 'Loading…'
              : activity.length === 0
                ? 'Nothing recorded yet.'
                : `${activity.length}${activity.length === 100 ? ' or more' : ''} recorded actions. The most recent was ${formatDateTime(activity[0].created_at, display)}.`}
          </p>
        ) : (
          <ul className="max-h-[360px] divide-y divide-[var(--color-surface-border)] overflow-y-auto">
            {(activity ?? []).map(a => (
              <li className="flex flex-wrap items-center justify-between gap-2 px-5 py-2.5" key={a.id}>
                <span className="min-w-0 text-[13px] text-foreground">
                  {describeAction(a.action)}
                  {a.target_label && <span className="text-muted-foreground"> · {a.target_label}</span>}
                </span>
                <span className="font-mono text-[12px] tabular-nums text-muted-foreground">
                  {formatDateTime(a.created_at, display)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card
        description="Access is limited by your role and agency, on the server — hiding a section on this screen never widens or narrows it."
        title="What you can see about residents"
      >
        <ul className="flex flex-col gap-2.5 text-[13px] leading-relaxed text-[var(--color-text-secondary)]">
          <li>
            <span className="font-semibold text-foreground">Scope. </span>
            {isProvincialAdmin
              ? 'You see incidents assigned to agencies of your own type, province-wide, and no other type’s.'
              : 'You see only incidents assigned to your own agency.'}
          </li>
          <li>
            <span className="font-semibold text-foreground">What is shown. </span>
            A reporter’s name, phone number, whether their identity is verified, their emergency
            contact and any history of false SOS reports, alongside the report itself.
          </li>
          <li>
            <span className="font-semibold text-foreground">Recordings. </span>
            A resident’s voice recording is played only inside the record panel, and only to
            someone with access to that incident.
          </li>
        </ul>
      </Card>

      <Card
        description="A copy of the data above, in a file you keep. It is generated on the spot from your live account."
        title="Take your data with you"
      >
        <RowList>
          <Row
            description="Your profile, security details, recorded activity and this browser’s settings, as one JSON file."
            icon={FileJson}
            label="Download my data"
          >
            <Button disabled={exporting} onClick={downloadMyData} size="sm" variant="outline">
              <Download data-icon="inline-start" />
              {exporting ? 'Preparing…' : 'Download'}
            </Button>
          </Row>
        </RowList>
      </Card>

      <Card
        description="Settings that live on this browser: appearance, alerts, map, incident and accessibility choices. They never leave this computer unless you export them."
        title="This browser’s settings"
      >
        <RowList>
          <Row
            description="Save them to a file, to set up another computer the same way."
            icon={Download}
            label="Export settings"
          >
            <Button onClick={saveBackup} size="sm" variant="outline">
              <Download data-icon="inline-start" />
              Export
            </Button>
          </Row>
          <Row
            description="Load a file you exported earlier. It replaces the settings on this browser."
            icon={Upload}
            label="Import settings"
          >
            <Button onClick={() => fileRef.current?.click()} size="sm" variant="outline">
              <Upload data-icon="inline-start" />
              Choose file…
            </Button>
            <input
              accept="application/json,.json"
              aria-label="Choose a settings backup file"
              className="sr-only"
              onChange={e => {
                const f = e.target.files?.[0];
                if (f) void loadBackup(f);
                e.target.value = '';
              }}
              ref={fileRef}
              type="file"
            />
          </Row>
          <Row
            description="Puts every setting on this browser back to how it shipped. Your account and agency settings are not affected."
            icon={RotateCcw}
            label="Reset all settings"
          >
            <Button onClick={resetEverything} size="sm" variant="outline">
              <RotateCcw data-icon="inline-start" />
              Reset
            </Button>
          </Row>
        </RowList>
      </Card>
    </div>
  );
}

function Value({ children }: { children: React.ReactNode }) {
  return <span className="text-[13.5px] font-medium text-foreground">{children}</span>;
}
