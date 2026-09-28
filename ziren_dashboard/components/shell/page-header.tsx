'use client';

/**
 * PageHeader — the status line that opens every admin page.
 *
 * Takes a sentence, not a title. The topbar breadcrumb already names the
 * route, so a heading that repeats it ("Account Management" under a crumb
 * reading "Accounts") spends the largest type on the page telling the
 * operator where they just clicked. This says what is happening instead:
 *
 *     12 active incidents across 3 agencies. 2 critical, both BFP.
 *
 * Compose the sentence from plain text plus <Fig> for each number. The type
 * treatment lives in `.status-line` — prose recedes, figures carry weight —
 * so it reads as a sentence to someone arriving and scans as figures to
 * someone who already knows the shape of their shift.
 *
 * Geometry note: `--color-frame`, not `--color-surface-base`. This header
 * sits INSIDE the app frame, and the page-background token renders a
 * near-invisible seam against the frame interior in light mode and the wrong
 * value entirely in dark.
 */

import type { ReactNode } from 'react';

export interface PageHeaderProps {
  /** The status sentence. Compose with <Fig> around each number. */
  children: ReactNode;
  /** Buttons, filters — anything trailing on the right. */
  actions?: ReactNode;
  /** Small line under the sentence: last refresh, scope, record count. */
  meta?: ReactNode;
  /**
   * Sticks to the top of the scroll container. On by default — these pages
   * are long lists and the refresh control should stay reachable. Turn it
   * off where the page owns its own sticky region (tab bars).
   */
  sticky?: boolean;
}

export function PageHeader({
  children,
  actions,
  meta,
  sticky = true,
}: PageHeaderProps) {
  return (
    <header
      className={[
        sticky ? 'sticky top-0 z-10' : '',
        'border-b border-[var(--color-surface-border)]',
        'bg-[var(--color-frame)] px-6 py-5 md:px-7',
      ].join(' ')}
    >
      <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-3">
        {/* 74ch, not 58. The measure was set when the type ran to 25px, where
            58 characters was already a full line; at the current size that cap
            broke a two-clause sentence across two lines and left a two-word
            orphan. Still short of the ~80ch where a line becomes tiring to
            track back from. */}
        <p className="status-line min-w-0 max-w-[74ch]">{children}</p>
        {actions && <div className="flex shrink-0 items-center gap-2">{actions}</div>}
      </div>
      {meta && (
        <p className="mt-2.5 text-meta text-[var(--color-text-muted)]">{meta}</p>
      )}
    </header>
  );
}
