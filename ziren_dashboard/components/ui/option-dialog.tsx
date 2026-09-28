'use client';

/**
 * Choosing ONE of a short list of options — in a dialog, not a dropdown.
 *
 * The same reasoning as Operational Area's barangay picker for a LONG list,
 * applied here to a short one: a native `<select>` says a value back with no
 * room to show what it means — no icon, no colour, no second line — and it
 * reads as a bare list of words rather than a considered choice. A dialog
 * gives each option its own row: an icon (colour-coded when the option has
 * one, e.g. a severity or an agency), its label, and an optional hint.
 *
 * Not for a list long enough to need a search box — that is BarangayDialog's
 * job. This is a single column, click-to-choose-and-close, meant for the
 * status/severity/type/agency/order filters a `<Select>` used to hold.
 */

import { useEffect, useRef } from 'react';
import { Check, X } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { cn } from '@/lib/utils';

export interface OptionItem {
  value: string;
  label: string;
  icon?: LucideIcon;
  /** Tints the icon and, once picked, the row — an agency or severity hue. Defaults to the neutral brand tint. */
  color?: string;
  /** A short second line — what the option means, not a restatement of its name. */
  hint?: string;
}

export function OptionDialog({
  open,
  onOpenChange,
  title,
  description,
  options,
  value,
  onChange,
  triggerRef,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** "Choose a status" — the dialog's own heading, not the field's short label. */
  title: string;
  description?: string;
  options: OptionItem[];
  value: string;
  onChange: (value: string) => void;
  /** The field that opens this dialog — focus returns to it on close, however closing happened. */
  triggerRef: React.RefObject<HTMLButtonElement | null>;
}) {
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[400px]"
        onCloseAutoFocus={e => {
          // Same fix as every other dialog opened from a plain button in this console:
          // Radix's own "restore whatever was focused before" does not reliably land back
          // on a trigger that isn't a <Dialog.Trigger> — confirmed by hand, more than once.
          e.preventDefault();
          triggerRef.current?.focus();
        }}
        onOpenAutoFocus={e => {
          e.preventDefault();
          (e.target as HTMLElement).querySelector<HTMLElement>('[data-option][tabindex="0"]')?.focus();
        }}
        showCloseButton={false}
      >
        <Picker
          description={description}
          onChoose={v => { onChange(v); onOpenChange(false); }}
          options={options}
          title={title}
          value={value}
        />
      </DialogContent>
    </Dialog>
  );
}

function Picker({
  title,
  description,
  options,
  value,
  onChoose,
}: {
  title: string;
  description?: string;
  options: OptionItem[];
  value: string;
  onChoose: (value: string) => void;
}) {
  const listEl = useRef<HTMLDivElement>(null);

  useEffect(() => {
    listEl.current?.querySelector('[aria-checked="true"]')?.scrollIntoView({ block: 'nearest' });
  }, []);

  function onListKey(e: React.KeyboardEvent<HTMLDivElement>) {
    const keys = ['ArrowUp', 'ArrowDown', 'Home', 'End'];
    if (!keys.includes(e.key)) return;
    const all = Array.from(e.currentTarget.querySelectorAll<HTMLElement>('[data-option]'));
    const at = all.indexOf(document.activeElement as HTMLElement);
    if (at < 0) return;
    e.preventDefault();
    const last = all.length - 1;
    const to =
      e.key === 'Home' ? 0
      : e.key === 'End' ? last
      : e.key === 'ArrowDown' ? Math.min(at + 1, last)
      : Math.max(at - 1, 0);
    all[to]?.focus();
    all[to]?.scrollIntoView({ block: 'nearest' });
  }

  // The list's one tab stop: the current choice, or the first row if the value matches nothing shown.
  const stop = options.some(o => o.value === value) ? value : options[0]?.value;

  return (
    <>
      <div className="flex items-start gap-3 px-5 pb-3 pt-5">
        <div className="min-w-0 flex-1">
          <DialogTitle className="text-[16px] font-bold leading-tight tracking-tight text-foreground">{title}</DialogTitle>
          {description && <DialogDescription className="mt-1 text-[13px] leading-snug">{description}</DialogDescription>}
        </div>
        <DialogClose
          aria-label="Close"
          className="-mr-1 -mt-1 flex size-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
        >
          <X aria-hidden="true" className="size-4" />
        </DialogClose>
      </div>

      <div
        aria-label={title}
        className="min-h-0 flex-1 space-y-1.5 overflow-y-auto px-5 pb-5"
        onKeyDown={onListKey}
        ref={listEl}
        role="radiogroup"
      >
        {options.map(o => (
          <Row active={o.value === value} key={o.value} onChoose={() => onChoose(o.value)} option={o} stop={stop === o.value} />
        ))}
      </div>
    </>
  );
}

function Row({
  option,
  active,
  stop,
  onChoose,
}: {
  option: OptionItem;
  active: boolean;
  /** This row is the list's tab stop. */
  stop: boolean;
  onChoose: () => void;
}) {
  const Icon = option.icon;
  const color = option.color ?? 'var(--color-brand)';
  return (
    <button
      aria-checked={active}
      className={cn(
        'flex w-full min-w-0 items-center gap-3 rounded-xl border px-3.5 py-2.5 text-left transition-colors',
        active
          ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
          : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] hover:bg-[var(--color-surface-hover)]',
      )}
      data-option
      onClick={onChoose}
      role="radio"
      tabIndex={stop ? 0 : -1}
      type="button"
    >
      {Icon && (
        <span
          aria-hidden="true"
          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
          style={{ backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
        >
          <Icon className="size-4" />
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[14px] font-semibold leading-snug text-foreground">{option.label}</span>
        {option.hint && <span className="block truncate text-[12px] text-muted-foreground">{option.hint}</span>}
      </span>
      <span
        aria-hidden="true"
        className={cn(
          'flex size-5 shrink-0 items-center justify-center rounded-full border',
          active ? 'border-[var(--color-brand-active)] bg-[var(--color-brand-active)] text-white' : 'border-[var(--color-border-strong)] text-transparent',
        )}
      >
        <Check className="size-3" strokeWidth={3} />
      </span>
    </button>
  );
}
