'use client';

/**
 * SearchInput — the one search field of the console.
 *
 * Every "find it in this list" box renders through here so they are all the
 * same object: same height, same corner, same border, same icon, same clear
 * button. There used to be six hand-built variants (pill-shaped in Settings,
 * borderless-looking grey in the Live Queue and Verification, hairline in
 * Incident Records) and the quiet ones were hard to spot as a search at all.
 *
 * What makes it findable:
 *   - a visible outline — a mid-grey mixed from the muted text token rather
 *     than the near-invisible surface-border hairline, so it reads on both the
 *     cream card and the dark one;
 *   - the card fill, not the recessed "input" grey, so it sits ABOVE the panel
 *     like a field you can type into instead of sinking into it;
 *   - a magnifier in the text colour, not the disabled-looking muted one;
 *   - an 8px corner. Deliberately not a pill: a pill is what a chip or a
 *     toggle looks like here, and a search box should not be mistaken for one.
 *
 * `type="search"` lets a phone show its search keyboard; the native clear
 * button is hidden globally (globals.css) because this draws its own.
 */

import { forwardRef, type InputHTMLAttributes, type ReactNode } from 'react';
import { Search, X } from 'lucide-react';
import { cn } from '@/lib/utils';

export type SearchInputSize = 'sm' | 'md' | 'lg';

const HEIGHT: Record<SearchInputSize, string> = {
  sm: 'h-8 text-[13px]',
  md: 'h-9 text-[13px]',
  lg: 'h-10 text-[14px]',
};

interface SearchInputProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'size' | 'type'> {
  value: string;
  onValueChange: (value: string) => void;
  size?: SearchInputSize;
  /** Accessible name. Placeholder text is not a label. */
  label: string;
  /** Drawn at the right edge instead of the clear button while the field is empty (e.g. a keyboard hint). */
  hint?: ReactNode;
  /** Sizing/placement of the wrapper (width, flex-basis, margin) — the field itself always fills it. */
  className?: string;
}

export const SearchInput = forwardRef<HTMLInputElement, SearchInputProps>(function SearchInput(
  { value, onValueChange, size = 'md', label, hint, className, placeholder = 'Search…', ...rest },
  ref,
) {
  return (
    <div className={cn('relative w-full', className)}>
      <Search
        aria-hidden="true"
        className="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-[var(--color-text-tertiary)]"
      />
      <input
        {...rest}
        aria-label={label}
        className={cn(
          'w-full rounded-[var(--radius-md)] border bg-[var(--color-surface-card)] pl-9 text-foreground',
          'border-[color-mix(in_srgb,var(--color-text-muted)_45%,transparent)]',
          'shadow-[inset_0_1px_1px_rgba(0,0,0,0.04)] outline-none transition-colors',
          'placeholder:text-muted-foreground hover:border-[var(--color-text-muted)]',
          'focus-visible:border-[var(--color-brand)] focus-visible:ring-2 focus-visible:ring-[var(--color-brand)]/25',
          value || hint ? 'pr-9' : 'pr-3',
          HEIGHT[size],
        )}
        onChange={e => onValueChange(e.target.value)}
        placeholder={placeholder}
        ref={ref}
        type="search"
        value={value}
      />
      {value ? (
        <button
          aria-label="Clear search"
          className="absolute right-1.5 top-1/2 flex size-6 -translate-y-1/2 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
          onClick={() => onValueChange('')}
          type="button"
        >
          <X aria-hidden="true" className="size-3.5" />
        </button>
      ) : hint ? (
        <span aria-hidden="true" className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2">
          {hint}
        </span>
      ) : null}
    </div>
  );
});
