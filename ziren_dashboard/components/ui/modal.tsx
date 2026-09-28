/**
 * Modal — accessible overlay dialog for confirm actions, detail views,
 * and form flows (e.g. dispatch confirm, rubric upload, station create).
 *
 * Built on a native <dialog>-style pattern using a portal-free approach
 * (fixed overlay + flex centering) to avoid hydration mismatches in Next.js
 * App Router. Mark the parent page 'use client' when using Modal.
 *
 * Props:
 *   open       — controls visibility
 *   onClose    — called when backdrop is clicked or Escape is pressed
 *   title      — modal heading
 *   size       — sm (400px) | md (540px) | lg (720px)
 *   children   — modal body
 *   footer     — action row (rendered below a divider)
 *
 * Destructive actions: use the Button danger variant in the footer and
 * require a separate confirm step — never allow a destructive action on
 * first click (per design prompt section 6).
 *
 * Accessibility:
 *   - role="dialog" + aria-modal="true"
 *   - aria-labelledby pointing at the title
 *   - Escape key closes
 *   - Focus trap is not implemented here — add focus-trap-react if needed
 *     for production. For the defense demo context, Escape + backdrop close
 *     is sufficient.
 */

'use client';

import { ReactNode, useEffect, useId } from 'react';
import { X } from 'lucide-react';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  size?: 'sm' | 'md' | 'lg';
  children: ReactNode;
  footer?: ReactNode;
}

const SIZE_CLASS: Record<string, string> = {
  sm: 'max-w-[400px]',
  md: 'max-w-[540px]',
  lg: 'max-w-[720px]',
};

export function Modal({
  open,
  onClose,
  title,
  size = 'md',
  children,
  footer,
}: ModalProps) {
  const titleId = useId();

  // Close on Escape key
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [open, onClose]);

  // Prevent body scroll while open
  useEffect(() => {
    document.body.style.overflow = open ? 'hidden' : '';
    return () => { document.body.style.overflow = ''; };
  }, [open]);

  if (!open) return null;

  return (
    /* Backdrop */
    <div
      // See components/efferd/ui/alert-dialog.tsx for why this is 1100, not
      // 50: it must clear the map overlay panels' z-[999]/z-[1000].
      className="fixed inset-0 z-[1100] flex items-center justify-center p-4"
      style={{ backgroundColor: 'rgba(0,0,0,0.35)' }}
      onClick={(e) => {
        // Close only if backdrop itself was clicked, not the dialog
        if (e.target === e.currentTarget) onClose();
      }}
      aria-hidden={!open}
    >
      {/* Dialog panel */}
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className={[
          'relative w-full flex flex-col',
          'bg-[var(--color-surface-overlay)]',
          'rounded-[var(--radius-xl)]',
          'shadow-[var(--shadow-lg)]',
          'border border-[var(--color-surface-border)]',
          'max-h-[90vh]',
          SIZE_CLASS[size],
        ].join(' ')}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-5 pb-4 border-b border-[var(--color-surface-border)] shrink-0">
          <h2
            id={titleId}
            className="text-h2 text-[var(--color-text-primary)] leading-tight"
          >
            {title}
          </h2>
          <button
            onClick={onClose}
            className={[
              'flex items-center justify-center',
              'w-8 h-8 rounded-[var(--radius-md)]',
              'text-[var(--color-text-muted)]',
              'hover:bg-[var(--color-surface-raised)]',
              'hover:text-[var(--color-text-secondary)]',
              'transition-colors',
              'focus:outline-none focus:ring-2 focus:ring-[var(--color-brand)]',
            ].join(' ')}
            aria-label="Close dialog"
          >
            <X size={18} strokeWidth={2} />
          </button>
        </div>

        {/* Body — scrollable */}
        <div className="flex-1 overflow-y-auto px-6 py-5 min-h-0">
          {children}
        </div>

        {/* Footer — action row */}
        {footer && (
          <div className="flex items-center justify-end gap-3 px-6 py-4 border-t border-[var(--color-surface-border)] shrink-0">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
}
