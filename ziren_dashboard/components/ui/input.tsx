/**
 * Input — text field with optional label, error, helper text, left icon, right element.
 * Uses inline styles for reliable rendering in Tailwind v4.
 */

import { type InputHTMLAttributes, forwardRef, useState } from 'react';
import { AlertCircle } from 'lucide-react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  helperText?: string;
  leftIcon?: React.ReactNode;
  rightElement?: React.ReactNode;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ label, error, helperText, leftIcon, rightElement, id, style, ...props }, ref) => {
    const inputId = id ?? (label ? label.toLowerCase().replace(/\s+/g, '-') : undefined);
    const [focused, setFocused] = useState(false);

    const borderColor = error
      ? 'var(--color-system-error)'
      : focused
        ? 'var(--color-brand)'
        : 'var(--color-surface-border)';

    const boxShadow = focused && !error
      ? '0 0 0 3px var(--color-brand-container)'
      : focused && error
        ? '0 0 0 3px rgba(220,38,38,0.15)'
        : 'none';

    // Wiring the message to the input by id is what makes a screen reader
    // announce it. Without this the error is visible but silent — the user
    // hears the field name, then nothing about why it was rejected.
    const errorId = inputId ? `${inputId}-error` : undefined;
    const helperId = inputId ? `${inputId}-helper` : undefined;
    const describedBy = error ? errorId : helperText ? helperId : undefined;

    return (
      <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
        {label && (
          <label
            htmlFor={inputId}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '6px',
              fontSize: '13px',
              fontWeight: 600,
              // The label tracks focus and error state so the active field is
              // identified by more than a ring colour alone.
              color: error
                ? 'var(--color-system-error)'
                : focused
                  ? 'var(--color-brand)'
                  : 'var(--color-text-primary)',
              transition: 'color 0.15s',
            }}
          >
            <span
              aria-hidden="true"
              style={{
                width: focused || error ? '3px' : '0px',
                height: '12px',
                borderRadius: '2px',
                backgroundColor: error
                  ? 'var(--color-system-error)'
                  : 'var(--color-brand)',
                transition: 'width 0.15s',
              }}
            />
            {label}
          </label>
        )}
        <div style={{ position: 'relative' }}>
          {leftIcon && (
            <span style={{
              position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)',
              color: 'var(--color-text-muted)', pointerEvents: 'none',
              display: 'flex', alignItems: 'center',
            }}>
              {leftIcon}
            </span>
          )}
          <input
            ref={ref}
            id={inputId}
            aria-invalid={error ? true : undefined}
            aria-describedby={describedBy}
            onFocus={e => { setFocused(true); props.onFocus?.(e); }}
            onBlur={e => { setFocused(false); props.onBlur?.(e); }}
            style={{
              width: '100%',
              height: '42px',
              paddingLeft: leftIcon ? '40px' : '12px',
              paddingRight: rightElement ? '40px' : '12px',
              borderRadius: '10px',
              border: `1.5px solid ${borderColor}`,
              backgroundColor: 'var(--color-surface-card)',
              fontSize: '14px',
              color: 'var(--color-text-primary)',
              fontFamily: 'inherit',
              outline: 'none',
              boxShadow,
              transition: 'border-color 0.15s, box-shadow 0.15s',
              ...style,
            }}
            {...props}
          />
          {rightElement && (
            <span style={{
              position: 'absolute', right: '12px', top: '50%', transform: 'translateY(-50%)',
              color: 'var(--color-text-muted)',
              display: 'flex', alignItems: 'center',
            }}>
              {rightElement}
            </span>
          )}
        </div>
        {error && (
          <p
            id={errorId}
            // Announced the moment it appears, without stealing focus from
            // the field the user is still correcting.
            role="alert"
            style={{
              display: 'flex',
              alignItems: 'flex-start',
              gap: '5px',
              fontSize: '12.5px',
              lineHeight: 1.45,
              fontWeight: 500,
              color: 'var(--color-system-error)',
            }}
          >
            {/* An icon as well as colour, so the message does not depend on
                red being distinguishable. */}
            <AlertCircle
              aria-hidden="true"
              style={{ width: '13px', height: '13px', flexShrink: 0, marginTop: '2px' }}
            />
            {error}
          </p>
        )}
        {helperText && !error && (
          <p id={helperId} style={{ fontSize: '12px', color: 'var(--color-text-muted)' }}>
            {helperText}
          </p>
        )}
      </div>
    );
  }
);
Input.displayName = 'Input';
