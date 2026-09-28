/**
 * Typed calls for the signed-in user's OWN account: security overview, recorded
 * activity, sessions and support contacts. Every one is scoped to the caller on
 * the server — none takes a user id.
 */

import { apiClient } from './client';

export interface AccountSecurity {
  email: string | null;
  role: string | null;
  /** null when the lookup failed, which is different from false. */
  email_confirmed: boolean | null;
  last_sign_in_at: string | null;
  account_created_at: string | null;
  /** From the audit trail; null for a password set before it was recorded. */
  last_password_change: string | null;
}

export const fetchAccountSecurity = (token: string) =>
  apiClient.get<AccountSecurity>('/users/me/security', token);

export interface ActivityItem {
  id: string;
  /** e.g. auth.login, auth.password_changed, station.created */
  action: string;
  target_type: string | null;
  target_label: string | null;
  metadata: { ip?: string | null; user_agent?: string | null } | null;
  created_at: string;
}

export const fetchMyActivity = (
  token: string,
  opts: { kind?: 'all' | 'auth'; limit?: number } = {},
) => {
  const params = new URLSearchParams();
  if (opts.kind) params.set('kind', opts.kind);
  if (opts.limit) params.set('limit', String(opts.limit));
  const qs = params.toString();
  return apiClient.get<{ items: ActivityItem[] }>(`/users/me/activity${qs ? `?${qs}` : ''}`, token);
};

export const revokeSessions = (token: string, scope: 'others' | 'global') =>
  apiClient.post<{ message: string }>('/users/me/sessions/revoke', { scope }, token);

export const changePassword = (token: string, currentPassword: string, newPassword: string) =>
  apiClient.post<{ message: string }>(
    '/users/me/change-password',
    { current_password: currentPassword, new_password: newPassword },
    token,
  );

export interface SupportContacts {
  provincial_admins: { full_name: string; email: string | null; phone_number: string | null }[];
  agency: {
    name: string;
    agency_type: string;
    municipality: string;
    contact_number: string | null;
    email: string | null;
  } | null;
}

export const fetchSupportContacts = (token: string) =>
  apiClient.get<SupportContacts>('/users/me/support-contacts', token);

/** Plain-English label for an audit action the account owner will see. */
export function describeAction(action: string): string {
  const known: Record<string, string> = {
    'auth.login': 'Signed in',
    'auth.password_changed': 'Password changed',
    'auth.sessions_revoked': 'Signed out other devices',
  };
  if (known[action]) return known[action];
  // station.created -> "Station created"
  const [noun, ...verb] = action.split('.');
  const words = `${noun.replace(/_/g, ' ')} ${verb.join(' ').replace(/_/g, ' ')}`.trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}
