import type { ReactNode } from 'react';
import { AlertCircle, CheckCircle2, Info, TriangleAlert } from 'lucide-react';

type AlertVariant = 'error' | 'warning' | 'success' | 'info';

interface AlertProps {
  variant?: AlertVariant;
  message: ReactNode;
  /** Optional bold lead-in above the message — TailAdmin's "Success Message" /
   * "Error Message" line. Most call sites are a single inline sentence and
   * skip it; pass it for a banner that deserves the fuller two-line shape. */
  title?: ReactNode;
}

// ── Alert variant config ──────────────────────────────────────
// All tokens reference the dark-shell system defined in globals.css.
// RULE: never use brand orange (--color-brand) here — these are
// system/status alerts, not actions.
const config: Record<
  AlertVariant,
  { bg: string; border: string; text: string; icon: React.ReactNode }
> = {
  error: {
    bg:     'bg-[var(--color-system-error-bg)]',
    border: 'border-[var(--color-system-error)]',
    text:   'text-[var(--color-system-error)]',
    icon:   <AlertCircle className="h-5 w-5 shrink-0" />,
  },
  warning: {
    bg:     'bg-[var(--color-system-warning-bg)]',
    border: 'border-[var(--color-system-warning)]',
    text:   'text-[var(--color-system-warning)]',
    icon:   <TriangleAlert className="h-5 w-5 shrink-0" />,
  },
  success: {
    bg:     'bg-[var(--color-system-success-bg)]',
    border: 'border-[var(--color-system-success)]',
    text:   'text-[var(--color-system-success)]',
    icon:   <CheckCircle2 className="h-5 w-5 shrink-0" />,
  },
  info: {
    bg:     'bg-[var(--color-system-info-bg)]',
    border: 'border-[var(--color-system-info)]',
    text:   'text-[var(--color-system-info)]',
    icon:   <Info className="h-5 w-5 shrink-0" />,
  },
};

export function Alert({ variant = 'error', message, title }: AlertProps) {
  const c = config[variant];
  return (
    <div
      className={`flex items-start gap-3 rounded-[var(--radius-lg)] border px-4 py-3.5 ${c.bg} ${c.border} border-opacity-30`}
      role="alert"
    >
      <span className={`-mt-0.5 ${c.text}`}>{c.icon}</span>
      <div className="min-w-0">
        {title && <p className="text-[13.5px] font-semibold leading-snug text-foreground">{title}</p>}
        <p className={title ? 'mt-0.5 text-[13px] leading-snug text-muted-foreground' : `text-[14px] leading-snug ${c.text}`}>
          {message}
        </p>
      </div>
    </div>
  );
}
