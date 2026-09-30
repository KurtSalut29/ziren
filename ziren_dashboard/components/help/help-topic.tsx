'use client';

/**
 * One help topic: a title row that opens to numbered steps, an optional tip
 * and a link to the page it is about.
 *
 * Shared by the Help page and the "Ask Ziren" dialog (ziren-help.tsx), so a
 * topic reads the same wherever it is opened.
 */

import Link from 'next/link';
import { ArrowRight, ChevronDown, Lightbulb } from 'lucide-react';
import type { HelpGroup, HelpTopic } from '@/lib/help/help-content';
import { Button } from '@/components/efferd/ui/button';
import { cn } from '@/lib/utils';

export function HelpTopicItem({
  topic,
  open,
  onToggle,
  onNavigate,
  currentPath,
}: {
  topic: HelpTopic;
  open: boolean;
  onToggle: () => void;
  /** Called when the topic's page link is followed, e.g. to close a dialog. */
  onNavigate?: () => void;
  /** The page being looked at: a link back to that same page is left out. */
  currentPath?: string;
}) {
  const bodyId = `help-${topic.id}`;
  const showLink = Boolean(topic.href) && topic.href !== currentPath;
  return (
    <li
      className={cn(
        'overflow-hidden rounded-[12px] border bg-[var(--color-surface-card)] transition-colors',
        open ? 'border-[color-mix(in_srgb,var(--color-brand)_45%,transparent)]' : 'border-[var(--color-surface-border)]',
      )}
    >
      <button
        aria-controls={bodyId}
        aria-expanded={open}
        className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-[var(--color-surface-hover)]"
        onClick={onToggle}
        type="button"
      >
        <span className="min-w-0 flex-1">
          <span className="block text-[14px] font-semibold text-foreground">{topic.title}</span>
          <span className="block text-[12.5px] text-muted-foreground">{topic.summary}</span>
        </span>
        <ChevronDown aria-hidden="true" className={cn('size-4 shrink-0 text-muted-foreground transition-transform', open && 'rotate-180')} />
      </button>
      {open && (
        <div className="border-t border-[var(--color-surface-border)] px-4 pb-4 pt-3" id={bodyId}>
          <ol className="flex flex-col gap-2.5">
            {topic.steps.map((step, i) => (
              <li className="flex gap-3 text-[13.5px] leading-relaxed text-foreground" key={i}>
                <span className="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-[var(--color-brand)] text-[11px] font-bold text-white">{i + 1}</span>
                <span>{step}</span>
              </li>
            ))}
          </ol>
          {topic.tip && (
            <p className="mt-3 flex gap-2 rounded-lg bg-[color-mix(in_srgb,var(--color-system-info)_9%,transparent)] px-3 py-2 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
              <Lightbulb aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-[var(--color-system-info)]" />
              {topic.tip}
            </p>
          )}
          {showLink && topic.href && (
            <Button asChild className="mt-3" size="sm">
              <Link href={topic.href} onClick={onNavigate}>
                {topic.hrefLabel ?? 'Open'} <ArrowRight data-icon="inline-end" size={14} />
              </Link>
            </Button>
          )}
        </div>
      )}
    </li>
  );
}

/** The groups, reduced to the topics that mention [query] anywhere. */
export function filterHelp(groups: HelpGroup[], query: string): HelpGroup[] {
  const q = query.trim().toLowerCase();
  if (!q) return groups;
  return groups
    .map(g => ({
      ...g,
      topics: g.topics.filter(t =>
        [t.title, t.summary, ...t.steps, t.tip ?? ''].join(' ').toLowerCase().includes(q)),
    }))
    .filter(g => g.topics.length > 0);
}
