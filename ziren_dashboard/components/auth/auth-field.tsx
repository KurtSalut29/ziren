/**
 * AuthField / AuthInput / AuthSelect — shared form primitives for the auth
 * pages (login, request-access). Tailwind focus-within states instead of JS
 * onFocus/onBlur handlers — smaller, and the ring reads as one continuous
 * transition rather than a hard swap.
 *
 * AuthField previously had no error prop, so a rejected field could not say
 * anything about itself and every message had to go in the page-level banner.
 * That produced errors like "Email and password are required" and left the
 * reader to work out which field was actually at fault. Errors now attach to
 * the field that caused them.
 *
 * The field id, error id and aria wiring travel through context so callers do
 * not have to thread them by hand — the accessible version is the default,
 * rather than something each page remembers to add.
 */

import {
  createContext,
  forwardRef,
  useContext,
  useId,
  type InputHTMLAttributes,
  type ReactNode,
} from 'react';
import { AlertCircle } from 'lucide-react';

interface FieldContext {
  id: string;
  errorId: string;
  hintId: string;
  hasError: boolean;
  hasHint: boolean;
}

const FieldCtx = createContext<FieldContext | null>(null);

export function AuthField({
  label,
  required,
  hint,
  error,
  action,
  children,
}: {
  label: string;
  required?: boolean;
  hint?: string;
  error?: string;
  /**
   * Trailing control on the label row — "Forgot password?" and similar.
   * Without this the password field had to be hand-built outside AuthField
   * to fit the link in, which is how it ended up with no error handling.
   */
  action?: ReactNode;
  children: ReactNode;
}) {
  const id = useId();
  const ctx: FieldContext = {
    id,
    errorId: `${id}-error`,
    hintId: `${id}-hint`,
    hasError: Boolean(error),
    hasHint: Boolean(hint),
  };

  return (
    <FieldCtx.Provider value={ctx}>
      {/* `group` drives the focus-within styling on the label below. */}
      <div className="group flex flex-col gap-1.5">
        <div className="flex items-center justify-between gap-3">
          <label
            htmlFor={id}
            className={[
              'flex items-center gap-1.5 text-[13px] font-medium transition-colors',
              // The label tracks focus and error, so the active field is marked
              // by weight and position too — not by ring colour alone.
              error
                ? 'text-[var(--color-system-error)]'
                : 'text-[var(--color-text-secondary)] group-focus-within:text-[var(--color-brand)]',
            ].join(' ')}
          >
            <span
              aria-hidden="true"
              className={[
                'h-3 rounded-sm transition-[width,background-color] duration-150',
                error
                  ? 'w-[3px] bg-[var(--color-system-error)]'
                  : 'w-0 bg-[var(--color-brand)] group-focus-within:w-[3px]',
              ].join(' ')}
            />
            {label}
            {required && (
              <span className="text-[var(--color-severity-critical)]">*</span>
            )}
          </label>
          {action}
        </div>

        {children}

        {error && (
          // role="alert" announces the message when it appears, without
          // pulling focus away from the field being corrected.
          <p
            id={ctx.errorId}
            role="alert"
            className="flex items-start gap-1.5 text-[12px] font-medium leading-[1.45] text-[var(--color-system-error)]"
          >
            {/* Icon as well as colour — the message must not depend on red
                being distinguishable. */}
            <AlertCircle aria-hidden="true" className="mt-[2px] h-3 w-3 shrink-0" />
            {error}
          </p>
        )}
        {hint && !error && (
          <p id={ctx.hintId} className="text-[11.5px] text-[var(--color-text-muted)]">
            {hint}
          </p>
        )}
      </div>
    </FieldCtx.Provider>
  );
}

/** Shared aria + id wiring for the controls below. */
function useFieldAria() {
  const ctx = useContext(FieldCtx);
  if (!ctx) return {};
  return {
    id: ctx.id,
    'aria-invalid': ctx.hasError || undefined,
    'aria-describedby': ctx.hasError
      ? ctx.errorId
      : ctx.hasHint
        ? ctx.hintId
        : undefined,
  } as const;
}

function controlClasses(hasError: boolean, icon: boolean, right: boolean, extra: string) {
  return [
    'h-11 w-full rounded-xl border text-[14px] outline-none transition-[border-color,box-shadow,background-color] duration-150',
    'bg-[var(--color-surface-base)] text-[var(--color-text-primary)]',
    'placeholder:text-[var(--color-text-muted)]',
    hasError
      ? // An invalid field keeps its red ring even while focused, so the
        // error does not appear to clear the moment it is clicked into.
        'border-[var(--color-system-error)] focus:border-[var(--color-system-error)] focus:bg-[var(--color-surface-card)] focus:shadow-[0_0_0_3.5px_var(--color-system-error-bg)]'
      : 'border-[var(--color-surface-border)] focus:border-[var(--color-brand)] focus:bg-[var(--color-surface-card)] focus:shadow-[0_0_0_3.5px_var(--color-brand-container)]',
    icon ? 'pl-10' : 'pl-3.5',
    right ? 'pr-10' : 'pr-3.5',
    extra,
  ].join(' ');
}

interface AuthInputProps extends InputHTMLAttributes<HTMLInputElement> {
  icon?: ReactNode;
  rightElement?: ReactNode;
}

export const AuthInput = forwardRef<HTMLInputElement, AuthInputProps>(
  ({ icon, rightElement, className = '', ...props }, ref) => {
    const ctx = useContext(FieldCtx);
    const aria = useFieldAria();
    const hasError = ctx?.hasError ?? false;

    return (
      <div className="group relative">
        {icon && (
          <span
            className={[
              'pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 transition-colors',
              hasError
                ? 'text-[var(--color-system-error)]'
                : 'text-[var(--color-text-muted)] group-focus-within:text-[var(--color-brand)]',
            ].join(' ')}
          >
            {icon}
          </span>
        )}
        <input
          ref={ref}
          {...aria}
          className={controlClasses(hasError, Boolean(icon), Boolean(rightElement), className)}
          {...props}
        />
        {rightElement && (
          <span className="absolute right-3.5 top-1/2 -translate-y-1/2">{rightElement}</span>
        )}
      </div>
    );
  }
);
AuthInput.displayName = 'AuthInput';

export const AuthSelect = forwardRef<
  HTMLSelectElement,
  React.SelectHTMLAttributes<HTMLSelectElement> & { icon?: ReactNode }
>(({ icon, className = '', children, ...props }, ref) => {
  const ctx = useContext(FieldCtx);
  const aria = useFieldAria();
  const hasError = ctx?.hasError ?? false;

  return (
    <div className="group relative">
      {icon && (
        <span
          className={[
            'pointer-events-none absolute left-3.5 top-1/2 z-10 -translate-y-1/2 transition-colors',
            hasError
              ? 'text-[var(--color-system-error)]'
              : 'text-[var(--color-text-muted)] group-focus-within:text-[var(--color-brand)]',
          ].join(' ')}
        >
          {icon}
        </span>
      )}
      <select
        ref={ref}
        {...aria}
        className={[
          controlClasses(hasError, Boolean(icon), false, className),
          'cursor-pointer appearance-none pr-9',
        ].join(' ')}
        {...props}
      >
        {children}
      </select>
    </div>
  );
});
AuthSelect.displayName = 'AuthSelect';
