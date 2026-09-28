/**
 * Client-side form validation for the admin dashboard.
 *
 * Server-side validation is always the authoritative check — these exist to
 * catch mistakes before a round trip, and to say something useful when they do.
 *
 * Two rules govern the messages here:
 *
 *  1. Name the fix, not the failure. "Invalid password" tells an admin they
 *     failed; "Add 1 uppercase letter and 1 number" tells them how to succeed.
 *  2. Stay in step with the API. `password` mirrors
 *     `RegisterRequest.password_strength` in ziren_backend/app/models/user.py.
 *     When the dashboard checked only length, "abcdefgh" passed here and was
 *     rejected by the API, surfacing as a generic banner after submit.
 *
 * The mobile app carries the same rules in
 * ziren_mobile/lib/core/utils/validators.dart. All three must agree.
 */

/** "a", "a and b", "a, b and c" — reads as a sentence, not a list of codes. */
function readableList(items: string[]): string {
  if (items.length === 1) return items[0];
  if (items.length === 2) return `${items[0]} and ${items[1]}`;
  return `${items.slice(0, -1).join(', ')} and ${items[items.length - 1]}`;
}

export function validateEmail(value: string): string | undefined {
  const v = value.trim();
  if (!v) return 'Enter your email address.';
  if (!v.includes('@')) {
    return 'Email addresses need an @ sign, like admin@ziren.ph.';
  }
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) {
    return 'That email does not look right. Example: admin@ziren.ph';
  }
  return undefined;
}

/**
 * Mirrors the server rule. Returns every unmet requirement at once —
 * fixing one rule per submit is what actually wastes an admin's time.
 */
export function validatePassword(value: string): string | undefined {
  if (!value) return 'Enter a password.';

  const missing: string[] = [];
  if (value.length < 8) missing.push('at least 8 characters');
  if (!/[A-Z]/.test(value)) missing.push('1 uppercase letter');
  if (!/[0-9]/.test(value)) missing.push('1 number');

  if (missing.length === 0) return undefined;
  return `Your password still needs ${readableList(missing)}.`;
}

export function validateConfirmPassword(
  password: string,
  confirm: string,
): string | undefined {
  if (!confirm) return 'Re-enter your password to confirm it.';
  if (password !== confirm) {
    return 'These passwords do not match. Check both fields and try again.';
  }
  return undefined;
}

export function validateRequired(
  value: string,
  fieldName: string,
): string | undefined {
  return value.trim() ? undefined : `Enter your ${fieldName.toLowerCase()}.`;
}

/**
 * Turns an API failure into something the admin can act on.
 *
 * FastAPI returns validation detail as an array of objects, a bare string, or
 * nothing at all depending on where the failure happened. The auth pages each
 * unpacked that inline and fell back to "Request failed. Please try again." —
 * which tells the reader nothing about whether to retry, fix a field, or call
 * someone.
 */
export function describeApiError(
  status: number,
  detail: unknown,
): string {
  if (Array.isArray(detail) && detail.length > 0) {
    // Pydantic validation errors: surface the message, not the error type.
    const messages = detail
      .map(d =>
        typeof d === 'object' && d !== null && 'msg' in d
          ? String((d as { msg: unknown }).msg).replace(/^Value error,\s*/, '')
          : String(d),
      )
      .filter(Boolean);
    if (messages.length > 0) return messages.join(' ');
  }

  if (typeof detail === 'string' && detail.trim()) return detail;

  switch (status) {
    case 400:
    case 422:
      return 'Some details were not accepted. Check the fields above and try again.';
    case 401:
      return 'That email and password do not match an account. Check for typos, or use Forgot password.';
    case 403:
      return 'This account does not have access to the dashboard. Contact your Provincial Admin.';
    case 404:
      return 'No account was found for that email address.';
    case 409:
      return 'An account with that email already exists. Try signing in instead.';
    case 429:
      return 'Too many attempts. Wait a minute before trying again.';
    default:
      if (status >= 500) {
        return 'The server had a problem handling that. Wait a moment and try again — if it keeps happening, contact your Provincial Admin.';
      }
      return 'That did not go through. Check your details and try again.';
  }
}
