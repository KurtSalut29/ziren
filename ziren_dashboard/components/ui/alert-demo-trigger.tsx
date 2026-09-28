'use client';

/**
 * AlertDemoTrigger — fires the incident interrupt on demand.
 *
 * WHY THIS EXISTS
 *
 * The interrupt only appears when a resident files a report, which makes it
 * the one feature in this console that cannot be shown to anyone without
 * either waiting for an emergency or staging one from a phone. That is a bad
 * position to be in during a demonstration, and a worse one during
 * development, where seeing the overlay meant editing a mock and reloading.
 *
 * WHY IT IS SAFE
 *
 * Gated on NEXT_PUBLIC_ENABLE_ALERT_DEMO rather than NODE_ENV, so it can be
 * turned on in a production build too (that's the whole point — a person
 * asking "does this actually work" wants the real console, not a recording
 * of one) without every future production deploy carrying it by default: the
 * flag defaults off, and a real dispatch console simply never sets it.
 *
 * It also cannot fake an incident into the system. It only pushes rows into
 * the alert hook's in-memory pending list, replaying REAL reports already in
 * this agency's queue — nothing is written, no report is created, and
 * dismissing the demo leaves the database exactly as it was.
 */

import { useState } from 'react';
import { Play, X } from 'lucide-react';

const PRESETS = [
  { n: 1, label: '1 report',  hint: 'the plain case' },
  { n: 3, label: '3 reports', hint: 'spotlight + the tray beside it' },
  { n: 7, label: '7 reports', hint: 'a tray long enough to scroll' },
];

export function AlertDemoTrigger({
  onSimulate,
}: {
  onSimulate: (count: number) => void;
}) {
  const [hidden, setHidden] = useState(false);

  if (process.env.NEXT_PUBLIC_ENABLE_ALERT_DEMO !== 'true' || hidden) return null;

  return (
    <div className="pointer-events-none fixed bottom-5 left-1/2 z-40 -translate-x-1/2">
      <div
        className="pointer-events-auto flex items-center gap-2 rounded-full border px-2 py-1.5 shadow-[var(--shadow-md)]"
        style={{
          borderColor: 'var(--color-surface-border)',
          backgroundColor: 'var(--color-surface-card)',
        }}
      >
        <span
          className="flex items-center gap-1.5 pl-2 pr-1 text-[11px] font-bold uppercase tracking-wide"
          style={{ color: 'var(--color-text-muted)' }}
        >
          <Play size={11} />
          Demo
        </span>

        {PRESETS.map(p => (
          <button
            className="rounded-full px-3 py-1.5 text-[12px] font-semibold transition-colors hover:bg-[var(--color-surface-raised)]"
            key={p.n}
            onClick={() => onSimulate(p.n)}
            style={{ color: 'var(--color-text-secondary)' }}
            title={p.hint}
            type="button"
          >
            {p.label}
          </button>
        ))}

        <button
          aria-label="Hide the demo trigger"
          className="flex size-6 items-center justify-center rounded-full transition-colors hover:bg-[var(--color-surface-raised)]"
          onClick={() => setHidden(true)}
          style={{ color: 'var(--color-text-muted)' }}
          type="button"
        >
          <X size={13} />
        </button>
      </div>
    </div>
  );
}
