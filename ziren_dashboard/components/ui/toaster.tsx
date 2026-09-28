'use client';

/**
 * Toaster - renders every toast, in one fixed place, above everything.
 *
 * WHERE IT SITS, AND WHY
 *
 * Top-centre, just under the header bar. It is in the middle of what the
 * operator is already looking at, and - unlike the top-right corner - it does
 * not sit on the close button every dialog in this app keeps there. It is
 * clear of the sidebar on the left and of the bottom-of-screen status bars
 * some pages pin. It is NOT inside any page, card or dialog: a message
 * rendered in one of those goes out of sight when the container scrolls or
 * closes, which was the fault this replaces.
 *
 * z-[3000] clears the Radix dialogs (z-[1100]) and the incident interrupt
 * (z-[2000]), so "Report rejected." is readable while the dialog that raised
 * it is still open, and so an error is never hidden behind the thing that
 * caused it.
 *
 * `pointer-events: auto` on each card is deliberate. A Radix modal sets
 * `pointer-events: none` on <body> while it is open, and that is inherited by
 * everything outside the dialog - without the override the close button on a
 * toast would be dead exactly when a dialog is showing.
 *
 * Severity is never colour alone: each kind has its own icon as well as its
 * own tint.
 */

import { AnimatePresence, motion } from 'framer-motion';
import { CheckCircle2, AlertCircle, Info, TriangleAlert, X } from 'lucide-react';
import { toast, useToasts, type ToastItem, type ToastKind } from '@/lib/toast';

const KIND: Record<ToastKind, { color: string; bg: string; Icon: typeof Info; label: string }> = {
  success: { color: 'var(--color-system-success)', bg: 'var(--color-system-success-bg)', Icon: CheckCircle2, label: 'Success' },
  error:   { color: 'var(--color-system-error)',   bg: 'var(--color-system-error-bg)',   Icon: AlertCircle,  label: 'Error' },
  warning: { color: 'var(--color-system-warning)', bg: 'var(--color-system-warning-bg)', Icon: TriangleAlert, label: 'Warning' },
  info:    { color: 'var(--color-system-info)',    bg: 'var(--color-system-info-bg)',    Icon: Info,          label: 'Notice' },
};

export function Toaster() {
  const items = useToasts();

  return (
    <div
      // A live region that is always mounted, so a screen reader is already
      // listening when the first toast arrives. `aria-live` also exempts it
      // from the aria-hidden a Radix dialog puts on everything outside itself.
      aria-live="polite"
      aria-atomic="false"
      className="pointer-events-none fixed inset-x-3 top-[68px] z-[3000] mx-auto flex max-w-[440px] flex-col items-stretch gap-2"
      data-toaster=""
    >
      <AnimatePresence initial={false}>
        {items.map(t => (
          <ToastCard item={t} key={t.id} />
        ))}
      </AnimatePresence>
    </div>
  );
}

function ToastCard({ item }: { item: ToastItem }) {
  const { color, bg, Icon, label } = KIND[item.kind];

  return (
    <motion.div
      animate={{ opacity: 1, y: 0, scale: 1 }}
      className="pointer-events-auto relative w-full overflow-hidden rounded-[12px] border shadow-[var(--shadow-lg)]"
      exit={{ opacity: 0, x: 24, transition: { duration: 0.15 } }}
      initial={{ opacity: 0, y: -10, scale: 0.98 }}
      layout
      role={item.kind === 'error' ? 'alert' : 'status'}
      style={{
        backgroundColor: 'var(--color-surface-card)',
        borderColor: 'var(--color-surface-border)',
      }}
      transition={{ duration: 0.18, ease: [0.16, 1, 0.3, 1] }}
    >
      <div className="flex items-start gap-3 py-3 pl-3.5 pr-2">
        <span
          aria-hidden="true"
          className="mt-px flex size-7 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: bg, color }}
        >
          <Icon size={16} />
        </span>

        <div className="min-w-0 flex-1 pt-0.5">
          {/* The word as well as the colour and the icon. */}
          <span className="sr-only">{label}: </span>
          <p
            className="text-[13.5px] font-medium leading-snug break-words"
            style={{ color: 'var(--color-text-primary)' }}
          >
            {item.message}
          </p>
          {item.detail && (
            <p
              className="mt-0.5 text-[12.5px] leading-snug break-words"
              style={{ color: 'var(--color-text-secondary)' }}
            >
              {item.detail}
            </p>
          )}
          {item.action && (
            <button
              className="mt-1.5 text-[12.5px] font-semibold underline-offset-2 hover:underline"
              onClick={() => { item.action?.onClick(); toast.dismiss(item.id); }}
              style={{ color }}
              type="button"
            >
              {item.action.label}
            </button>
          )}
        </div>

        <button
          aria-label="Dismiss message"
          className="flex size-7 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-[var(--color-surface-raised)]"
          onClick={() => toast.dismiss(item.id)}
          style={{ color: 'var(--color-text-muted)' }}
          type="button"
        >
          <X size={14} />
        </button>
      </div>

      {/* The countdown. Its length IS the time the toast has left, so nobody
          has to guess whether it is about to go. Keyed on the stamp so a
          repeated message restarts it. */}
      <motion.div
        animate={{ scaleX: 0 }}
        aria-hidden="true"
        className="h-[3px] origin-left"
        initial={{ scaleX: 1 }}
        key={`bar-${item.id}-${item.stamp}`}
        style={{ backgroundColor: color, opacity: 0.55 }}
        transition={{ duration: item.duration / 1000, ease: 'linear' }}
      />
    </motion.div>
  );
}
