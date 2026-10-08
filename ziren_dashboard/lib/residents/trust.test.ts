import { describe, expect, it } from 'vitest';
import { isIdVerified, reportingState } from './trust';

describe('a resident is verified when an administrator approved the ID', () => {
  it('level 2 is verified, whatever is_verified says', () => {
    expect(isIdVerified({ verification_level: 2 })).toBe(true);
    // The reporter of 2026-10-08: approved, never toggled - shown as "Unverified" before.
    expect(isIdVerified({ verification_level: 2, is_verified: false } as never)).toBe(true);
  });

  it('a switched-on account without an approved ID is not verified', () => {
    expect(isIdVerified({ verification_level: 0, is_verified: true } as never)).toBe(false);
    expect(isIdVerified({ verification_level: 1 })).toBe(false); // submitted, waiting
  });

  it('nothing known is not verified', () => {
    expect(isIdVerified(null)).toBe(false);
    expect(isIdVerified({})).toBe(false);
    expect(isIdVerified({ verification_level: null })).toBe(false);
  });
});

describe('an unverified resident reports for their first 7 days', () => {
  const now = new Date('2026-10-08T00:00:00Z');

  it('counts the days left, today included', () => {
    const r = reportingState({ verification_level: 0, reporting_grace_ends_at: '2026-10-10T12:00:00Z' }, now);
    expect(r).toEqual({ kind: 'grace', until: new Date('2026-10-10T12:00:00Z'), daysLeft: 3 });
    const last = reportingState({ verification_level: 0, reporting_grace_ends_at: '2026-10-08T03:00:00Z' }, now);
    expect(last.kind === 'grace' && last.daysLeft).toBe(1);
  });

  it('is paused once the week is over, by the server or by the clock', () => {
    expect(reportingState({ verification_level: 0, reporting_locked: true }, now).kind).toBe('paused');
    expect(reportingState({ verification_level: 0, reporting_grace_ends_at: '2026-10-07T23:59:59Z' }, now).kind).toBe('paused');
    // No deadline from the server: an older backend, which refused every unverified report.
    expect(reportingState({ verification_level: 1 }, now).kind).toBe('paused');
  });

  it('a verified resident is never paused', () => {
    expect(reportingState({ verification_level: 2, reporting_locked: true }, now).kind).toBe('verified');
  });
});
