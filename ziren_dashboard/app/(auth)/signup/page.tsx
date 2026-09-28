'use client';

/**
 * Request Access — replaces the open "Create Account" signup flow.
 *
 * Agency Admin accounts are provisioned, not self-registered. This page
 * records a request in access_requests via POST /auth/access-request; it
 * creates no account and collects no password.
 *
 * A Provincial Admin approves the request through POST /users/provincial/agency-admins,
 * which creates the account and sends a Supabase invite. The applicant sets
 * their own password on /accept-invite.
 *
 * It used to post to /auth/register with role='agency_admin'. Once the
 * privileged-role validator landed, that returned 422 for every applicant:
 * "Self-registration as 'agency_admin' is not permitted." 
 */

import { Building2, CheckCircle, Mail, User } from 'lucide-react';
import Link from 'next/link';

import { describeApiError } from '@/lib/utils/validators';
import { useEffect, useState } from 'react';
import { motion } from 'framer-motion';

import { Alert } from '@/components/ui/alert';
import { AuthShell } from '@/components/auth/auth-shell';
import { AuthField, AuthInput, AuthSelect } from '@/components/auth/auth-field';

interface AgencyOption {
  id: string;
  name: string;
  agency_type: string;
  municipality: string;
}

// ── Confirmation screen ─────────────────────────────────────────────────────
function ConfirmationScreen({ email }: { email: string }) {
  const steps = [
    'Your request is reviewed by a Provincial Admin',
    'Your account is activated once approved',
    'You receive an email to set your password',
    'Sign in and start managing your agency',
  ];

  return (
    <div className="flex flex-col items-center text-center">
      <motion.div
        initial={{ scale: 0.6, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        transition={{ type: 'spring', stiffness: 300, damping: 20 }}
        className="mb-5 flex h-14 w-14 items-center justify-center rounded-full"
        style={{ backgroundColor: 'var(--color-system-success-bg)' }}
      >
        <CheckCircle style={{ width: '28px', height: '28px', color: 'var(--color-system-success)' }} />
      </motion.div>

      <h2 className="text-[20px] font-bold tracking-tight text-[var(--color-text-primary)]">
        Request submitted
      </h2>
      <p className="mt-2 max-w-[320px] text-[14px] leading-relaxed text-[var(--color-text-secondary)]">
        Your access request has been sent for verification.
      </p>
      <p className="mt-1.5 mb-6 max-w-[320px] text-[12.5px] leading-relaxed text-[var(--color-text-muted)]">
        A Provincial Admin will review your request. You&apos;ll receive a confirmation at{' '}
        <span className="font-medium text-[var(--color-text-secondary)]">{email}</span>.
      </p>

      <div
        className="w-full rounded-xl p-4 text-left"
        style={{ backgroundColor: 'var(--color-surface-raised)', border: '1px solid var(--color-surface-border)' }}
      >
        {steps.map((step, i) => (
          <div key={i} className="mb-2.5 flex items-start gap-3 last:mb-0">
            <span
              className="mt-0.5 flex h-[18px] w-[18px] shrink-0 items-center justify-center rounded-full text-[11px] font-bold"
              style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
            >
              {i + 1}
            </span>
            <span className="text-[13px] text-[var(--color-text-secondary)]">{step}</span>
          </div>
        ))}
      </div>

      <Link
        href="/login"
        className="mt-6 text-[13.5px] font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75"
      >
        ← Back to sign in
      </Link>
    </div>
  );
}

// ── Main page ────────────────────────────────────────────────────────────────
export default function RequestAccessPage() {
  const [fullName, setFullName]   = useState('');
  const [position, setPosition]   = useState('');
  const [email, setEmail]         = useState('');
  const [agencyId, setAgencyId]   = useState('');
  const [agencies, setAgencies]   = useState<AgencyOption[]>([]);
  const [error, setError]         = useState('');
  const [loading, setLoading]     = useState(false);
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    fetch(`${process.env.NEXT_PUBLIC_API_BASE_URL}/users/agencies-list/public`)
      .then(r => r.ok ? r.json() : [])
      .then(setAgencies)
      .catch(() => setAgencies([]));
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');

    if (!agencyId) { setError('Select the agency you work for.'); return; }

    setLoading(true);
    try {
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_BASE_URL}/auth/access-request`,
        {
          method:  'POST',
          headers: { 'Content-Type': 'application/json' },
          // No password and no role. This records a request; the account is
          // created by a Provincial Admin via /users/provincial/agency-admins, which
          // sends the invite that lands on /accept-invite. Posting to
          // /auth/register with role='agency_admin' is what produced
          // "Self-registration as 'agency_admin' is not permitted."
          body:    JSON.stringify({
            full_name: fullName.trim(),
            email:     email.trim(),
            position:  position.trim() || null,
            agency_id: agencyId,
          }),
        }
      );

      const data = await res.json();

      if (!res.ok) {
        setError(describeApiError(res.status, data.detail));
        return;
      }

      setSubmitted(true);
    } catch {
      setError('Unable to connect to server. Check your connection and try again.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <AuthShell eyebrow="Request Access" maxWidth={460}>
      {submitted ? (
        <ConfirmationScreen email={email} />
      ) : (
        <>
          <h1 className="text-center text-[22px] font-bold tracking-tight text-[var(--color-text-primary)]">
            Request access
          </h1>
          <p className="mt-1 mb-6 text-center text-[14px] text-[var(--color-text-muted)]">
            A Provincial Admin will verify and activate your account.
          </p>

          {error && (
            <div className="mb-5">
              <Alert variant="error" message={error} />
            </div>
          )}

          <form onSubmit={handleSubmit} className="flex flex-col gap-4">
            <div className="grid grid-cols-2 gap-3">
              <AuthField label="Full name" required>
                <AuthInput
                  type="text"
                  autoComplete="name"
                  placeholder="Juan dela Cruz"
                  value={fullName}
                  onChange={e => { setFullName(e.target.value); setError(''); }}
                  required
                  icon={<User size={16} strokeWidth={1.8} />}
                />
              </AuthField>

              <AuthField label="Position / rank">
                <AuthInput
                  type="text"
                  placeholder="e.g. Fire Officer I"
                  value={position}
                  onChange={e => { setPosition(e.target.value); setError(''); }}
                  icon={<User size={16} strokeWidth={1.8} />}
                />
              </AuthField>
            </div>

            <AuthField label="Agency" required>
              <AuthSelect
                value={agencyId}
                onChange={e => { setAgencyId(e.target.value); setError(''); }}
                required
                icon={<Building2 size={16} strokeWidth={1.8} />}
              >
                <option value="">Select your agency…</option>
                {agencies.map(a => (
                  <option key={a.id} value={a.id}>
                    {a.agency_type} — {a.name} ({a.municipality})
                  </option>
                ))}
              </AuthSelect>
            </AuthField>

            <AuthField
              label="Official email address"
              required
              hint="Use your official government email address where possible."
            >
              <AuthInput
                type="email"
                autoComplete="email"
                placeholder="juandelacruz@bfp.gov.ph"
                value={email}
                onChange={e => { setEmail(e.target.value); setError(''); }}
                required
                icon={<Mail size={16} strokeWidth={1.8} />}
              />
            </AuthField>


            <motion.button
              type="submit"
              disabled={loading}
              whileHover={loading ? {} : { scale: 1.01 }}
              whileTap={loading ? {} : { scale: 0.98 }}
              transition={{ duration: 0.12 }}
              className="mt-1 flex h-11 items-center justify-center gap-2 rounded-xl text-[14.5px] font-semibold text-white disabled:cursor-not-allowed disabled:opacity-60"
              style={{ backgroundColor: 'var(--color-brand)' }}
            >
              {loading && (
                <svg className="animate-spin" style={{ width: '16px', height: '16px' }} viewBox="0 0 24 24" fill="none">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                </svg>
              )}
              {loading ? 'Submitting request…' : 'Submit access request'}
            </motion.button>
          </form>

          <p className="mt-5 text-center text-[13px] text-[var(--color-text-muted)]">
            Already have an account?{' '}
            <Link href="/login" className="font-semibold text-[var(--color-brand)] transition-opacity hover:opacity-75">
              Sign in
            </Link>
          </p>
        </>
      )}
    </AuthShell>
  );
}
