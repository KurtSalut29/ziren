'use client';

/**
 * A single-choice filter: a button dressed like a `<SelectTrigger>` that
 * opens an `OptionDialog` instead of a native listbox. Drop-in for a `Select`
 * whose options are a short, known list worth showing with an icon rather
 * than as bare text — status, severity, type, agency, sort order.
 *
 * `size` mirrors `SelectTrigger`'s own prop (`'sm'` = 28px, `'default'` =
 * 32px) rather than PeriodPicker's `'sm'|'md'` naming — this replaces a
 * `Select` directly at each call site, so it matches that component's
 * sizing scheme, not a different control's.
 */

import { useRef, useState } from 'react';
import { ChevronDown } from 'lucide-react';
import { cn } from '@/lib/utils';
import { OptionDialog, type OptionItem } from './option-dialog';

export function OptionPicker({
  label,
  description,
  options,
  value,
  onChange,
  placeholder,
  size = 'default',
  className,
}: {
  /** The dialog's own heading, e.g. "Choose a status" — not the field's short label. */
  label: string;
  description?: string;
  options: OptionItem[];
  value: string;
  onChange: (value: string) => void;
  /** Trigger text when the current value matches no option (should not normally happen — every list here includes an "All"/"Any" option). */
  placeholder: string;
  size?: 'sm' | 'default';
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const current = options.find(o => o.value === value);
  const Icon = current?.icon;

  return (
    <>
      <button
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-label={`${label}: ${current?.label ?? placeholder}`}
        className={cn(
          'flex w-full items-center gap-1.5 rounded-lg border border-input bg-transparent pl-2.5 pr-2 text-[13px] text-foreground outline-none transition-colors hover:bg-[var(--color-surface-hover)] focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30 dark:hover:bg-input/50',
          size === 'sm' ? 'h-7 rounded-[min(var(--radius-md),10px)]' : 'h-8',
          className,
        )}
        onClick={() => setOpen(true)}
        ref={triggerRef}
        type="button"
      >
        {Icon && <Icon aria-hidden="true" className="size-4 shrink-0" style={{ color: current?.color }} />}
        <span className="min-w-0 flex-1 truncate text-left">{current?.label ?? placeholder}</span>
        <ChevronDown aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
      </button>

      <OptionDialog
        description={description}
        onChange={onChange}
        onOpenChange={setOpen}
        open={open}
        options={options}
        title={label}
        triggerRef={triggerRef}
        value={value}
      />
    </>
  );
}
