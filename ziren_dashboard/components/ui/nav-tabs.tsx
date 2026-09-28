'use client';

/**
 * NavTabs — the view switcher of the console. Every place that says "this
 * screen has several views, pick one" (Geographic Overview, Accounts,
 * Verification, System Governance, System Analytics) renders through here, so
 * navigation looks and behaves the same wherever it appears.
 *
 * What it owes a reader who has never seen it:
 *   - It reads as NAVIGATION, not as a caption. Each view has an icon and a
 *     label in a readable ink (not the washed-out muted grey that marks
 *     disabled text), the whole tab is the click target and lights up on
 *     hover, and a rule runs the full width of the bar with the current view's
 *     orange underline sitting ON that rule — the same mark the sidebar's
 *     active item uses, so "orange = where you are" holds everywhere.
 *   - The tabs are centred in their bar, so the bar has a middle and reads as
 *     one control instead of a list that happens to start at the left edge.
 *   - The active tab's label stays a text colour: orange text at this size is
 *     under 4.5:1 against the card. The underline and the icon carry the hue.
 *   - A bar wider than its space scrolls, and says so with a soft fade at the
 *     edge that still has tabs beyond it; the active tab is scrolled into view
 *     so a deep link to a far tab does not open on a bar hiding it.
 *   - Arrow keys move between tabs (Home/End jump); Enter or Space opens the
 *     focused one. Only the active tab is a tab stop, as a tab list should be.
 *     Opening is deliberate rather than on focus: some views mount a map.
 *
 * A tab renders as a Link when it carries an `href` (Governance's tabs are real
 * sub-routes) and as a button otherwise.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

export interface NavTabItem {
  key: string;
  label: string;
  icon?: LucideIcon;
  /** One line on what the view is for — the native tooltip. */
  hint?: string;
  /** A count worth a glance, drawn as an amber pill after the label. */
  badge?: number;
  /** Replaces `hint` in the tooltip (the badge says what it counts). */
  title?: string;
  /** Makes the tab a route link instead of a button. */
  href?: string;
}

/** How far in from the strip's edge the active tab is kept — clear of the 40px fade. */
const EDGE = 40;

export function NavTabs({
  tabs,
  activeKey,
  onSelect,
  ariaLabel,
  panelId,
  idPrefix = 'nav-tab',
  className,
  framed = true,
}: {
  tabs: NavTabItem[];
  activeKey: string;
  /** Omit when every tab carries its own `href`. */
  onSelect?: (key: string) => void;
  ariaLabel: string;
  /** The id of the tabpanel these tabs control, when there is one. */
  panelId?: string;
  /** Tab ids are `${idPrefix}-${key}` — what the panel's aria-labelledby points at. */
  idPrefix?: string;
  className?: string;
  /** Draws the full-width rule under the tabs. Off where the bar already sits on a border of its own (a card's foot). */
  framed?: boolean;
}) {
  const scroller = useRef<HTMLDivElement>(null);
  const [fade, setFade] = useState({ left: false, right: false });

  const measure = useCallback(() => {
    const el = scroller.current;
    if (!el) return;
    const left = el.scrollLeft > 4;
    const right = el.scrollLeft + el.clientWidth < el.scrollWidth - 4;
    setFade(f => (f.left === left && f.right === right ? f : { left, right }));
  }, []);

  useEffect(() => {
    measure();
    const el = scroller.current;
    if (!el || typeof ResizeObserver === 'undefined') return;
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, [measure, tabs.length]);

  // A count appearing on a tab widens it and pushes every tab after it to the right — so
  // "where the active tab is" has to be worked out again when that happens, not only when
  // the active tab changes.
  const layoutKey = tabs.map(t => `${t.key}:${t.badge ?? 0}`).join('|');

  // Bring the active tab into view — sideways only, so this can never move the page.
  useEffect(() => {
    const el = scroller.current;
    const tab = el?.querySelector<HTMLElement>('[aria-selected="true"]');
    if (!el || !tab) return;
    const start = tab.offsetLeft;
    const end = start + tab.offsetWidth;
    if (start < el.scrollLeft + EDGE) el.scrollTo({ left: Math.max(0, start - EDGE) });
    else if (end > el.scrollLeft + el.clientWidth - EDGE) el.scrollTo({ left: end - el.clientWidth + EDGE });
  }, [activeKey, layoutKey]);

  function onKeyDown(e: React.KeyboardEvent) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) return;
    const all = Array.from(scroller.current?.querySelectorAll<HTMLElement>('[role="tab"]') ?? []);
    const at = all.indexOf(document.activeElement as HTMLElement);
    if (at < 0) return;
    e.preventDefault();
    const to = e.key === 'Home' ? 0
      : e.key === 'End' ? all.length - 1
      : (at + (e.key === 'ArrowRight' ? 1 : -1) + all.length) % all.length;
    all[to]?.focus();
  }

  return (
    <div className={cn('relative', framed && 'border-b border-[var(--color-border-strong)]', className)}>
      <div
        aria-label={ariaLabel}
        className="overflow-x-auto px-3 [scrollbar-width:none] sm:px-4 [&::-webkit-scrollbar]:hidden"
        onKeyDown={onKeyDown}
        onScroll={measure}
        ref={scroller}
        role="tablist"
      >
        {/* Auto margins, not justify-center: when the tabs are wider than the bar the margins
            collapse to zero and the bar scrolls from its left edge, where justify-center would
            push the first tab out of reach. */}
        <div className="mx-auto flex w-max gap-1">
          {tabs.map(t => {
            const active = t.key === activeKey;
            const Icon = t.icon;
            const tabClass = cn(
              'relative flex shrink-0 cursor-pointer items-center gap-2 whitespace-nowrap rounded-t-[var(--radius-control)] px-4 py-3.5 text-[13.5px] transition-colors',
              // The page-wide focus ring is an outer glow; inside a scrolling strip it would be
              // clipped top and bottom, so the ring sits inside the tab instead.
              'focus-visible:outline-none focus-visible:[box-shadow:inset_0_0_0_2px_var(--color-brand)]',
              active
                ? 'font-semibold text-foreground'
                : 'font-medium text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
            );
            const content = (
              <>
                {Icon && (
                  <Icon
                    aria-hidden="true"
                    className={cn('size-4 shrink-0', active ? 'text-[var(--color-brand)]' : 'text-[var(--color-text-tertiary)]')}
                  />
                )}
                {t.label}
                {!!t.badge && (
                  // TailAdmin's "Tab with badge" — a brand-tinted pill, not an
                  // alert colour. The count is a quantity to glance at, not a
                  // warning; amber here would compete with the one meaning
                  // amber already carries elsewhere in this app (a negative
                  // KPI delta, a "busy" presence dot).
                  <span
                    className="inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-full px-1.5 text-[10.5px] font-bold leading-none"
                    style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
                  >
                    {t.badge}
                  </span>
                )}
                {active && (
                  <span
                    aria-hidden="true"
                    className="absolute inset-x-0 bottom-0 h-[3px] rounded-t-full bg-[var(--color-brand)]"
                  />
                )}
              </>
            );
            const shared = {
              'aria-selected': active,
              className: tabClass,
              id: `${idPrefix}-${t.key}`,
              role: 'tab' as const,
              tabIndex: active ? 0 : -1,
              title: t.title ?? t.hint,
            };
            return t.href ? (
              <Link {...shared} aria-controls={panelId} href={t.href} key={t.key}>
                {content}
              </Link>
            ) : (
              <button {...shared} aria-controls={panelId} key={t.key} onClick={() => onSelect?.(t.key)} type="button">
                {content}
              </button>
            );
          })}
        </div>
      </div>

      {fade.left && (
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-y-0 left-0 w-10"
          style={{ backgroundImage: 'linear-gradient(to right, var(--color-surface-card), transparent)' }}
        />
      )}
      {fade.right && (
        <span
          aria-hidden="true"
          className="pointer-events-none absolute inset-y-0 right-0 w-10"
          style={{ backgroundImage: 'linear-gradient(to left, var(--color-surface-card), transparent)' }}
        />
      )}
    </div>
  );
}
