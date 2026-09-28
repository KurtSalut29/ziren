'use client';

/**
 * Pagination — TailAdmin's "Pagination with Text and Icon", the one pager
 * every paged list on this console should use instead of hand-rolling its own
 * Previous/Next row. Four screens (Audit Logs, Incident Records, Incident
 * Monitoring, the Narrative Report library) each wrote a slightly different
 * version of this before; this is the one shape, so a dispatcher who learns
 * it once recognises it everywhere.
 */

import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';
import { cn } from '@/lib/utils';

export function Pagination({
  page,
  pageCount,
  onPrevious,
  onNext,
  disabled = false,
  className,
  align = 'between',
}: {
  /** 1-indexed page number, for display only — "Page {page} of {pageCount}". */
  page: number;
  pageCount: number;
  onPrevious: () => void;
  onNext: () => void;
  disabled?: boolean;
  className?: string;
  /** 'between' puts the page label at the start and the buttons at the end —
   * a table's own footer row. 'center' groups the label between the two
   * buttons — a standalone pager under a list with no footer of its own. */
  align?: 'between' | 'center';
}) {
  if (pageCount <= 1) return null;
  const atStart = page <= 1;
  const atEnd = page >= pageCount;
  const label = <span className="text-meta text-muted-foreground">Page {page} of {pageCount}</span>;

  return (
    <div className={cn('flex items-center gap-3', align === 'center' ? 'justify-center' : 'justify-between', className)}>
      {align === 'between' && label}
      <div className="flex items-center gap-2">
        <Button disabled={atStart || disabled} onClick={onPrevious} size="sm" variant="outline">
          <ChevronLeft data-icon="inline-start" />
          Previous
        </Button>
        {align === 'center' && label}
        <Button disabled={atEnd || disabled} onClick={onNext} size="sm" variant="outline">
          Next
          <ChevronRight data-icon="inline-end" />
        </Button>
      </div>
    </div>
  );
}
