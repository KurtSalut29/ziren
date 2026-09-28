'use client';

/**
 * Choosing a barangay — in a dialog, not a dropdown.
 *
 * A municipality can have thirty-odd barangays. A dropdown that long runs off the
 * screen and scrolls inside itself, and the reader hunts down it one name at a
 * time. A dialog has room for what a long list needs: a search box, every name on
 * view at once in two columns, and — because the reader is usually choosing a
 * barangay for a reason — how many reports each one has in the period on screen.
 *
 * One click chooses and closes. Whole municipality is always the first row, so
 * undoing a choice is as easy as making it. Keyboard: type to search, ↓ from the
 * box to the list, arrows to move, Enter to choose, Esc to leave; Enter in the box
 * chooses when the search has narrowed to a single barangay.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { Check, MapPin, MapPinned, X } from 'lucide-react';
import { SearchInput } from '@/components/ui/search-input';
import type { LucideIcon } from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { cn } from '@/lib/utils';
import { fmtInt } from './kit';

export interface BarangayOption {
  name: string;
  /** Reports in the period on screen whose address names this barangay. */
  incidents: number;
}

type Sort = 'name' | 'reports';

/** Case- and accent-blind, so "nino" finds "Niño". */
const plain = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();

export function BarangayDialog({
  open,
  onOpenChange,
  municipality,
  options,
  total,
  periodWords,
  value,
  onChange,
  triggerRef,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  municipality: string;
  options: BarangayOption[];
  /** Reports in the whole municipality this period — the count on the "Whole municipality" row. */
  total: number;
  /** What the counts are counting: "the last 30 days". */
  periodWords: string;
  value: string | null;
  onChange: (barangay: string | null) => void;
  /** The field that opens this dialog — focus returns to it on close, however closing happened. */
  triggerRef: React.RefObject<HTMLButtonElement | null>;
}) {
  return (
    <Dialog onOpenChange={onOpenChange} open={open}>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[620px]"
        onCloseAutoFocus={e => {
          // Radix's default is "refocus whatever had focus before the dialog opened", which
          // in principle is the trigger — but that is a plain button, not a <Dialog.Trigger>,
          // and in practice focus landed on <body> instead (checked with the keyboard: the
          // next Tab press started at the top of the page). Naming the element directly
          // makes this dependable rather than incidental.
          e.preventDefault();
          triggerRef.current?.focus();
        }}
        onOpenAutoFocus={e => {
          // Land in the search box: the first thing anyone does here is type.
          e.preventDefault();
          (e.target as HTMLElement).querySelector<HTMLInputElement>('input[type="search"]')?.focus();
        }}
        showCloseButton={false}
      >
        <Picker
          municipality={municipality}
          onChoose={b => { onChange(b); onOpenChange(false); }}
          options={options}
          periodWords={periodWords}
          total={total}
          value={value}
        />
      </DialogContent>
    </Dialog>
  );
}

function Picker({
  municipality,
  options,
  total,
  periodWords,
  value,
  onChoose,
}: {
  municipality: string;
  options: BarangayOption[];
  total: number;
  periodWords: string;
  value: string | null;
  onChoose: (barangay: string | null) => void;
}) {
  const [q, setQ] = useState('');
  const [sort, setSort] = useState<Sort>('name');
  const listEl = useRef<HTMLDivElement>(null);

  useEffect(() => {
    listEl.current?.querySelector('[aria-checked="true"]')?.scrollIntoView({ block: 'nearest' });
  }, []);

  const shown = useMemo(() => {
    const needle = plain(q);
    const list = options.filter(b => !needle || plain(b.name).includes(needle));
    return [...list].sort((a, b) =>
      sort === 'reports' ? b.incidents - a.incidents || a.name.localeCompare(b.name) : a.name.localeCompare(b.name));
  }, [options, q, sort]);

  const focusables = (root: HTMLElement) => Array.from(root.querySelectorAll<HTMLElement>('[data-option]'));

  /** Arrow keys over [Whole municipality, ...barangays]; Up/Down move by a row of the grid. */
  function onListKey(e: React.KeyboardEvent<HTMLDivElement>) {
    const keys = ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'];
    if (!keys.includes(e.key)) return;
    const all = focusables(e.currentTarget);
    const at = all.indexOf(document.activeElement as HTMLElement);
    if (at < 0) return;
    e.preventDefault();
    const grid = e.currentTarget.querySelector<HTMLElement>('[data-grid]');
    const cols = grid ? getComputedStyle(grid).gridTemplateColumns.split(' ').length : 1;
    const last = all.length - 1;
    const to =
      e.key === 'Home' ? 0
      : e.key === 'End' ? last
      : e.key === 'ArrowRight' ? Math.min(at + 1, last)
      : e.key === 'ArrowLeft' ? Math.max(at - 1, 0)
      : e.key === 'ArrowDown' ? (at === 0 ? Math.min(1, last) : Math.min(at + cols, last))
      : /* ArrowUp */ at - 1 - cols >= 0 ? at - cols : 0;    // above the first row of barangays is the whole-municipality row
    all[to]?.focus();
    all[to]?.scrollIntoView({ block: 'nearest' });
  }

  // The one tab stop of the list: the current choice, or the first row.
  const stop = value && shown.some(b => b.name === value) ? value : null;

  return (
    <>
      {/* ── who is choosing what ─────────────────────────────────────── */}
      <div className="flex items-start gap-3.5 px-5 pb-3 pt-5 sm:px-6">
        <span
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-xl bg-[var(--color-brand-subtle)] text-[var(--color-brand)]"
        >
          <MapPin className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <DialogTitle className="text-[18px] font-bold leading-tight tracking-tight text-foreground">
            Choose a barangay
          </DialogTitle>
          <DialogDescription className="mt-1 text-[13px] leading-snug">
            {municipality} · {options.length} barangays. Every tab will show the figures for the one you pick.
          </DialogDescription>
        </div>
        <DialogClose
          aria-label="Close"
          className="-mr-1 -mt-1 flex size-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
        >
          <X aria-hidden="true" className="size-4" />
        </DialogClose>
      </div>

      {/* ── find it ──────────────────────────────────────────────────── */}
      <div className="flex flex-wrap items-center gap-2.5 px-5 pb-3 sm:px-6">
        <SearchInput
          className="min-w-[200px] flex-1"
          label="Search barangays"
          onKeyDown={e => {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              const root = e.currentTarget.closest<HTMLElement>('[role="dialog"]');
              const list = root ? focusables(root) : [];
              (list.find(el => el.getAttribute('tabindex') === '0') ?? list[0])?.focus();
            } else if (e.key === 'Enter' && shown.length === 1) {
              e.preventDefault();
              onChoose(shown[0].name);
            }
          }}
          onValueChange={setQ}
          placeholder={`Search ${options.length} barangays`}
          size="lg"
          value={q}
        />

        <div aria-label="Sort barangays" className="flex h-10 items-center gap-0.5 rounded-[var(--radius-control)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-[3px]" role="group">
          {([['name', 'A–Z'], ['reports', 'Most reports']] as const).map(([key, label]) => (
            <button
              aria-pressed={sort === key}
              className={cn(
                'h-[30px] whitespace-nowrap rounded-[calc(var(--radius-control)-3px)] px-3 text-[12.5px] font-semibold transition-colors',
                sort === key
                  ? 'bg-[var(--color-surface-card)] text-foreground shadow-[0_1px_2px_rgba(0,0,0,0.1),0_0_0_1px_var(--color-surface-border)]'
                  : 'text-muted-foreground hover:text-foreground',
              )}
              key={key}
              onClick={() => setSort(key)}
              type="button"
            >
              {label}
            </button>
          ))}
        </div>
      </div>

      {/* ── the choices ──────────────────────────────────────────────── */}
      <div
        aria-label="Barangay"
        className="min-h-0 flex-1 overflow-y-auto px-5 pb-4 pt-1 sm:px-6"
        onKeyDown={onListKey}
        ref={listEl}
        role="radiogroup"
      >
        <Row
          active={value === null}
          hint={`All ${options.length} barangays`}
          icon={MapPinned}
          name="Whole municipality"
          stop={stop === null}
          onChoose={() => onChoose(null)}
          right={<Count n={total} />}
        />

        <div className="mt-2.5 grid grid-cols-1 gap-2 sm:grid-cols-2" data-grid>
          {shown.map(b => (
            <Row
              active={value === b.name}
              key={b.name}
              name={b.name}
              onChoose={() => onChoose(b.name)}
              right={<Count n={b.incidents} />}
              stop={stop === b.name}
            />
          ))}
        </div>

        {shown.length === 0 && (
          <div className="mt-4 rounded-xl border border-dashed border-[var(--color-surface-border)] px-4 py-8 text-center">
            <p className="text-[14px] font-semibold text-foreground">No barangay matches “{q.trim()}”</p>
            <p className="mt-1 text-[13px] text-muted-foreground">Check the spelling, or clear the search to see all {options.length}.</p>
            <button
              className="mt-3 rounded-lg border border-[var(--color-surface-border)] px-3 py-1.5 text-[13px] font-semibold text-foreground hover:bg-[var(--color-surface-hover)]"
              onClick={() => setQ('')}
              type="button"
            >
              Clear search
            </button>
          </div>
        )}
        <p aria-live="polite" className="sr-only">{shown.length} of {options.length} barangays shown</p>
      </div>

      <p className="border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/45 px-5 py-3 text-[12.5px] leading-snug text-muted-foreground sm:px-6">
        Counts are reports in {periodWords}, placed by the barangay named in each report’s address.
      </p>
    </>
  );
}

function Count({ n }: { n: number }) {
  return n > 0
    ? <span className="shrink-0 text-[12.5px] tabular-nums text-[var(--color-text-secondary)]"><strong className="font-semibold text-foreground">{fmtInt(n)}</strong> report{n === 1 ? '' : 's'}</span>
    : <span className="shrink-0 text-[12.5px] text-muted-foreground">No reports</span>;
}

function Row({
  name,
  hint,
  icon: Icon,
  right,
  active,
  stop,
  onChoose,
}: {
  name: string;
  hint?: string;
  icon?: LucideIcon;
  right: React.ReactNode;
  active: boolean;
  /** This row is the list's tab stop. */
  stop: boolean;
  onChoose: () => void;
}) {
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
      {Icon && <Icon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />}
      <span className="min-w-0 flex-1">
        <span className="block break-words text-[14px] font-semibold leading-snug text-foreground">{name}</span>
        {hint && <span className="block truncate text-[12px] text-muted-foreground">{hint}</span>}
      </span>
      {right}
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
