'use client';

import { useEffect, useMemo, useState } from 'react';
import { Building2, CalendarDays, Copy, Fingerprint, Landmark, Mail, Phone, User } from 'lucide-react';
import { ApiError, apiClient } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDate } from '@/lib/format/datetime';
import { Input } from '@/components/efferd/ui/input';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, SaveBar, StatusDot,
} from '@/components/settings/kit';
import { useNotice } from '@/lib/toast';

interface MyProfile {
  id: string;
  full_name: string;
  email: string;
  phone_number: string | null;
  role: string;
  is_verified: boolean;
  created_at: string;
  agency_type: string | null;
  agency_name: string | null;
  agency_municipality: string | null;
  agency_contact_number: string | null;
  avatar_url: string | null;
}

const ROLE_LABEL: Record<string, string> = {
  agency_admin: 'Agency Admin',
  provincial_admin: 'Provincial Admin',
};

const AGENCY_COLOR: Record<string, string> = {
  BFP: 'var(--color-agency-bfp)',
  PNP: 'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

/**
 * A Philippine mobile number in any of the forms people actually write:
 * 09171234567, 0917 123 4567, +63 917 123 4567, 0917-123-4567. Landlines and
 * anything else are accepted as long as they are plausible digits, because an
 * agency office line is a legitimate contact for an admin.
 */
function phoneProblem(raw: string): string | null {
  const v = raw.trim();
  if (v === '') return null; // clearing the number is allowed
  const digits = v.replace(/[\s\-().]/g, '');
  if (!/^\+?\d{7,15}$/.test(digits)) return 'Use digits only, for example 0917 123 4567 or +63 917 123 4567.';
  return null;
}

export function ProfilePanel({ token }: { token: string }) {
  const display = displayPrefs.use();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [form, setForm] = useState({ full_name: '', phone_number: '' });
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const setNotice = useNotice();
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    apiClient.get<MyProfile>('/users/me', token)
      .then(p => { setProfile(p); setForm({ full_name: p.full_name, phone_number: p.phone_number ?? '' }); })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setLoadError(e instanceof Error ? e.message : 'Failed to load your profile.');
      });
  }, [token]);

  const dirty = !!profile && (
    form.full_name.trim() !== profile.full_name ||
    form.phone_number.trim() !== (profile.phone_number ?? '')
  );
  const nameProblem = form.full_name.trim() === '' ? 'Your name cannot be empty.' : null;
  const phoneErr = useMemo(() => phoneProblem(form.phone_number), [form.phone_number]);
  const valid = !nameProblem && !phoneErr;

  async function save() {
    if (!profile || !valid) return;
    setSaving(true);
    setNotice(null);
    try {
      const updated = await apiClient.patch<MyProfile>(
        '/users/me',
        { full_name: form.full_name.trim(), phone_number: form.phone_number.trim() || null },
        token,
      );
      setProfile({ ...profile, ...updated });
      setForm({ full_name: updated.full_name, phone_number: updated.phone_number ?? '' });
      setNotice({ tone: 'success', text: 'Your profile was updated.' });
    } catch (e) {
      setNotice({ tone: 'danger', text: e instanceof Error ? e.message : 'Could not save your profile.' });
    } finally {
      setSaving(false);
    }
  }

  function discard() {
    if (!profile) return;
    setForm({ full_name: profile.full_name, phone_number: profile.phone_number ?? '' });
    setNotice(null);
  }

  async function copyId() {
    if (!profile) return;
    try {
      await navigator.clipboard.writeText(profile.id);
      setCopied(true);
      setTimeout(() => setCopied(false), 1800);
    } catch { /* clipboard blocked */ }
  }

  if (loadError) {
    return (
      <div className="flex flex-col gap-6">
        <PanelHeader icon={User} scope="account" title="Profile" />
        <Callout title="Could not load your profile" tone="danger">{loadError}</Callout>
      </div>
    );
  }

  const initials = (profile?.full_name ?? '?')
    .split(/[\s._-]+/).filter(Boolean).slice(0, 2).map(p => p[0]?.toUpperCase()).join('') || '?';
  const agencyColor = profile?.agency_type ? AGENCY_COLOR[profile.agency_type] : undefined;

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Who you are to the people you work with. Your name and number are what other administrators see when they need to reach you."
        icon={User}
        scope="account"
        title="Profile"
      />

      {!profile ? (
        <>
          <Skeleton className="h-28 rounded-[var(--radius-card)]" />
          <Skeleton className="h-64 rounded-[var(--radius-card)]" />
        </>
      ) : (
        <>
          {/* Identity — who the console thinks is signed in, at a glance.
              TailAdmin's Profile page banner, adapted: this product has no
              per-user cover photo, so the band is the agency's own locked
              hue (or brand, for a Provincial Admin) — reinforcing identity
              instead of standing in for a photo nobody uploaded. */}
          <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
            <div
              aria-hidden="true"
              className="h-20 w-full sm:h-24"
              style={{
                background: `linear-gradient(135deg, ${agencyColor ?? 'var(--color-brand)'}, color-mix(in srgb, ${agencyColor ?? 'var(--color-brand)'} 55%, black))`,
              }}
            />
            <div className="flex flex-wrap items-end gap-5 px-5 pb-5 sm:items-center">
              <span className="-mt-10 shrink-0 rounded-full ring-4 ring-[var(--color-surface-card)] sm:-mt-12">
                {profile.avatar_url ? (
                  // The signed URL is minted fresh by the server on every fetch.
                  // eslint-disable-next-line @next/next/no-img-element
                  <img alt="" className="size-20 rounded-full object-cover sm:size-24" src={profile.avatar_url} />
                ) : (
                  <span
                    aria-hidden="true"
                    className="flex size-20 items-center justify-center rounded-full text-[24px] font-bold text-white sm:size-24 sm:text-[28px]"
                    style={{ backgroundColor: agencyColor ?? 'var(--color-brand)' }}
                  >
                    {initials}
                  </span>
                )}
              </span>
              <div className="min-w-0 flex-1 pt-1">
                <p className="truncate text-[18px] font-bold leading-tight text-foreground">{profile.full_name}</p>
                <p className="mt-0.5 truncate text-[13px] text-muted-foreground">{profile.email}</p>
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <span
                    className="rounded-full px-2.5 py-0.5 text-[11.5px] font-bold"
                    style={{
                      color: agencyColor ?? 'var(--color-text-secondary)',
                      backgroundColor: `color-mix(in srgb, ${agencyColor ?? 'var(--color-text-muted)'} 12%, transparent)`,
                    }}
                  >
                    {profile.agency_type ? `${profile.agency_type} · ` : ''}{ROLE_LABEL[profile.role] ?? profile.role}
                  </span>
                  <StatusDot tone={profile.is_verified ? 'success' : 'warning'}>
                    {profile.is_verified ? 'Verified account' : 'Not yet verified'}
                  </StatusDot>
                </div>
              </div>
            </div>
          </div>


          <Card description="These two fields are yours to change." title="Your details">
            <RowList>
              <Row htmlFor="profile-name" label="Full name">
                <Input
                  aria-invalid={!!nameProblem}
                  className="max-w-[380px]"
                  id="profile-name"
                  onChange={e => { setForm(f => ({ ...f, full_name: e.target.value })); setNotice(null); }}
                  value={form.full_name}
                />
                {nameProblem && <span className="mt-1.5 block text-[12px]" style={{ color: 'var(--color-severity-critical)' }}>{nameProblem}</span>}
              </Row>
              <Row htmlFor="profile-phone" label="Phone number">
                <Input
                  aria-invalid={!!phoneErr}
                  className="max-w-[380px]"
                  id="profile-phone"
                  inputMode="tel"
                  onChange={e => { setForm(f => ({ ...f, phone_number: e.target.value })); setNotice(null); }}
                  placeholder="0917 123 4567"
                  value={form.phone_number}
                />
                {phoneErr && <span className="mt-1.5 block text-[12px]" style={{ color: 'var(--color-severity-critical)' }}>{phoneErr}</span>}
              </Row>
              <Row
                description="Your email is your sign-in and where password-reset links go, so it can only be changed by a Provincial Admin."
                htmlFor="profile-email"
                label="Email"
              >
                <Input className="max-w-[380px]" disabled id="profile-email" value={profile.email} />
              </Row>
            </RowList>
          </Card>

          <Card description="Set by your agency and Provincial Admin — shown here so you can confirm they are right." flush title="Your account">
            <RowList>
              <Row icon={Landmark} label="Role">
                <span className="text-[13.5px] font-medium text-foreground">{ROLE_LABEL[profile.role] ?? profile.role}</span>
              </Row>
              <Row icon={Building2} label={profile.role === 'provincial_admin' ? 'Agency type' : 'Agency'}>
                <span className="text-[13.5px] font-medium text-foreground">
                  {profile.agency_name
                    ? `${profile.agency_type ? profile.agency_type + ' — ' : ''}${profile.agency_name}`
                    : (profile.agency_type ?? 'Not assigned')}
                </span>
              </Row>
              {profile.agency_municipality && (
                <Row label="Municipality">
                  <span className="text-[13.5px] font-medium text-foreground">{profile.agency_municipality}</span>
                </Row>
              )}
              {profile.agency_contact_number && (
                <Row icon={Phone} label="Agency phone">
                  <span className="text-[13.5px] font-medium text-foreground">{profile.agency_contact_number}</span>
                </Row>
              )}
              <Row icon={Mail} label="Sign-in email">
                <span className="text-[13.5px] font-medium text-foreground">{profile.email}</span>
              </Row>
              <Row icon={CalendarDays} label="Member since">
                <span className="text-[13.5px] font-medium text-foreground">{formatDate(profile.created_at, display)}</span>
              </Row>
              <Row
                description="Quote this if you ever need to ask for help with your account."
                icon={Fingerprint}
                label="Account ID"
              >
                <span className="flex items-center gap-2">
                  <code className="rounded-md bg-[var(--color-surface-raised)] px-2 py-1 font-mono text-[12px] text-foreground">
                    {profile.id}
                  </code>
                  <Button onClick={copyId} size="sm" variant="outline">
                    <Copy data-icon="inline-start" />
                    {copied ? 'Copied' : 'Copy'}
                  </Button>
                </span>
              </Row>
            </RowList>
          </Card>

          <SaveBar
            dirty={dirty && valid}
            onDiscard={discard}
            onSave={save}
            saving={saving}
          />
        </>
      )}
    </div>
  );
}
