'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import {
  Check, Eye, EyeOff, KeyRound, ShieldAlert, X,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  changePassword, fetchAccountSecurity, revokeSessions, type AccountSecurity,
} from '@/lib/api/account';
import { signOut } from '@/lib/hooks/useAuth';
import { displayPrefs } from '@/lib/prefs/definitions';
import { formatDate, formatTime } from '@/lib/format/datetime';
import { Input } from '@/components/efferd/ui/input';
import { Button } from '@/components/efferd/ui/button';
import { Switch } from '@/components/efferd/ui/switch';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Callout, Card, PanelHeader, Row, RowList, Stat, StatGrid,
} from '@/components/settings/kit';
import { cn } from '@/lib/utils';
import { useNotice } from '@/lib/toast';

/** The rules the server enforces, in the order a person satisfies them. */
const RULES = [
  { key: 'len', label: 'At least 8 characters', test: (p: string) => p.length >= 8 },
  { key: 'upper', label: 'One uppercase letter', test: (p: string) => /[A-Z]/.test(p) },
  { key: 'digit', label: 'One number', test: (p: string) => /\d/.test(p) },
] as const;

/**
 * Beyond the required minimum: things that make a password harder to guess but
 * that the server does not insist on. Shown as strength, not as a rule, so a
 * person is not told they have failed when they have merely met the minimum.
 */
function strength(p: string): { score: 0 | 1 | 2 | 3 | 4; label: string } {
  if (!p) return { score: 0, label: '' };
  const met = RULES.filter(r => r.test(p)).length;
  if (met < RULES.length) return { score: 1, label: 'Too weak' };
  let bonus = 0;
  if (p.length >= 12) bonus += 1;
  if (/[^A-Za-z0-9]/.test(p)) bonus += 1;
  if (p.length >= 16) bonus += 1;
  const score = (2 + Math.min(bonus, 2)) as 2 | 3 | 4;
  return { score, label: score === 2 ? 'Acceptable' : score === 3 ? 'Good' : 'Strong' };
}

export function SecurityPanel({ token }: { token: string }) {
  const display = displayPrefs.use();
  const [overview, setOverview] = useState<AccountSecurity | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    fetchAccountSecurity(token)
      .then(setOverview)
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setFailed(true);
      });
  }, [token]);

  return (
    <div className="flex flex-col gap-6">
      <PanelHeader
        description="Protect the account that can dispatch crews. Check its health, change the password, and see how it is signed in."
        icon={KeyRound}
        scope="account"
        title="Account & Security"
      />

      <Card title="Security check-up">
        {failed ? (
          <Callout title="Could not load your security details" tone="warning">
            The rest of this page still works. Reload to try again.
          </Callout>
        ) : !overview ? (
          <Skeleton className="h-24 rounded-[12px]" />
        ) : (
          <div className="flex flex-col gap-4">
            <StatGrid>
              <Stat
                hint={overview.email ?? undefined}
                label="Email"
                tone={overview.email_confirmed === false ? 'warning' : overview.email_confirmed ? 'success' : undefined}
                value={overview.email_confirmed === null ? '—' : overview.email_confirmed ? 'Verified' : 'Unverified'}
              />
              <Stat
                hint={overview.last_sign_in_at ? `at ${formatTime(overview.last_sign_in_at, display)}` : undefined}
                label="Last sign-in"
                value={overview.last_sign_in_at ? formatDate(overview.last_sign_in_at, display) : '—'}
              />
              <Stat
                hint={overview.last_password_change ? `at ${formatTime(overview.last_password_change, display)}` : 'Not changed since sign-ins were recorded'}
                label="Password changed"
                value={overview.last_password_change ? formatDate(overview.last_password_change, display) : 'Not recorded'}
              />
              <Stat
                label="Account created"
                value={overview.account_created_at ? formatDate(overview.account_created_at, display) : '—'}
              />
            </StatGrid>
            {overview.email_confirmed === false && (
              <Callout title="Your email address is not verified" tone="warning">
                Password-reset links go to this address. Ask a Provincial Admin to confirm it.
              </Callout>
            )}
          </div>
        )}
      </Card>

      <PasswordCard token={token} />

      <Card
        description="A second step at sign-in, such as a code from an authenticator app."
        title="Two-step verification"
      >
        <Callout title="Not offered by this deployment yet" tone="neutral" icon={ShieldAlert}>
          Ziren signs in with an email and password only. Until a second step exists, the
          strongest protections are a long password used nowhere else, signing out of
          shared computers, and ending other devices’ sessions from{' '}
          <span className="font-semibold text-foreground">Login & Devices</span>.
        </Callout>
      </Card>
    </div>
  );
}

// ── Change password ──────────────────────────────────────────────────────

function PasswordCard({ token }: { token: string }) {
  const router = useRouter();
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [show, setShow] = useState(false);
  const [endOthers, setEndOthers] = useState(true);
  const [saving, setSaving] = useState(false);
  const setMsg = useNotice();

  const s = useMemo(() => strength(next), [next]);
  const rulesMet = RULES.every(r => r.test(next));
  const matches = next !== '' && next === confirm;
  const canSubmit = current !== '' && rulesMet && matches && !saving;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!canSubmit) return;
    setSaving(true);
    setMsg(null);
    try {
      await changePassword(token, current, next);
      let text = 'Password changed.';
      if (endOthers) {
        try {
          await revokeSessions(token, 'others');
          text += ' Every other device has been signed out.';
        } catch {
          text += ' It could not sign out your other devices — do that from Login & Devices.';
        }
      }
      setMsg({ tone: 'success', text });
      setCurrent(''); setNext(''); setConfirm('');
    } catch (err) {
      if (err instanceof ApiError && err.status === 401) { signOut(); router.replace('/login'); return; }
      setMsg({ tone: 'danger', text: err instanceof Error ? err.message : 'Could not change the password.' });
    } finally {
      setSaving(false);
    }
  }

  const barColor = ['transparent', 'var(--color-severity-critical)', 'var(--color-system-warning)', 'var(--color-system-success)', 'var(--color-system-success)'][s.score];

  return (
    <Card
      description="You will be asked for your current password. That is deliberate: someone at an unlocked screen should not be able to lock you out of your own account."
      title="Change password"
    >
      <form className="flex flex-col gap-4" onSubmit={submit}>

        <RowList>
          <Row htmlFor="pw-current" label="Current password">
            <Input
              autoComplete="current-password"
              className="max-w-[380px]"
              id="pw-current"
              onChange={e => setCurrent(e.target.value)}
              type={show ? 'text' : 'password'}
              value={current}
            />
          </Row>
          <Row htmlFor="pw-new" label="New password">
            <Input
              autoComplete="new-password"
              className="max-w-[380px]"
              id="pw-new"
              onChange={e => setNext(e.target.value)}
              type={show ? 'text' : 'password'}
              value={next}
            />
          </Row>
          <Row htmlFor="pw-confirm" label="Confirm new password">
            <Input
              aria-invalid={confirm !== '' && !matches}
              autoComplete="new-password"
              className="max-w-[380px]"
              id="pw-confirm"
              onChange={e => setConfirm(e.target.value)}
              type={show ? 'text' : 'password'}
              value={confirm}
            />
            {confirm !== '' && !matches && (
              <span className="mt-1.5 block text-[12px]" style={{ color: 'var(--color-severity-critical)' }}>Doesn’t match yet.</span>
            )}
          </Row>
        </RowList>

        <button
          className="inline-flex w-fit items-center gap-1.5 text-[12.5px] font-semibold text-[var(--color-text-secondary)] hover:text-foreground"
          onClick={() => setShow(v => !v)}
          type="button"
        >
          {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
          {show ? 'Hide passwords' : 'Show passwords'}
        </button>

        {next && (
          <div className="flex flex-col gap-3 rounded-[12px] bg-[var(--color-surface-raised)] px-4 py-3">
            <div className="flex items-center gap-3">
              <div className="flex flex-1 gap-1" aria-hidden="true">
                {[1, 2, 3, 4].map(i => (
                  <span
                    className="h-1.5 flex-1 rounded-full bg-[var(--color-surface-border)]"
                    key={i}
                    style={i <= s.score ? { backgroundColor: barColor } : undefined}
                  />
                ))}
              </div>
              <span className="w-20 text-right text-[12px] font-semibold" style={{ color: barColor === 'transparent' ? undefined : barColor }}>
                {s.label}
              </span>
            </div>
            <ul className="grid gap-1 sm:grid-cols-3">
              {RULES.map(r => {
                const ok = r.test(next);
                return (
                  <li className={cn('flex items-center gap-1.5 text-[12.5px]', ok ? 'text-foreground' : 'text-muted-foreground')} key={r.key}>
                    {ok ? <Check className="size-3.5" style={{ color: 'var(--color-system-success)' }} strokeWidth={3} /> : <X className="size-3.5" />}
                    {r.label}
                  </li>
                );
              })}
            </ul>
            <p className="text-[12px] text-muted-foreground">
              Longer is stronger: 12 or more characters and a symbol move it from Acceptable to Good.
            </p>
          </div>
        )}

        <div className="flex flex-wrap items-center justify-between gap-3">
          <label className="flex items-center gap-2.5 text-[13px] text-foreground" htmlFor="pw-others">
            <Switch checked={endOthers} id="pw-others" onCheckedChange={v => setEndOthers(Boolean(v))} />
            Also sign me out of my other devices
          </label>
          <Button disabled={!canSubmit} type="submit">
            <KeyRound data-icon="inline-start" />
            {saving ? 'Changing…' : 'Change password'}
          </Button>
        </div>
      </form>
    </Card>
  );
}
