import { cn } from '@/lib/utils';

/**
 * A filter control with its name above it, so no control on a filter bar has
 * to be guessed at from its icon or placeholder alone — the caption + control
 * pattern Operational Area's header established, shared wherever else a
 * filter row wants the same clarity (Incident Records, and any filter bar
 * after it). Usually paired with a `sm:flex-[N_1_minPx]` className so a row
 * of these fills its container edge-to-edge instead of huddling left with
 * dead space beside it — see callers for the exact ratios chosen.
 */
export function FilterField({
  label,
  aside,
  className,
  children,
}: {
  label: string;
  /** Sits opposite the label — e.g. the dates a period covers. */
  aside?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={cn('flex min-w-0 flex-col gap-1.5', className)}>
      <div className="flex items-center justify-between gap-3">
        <span className="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">{label}</span>
        {aside}
      </div>
      {children}
    </div>
  );
}
