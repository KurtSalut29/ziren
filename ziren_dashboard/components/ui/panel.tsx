/**
 * Panel — a flat bordered content block.
 *
 * The restyle rule in globals.css is that cards carry a 1px border and no
 * shadow; elevation is reserved for popovers, so that a raised surface still
 * means "this floats above the page" when a menu opens. The existing Card
 * component predates that rule and its default variant still applies
 * shadow-sm/shadow-md on hover, which is why several pages ended up wrapping
 * a `variant="flat"` Card around a hand-rolled bordered div to opt out.
 *
 * Panel is that pattern, named. Use it for page content blocks; keep Card for
 * the pre-restyle surfaces that still depend on its variants.
 */

import type { ReactNode } from 'react';

export function Panel({
  title,
  subtitle,
  action,
  children,
  className = '',
  bodyClassName = 'px-5 pb-5',
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
  bodyClassName?: string;
}) {
  return (
    <section
      className={[
        'flex flex-col overflow-hidden rounded-[var(--radius-card)]',
        'border border-[var(--color-surface-border)] bg-[var(--color-surface-card)]',
        className,
      ].join(' ')}
    >
      {(title || action) && (
        <div className="flex items-start justify-between gap-3 px-5 pb-3 pt-4">
          <div className="min-w-0">
            {title && (
              <h2 className="text-card-title truncate text-[var(--color-text-primary)]">
                {title}
              </h2>
            )}
            {subtitle && (
              <p className="mt-0.5 truncate text-meta text-[var(--color-text-muted)]">
                {subtitle}
              </p>
            )}
          </div>
          {action && <div className="shrink-0">{action}</div>}
        </div>
      )}
      <div className={bodyClassName}>{children}</div>
    </section>
  );
}

/**
 * Skeleton — a loading placeholder.
 *
 * Uses --color-surface-raised rather than a literal Tailwind grey. The pages
 * that hardcoded `bg-neutral-100` rendered a near-white block on a #171717
 * card under the dark theme, so every dark-mode load flashed bright panels
 * where the content was about to appear.
 */
export function Skeleton({
  className = '',
  rounded = 'var(--radius-card)',
}: {
  className?: string;
  rounded?: string;
}) {
  return (
    <div
      className={`animate-pulse bg-[var(--color-surface-raised)] ${className}`}
      style={{ borderRadius: rounded }}
    />
  );
}
