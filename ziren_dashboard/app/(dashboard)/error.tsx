'use client';

/**
 * A page that throws must not take the console down with it.
 *
 * With no boundary here, a render error on any one page bubbled past the
 * dashboard layout and unmounted it - and the layout is where the incident
 * alert lives. One broken page meant no new-report alarm on ANY page until a
 * reload. This boundary sits inside the layout, so the shell, the sidebar and
 * the alert keep running while only the broken page is replaced.
 */

import { useEffect } from 'react';
import { RotateCw, TriangleAlert } from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';

export default function DashboardPageError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error('dashboard page crashed', error);
  }, [error]);

  return (
    <div className="flex flex-1 items-center justify-center p-6">
      <div className="flex max-w-[440px] flex-col items-center gap-3 text-center">
        <span
          className="flex size-11 items-center justify-center rounded-full"
          style={{ backgroundColor: 'var(--color-severity-medium-bg)', color: 'var(--color-severity-medium)' }}
        >
          <TriangleAlert aria-hidden="true" className="size-5" />
        </span>
        <h2 className="text-[17px] font-semibold text-[var(--color-text-primary)]">
          This page could not load
        </h2>
        <p className="text-[13.5px] leading-relaxed text-[var(--color-text-secondary)]">
          New-report alerts are still running. Try the page again, or use the sidebar to keep working.
        </p>
        <Button onClick={reset} size="sm" variant="outline">
          <RotateCw data-icon="inline-start" />
          Try again
        </Button>
      </div>
    </div>
  );
}
