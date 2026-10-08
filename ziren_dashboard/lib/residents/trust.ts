/**
 * What "verified" means for a resident - the dashboard's one definition, the
 * twin of the backend's app/core/resident_trust.py.
 *
 * NOT `is_verified`: on a resident that column is an account-active switch
 * (False at sign-up, flipped by the Provincial Admin's suspend/reactivate), so
 * an approved resident showed as "Unverified" and a reactivated one with no ID
 * as "Verified". An administrator approving the ID writes verification_level 2.
 */

export const VERIFIED_LEVEL = 2;

export function isIdVerified(u: { verification_level?: number | null } | null | undefined): boolean {
  return (u?.verification_level ?? 0) >= VERIFIED_LEVEL;
}

/**
 * Whether an unverified resident may still report (2026-10-08): for their
 * first 7 days, then only once verified. The server computes it
 * (resident_trust.GRACE_DAYS) and sends the deadline; `now` is passed in so a
 * list left open past the deadline still reads right.
 */
export type ReportingState =
  | { kind: 'verified' }
  | { kind: 'grace'; until: Date; daysLeft: number }
  | { kind: 'paused' };

export function reportingState(
  u: {
    verification_level?: number | null;
    reporting_grace_ends_at?: string | null;
    reporting_locked?: boolean | null;
  },
  now: Date = new Date(),
): ReportingState {
  if (isIdVerified(u)) return { kind: 'verified' };
  const ends = u.reporting_grace_ends_at ? new Date(u.reporting_grace_ends_at) : null;
  if (u.reporting_locked || !ends || Number.isNaN(ends.getTime()) || ends <= now) {
    return { kind: 'paused' };
  }
  const daysLeft = Math.max(1, Math.ceil((ends.getTime() - now.getTime()) / 86_400_000));
  return { kind: 'grace', until: ends, daysLeft };
}
