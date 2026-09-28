'use client';

/**
 * Forgot password - ask for the reset email.
 *
 * The login page has always linked here, and there was no page: the link was a
 * 404, so the only way anyone ever got a reset email was from somewhere else
 * (the mobile app's own form) - and that email then pointed at a dashboard
 * page that did not exist either.
 *
 * The backend answers the same whether or not the address has an account, so
 * this page does too: it never says "no such user".
 */

import { ArrowLeft, CheckCircle2, Mail } from 'lucide-react';
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';

import { Alert } from '@/components/ui/alert';
import { AuthShell } from '@/components/auth/auth-shell';
import { AuthField, AuthInput } from '@/components/auth/auth-field';
import { validateEmail } from '@/lib/utils/validators';

/** The backend allows five requests a minute; a resend button that always fails is worse than a wait. */
const RESEND_AFTER_S = 45;

export default function ForgotPasswordPage() {
  const [email, setEmail]     = useState('');
  const [fieldError, setFieldError] = useState<string | undefined>();
  const [error, setError]     = useState('');
  const [loading, setLoading] = useState(false);
  const [sentTo, setSentTo]   = useState<string | null>(null);
  const [wait, setWait]       = useState(0);

  useEffect(() => {
    if (wait <= 0) return;
    const id = setTimeout(() => setWait(w => w - 1), 1000);
    return () => clearTimeout(id);
  }, [wait]);

  async function send(e?: React.FormEvent) {
    e?.preventDefault();
    setError('');
    const problem = validateEmail(email);
    if (problem) { setFieldError(problem); return; }
    setFieldError(undefined);

    setLoading(true);
    try {
      const res = await fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/password-reset`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ email: email.trim() }),
      });
      if (res.status === 429) {
        setError('Too many requests. Wait a minute and try again.');
        return;
      }
      if (!res.ok) {
        setError('Could not send the email right now. Try again in a moment.');
        return;
      }
      setSentTo(email.trim());
      setWait(RESEND_AFTER_S);
    } catch {
      setError('Unable to connect to server. Check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthShell
      eyebrow="Dispatch Portal"
      footer={
        <p className="text-center text-[13px] text-[var(--color-text-muted)]">
          The link works once and expires, so open it as soon as it arrives.
        </p>
      }
    >
      {sentTo ? (
        <div className="flex flex-col items-center text-center">
          <div
            className="mb-5 flex size-[60px] items-center justify-center rounded-full"
            style={{ backgroundColor: 'var(--color-system-success-bg)' }}
          >
            <CheckCircle2 size={30} style={{ color: 'var(--color-system-success)' }} />
          </div>
          <h1 className="text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            Check your email
          </h1>
          <p className="mt-2 max-w-[340px] text-[14px] leading-relaxed text-[var(--color-text-muted)]">
            If an account exists for{' '}
            <span className="font-medium text-[var(--color-text-secondary)]">{sentTo}</span>,
            a reset link is on its way. It can take a minute, and it may land in spam.
          </p>

          {error && <div className="mt-5 w-full"><Alert variant="error" message={error} /></div>}

          <button
            className="mt-6 text-[13px] font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75 disabled:cursor-not-allowed disabled:opacity-50"
            disabled={wait > 0 || loading}
            onClick={() => send()}
            type="button"
          >
            {wait > 0 ? `Send it again in ${wait}s` : loading ? 'Sending…' : 'Send it again'}
          </button>
          <button
            className="mt-2 text-[13px] text-[var(--color-text-muted)] transition-colors hover:text-[var(--color-text-secondary)]"
            onClick={() => { setSentTo(null); setWait(0); }}
            type="button"
          >
            Use a different email
          </button>
        </div>
      ) : (
        <>
          <h1 className="text-center text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            Reset your password
          </h1>
          <p className="mt-1 mb-7 text-center text-[14px] text-[var(--color-text-muted)]">
            Enter the email you sign in with and we will send you a link.
          </p>

          {error && <div className="mb-5"><Alert variant="error" message={error} /></div>}

          <form className="flex flex-col gap-4" onSubmit={send}>
            <AuthField error={fieldError} label="Email address">
              <AuthInput
                autoComplete="email"
                icon={<Mail size={16} strokeWidth={1.8} />}
                onChange={e => { setEmail(e.target.value); setError(''); setFieldError(undefined); }}
                placeholder="admin@bfp.gov.ph"
                type="email"
                value={email}
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
              {loading ? 'Sending…' : 'Send reset link'}
            </motion.button>
          </form>
        </>
      )}

      <p className="mt-6 text-center text-[13px] text-[var(--color-text-muted)]">
        <Link
          className="inline-flex items-center gap-1.5 font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75"
          href="/login"
        >
          <ArrowLeft size={13} /> Back to sign in
        </Link>
      </p>
    </AuthShell>
  );
}
