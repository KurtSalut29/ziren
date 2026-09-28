'use client';

/**
 * PrefsApplier — turns saved preferences into what is actually on screen.
 *
 * Mounted once, in the dashboard layout, so that a preference applies on EVERY
 * page and not only on the one that edits it. That is the whole reason this is a
 * component of its own: the accessibility settings used to be applied by an
 * effect inside a hook that only the Settings page mounted, so they worked there
 * and silently did nothing on the console itself.
 *
 * It renders nothing. Two jobs:
 *
 *  1. Write the display and accessibility choices to <html> — a data attribute,
 *     a class or a custom property each — where the stylesheet picks them up.
 *  2. Run IdleGuard when the operator has chosen an idle sign-out.
 */

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { LogOut, Timer } from 'lucide-react';
import { signOut } from '@/lib/hooks/useAuth';
import {
  FONT_SCALE_VALUES,
  accessibilityPrefs,
  displayPrefs,
  privacyPrefs,
} from '@/lib/prefs/definitions';
import { Button } from '@/components/efferd/ui/button';

/** WCAG 1.4.12 asks for 0.12em letter and 0.16em word spacing to survive; these
 *  are the two steps below and at that level, kept modest so a dense table still
 *  fits. Line height is left alone — see the note in globals.css. */
const TEXT_SPACING: Record<string, { letter: string; word: string }> = {
  normal:  { letter: '0em',     word: '0em' },
  relaxed: { letter: '0.02em',  word: '0.08em' },
  wide:    { letter: '0.04em',  word: '0.16em' },
};

export function PrefsApplier() {
  const display = displayPrefs.use();
  const a11y = accessibilityPrefs.use();

  useEffect(() => {
    const root = document.documentElement;
    root.dataset.density = display.density;
  }, [display.density]);

  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--user-font-scale', String(FONT_SCALE_VALUES[a11y.fontScale]));
    root.classList.toggle('a11y-high-contrast', a11y.highContrast);
    root.classList.toggle('a11y-reduced-motion', a11y.reducedMotion);
    root.classList.toggle('a11y-larger-controls', a11y.largerControls);
    root.classList.toggle('a11y-strong-focus', a11y.strongFocus);
    root.classList.toggle('a11y-underline-links', a11y.underlineLinks);

    const sp = TEXT_SPACING[a11y.textSpacing] ?? TEXT_SPACING.normal;
    root.style.setProperty('--user-letter-spacing', sp.letter);
    root.style.setProperty('--user-word-spacing', sp.word);
    root.dataset.textSpacing = a11y.textSpacing;
  }, [a11y]);

  return <IdleGuard />;
}

// ── Idle sign-out ────────────────────────────────────────────────────────

const WARN_SECONDS = 60;
const ACTIVITY_EVENTS = ['mousemove', 'mousedown', 'keydown', 'scroll', 'touchstart', 'wheel'] as const;

/**
 * Signs this browser out after a stretch with no input, if the operator chose
 * that under Settings → Privacy. Off by default: a wall display or a shared
 * dispatch terminal is SUPPOSED to sit untouched while it watches the queue,
 * and signing it out would blind it. The setting is for the workstation that
 * walks away from a desk.
 *
 * The last minute is a visible countdown with a button, not a silent drop —
 * losing a session under someone's hands is its own kind of failure.
 */
function IdleGuard() {
  const { idleMinutes } = privacyPrefs.use();
  const router = useRouter();
  const lastActive = useRef(Date.now());
  const [secondsLeft, setSecondsLeft] = useState<number | null>(null);

  useEffect(() => {
    if (idleMinutes === 0) {
      setSecondsLeft(null);
      return;
    }
    lastActive.current = Date.now();

    const bump = () => {
      // Once the warning is up, plain mouse movement must not dismiss it — the
      // countdown is answered with the button, on purpose.
      if (Date.now() - lastActive.current < idleMinutes * 60_000 - WARN_SECONDS * 1000) {
        lastActive.current = Date.now();
      }
    };
    for (const e of ACTIVITY_EVENTS) window.addEventListener(e, bump, { passive: true });

    const tick = setInterval(() => {
      const idleFor = Date.now() - lastActive.current;
      const remaining = Math.ceil((idleMinutes * 60_000 - idleFor) / 1000);
      if (remaining <= 0) {
        clearInterval(tick);
        signOut();
        router.replace('/login');
      } else if (remaining <= WARN_SECONDS) {
        setSecondsLeft(remaining);
      } else {
        setSecondsLeft(null);
      }
    }, 1000);

    return () => {
      clearInterval(tick);
      for (const e of ACTIVITY_EVENTS) window.removeEventListener(e, bump);
    };
  }, [idleMinutes, router]);

  if (secondsLeft === null) return null;

  return (
    <div
      aria-live="assertive"
      className="fixed inset-x-0 bottom-6 z-[200] mx-auto flex w-[min(92vw,440px)] items-center gap-3 rounded-[var(--radius-card)] border bg-[var(--color-surface-card)] px-4 py-3 shadow-[var(--shadow-popover,0_8px_30px_rgba(0,0,0,0.18))]"
      role="alertdialog"
      style={{ borderColor: 'var(--color-system-warning)' }}
    >
      <Timer aria-hidden="true" className="size-5 shrink-0" style={{ color: 'var(--color-system-warning)' }} />
      <div className="min-w-0 flex-1">
        <p className="text-[13.5px] font-semibold text-foreground">Still there?</p>
        <p className="text-[12.5px] text-muted-foreground">
          Signing out in <span className="font-mono font-semibold tabular-nums">{secondsLeft}s</span> because
          of inactivity.
        </p>
      </div>
      <Button
        onClick={() => {
          lastActive.current = Date.now();
          setSecondsLeft(null);
        }}
        size="sm"
      >
        Stay signed in
      </Button>
      <Button
        aria-label="Sign out now"
        onClick={() => {
          signOut();
          router.replace('/login');
        }}
        size="sm"
        variant="ghost"
      >
        <LogOut className="size-4" />
      </Button>
    </div>
  );
}
