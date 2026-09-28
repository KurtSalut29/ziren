'use client';

/**
 * AuthShell — shared centered auth container for /login and /signup.
 *
 * Replaces the old split-screen (brand panel + form panel) layout with a
 * single centered column on an ambient background — the pattern used by
 * Linear, Vercel, and Raycast for auth in 2026 rather than a marketing
 * side-panel. Logo + wordmark sit above a card; ambient dot-grid + soft
 * brand-color glow give it depth without competing with the form.
 */

import { motion } from 'framer-motion';
import type { ReactNode } from 'react';

import { ZirenLogo } from '@/components/brand/ziren-logo';

export function AuthShell({
  eyebrow,
  children,
  footer,
  maxWidth = 440,
}: {
  /** Small uppercase label above the logo, e.g. "Dispatch Portal" */
  eyebrow: string;
  children: ReactNode;
  footer?: ReactNode;
  maxWidth?: number;
}) {
  return (
    <main
      className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-6 py-16"
      // #0f1016 is measured, not picked: it is the colour the artwork's own
      // bottom edge settles to. Because the two match, the image can be laid
      // across the top at full width and the page simply CONTINUES into flat
      // colour below it — no seam, at any viewport aspect.
      style={{ backgroundColor: '#0f1016' }}
    >
      {/*
        Responsive without a media query.

        `100% auto` scales the artwork to the viewport WIDTH and lets its
        height fall where it will, anchored to the top. On a desktop at 16:9
        that fills the screen; on a laptop at 16:10 a band of flat colour
        appears below it; on a tablet in portrait the scene occupies the top
        third and the rest is that same colour. Every one of those is correct,
        and none of them crops the three agencies out of frame — which `cover`
        would do the moment the viewport got taller than 16:9.
      */}
      <div aria-hidden="true" className="pointer-events-none absolute inset-0">
        <div
          className="absolute inset-0"
          style={{
            backgroundImage: 'url(/auth-backdrop.jpg)',
            backgroundSize: '100% auto',
            backgroundPosition: 'top center',
            backgroundRepeat: 'no-repeat',
          }}
        />
        {/*
          Scrim. Contrast, not styling: the artwork has a burning house and
          police lights in it, and the wordmark and eyebrow above the card are
          white. Heaviest at the very top, where the masthead sits.
        */}
        <div
          className="absolute inset-0"
          style={{
            background:
              'linear-gradient(to bottom, rgba(0,0,0,0.62) 0%, ' +
              'rgba(0,0,0,0.30) 38%, rgba(15,16,22,0.78) 100%)',
          }}
        />
      </div>

      {/* Logo + wordmark */}
      <motion.div
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
        className="relative z-10 mb-8 flex flex-col items-center gap-3"
      >
        <div
          className="flex items-center justify-center rounded-2xl"
          style={{
            // Raised from 44px. The mark was hard to read at that size, and
            // the reason was the asset rather than the box: it shipped
            // 344x589 instead of square, so object-fit:contain drew the
            // monogram at 58% of the width it was given. That is fixed in
            // make-logo-assets.mjs; this is the size the badge should have had
            // all along, now that `size` means what it says.
            width: '72px', height: '72px',
            backgroundColor: 'var(--color-surface-card)',
            boxShadow: '0 8px 24px -6px rgba(0,0,0,0.55)',
          }}
        >
          {/* The monogram, not the lockup — the wordmark inside a box this
              size would render a few px tall, and the eyebrow below already
              names the product. */}
          <ZirenLogo alt="Ziren" priority size={48} />
        </div>
        <p
          className="text-[11px] font-semibold uppercase"
          style={{
            letterSpacing: '1.5px',
            // The ground behind this is now a dark photograph, so the muted
            // grey it used to use is unreadable here.
            color: 'rgba(255,255,255,0.78)',
            textShadow: '0 1px 8px rgba(0,0,0,0.6)',
          }}
        >
          {eyebrow}
        </p>
      </motion.div>

      {/* Card */}
      <motion.div
        initial={{ opacity: 0, y: 14, scale: 0.985 }}
        animate={{ opacity: 1, y: 0, scale: 1 }}
        transition={{ duration: 0.45, delay: 0.05, ease: [0.16, 1, 0.3, 1] }}
        className="relative z-10 w-full"
        style={{
          maxWidth: `${maxWidth}px`,
          backgroundColor: 'var(--color-surface-card)',
          border: '1px solid var(--color-surface-border)',
          borderRadius: 'var(--radius-2xl)',
          boxShadow: '0 1px 2px rgba(15,23,42,0.04), 0 16px 40px -12px rgba(15,23,42,0.10)',
          padding: '36px',
        }}
      >
        {children}
      </motion.div>

      {footer && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.4, delay: 0.2 }}
          className="relative z-10 mt-6"
        >
          {footer}
        </motion.div>
      )}
    </main>
  );
}
