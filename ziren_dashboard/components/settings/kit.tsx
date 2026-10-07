'use client';

/**
 * The building blocks of the Settings screen.
 *
 * Every panel is assembled from the same small set of pieces, so a new setting
 * looks like it belongs the day it is added:
 *
 *   PanelHeader   the section's icon, title, description and SCOPE
 *   Card          a titled group of related settings
 *   Row           one setting: what it is on the left, its control on the right
 *   Segmented     pick one of a few short options
 *   OptionCards   pick one of a few options that deserve a picture
 *   Callout       something the reader must not miss
 *   Stat          a figure with a caption
 *
 * SCOPE is the design idea that matters most here. A setting that "saves" is
 * only useful if the reader knows WHAT it changed and FOR WHOM: this browser,
 * their own account, every dispatcher in their agency, the whole province. Those
 * are four different blast radii, and confusing them is how a shared dispatch
 * terminal ends up with someone else's font size, or one admin switches off an
 * alert for a whole agency believing it was only theirs. Every panel therefore
 * says where it saves, in the header, before the first control.
 */

import { createContext, useContext, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import {
  AlertTriangle, Building2, Check, CheckCircle2, Info, Landmark, Laptop,
  Save, UserRound,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';
import { SearchInput } from '@/components/ui/search-input';
import { NavTabs } from '@/components/ui/nav-tabs';
import { Switch } from '@/components/efferd/ui/switch';
import { Button } from '@/components/efferd/ui/button';

// ── Scope ────────────────────────────────────────────────────────────────

export type SettingsScope = 'browser' | 'account' | 'agency' | 'province';

const SCOPE: Record<SettingsScope, { label: string; hint: string; icon: LucideIcon }> = {
  browser: {
    label: 'This browser',
    hint: 'Saved on this device only. It does not follow you to another computer, and a shared terminal keeps its own.',
    icon: Laptop,
  },
  account: {
    label: 'Your account',
    hint: 'Saved to your Ziren account. It follows you to any device you sign in on.',
    icon: UserRound,
  },
  agency: {
    label: 'Your whole agency',
    hint: 'Saved to your agency. It applies to every dispatcher and admin in it, not just you.',
    icon: Building2,
  },
  province: {
    label: 'Province-wide',
    hint: 'Applies across the province. Changes here are recorded in the audit log.',
    icon: Landmark,
  },
};

export function ScopeChip({ scope }: { scope: SettingsScope }) {
  const { label, hint, icon: Icon } = SCOPE[scope];
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-2.5 py-1 text-[11.5px] font-semibold text-[var(--color-text-secondary)]"
      title={hint}
    >
      <Icon aria-hidden="true" className="size-3.5" />
      {label}
    </span>
  );
}

// ── Panel header ─────────────────────────────────────────────────────────

/**
 * A section's heading: what it is, in a sentence, and — under it, before the
 * first control — WHERE it saves. That last line is what keeps a shared
 * terminal's font size from being mistaken for an account setting, so it is
 * text on the page and not only a tooltip.
 */
export function PanelHeader({
  icon: Icon,
  title,
  description,
  scope,
  meta,
}: {
  icon: LucideIcon;
  title: string;
  description?: React.ReactNode;
  /** One or more — a panel can mix per-browser and per-account settings. */
  scope?: SettingsScope | SettingsScope[];
  /** Small right-aligned status, e.g. a saved indicator. */
  meta?: React.ReactNode;
}) {
  const scopes = scope === undefined ? [] : Array.isArray(scope) ? scope : [scope];
  return (
    <header className="flex flex-col gap-2" data-panel-header>
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
        <h2 className="flex items-center gap-2.5 text-[19px] font-bold leading-tight tracking-tight text-foreground">
          <Icon aria-hidden="true" className="size-5 shrink-0 text-[var(--color-brand)]" />
          {title}
        </h2>
        {meta && <div className="shrink-0">{meta}</div>}
      </div>
      {description && (
        <p className="max-w-[68ch] text-[14px] leading-relaxed text-muted-foreground">{description}</p>
      )}
      {scopes.length > 0 && (
        <ul aria-label="Where these settings are saved" className="mt-1 flex flex-col gap-1.5">
          {scopes.map(s => {
            const { label, hint, icon: ScopeIcon } = SCOPE[s];
            return (
              <li className="flex items-start gap-2 text-[12.5px] leading-relaxed text-muted-foreground" key={s}>
                <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-2.5 py-0.5 text-[11.5px] font-semibold text-[var(--color-text-secondary)]">
                  <ScopeIcon aria-hidden="true" className="size-3.5" />
                  {label}
                </span>
                <span className="pt-0.5">{hint}</span>
              </li>
            );
          })}
        </ul>
      )}
    </header>
  );
}

// ── Section + Row ────────────────────────────────────────────────────────

/**
 * Sections are FLAT: a bold title, a muted sentence, then the rows — no box
 * around them, a hairline between one section and the next. A `flush` section is
 * the exception: it holds a list or a table that brings its own padding and needs
 * a container to sit in, so it keeps a bordered box, and the rows inside it pad
 * themselves to match.
 */
const BoxedContext = createContext(false);

export function Card({
  title,
  description,
  action,
  children,
  className,
  flush = false,
}: {
  title?: string;
  description?: React.ReactNode;
  /** Top-right of the section heading: a button, a chip. */
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
  /** A list or table that carries its own padding — drawn inside a bordered box. */
  flush?: boolean;
}) {
  const hasHeader = Boolean(title || action);
  return (
    <section
      className={cn(
        'flex flex-col gap-4 border-t border-[var(--color-surface-border)] pt-7',
        // The first section under a panel's heading needs no rule above it.
        '[[data-panel-header]+&]:border-t-0 [[data-panel-header]+&]:pt-1',
        className,
      )}
    >
      {hasHeader && (
        <div className="flex flex-wrap items-end justify-between gap-x-4 gap-y-2">
          <div className="min-w-0">
            {title && <h3 className="text-[15px] font-semibold tracking-tight text-foreground">{title}</h3>}
            {description && (
              <p className="mt-0.5 max-w-[68ch] text-[13px] leading-relaxed text-muted-foreground">
                {description}
              </p>
            )}
          </div>
          {action && <div className="shrink-0">{action}</div>}
        </div>
      )}
      <BoxedContext.Provider value={flush}>
        {flush ? (
          <div className="overflow-hidden rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]">
            {children}
          </div>
        ) : (
          <div>{children}</div>
        )}
      </BoxedContext.Provider>
    </section>
  );
}

/** A list of Rows, hairline-separated. */
export function RowList({ children }: { children: React.ReactNode }) {
  return <div className="flex flex-col divide-y divide-[var(--color-surface-border)]">{children}</div>;
}

/**
 * One setting: its name on the left, its control on the right, and a line of
 * explanation under the control — the layout every settings screen a person
 * has used before has, so nothing has to be learned.
 */
export function Row({
  label,
  description,
  icon: Icon,
  htmlFor,
  badge,
  children,
  stacked = false,
}: {
  label: string;
  description?: React.ReactNode;
  icon?: LucideIcon;
  /** Matched to the control's id so clicking the label focuses it. */
  htmlFor?: string;
  badge?: React.ReactNode;
  children?: React.ReactNode;
  /** Control under the text instead of beside it — for wide controls. */
  stacked?: boolean;
}) {
  const boxed = useContext(BoxedContext);
  const hasControl = children !== undefined;
  const name = (
    <label
      className={cn('flex flex-wrap items-center gap-x-2 gap-y-1 self-start text-[14px] font-medium leading-snug text-foreground', hasControl && !stacked && 'min-h-9')}
      htmlFor={htmlFor}
    >
      {Icon && <Icon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />}
      {label}
      {badge}
    </label>
  );
  const note = description ? (
    <p className={cn('max-w-[64ch] text-[12.5px] leading-relaxed text-muted-foreground', hasControl && !stacked && 'mt-1.5')}>
      {description}
    </p>
  ) : null;

  if (stacked) {
    return (
      <div className={cn('flex flex-col gap-2.5 py-4', boxed && 'px-5')}>
        <div className="flex flex-col gap-0.5">
          {name}
          {note}
        </div>
        {hasControl && <div className="w-full min-w-0">{children}</div>}
      </div>
    );
  }
  return (
    <div className={cn('grid gap-x-8 gap-y-1.5 py-4 sm:grid-cols-[minmax(0,220px)_minmax(0,1fr)]', boxed && 'px-5')}>
      {name}
      <div className="min-w-0">
        {hasControl && <div>{children}</div>}
        {note}
      </div>
    </div>
  );
}

/** A switch as a Row's control. */
export function ToggleRow({
  id,
  label,
  description,
  icon,
  checked,
  onChange,
  disabled,
  badge,
}: {
  id: string;
  label: string;
  description?: React.ReactNode;
  icon?: LucideIcon;
  checked: boolean;
  onChange: (next: boolean) => void;
  disabled?: boolean;
  badge?: React.ReactNode;
}) {
  return (
    <Row badge={badge} description={description} htmlFor={id} icon={icon} label={label}>
      <span className="flex min-h-9 items-center">
        <Switch checked={checked} disabled={disabled} id={id} onCheckedChange={v => onChange(Boolean(v))} />
      </span>
    </Row>
  );
}

// ── Choosers ─────────────────────────────────────────────────────────────

export interface ChoiceOption<T> {
  value: T;
  label: string;
  hint?: string;
  icon?: LucideIcon;
}

/** Pick one of a few short options. A radio group, keyboard-operable. */
export function Segmented<T extends string | number>({
  value,
  onChange,
  options,
  ariaLabel,
  disabled,
}: {
  value: T;
  onChange: (next: T) => void;
  options: ChoiceOption<T>[];
  ariaLabel: string;
  disabled?: boolean;
}) {
  return (
    <div
      aria-label={ariaLabel}
      className={cn(
        'inline-flex flex-wrap gap-0.5 rounded-[10px] bg-[var(--color-surface-raised)] p-0.5',
        disabled && 'opacity-50',
      )}
      role="radiogroup"
    >
      {options.map(o => {
        const active = o.value === value;
        return (
          <button
            aria-checked={active}
            className={cn(
              'rounded-lg px-3 py-1.5 text-[12.5px] font-medium transition-[background,color,box-shadow]',
              active
                ? 'bg-[var(--color-surface-card)] text-foreground shadow-[0_1px_2px_rgba(0,0,0,0.08),0_0_0_1px_var(--color-surface-border)]'
                : 'text-[var(--color-text-secondary)] hover:text-foreground',
            )}
            disabled={disabled}
            key={String(o.value)}
            onClick={() => onChange(o.value)}
            role="radio"
            title={o.hint}
            type="button"
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

/** Pick one of a few options that are worth a picture and a sentence. */
export function OptionCards<T extends string | number>({
  value,
  onChange,
  options,
  ariaLabel,
  columns = 3,
}: {
  value: T;
  onChange: (next: T) => void;
  options: ChoiceOption<T>[];
  ariaLabel: string;
  columns?: 2 | 3 | 4;
}) {
  const cols = { 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-4' }[columns];
  return (
    <div aria-label={ariaLabel} className={cn('grid grid-cols-1 gap-3', cols)} role="radiogroup">
      {options.map(o => {
        const active = o.value === value;
        const Icon = o.icon;
        return (
          <button
            aria-checked={active}
            className={cn(
              'group relative flex flex-col items-start gap-2 rounded-[12px] border px-4 py-3.5 text-left transition-colors',
              active
                ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
                : 'border-[var(--color-surface-border)] hover:bg-[var(--color-surface-raised)]',
            )}
            key={String(o.value)}
            onClick={() => onChange(o.value)}
            role="radio"
            type="button"
          >
            {Icon && (
              <Icon
                aria-hidden="true"
                className="size-5"
                style={{ color: active ? 'var(--color-brand)' : 'var(--color-text-muted)' }}
              />
            )}
            <span className="block text-[13.5px] font-semibold text-foreground">{o.label}</span>
            {o.hint && <span className="block text-[12px] leading-snug text-muted-foreground">{o.hint}</span>}
            {active && (
              <span
                aria-hidden="true"
                className="absolute right-3 top-3 flex size-5 items-center justify-center rounded-full bg-[var(--color-brand)] text-white"
              >
                <Check className="size-3" strokeWidth={3} />
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

/** A range slider, styled to the brand. */
export function RangeControl({
  id,
  value,
  min,
  max,
  step,
  onChange,
  format,
  ariaLabel,
}: {
  id: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (v: number) => void;
  format: (v: number) => string;
  ariaLabel: string;
}) {
  return (
    <div className="flex items-center gap-3">
      <input
        aria-label={ariaLabel}
        className="h-1.5 w-40 cursor-pointer accent-[var(--color-brand)]"
        id={id}
        max={max}
        min={min}
        onChange={e => onChange(Number(e.target.value))}
        step={step}
        type="range"
        value={value}
      />
      <span className="w-11 text-right font-mono text-[12.5px] font-semibold tabular-nums text-foreground">
        {format(value)}
      </span>
    </div>
  );
}

// ── Callout / Stat ───────────────────────────────────────────────────────

type Tone = 'info' | 'success' | 'warning' | 'danger' | 'neutral';

const TONE: Record<Tone, { color: string; icon: LucideIcon }> = {
  info:    { color: 'var(--color-system-info, #0ea5e9)', icon: Info },
  success: { color: 'var(--color-system-success)', icon: CheckCircle2 },
  warning: { color: 'var(--color-system-warning)', icon: AlertTriangle },
  danger:  { color: 'var(--color-severity-critical)', icon: AlertTriangle },
  neutral: { color: 'var(--color-text-muted)', icon: Info },
};

/** Something the reader must not miss. */
export function Callout({
  tone = 'info',
  title,
  children,
  action,
  icon,
}: {
  tone?: Tone;
  title?: string;
  children?: React.ReactNode;
  action?: React.ReactNode;
  icon?: LucideIcon;
}) {
  const { color, icon: DefaultIcon } = TONE[tone];
  const Icon = icon ?? DefaultIcon;
  return (
    <div
      className="flex flex-wrap items-start gap-3 rounded-[var(--radius-card)] border px-4 py-3"
      role={tone === 'danger' || tone === 'warning' ? 'alert' : 'note'}
      style={{
        borderColor: `color-mix(in srgb, ${color} 35%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${color} 7%, transparent)`,
      }}
    >
      <Icon aria-hidden="true" className="mt-0.5 size-4 shrink-0" style={{ color }} />
      <div className="min-w-0 flex-1">
        {title && <p className="text-[13px] font-semibold text-foreground">{title}</p>}
        {children && (
          <div className={cn('text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]', title && 'mt-0.5')}>
            {children}
          </div>
        )}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

/** A figure with a caption. */
export function Stat({
  label,
  value,
  hint,
  tone,
}: {
  label: string;
  value: React.ReactNode;
  hint?: string;
  tone?: 'success' | 'warning' | 'danger';
}) {
  const color = tone ? TONE[tone].color : undefined;
  return (
    <div className="rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3">
      <p className="text-[11.5px] font-semibold uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-1 whitespace-nowrap text-[20px] font-bold leading-none tabular-nums text-foreground" style={color ? { color } : undefined}>
        {value}
      </p>
      {hint && <p className="mt-1.5 text-[12px] text-muted-foreground">{hint}</p>}
    </div>
  );
}

export function StatGrid({ children, columns = 4 }: { children: React.ReactNode; columns?: 2 | 3 | 4 }) {
  const cols = { 2: 'sm:grid-cols-2', 3: 'sm:grid-cols-3', 4: 'sm:grid-cols-2 lg:grid-cols-4' }[columns];
  return <div className={cn('grid grid-cols-1 gap-3', cols)}>{children}</div>;
}

// ── Saved indicator ──────────────────────────────────────────────────────

/**
 * A quiet "Saved" that appears for a moment after a per-browser setting
 * changes. Per-browser settings apply instantly with no Save button, and an
 * instant change with no acknowledgement leaves the reader unsure it took.
 * Pass a value that changes whenever anything is edited (a counter, or the
 * prefs object) as `signal`.
 */
export function SavedFlash({ signal }: { signal: unknown }) {
  const [visible, setVisible] = useState(false);
  // Compared with the value last seen, not a "first render" flag: React runs an
  // effect twice on mount in development, and a flag flipped by the first run
  // made every panel announce "Saved" just for being opened.
  const seen = useRef(signal);
  useEffect(() => {
    if (Object.is(seen.current, signal)) return;
    seen.current = signal;
    setVisible(true);
    const t = setTimeout(() => setVisible(false), 1800);
    return () => clearTimeout(t);
  }, [signal]);
  return (
    <span
      aria-live="polite"
      className={cn(
        'inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-[12px] font-semibold transition-opacity duration-200',
        visible ? 'opacity-100' : 'opacity-0',
      )}
      style={{
        color: 'var(--color-system-success)',
        backgroundColor: 'color-mix(in srgb, var(--color-system-success) 10%, transparent)',
      }}
    >
      <Check aria-hidden="true" className="size-3.5" strokeWidth={3} />
      {visible ? 'Saved' : ''}
    </span>
  );
}

// ── Save bar ─────────────────────────────────────────────────────────────

/**
 * Where the page's top-right "Save changes" lives. The page owns the slot; a
 * panel's SaveBar drops its buttons into it while there is something unsaved, so
 * the primary action is always in the same corner whichever section is open.
 * With no slot (a panel shown on its own) it falls back to a floating bar.
 */
export const SaveSlotContext = createContext<HTMLElement | null>(null);

/**
 * For settings that go to the server, where a change is a decision and not a
 * preview. Appears only while there is something unsaved, so a form at rest
 * carries no chrome, and offers Discard as prominently as Save.
 */
export function SaveBar({
  dirty,
  saving,
  onSave,
  onDiscard,
  label = 'Save changes',
  message = 'You have unsaved changes.',
}: {
  dirty: boolean;
  saving: boolean;
  onSave: () => void;
  onDiscard: () => void;
  label?: string;
  message?: string;
}) {
  const slot = useContext(SaveSlotContext);
  if (!dirty) return null;

  const actions = (
    <span className="flex items-center gap-2">
      <Button disabled={saving} onClick={onDiscard} size="sm" type="button" variant="ghost">
        Discard
      </Button>
      <Button className="rounded-full px-5" disabled={saving} onClick={onSave} size="sm" type="button">
        <Save data-icon="inline-start" />
        {saving ? 'Saving…' : label}
      </Button>
    </span>
  );

  if (slot) {
    return createPortal(
      <div aria-label="Unsaved changes" className="flex items-center gap-3" data-save-active role="region">
        <span className="hidden items-center gap-2 text-[13px] font-medium text-foreground lg:flex">
          <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: 'var(--color-system-warning)' }} />
          {message}
        </span>
        {actions}
      </div>,
      slot,
    );
  }

  return (
    <div
      className="sticky bottom-4 z-10 flex flex-wrap items-center justify-between gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 shadow-[0_8px_30px_rgba(0,0,0,0.14)]"
      role="region"
      aria-label="Unsaved changes"
    >
      <span className="flex items-center gap-2 text-[13px] font-medium text-foreground">
        <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: 'var(--color-system-warning)' }} />
        {message}
      </span>
      {actions}
    </div>
  );
}

// ── Small pieces ─────────────────────────────────────────────────────────

/** A keyboard key, for shortcut lists. */
export function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex min-w-[22px] items-center justify-center rounded-md border border-[var(--color-surface-border)] border-b-2 bg-[var(--color-surface-raised)] px-1.5 py-0.5 font-mono text-[11.5px] font-semibold text-foreground">
      {children}
    </kbd>
  );
}

/** A status dot + word — colour is never the only signal. */
export function StatusDot({
  tone,
  children,
}: {
  tone: 'success' | 'warning' | 'danger' | 'neutral';
  children: React.ReactNode;
}) {
  const color = TONE[tone === 'neutral' ? 'neutral' : tone].color;
  return (
    <span className="inline-flex items-center gap-1.5 text-[13px] font-medium" style={{ color }}>
      <span aria-hidden="true" className="size-1.5 rounded-full" style={{ backgroundColor: color }} />
      {children}
    </span>
  );
}

// ── Navigation: tabs, section pills, search ──────────────────────────────

export interface RailItem {
  key: string;
  label: string;
  icon: LucideIcon;
  /** Words a person might type to look for this — beyond its label. */
  keywords?: string[];
}

export interface RailGroup {
  label: string;
  icon: LucideIcon;
  items: RailItem[];
}

/**
 * The tab strip: one tab per GROUP (Agency, Profile, Preferences, Support),
 * and — when the open group has more than one section — a row of pills under it
 * for the sections. Fifteen tabs in one strip would scroll off any screen; four
 * or five groups read at a glance, and each pill is one click from anywhere in
 * its group.
 */
export function SettingsTabs({
  groups,
  activeKey,
  onSelect,
}: {
  groups: RailGroup[];
  activeKey: string;
  onSelect: (key: string) => void;
}) {
  const activeGroup = groups.find(g => g.items.some(i => i.key === activeKey)) ?? groups[0];
  return (
    <nav aria-label="Settings sections" className="flex flex-col">
      <NavTabs
        activeKey={activeGroup.label}
        ariaLabel="Settings groups"
        idPrefix="settings-group"
        onSelect={label => {
          const g = groups.find(x => x.label === label);
          if (g && g !== activeGroup) onSelect(g.items[0].key);
        }}
        tabs={groups.map(g => ({ key: g.label, label: g.label, icon: g.icon }))}
      />

      {activeGroup.items.length > 1 && (
        <div
          aria-label={`${activeGroup.label} sections`}
          className="flex gap-2 overflow-x-auto py-4 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        >
          {activeGroup.items.map(item => {
            const active = item.key === activeKey;
            const Icon = item.icon;
            return (
              <button
                aria-current={active ? 'page' : undefined}
                className={cn(
                  'flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full border px-3.5 py-1.5 text-[13px] font-medium transition-colors',
                  active
                    ? 'border-transparent bg-[var(--color-brand-subtle)] text-[var(--color-brand)]'
                    : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-raised)] hover:text-foreground',
                )}
                key={item.key}
                onClick={() => onSelect(item.key)}
                type="button"
              >
                <Icon aria-hidden="true" className="size-3.5" />
                {item.label}
              </button>
            );
          })}
        </div>
      )}
    </nav>
  );
}

/** Find a section by any word a person might use for it. */
export function SettingsSearch({
  groups,
  onSelect,
}: {
  groups: RailGroup[];
  onSelect: (key: string) => void;
}) {
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  // "/" jumps to the search from anywhere on the page, the way it does in the
  // tools people already live in — unless they are already typing in a field.
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
      e.preventDefault();
      inputRef.current?.focus();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  // Every word typed has to match somewhere in the item's label, its group or
  // its keywords, so "sound alert" finds Notifications without the reader
  // having to know it lives there.
  const words = query.trim().toLowerCase().split(/\s+/).filter(Boolean);
  const results = words.length
    ? groups.flatMap(g =>
        g.items
          .filter(item => {
            const hay = [item.label, g.label, ...(item.keywords ?? [])].join(' ').toLowerCase();
            return words.every(w => hay.includes(w));
          })
          .map(item => ({ item, group: g.label })),
      )
    : [];

  function choose(key: string) {
    onSelect(key);
    setQuery('');
  }

  return (
    <div
      className="relative w-full sm:w-[300px]"
      data-page-search="true"
      onBlur={e => { if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setQuery(''); }}
    >
      <SearchInput
        hint={<Kbd>/</Kbd>}
        label="Search settings"
        onKeyDown={e => {
          if (e.key === 'Enter' && results[0]) choose(results[0].item.key);
          if (e.key === 'Escape') setQuery('');
        }}
        onValueChange={setQuery}
        placeholder="Search settings…"
        ref={inputRef}
        size="lg"
        value={query}
      />

      {words.length > 0 && (
        <div
          aria-label="Search results"
          className="absolute right-0 top-full z-30 mt-2 w-full min-w-[300px] overflow-hidden rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-overlay)] p-1.5 shadow-[0_12px_40px_rgba(0,0,0,0.16)]"
          role="listbox"
        >
          <p className="px-2.5 pb-1 pt-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">
            {results.length} {results.length === 1 ? 'result' : 'results'}
          </p>
          {results.length === 0 && (
            <p className="px-2.5 pb-2 text-[12.5px] text-muted-foreground">
              Nothing matches “{query.trim()}”. Try a shorter word.
            </p>
          )}
          {results.map(({ item, group }) => {
            const Icon = item.icon;
            return (
              <button
                className="flex w-full items-center gap-2.5 rounded-[10px] px-2.5 py-2 text-left text-[13.5px] font-medium text-foreground transition-colors hover:bg-[var(--color-surface-raised)] focus-visible:bg-[var(--color-surface-raised)] focus-visible:outline-none"
                key={item.key}
                onClick={() => choose(item.key)}
                role="option"
                aria-selected={false}
                type="button"
              >
                <Icon aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
                <span className="min-w-0 flex-1 truncate">{item.label}</span>
                <span className="shrink-0 text-[11.5px] font-normal text-muted-foreground">{group}</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
