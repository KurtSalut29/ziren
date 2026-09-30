'use client';

/**
 * One choice in the incident dialog's action bar (Accept, Dispatch, Chat,
 * Reject, Cancel incident…).
 *
 * These used to be the console's small 28px buttons: an icon and one word.
 * The stations' feedback (2026-09-30) was that the bar looked unfinished for
 * the most consequential clicks in the whole product. Each choice is now a
 * proper target: an icon in its own tile and the action's name, with one short
 * line saying what pressing it means as its tooltip, so nobody has to guess the difference
 * between "Reject" and "Cancel incident".
 *
 * Two weights, and only two:
 *   solid  — the step that moves the report forward (Accept, Dispatch, Mark
 *            resolved). One per state, so the eye has one place to land.
 *   tinted — everything else: a wash of the action's colour with a matching
 *            border. Deliberate, but never competing with the solid one.
 *
 * The colour is passed in, not chosen here, because colour on this console
 * carries meaning (see globals.css) and the dialog owns which action gets
 * which.
 */

import Link from 'next/link';
import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

interface ActionButtonProps {
  icon: LucideIcon;
  label: string;
  /** What pressing this means, as the tooltip. A visible second line was
   * tried first and made the bar too heavy (the user: "masyadong malaki"). */
  hint: string;
  /** The action's colour, as a CSS colour or var(). */
  color: string;
  /** Solid fill, with this as the text colour on top of it. */
  solidText?: string;
  onClick?: () => void;
  /** Renders a link instead of a button. */
  href?: string;
  title?: string;
  /** Sits after the label: the Chat button's unread count. */
  children?: React.ReactNode;
}

export function ActionButton({
  icon: Icon, label, hint, color, solidText, onClick, href, title, children,
}: ActionButtonProps) {
  const solid = Boolean(solidText);
  const className = cn(
    'group/action inline-flex h-10 min-w-0 items-center gap-2 rounded-[11px] border py-0 pl-1.5 pr-3 text-left',
    'transition-[transform,box-shadow,background-color,filter] duration-150',
    // No lift on hover, and only a faint tint under the solid button: a wide
    // coloured glow was tried first and read as overdone on a dispatch
    // console ("masyadong OA").
    'active:scale-[0.98]',
    'sm:h-[38px] sm:shrink-0 sm:pr-3.5',
    // The console's focus ring is a box-shadow in a zero-specificity rule
    // (globals.css), which the shadows below would silently replace. Restated
    // here so a keyboard user still sees where they are.
    'outline-none focus-visible:!shadow-[0_0_0_2px_var(--color-surface-card),0_0_0_4px_var(--color-text-primary)]',
    solid
      ? 'border-transparent bg-[var(--act)] text-[var(--act-fg)] shadow-[0_1px_2px_rgba(16,24,40,0.10),0_3px_8px_-5px_var(--act)] hover:brightness-105 hover:shadow-[0_1px_2px_rgba(16,24,40,0.12),0_5px_10px_-5px_var(--act)]'
      : 'border-[color-mix(in_srgb,var(--act)_38%,transparent)] bg-[color-mix(in_srgb,var(--act)_8%,var(--color-surface-card))] text-[var(--act)] shadow-[0_1px_2px_rgba(16,24,40,0.05)] hover:border-[color-mix(in_srgb,var(--act)_60%,transparent)] hover:bg-[color-mix(in_srgb,var(--act)_15%,var(--color-surface-card))]',
  );
  const style = { '--act': color, '--act-fg': solidText ?? color } as React.CSSProperties;

  const content = (
    <>
      <span
        aria-hidden
        className={cn(
          'flex size-[26px] shrink-0 items-center justify-center rounded-[7px]',
          solid
            ? 'bg-[color-mix(in_srgb,var(--act-fg)_20%,transparent)]'
            : 'bg-[color-mix(in_srgb,var(--act)_15%,transparent)]',
        )}
      >
        <Icon className="size-[15px]" strokeWidth={2.5} />
      </span>
      <span className="flex min-w-0 items-center whitespace-nowrap text-[13px] font-bold leading-none">
        {label}
        {children}
      </span>
    </>
  );

  if (href) {
    return (
      <Link className={className} data-action-weight={solid ? 'solid' : 'tinted'} href={href} style={style} title={title ?? hint}>
        {content}
      </Link>
    );
  }
  return (
    <button
      className={className}
      data-action-weight={solid ? 'solid' : 'tinted'}
      onClick={onClick}
      style={style}
      title={title ?? hint}
      type="button"
    >
      {content}
    </button>
  );
}
