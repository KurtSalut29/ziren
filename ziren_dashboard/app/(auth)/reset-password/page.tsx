'use client';

/**
 * Reset password - where the emailed link lands.
 *
 * Supabase puts the recovery token in the URL FRAGMENT, not the query string
 * (`/reset-password#access_token=...&type=recovery`), so it is read in an
 * effect from `window.location.hash` and never reaches a server. It is sent to
 * the backend once, with the new password, and nowhere else.
 *
 * A link that is expired, already used or opened by a mail scanner first comes
 * back as `#error=access_denied&error_code=otp_expired`. That is the most
 * common reason a reset "does not work", so it gets its own message and a
 * button straight back to asking for a new one rather than a blank form that
 * can only fail.
 */

import { ArrowLeft, Check, CheckCircle2, Eye, EyeOff, Lock, LinkIcon, X } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useState } from 'react';
import { motion } from 'framer-motion';

import { Alert } from '@/components/ui/alert';
import { AuthShell } from '@/components/auth/auth-shell';
import { AuthField, AuthInput } from '@/components/auth/auth-field';
import { toast } from '@/lib/toast';

type LinkState = 'checking' | 'ready' | 'expired' | 'missing';

/** The same rule the backend enforces (models/user.py) - one policy everywhere. */
const RULES = [
  { key: 'len',   label: 'At least 8 characters', test: (p: string) => p.length >= 8 },
  { key: 'upper', label: 'One uppercase letter',  test: (p: string) => /[A-Z]/.test(p) },
  { key: 'digit', label: 'One number',            test: (p: string) => /[0-9]/.test(p) },
];

export default function ResetPasswordPage() {
  const router = useRouter();

  const [link, setLink]         = useState<LinkState>('checking');
  const [token, setToken]       = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm]   = useState('');
  const [showPass, setShowPass] = useState(false);
  const [error, setError]       = useState('');
  const [confirmError, setConfirmError] = useState<string | undefined>();
  const [loading, setLoading]   = useState(false);
  const [done, setDone]         = useState(false);

  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1));
    if (params.get('error') || params.get('error_code')) { setLink('expired'); return; }
    const t = params.get('access_token');
    if (!t || params.get('type') !== 'recovery') { setLink('missing'); return; }
    setToken(t);
    setLink('ready');
  }, []);

  const unmet = useMemo(() => RULES.filter(r => !r.test(password)), [password]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setConfirmError(undefined);

    if (unmet.length > 0) { setError(`Your password still needs: ${unmet.map(r => r.label.toLowerCase()).join(', ')}.`); return; }
    if (password !== confirm) { setConfirmError('The two passwords do not match.'); return; }

    setLoading(true);
    try {
      const res = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/reset-password`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ access_token: token, password }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        // 422 carries a list of field errors; anything else a plain string.
        const detail = typeof data.detail === 'string'
          ? data.detail
          : Array.isArray(data.detail) ? data.detail.map((d: { msg?: string }) => d.msg).filter(Boolean).join(' ') : '';
        if (res.status === 400) setLink('expired');
        else setError(detail || 'Could not update your password. Try again.');
        return;
      }
      // The token is spent; do not leave it in the address bar.
      window.history.replaceState(null, '', window.location.pathname);
      setDone(true);
      toast.success('Password updated. You can now sign in.');
    } catch {
      setError('Unable to connect to server. Check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthShell eyebrow="Dispatch Portal">
      {link === 'checking' && (
        <div className="flex justify-center py-10" aria-busy="true">
          <div className="size-6 animate-spin rounded-full border-2 border-[var(--color-surface-border)] border-t-[var(--color-brand)]" />
        </div>
      )}

      {(link === 'expired' || link === 'missing') && (
        <div className="flex flex-col items-center text-center">
          <div
            className="mb-5 flex size-[60px] items-center justify-center rounded-full"
            style={{ backgroundColor: 'var(--color-system-warning-bg)' }}
          >
            <LinkIcon size={28} style={{ color: 'var(--color-system-warning)' }} />
          </div>
          <h1 className="text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            {link === 'expired' ? 'This link has expired' : 'This is not a reset link'}
          </h1>
          <p className="mt-2 max-w-[340px] text-[14px] leading-relaxed text-[var(--color-text-muted)]">
            {link === 'expired'
              ? 'Reset links work once and stop working after a short while. Some mail programs open the link before you do, which uses it up. Request a new one and open it right away.'
              : 'Open the link from the reset email itself. If you copied it, make sure the whole address came with it, including everything after the # sign.'}
          </p>
          <Link
            className="mt-6 flex h-11 w-full items-center justify-center rounded-xl text-[14.5px] font-semibold text-white"
            href="/forgot-password"
            style={{ backgroundColor: 'var(--color-brand)' }}
          >
            Request a new link
          </Link>
        </div>
      )}

      {link === 'ready' && !done && (
        <>
          <h1 className="text-center text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            Choose a new password
          </h1>
          <p className="mt-1 mb-7 text-center text-[14px] text-[var(--color-text-muted)]">
            You will use it the next time you sign in.
          </p>

          {error && <div className="mb-5"><Alert variant="error" message={error} /></div>}

          <form className="flex flex-col gap-4" onSubmit={handleSubmit}>
            <AuthField label="New password">
              <AuthInput
                autoComplete="new-password"
                icon={<Lock size={16} strokeWidth={1.8} />}
                onChange={e => { setPassword(e.target.value); setError(''); }}
                placeholder="Create a new password"
                rightElement={
                  <button
                    aria-label={showPass ? 'Hide password' : 'Show password'}
                    className="text-[var(--color-text-muted)] transition-colors hover:text-[var(--color-text-secondary)]"
                    onClick={() => setShowPass(v => !v)}
                    type="button"
                  >
                    {showPass ? <EyeOff size={16} strokeWidth={1.8} /> : <Eye size={16} strokeWidth={1.8} />}
                  </button>
                }
                type={showPass ? 'text' : 'password'}
                value={password}
              />
            </AuthField>

            {/* The rules, ticking off as they are met - fixing one per submit is
                what wastes time. Icon and text as well as colour. */}
            <ul aria-label="Password requirements" className="-mt-1 flex flex-col gap-1">
              {RULES.map(r => {
                const ok = r.test(password);
                return (
                  <li
                    className="flex items-center gap-2 text-[12.5px]"
                    key={r.key}
                    style={{ color: ok ? 'var(--color-system-success)' : 'var(--color-text-muted)' }}
                  >
                    {ok ? <Check size={13} /> : <X size={13} />}
                    {r.label}
                  </li>
                );
              })}
            </ul>

            <AuthField error={confirmError} label="Confirm new password">
              <AuthInput
                autoComplete="new-password"
                icon={<Lock size={16} strokeWidth={1.8} />}
                onChange={e => { setConfirm(e.target.value); setConfirmError(undefined); setError(''); }}
                placeholder="Type it again"
                type={showPass ? 'text' : 'password'}
                value={confirm}
              />
            </AuthField>

            <motion.button
              className="mt-1 flex h-11 items-center justify-center gap-2 rounded-xl text-[14.5px] font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
              disabled={loading}
              style={{ backgroundColor: loading ? 'var(--color-brand-dim)' : 'var(--color-brand)' }}
              transition={{ duration: 0.12 }}
              type="submit"
              whileHover={loading ? {} : { scale: 1.01 }}
              whileTap={loading ? {} : { scale: 0.98 }}
            >
              {loading ? 'Updating…' : 'Update password'}
            </motion.button>
          </form>
        </>
      )}

      {done && (
        <div className="flex flex-col items-center text-center">
          <div
            className="mb-5 flex size-[60px] items-center justify-center rounded-full"
            style={{ backgroundColor: 'var(--color-system-success-bg)' }}
          >
            <CheckCircle2 size={30} style={{ color: 'var(--color-system-success)' }} />
          </div>
          <h1 className="text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            Password updated
          </h1>
          <p className="mt-2 max-w-[340px] text-[14px] leading-relaxed text-[var(--color-text-muted)]">
            Sign in with your new password.
          </p>
          <button
            className="mt-6 flex h-11 w-full items-center justify-center rounded-xl text-[14.5px] font-semibold text-white"
            onClick={() => router.push('/login')}
            style={{ backgroundColor: 'var(--color-brand)' }}
            type="button"
          >
            Go to sign in
          </button>
        </div>
      )}

      {link === 'ready' && !done && (
        <p className="mt-6 text-center text-[13px] text-[var(--color-text-muted)]">
          <Link
            className="inline-flex items-center gap-1.5 font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75"
            href="/login"
          >
            <ArrowLeft size={13} /> Back to sign in
          </Link>
        </p>
      )}
    </AuthShell>
  );
}
