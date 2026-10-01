'use client';

/**
 * Help's two ways in — the written step-by-step topics, or a demo where the
 * mascot walks through a page — and the list of demos for the caller's role.
 * Shared by the "Ask Ziren" dialog and the full Help page.
 */

import Image from 'next/image';
import { ListOrdered, Play, PlayCircle } from 'lucide-react';
import type { DemoScript } from '@/lib/help/demo-types';
import { cn } from '@/lib/utils';

export type HelpMode = 'steps' | 'demo';

export function HelpModeSwitch({ mode, onChange }: { mode: HelpMode; onChange: (m: HelpMode) => void }) {
  return (
    <div aria-label="How to get help" className="grid grid-cols-2 gap-2" role="radiogroup">
      <ModeCard
        caption="Read the guides"
        icon={ListOrdered}
        onClick={() => onChange('steps')}
        selected={mode === 'steps'}
        testId="help-mode-steps"
        title="Step by step"
      />
      <ModeCard
        caption="Ziren shows you"
        icon={PlayCircle}
        onClick={() => onChange('demo')}
        selected={mode === 'demo'}
        testId="help-mode-demo"
        title="Demo"
      />
    </div>
  );
}

function ModeCard({
  title,
  caption,
  icon: Icon,
  selected,
  onClick,
  testId,
}: {
  title: string;
  caption: string;
  icon: typeof Play;
  selected: boolean;
  onClick: () => void;
  testId: string;
}) {
  return (
    <button
      aria-checked={selected}
      className={cn(
        'flex items-center gap-3 rounded-xl border px-3 py-2.5 text-left transition-colors',
        selected
          ? 'border-[var(--color-brand)] bg-[color-mix(in_srgb,var(--color-brand)_10%,var(--color-surface-card))] shadow-[0_0_0_1px_var(--color-brand)]'
          : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] hover:bg-[var(--color-surface-hover)]',
      )}
      data-testid={testId}
      onClick={onClick}
      role="radio"
      type="button"
    >
      <span
        className={cn(
          'flex size-9 shrink-0 items-center justify-center rounded-full',
          selected ? 'bg-[var(--color-brand)] text-white' : 'bg-[var(--color-brand-subtle)] text-[var(--color-brand)]',
        )}
      >
        <Icon aria-hidden="true" className="size-[18px]" />
      </span>
      <span className="min-w-0">
        <span className="block text-[14px] font-extrabold leading-tight text-foreground">{title}</span>
        <span className="block text-[12px] leading-snug text-muted-foreground">{caption}</span>
      </span>
    </button>
  );
}

/**
 * The demos: the one for the page being looked at first (when there is one),
 * then every other page. Choosing one goes to that page and starts it.
 */
export function DemoList({
  demos,
  here,
  onStart,
}: {
  demos: DemoScript[];
  here?: DemoScript;
  onStart: (d: DemoScript) => void;
}) {
  const others = demos.filter(d => d.id !== here?.id);
  return (
    <div className="flex flex-col gap-5" data-testid="demo-list">
      <div className="flex items-end gap-2">
        <Image
          alt=""
          aria-hidden="true"
          className="h-[86px] w-auto shrink-0 select-none object-contain drop-shadow-[0_4px_6px_rgba(0,0,0,0.25)]"
          height={172}
          src="/demo/point_right.png"
          width={136}
        />
        <p className="relative mb-2 min-w-0 flex-1 rounded-2xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-2.5 text-[13.5px] font-semibold leading-relaxed text-foreground shadow-[var(--shadow-card)]">
          Pick a page and I will take you there and show you how to use it, one part at a time. Nothing is changed — the page cannot be clicked while I talk.
        </p>
      </div>

      {here && (
        <section>
          <h3 className="mb-2 text-[11.5px] font-semibold uppercase tracking-wider text-[var(--color-brand)]">On this page</h3>
          <button
            className="group flex w-full items-center gap-4 rounded-2xl border-2 border-[var(--color-brand)] bg-[color-mix(in_srgb,var(--color-brand)_8%,var(--color-surface-card))] p-4 text-left transition-colors hover:bg-[color-mix(in_srgb,var(--color-brand)_14%,var(--color-surface-card))]"
            data-testid={`demo-${here.id}`}
            onClick={() => onStart(here)}
            type="button"
          >
            <span className="min-w-0 flex-1">
              <span className="block text-[16px] font-extrabold text-foreground">{here.title}</span>
              <span className="block text-[13px] text-muted-foreground">{here.summary}</span>
              <span className="mt-1 block text-[12px] font-semibold text-[var(--color-brand)]">{here.steps.length} steps</span>
            </span>
            <span className="flex h-10 shrink-0 items-center gap-1.5 rounded-xl bg-[var(--color-brand)] px-4 text-[13.5px] font-extrabold text-white shadow-[0_4px_12px_rgba(252,90,5,0.35)] group-hover:brightness-110">
              <Play className="size-4 fill-current" /> Start demo
            </span>
          </button>
        </section>
      )}

      <section>
        <h3 className="mb-2 text-[11.5px] font-semibold uppercase tracking-wider text-muted-foreground">
          {here ? 'Other pages' : 'Pages'}
        </h3>
        <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2">
          {others.map(d => (
            <li key={d.id}>
              <button
                className="group flex w-full items-center gap-3 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2.5 text-left transition-colors hover:border-[color-mix(in_srgb,var(--color-brand)_45%,transparent)] hover:bg-[var(--color-surface-hover)]"
                data-testid={`demo-${d.id}`}
                onClick={() => onStart(d)}
                type="button"
              >
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[13.5px] font-bold text-foreground">{d.title}</span>
                  <span className="block truncate text-[12px] text-muted-foreground">{d.summary}</span>
                </span>
                <span className="flex size-8 shrink-0 items-center justify-center rounded-full bg-[var(--color-brand-subtle)] text-[var(--color-brand)] transition-colors group-hover:bg-[var(--color-brand)] group-hover:text-white">
                  <Play className="size-3.5 fill-current" />
                </span>
              </button>
            </li>
          ))}
        </ul>
      </section>
    </div>
  );
}
