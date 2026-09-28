/**
 * Card — surface container used throughout the dashboard.
 *
 * Variants:
 *   default  — white card with border and hover shadow (incident rows, stat cards)
 *   raised   — slightly elevated, no hover effect (modal interiors, panels)
 *   flat     — no shadow, no border (embedded content, form sections)
 *
 * The optional `severityColor` prop draws the 4px left-side accent strip used on
 * incident cards to anchor severity at a glance — always paired with a badge/label
 * per the accessibility rule in globals.css.
 */

import { ReactNode } from 'react';
import { MoreHorizontal } from 'lucide-react';

interface CardProps {
  children: ReactNode;
  variant?: 'default' | 'raised' | 'flat';
  /** Hex or CSS var — draws a 4px left-strip accent for severity anchoring */
  severityColor?: string;
  className?: string;
  onClick?: () => void;
}

export function Card({
  children,
  variant = 'default',
  severityColor,
  className = '',
  onClick,
}: CardProps) {
  const base =
    'relative rounded-[20px] bg-[var(--color-surface-card)] overflow-hidden transition-[border-color,box-shadow]';

  const variants: Record<string, string> = {
    default:
      'border border-[var(--color-surface-border)] shadow-[var(--shadow-sm)] hover:shadow-[var(--shadow-md)]',
    raised:
      'border border-[var(--color-surface-border)] shadow-[var(--shadow-md)]',
    flat: '',
  };

  const interactive = onClick
    ? 'cursor-pointer hover:border-[var(--color-brand-container)]'
    : '';

  return (
    <div
      className={[base, variants[variant], interactive, className].join(' ')}
      onClick={onClick}
      role={onClick ? 'button' : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={
        onClick
          ? (e) => (e.key === 'Enter' || e.key === ' ') && onClick()
          : undefined
      }
    >
      {/* Severity left-strip — 4px left border accent */}
      {severityColor && (
        <div
          aria-hidden="true"
          className="absolute left-0 top-0 bottom-0 w-1"
          style={{ backgroundColor: severityColor }}
        />
      )}

      {/* Offset content when strip is present */}
      <div className={severityColor ? 'pl-1' : ''}>{children}</div>
    </div>
  );
}

/**
 * CardHeader — title + optional subtitle row inside a Card.
 */
export function CardHeader({
  title,
  subtitle,
  action,
  menu = false,
  onMenuClick,
  className = '',
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  /** Show a trailing "..." kebab button — visual affordance matching the reference design's card menus */
  menu?: boolean;
  onMenuClick?: () => void;
  className?: string;
}) {
  return (
    <div
      className={[
        'flex items-start justify-between gap-3 px-5 pt-5 pb-3',
        className,
      ].join(' ')}
    >
      <div className="min-w-0">
        <h3 className="text-h3 text-[var(--color-text-primary)] truncate">
          {title}
        </h3>
        {subtitle && (
          <p className="text-body-sm text-[var(--color-text-muted)] mt-0.5">
            {subtitle}
          </p>
        )}
      </div>
      {action && <div className="shrink-0">{action}</div>}
      {menu && !action && (
        <button
          type="button"
          onClick={onMenuClick}
          aria-label="Card options"
          className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[var(--color-text-muted)] transition-colors hover:bg-[var(--color-surface-raised)] hover:text-[var(--color-text-secondary)]"
        >
          <MoreHorizontal size={16} strokeWidth={2} />
        </button>
      )}
    </div>
  );
}

/**
 * CardBody — padded content area inside a Card.
 */
export function CardBody({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={['px-5 pb-5', className].join(' ')}>{children}</div>;
}

/**
 * CardFooter — bottom row, typically for actions.
 */
export function CardFooter({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={[
        'flex items-center gap-2 px-5 py-3 border-t border-[var(--color-surface-border)]',
        className,
      ].join(' ')}
    >
      {children}
    </div>
  );
}
