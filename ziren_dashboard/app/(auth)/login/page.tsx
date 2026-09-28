'use client';

import { Eye, EyeOff, Lock, Mail } from 'lucide-react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { motion } from 'framer-motion';

import { Alert } from '@/components/ui/alert';
import { AuthShell } from '@/components/auth/auth-shell';
import { AuthField, AuthInput } from '@/components/auth/auth-field';
import { describeApiError, validateEmail } from '@/lib/utils/validators';

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail]       = useState('');
  const [password, setPassword] = useState('');
  const [showPass, setShowPass] = useState(false);
  const [remember, setRemember] = useState(false);
  const [error, setError]       = useState('');
  const [loading, setLoading]   = useState(false);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; password?: string }>({});

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setFieldErrors({});

    // Per-field rather than one banner saying "email and password are
    // required" — that message left the reader to work out which of the two
    // was actually the problem.
    const nextFieldErrors: { email?: string; password?: string } = {};
    const emailError = validateEmail(email);
    if (emailError) nextFieldErrors.email = emailError;
    if (!password) nextFieldErrors.password = 'Enter your password.';

    if (Object.keys(nextFieldErrors).length > 0) {
      setFieldErrors(nextFieldErrors);
      return;
    }

    setLoading(true);
    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/login`,
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          body:    JSON.stringify({ email: email.trim(), password }),
        }
      );

      const data = await res.json();

      if (!res.ok) {
        setError(describeApiError(res.status, data.detail));
        return;
      }

      const role = data.user?.role as string | undefined;
      if (role !== 'agency_admin' && role !== 'provincial_admin') {
        setError(
          'Access denied. This portal is for Agency Admins and Provincial Admins only. ' +
          'Residents and Responders should use the Ziren mobile app.'
        );
        return;
      }

      sessionStorage.setItem('access_token',     data.tokens.access_token);
      sessionStorage.setItem('refresh_token',    data.tokens.refresh_token);
      sessionStorage.setItem('user_role',        role);
      sessionStorage.setItem('user_email',       data.user.email);
      sessionStorage.setItem('user_agency_type', data.user?.agency_type ?? '');

      // Where each role starts. An Agency Admin works the live queue; a Provincial
      // Admin has no queue (see nav-config.ts) and starts on the Dashboard.
      router.push(role === 'provincial_admin' ? '/overview' : '/incidents');
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
          Residents and Responders — use the{' '}
          <span className="font-medium text-[var(--color-text-secondary)]">Ziren mobile app</span>{' '}
          to report emergencies.
        </p>
      }
    >
      <h1 className="text-center text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
        Welcome back
      </h1>
      <p className="mt-1 mb-7 text-center text-[14px] text-[var(--color-text-muted)]">
        Sign in to your dispatch portal account
      </p>

      {error && (
        <div className="mb-5">
          <Alert variant="error" message={error} />
        </div>
      )}

      <form onSubmit={handleSubmit} className="flex flex-col gap-4">
        <AuthField label="Email address" error={fieldErrors.email}>
          <AuthInput
            type="email"
            autoComplete="email"
            placeholder="admin@bfp.gov.ph"
            value={email}
            onChange={e => {
              setEmail(e.target.value);
              setError('');
              // Clear this field's error as soon as it is being corrected —
              // keeping it up while the user retypes reads as if the new
              // input is also wrong.
              setFieldErrors(prev => ({ ...prev, email: undefined }));
            }}
            icon={<Mail size={16} strokeWidth={1.8} />}
          />
        </AuthField>

        <AuthField
          label="Password"
          error={fieldErrors.password}
          action={
            <Link
              href="/forgot-password"
              className="text-[12.5px] font-medium text-[var(--color-brand)] transition-opacity hover:opacity-75"
            >
              Forgot password?
            </Link>
          }
        >
          <AuthInput
            type={showPass ? 'text' : 'password'}
            autoComplete="current-password"
            placeholder="Enter your password"
            value={password}
            onChange={e => {
              setPassword(e.target.value);
              setError('');
              setFieldErrors(prev => ({ ...prev, password: undefined }));
            }}
            icon={<Lock size={16} strokeWidth={1.8} />}
            rightElement={
              <button
                type="button"
                onClick={() => setShowPass(v => !v)}
                className="text-[var(--color-text-muted)] transition-colors hover:text-[var(--color-text-secondary)]"
                aria-label={showPass ? 'Hide password' : 'Show password'}
              >
                {showPass ? <EyeOff size={16} strokeWidth={1.8} /> : <Eye size={16} strokeWidth={1.8} />}
              </button>
            }
          />
        </AuthField>

        <label className="flex cursor-pointer select-none items-center gap-2.5 py-1">
          <input
            type="checkbox"
            checked={remember}
            onChange={e => setRemember(e.target.checked)}
            className="h-4 w-4 rounded accent-[var(--color-brand)]"
          />
          <span className="text-[13px] font-medium text-[var(--color-text-secondary)]">
            Keep me signed in
          </span>
        </label>

        <motion.button
          type="submit"
          disabled={loading}
          whileHover={loading ? {} : { scale: 1.01 }}
          whileTap={loading ? {} : { scale: 0.98 }}
          transition={{ duration: 0.12 }}
          className="mt-1 flex h-11 items-center justify-center gap-2 rounded-xl text-[14.5px] font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
          style={{ backgroundColor: loading ? 'var(--color-brand-dim)' : 'var(--color-brand)' }}
        >
          {loading && (
            <svg className="animate-spin" style={{ width: '16px', height: '16px' }} viewBox="0 0 24 24" fill="none">
              <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
              <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
            </svg>
          )}
          {loading ? 'Signing in…' : 'Sign in'}
        </motion.button>
      </form>

      <p className="mt-6 text-center text-[13px] text-[var(--color-text-muted)]">
        Need access?{' '}
        <Link href="/signup" className="font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75">
          Request an account
        </Link>
      </p>
    </AuthShell>
  );
}
