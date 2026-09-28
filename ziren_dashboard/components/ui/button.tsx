/**
 * Button — primary interactive element used throughout the dashboard.
 *
 * Variants:
 *   primary — brand orange, main actions (Save, Dispatch, Confirm)
 *   outline — bordered, secondary actions (Cancel, Back, Edit)
 *   ghost   — low-emphasis, icon buttons, table row actions
 *   danger  — destructive actions (Delete, Suspend, Flag) — always requires confirm step
 *
 * Sizes: sm (32px) | md (40px) | lg (48px, full-width)
 *
 * Uses inline styles for critical dimensions so Tailwind v4's JIT
 * scan doesn't miss dynamically-constructed class strings.
 */

import { type ButtonHTMLAttributes, forwardRef } from 'react';
import { Loader2 } from 'lucide-react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'outline' | 'ghost' | 'danger' | 'success';
  size?: 'sm' | 'md' | 'lg';
  isLoading?: boolean;
}

const VARIANT_STYLES: Record<string, React.CSSProperties> = {
  // TailAdmin's Primary Button — solid brand fill, a hairline lift instead of a
  // flat fill, and an opaque hover shade rather than a translucent one.
  primary: {
    backgroundColor: 'var(--color-brand)',
    color: '#ffffff',
    border: 'none',
    boxShadow: '0 1px 2px rgba(16, 24, 40, 0.05)',
  },
  // TailAdmin's Outline Button — a card-toned control with a neutral ring, not
  // a brand-coloured one. Brand is reserved for the primary action on a row;
  // an outline button that also carries it reads as two primaries side by side.
  // Border is --color-border-strong, not --color-surface-border: the latter
  // is a ~1.2:1 hairline meant to separate a card from the page, which in a
  // dark dialog (this component's own Cancel button, on the dispatch modal)
  // made the button read as plain text with no boundary until hover.
  outline: {
    backgroundColor: 'var(--color-surface-card)',
    color: 'var(--color-text-secondary)',
    border: '1px solid var(--color-border-strong)',
    boxShadow: '0 1px 2px rgba(16, 24, 40, 0.05)',
  },
  ghost: {
    backgroundColor: 'transparent',
    color: 'var(--color-text-secondary)',
    border: '1.5px solid var(--color-border-strong)',
  },
  danger: {
    backgroundColor: 'var(--color-system-error-bg)',
    color: 'var(--color-system-error)',
    border: '1.5px solid var(--color-system-error)',
  },
  success: {
    backgroundColor: 'var(--color-system-success)',
    color: '#ffffff',
    border: 'none',
  },
};

const SIZE_STYLES: Record<string, React.CSSProperties> = {
  sm: { height: '32px', padding: '0 12px', fontSize: '12px', borderRadius: '8px' },
  md: { height: '40px', padding: '0 16px', fontSize: '13.5px', borderRadius: '10px' },
  lg: { height: '48px', padding: '0 24px', fontSize: '15px', borderRadius: '10px', width: '100%' },
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ variant = 'primary', size = 'md', isLoading = false, disabled, style, children, ...props }, ref) => {
    const isDisabled = disabled || isLoading;

    const baseStyle: React.CSSProperties = {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontWeight: 600,
      fontFamily: 'inherit',
      cursor: isDisabled ? 'not-allowed' : 'pointer',
      opacity: isDisabled ? 0.45 : 1,
      transition: 'background-color 0.15s, opacity 0.15s, box-shadow 0.15s',
      // No `outline: 'none'` here. It used to sit in this inline style, and
      // because inline styles outrank stylesheet rules it silently defeated
      // any :focus-visible ring globals.css tried to apply — leaving every
      // button in the dashboard with no keyboard focus indicator at all.
      // The ring now comes from the :focus-visible rule in globals.css.
      userSelect: 'none',
      whiteSpace: 'nowrap',
      gap: '6px',
      ...VARIANT_STYLES[variant],
      ...SIZE_STYLES[size],
      ...style,
    };

    function handleMouseEnter(e: React.MouseEvent<HTMLButtonElement>) {
      if (isDisabled) return;
      const el = e.currentTarget;
      if (variant === 'primary') el.style.backgroundColor = 'var(--color-brand-dim)';
      if (variant === 'outline') el.style.backgroundColor = 'var(--color-surface-hover)';
      if (variant === 'outline') el.style.color = 'var(--color-text-primary)';
      if (variant === 'ghost')   el.style.backgroundColor = 'var(--color-surface-raised)';
      if (variant === 'danger')  el.style.backgroundColor = 'var(--color-system-error)';
      if (variant === 'danger')  el.style.color = '#fff';
      if (variant === 'success') el.style.backgroundColor = '#15803d';
    }

    function handleMouseLeave(e: React.MouseEvent<HTMLButtonElement>) {
      if (isDisabled) return;
      const el = e.currentTarget;
      if (variant === 'primary') el.style.backgroundColor = 'var(--color-brand)';
      if (variant === 'outline') el.style.backgroundColor = 'var(--color-surface-card)';
      if (variant === 'outline') el.style.color = 'var(--color-text-secondary)';
      if (variant === 'ghost')   el.style.backgroundColor = 'transparent';
      if (variant === 'danger')  el.style.backgroundColor = 'var(--color-system-error-bg)';
      if (variant === 'danger')  el.style.color = 'var(--color-system-error)';
      if (variant === 'success') el.style.backgroundColor = 'var(--color-system-success)';
    }

    return (
      <button
        ref={ref}
        disabled={isDisabled}
        style={baseStyle}
        // Brand-filled variants would swallow a brand-coloured focus ring,
        // so they opt into the dark one (see globals.css).
        data-focus-ring={
          variant === 'primary' || variant === 'success' ? 'inverse' : undefined
        }
        onMouseEnter={handleMouseEnter}
        onMouseLeave={handleMouseLeave}
        {...props}
      >
        {isLoading && <Loader2 style={{ width: '15px', height: '15px', animation: 'spin 1s linear infinite', flexShrink: 0 }} />}
        {children}
      </button>
    );
  }
);
Button.displayName = 'Button';
