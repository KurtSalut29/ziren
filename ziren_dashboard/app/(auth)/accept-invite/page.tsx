'use client';

import { CheckCircle, Eye, EyeOff, Lock, Siren } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { Suspense, useEffect, useState } from 'react';

import { ZirenLogoOnDark } from '@/components/brand/ziren-logo';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';

function AcceptInviteForm() {
  const router = useRouter();

  const [accessToken, setAccessToken]   = useState('');
  const [password, setPassword]         = useState('');
  const [confirm, setConfirm]           = useState('');
  const [showPass, setShowPass]         = useState(false);
  const [error, setError]               = useState('');
  const [loading, setLoading]           = useState(false);
  const [tokenMissing, setTokenMissing] = useState(false);
  const [done, setDone]                 = useState(false);

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1));
    const token  = params.get('access_token');
    const type   = params.get('type');
    if (!token || type !== 'invite') {
      setTokenMissing(true);
      return;
    }
    setAccessToken(token);
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');

    if (password.length < 8) { setError('Password must be at least 8 characters.'); return; }
    if (password !== confirm)  { setError('Passwords do not match.'); return; }

    setLoading(true);
    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/accept-invite`,
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ access_token: accessToken, password }),
        }
      );

      const data = await res.json();

      if (!res.ok) {
        setError(data.detail ?? 'Failed to set password. The invite link may have expired.');
        return;
      }

      sessionStorage.setItem('access_token',     data.tokens.access_token);
      sessionStorage.setItem('refresh_token',    data.tokens.refresh_token);
      sessionStorage.setItem('user_role',        data.user.role);
      sessionStorage.setItem('user_email',       data.user.email);
      sessionStorage.setItem('user_agency_type', data.user?.agency_type ?? '');

      setDone(true);
      const home = data.user.role === 'provincial_admin' ? '/overview' : '/incidents';
      setTimeout(() => router.push(home), 1800);
    } catch {
      setError('Unable to connect to server. Check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="flex min-h-screen bg-[var(--color-surface-base)]">

      {/* ── Brand panel ─────────────────────────────── */}
      <div
        className="hidden lg:flex flex-col justify-between p-12 shrink-0 relative overflow-hidden"
        style={{ width: '480px', backgroundColor: 'var(--color-brand)' }}
      >
        <div
          aria-hidden="true"
          className="absolute inset-0 pointer-events-none"
          style={{
            backgroundImage:
              'radial-gradient(circle at 20% 20%, rgba(255,255,255,0.08) 0%, transparent 60%),' +
              'radial-gradient(circle at 80% 80%, rgba(0,0,0,0.12) 0%, transparent 50%)',
          }}
        />
        <div className="relative flex items-center gap-3">
          <div
            className="flex items-center justify-center rounded-[var(--radius-lg)] overflow-hidden"
            style={{ width: '40px', height: '40px', backgroundColor: 'rgba(255,255,255,0.2)' }}
          >
            {/* Explicitly the on-dark artwork: this hero panel is a dark
                brand gradient in BOTH themes, so following the page theme
                here would put a near-black mark on it half the time. */}
            <ZirenLogoOnDark size={40} />
          </div>
          <span className="text-[22px] font-bold text-white tracking-tight">Ziren</span>
        </div>

        <div className="relative">
          <p className="text-[38px] font-extrabold leading-tight text-white mb-4 tracking-tight">
            Activate your<br />account.
          </p>
          <p className="text-[16px] leading-relaxed max-w-[320px]" style={{ color: 'rgba(255,255,255,0.72)' }}>
            Set a secure password to complete your Agency Admin account setup.
          </p>
        </div>

        <div className="relative flex items-center gap-3">
          <div className="h-px flex-1" style={{ backgroundColor: 'rgba(255,255,255,0.2)' }} />
          <p className="text-[11px] font-semibold uppercase tracking-widest" style={{ color: 'rgba(255,255,255,0.5)' }}>
            Dispatch Portal
          </p>
          <div className="h-px flex-1" style={{ backgroundColor: 'rgba(255,255,255,0.2)' }} />
        </div>
      </div>

      {/* ── Form panel ──────────────────────────────── */}
      <div className="flex flex-1 flex-col items-center justify-center px-6 py-12">
        <div className="w-full" style={{ maxWidth: '400px' }}>

          {/* Mobile wordmark */}
          <div className="flex items-center gap-3 mb-8 lg:hidden">
            <div
              className="flex items-center justify-center rounded-[var(--radius-lg)]"
              style={{ width: '40px', height: '40px', backgroundColor: 'var(--color-brand)' }}
            >
              <Siren className="h-5 w-5 text-white" />
            </div>
            <span className="text-[22px] font-bold tracking-tight" style={{ color: 'var(--color-brand)' }}>
              Ziren
            </span>
          </div>

          {done ? (
            /* Success state */
            <div className="flex flex-col items-center text-center">
              <div
                className="flex items-center justify-center rounded-full mb-5"
                style={{ width: '60px', height: '60px', backgroundColor: 'var(--color-system-success-bg)' }}
              >
                <CheckCircle style={{ width: '30px', height: '30px', color: 'var(--color-system-success)' }} />
              </div>
              <h2 className="text-[24px] font-extrabold tracking-tight mb-2" style={{ color: 'var(--color-text-primary)' }}>
                Account activated!
              </h2>
              <p className="text-[14px]" style={{ color: 'var(--color-text-muted)' }}>
                Redirecting you to the dashboard…
              </p>
            </div>

          ) : tokenMissing ? (
            /* Invalid link */
            <>
              <h1 className="text-[24px] font-extrabold tracking-tight mb-2" style={{ color: 'var(--color-text-primary)' }}>
                Invalid invite link
              </h1>
              <p className="text-[14px] mb-6" style={{ color: 'var(--color-text-secondary)' }}>
                This link is invalid or has already been used. Contact your Provincial Admin for a new invite.
              </p>
              <Button variant="outline" size="md" onClick={() => router.push('/login')}>
                Back to sign in
              </Button>
            </>

          ) : (
            /* Set password form */
            <>
              <h1 className="text-[28px] font-extrabold tracking-tight leading-tight mb-1.5" style={{ color: 'var(--color-text-primary)' }}>
                Set your password
              </h1>
              <p className="text-[14px] mb-7" style={{ color: 'var(--color-text-muted)' }}>
                Choose a password to activate your Agency Admin account.
              </p>

              {error && (
                <div className="mb-5">
                  <Alert variant="error" message={error} />
                </div>
              )}

              <form onSubmit={handleSubmit} className="flex flex-col gap-4">
                <Input
                  label="New password"
                  type={showPass ? 'text' : 'password'}
                  autoComplete="new-password"
                  placeholder="At least 8 characters"
                  value={password}
                  onChange={(e) => { setPassword(e.target.value); setError(''); }}
                  leftIcon={<Lock className="h-4 w-4" />}
                  rightElement={
                    <button
                      type="button"
                      onClick={() => setShowPass(v => !v)}
                      className="transition-colors"
                      style={{ color: 'var(--color-text-muted)' }}
                      aria-label={showPass ? 'Hide password' : 'Show password'}
                    >
                      {showPass ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </button>
                  }
                  required
                />

                <Input
                  label="Confirm password"
                  type={showPass ? 'text' : 'password'}
                  autoComplete="new-password"
                  placeholder="Repeat your password"
                  value={confirm}
                  onChange={(e) => { setConfirm(e.target.value); setError(''); }}
                  leftIcon={<Lock className="h-4 w-4" />}
                  required
                />

                <div className="mt-2">
                  <Button type="submit" variant="primary" size="lg" isLoading={loading}>
                    <CheckCircle className="mr-1.5 h-4 w-4" data-icon="inline-start" />
                    Activate account
                  </Button>
                </div>
              </form>
            </>
          )}
        </div>
      </div>
    </main>
  );
}

export default function AcceptInvitePage() {
  return (
    <Suspense>
      <AcceptInviteForm />
    </Suspense>
  );
}
