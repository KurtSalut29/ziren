import { parseHotlines } from '@/lib/format/hotlines';
import { cn } from '@/lib/utils';

/**
 * A station's hotline numbers, each its own tel: link — "Globe 0955-723-6300 ·
 * Smart 0948-024-3466". Falls back to the raw text when nothing in it parses,
 * so an unusual value is still shown rather than hidden.
 */
export function HotlineLinks({ value, className }: { value: string | null | undefined; className?: string }) {
  const numbers = parseHotlines(value);
  if (numbers.length === 0) return value ? <span className={className}>{value}</span> : null;
  return (
    <span className={cn('inline-flex flex-wrap items-center gap-x-3 gap-y-1', className)}>
      {numbers.map(n => (
        <a
          className="inline-flex items-baseline gap-1 tabular-nums underline-offset-2 hover:underline"
          href={`tel:${n.dial}`}
          key={n.dial}
        >
          {n.label && <span className="text-[11.5px] font-medium text-muted-foreground no-underline">{n.label}</span>}
          <span>{n.display}</span>
        </a>
      ))}
    </span>
  );
}
