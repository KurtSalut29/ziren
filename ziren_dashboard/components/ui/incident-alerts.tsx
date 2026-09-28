'use client';

/**
 * AlertSoundNudge - a slim bar that appears ONLY while the browser is really
 * keeping this page silent, and goes away by itself the moment it is not.
 *
 * WHY IT EXISTS AT ALL
 *
 * Browsers refuse to play any audio on a page until it has seen a real user
 * gesture (a click, a key press, a tap). That is a platform rule meant to stop
 * adverts blaring, not something this app can override, and it applies to a page
 * that has just been loaded or reloaded. On an emergency console the failure is
 * worse than an annoyance: a dispatcher who never touched the page gets a
 * completely silent first alert and cannot tell from looking at it (found
 * 2026-09-15). So while the page is silent, the bar says so.
 *
 * WHAT CHANGED (2026-09-25)
 *
 * The bar used to be tied to the browser's desktop-NOTIFICATION permission, a
 * different thing. It stayed on screen until that permission was answered, even
 * when the sound had long been unlocked by an earlier click, and claimed that new
 * reports "arrive silently" when they did not. It now follows the real audio
 * state (`audioReady`, read from the AudioContext) and nothing else:
 *
 *   - Signed in this session, or the site is allowed to play sound: the state
 *     is "running" from the start and the bar never appears.
 *   - Freshly loaded, nobody has clicked yet: the bar shows, and the FIRST click,
 *     key press or tap ANYWHERE on the page clears it. Pressing the button is
 *     optional - useIncidentAlerts unlocks audio on any gesture.
 *   - The desktop-alert permission is asked for by itself on that same first
 *     click (once per browser), so it needs no bar of its own.
 *
 * The bar is in the page flow, not floating: as a card it covered the sticky
 * header, then the search box, then the lower queue rows, then intercepted clicks
 * on incident rows. A prompt that has to stay until it is answered must push the
 * page down rather than cover it. Same slot as the responder-distress banner.
 */

import { Volume2 } from 'lucide-react';

export function AlertSoundNudge({
  audioReady,
  onEnable,
}: {
  /** null = not looked at yet (render nothing rather than flash). */
  audioReady: boolean | null;
  onEnable: () => void;
}) {
  if (audioReady !== false) return null;

  return (
    <div
      aria-label="Alert sound"
      className="flex items-center gap-3 border-b px-4 py-2 md:px-6"
      role="region"
      style={{
        borderColor: 'var(--color-surface-border)',
        backgroundColor: 'var(--color-brand-subtle)',
      }}
    >
      <Volume2 className="shrink-0" size={16} style={{ color: 'var(--color-brand)' }} />
      <p className="min-w-0 flex-1 text-[13px] leading-snug font-medium" style={{ color: 'var(--color-text-primary)' }}>
        Click anywhere on the page to turn on the alert sound. The browser keeps a page silent until you do.
      </p>
      <button
        className="shrink-0 rounded-full px-3.5 py-1 text-[12px] font-semibold transition-opacity hover:opacity-90"
        onClick={onEnable}
        style={{
          backgroundColor: 'var(--color-brand)',
          color: 'var(--color-text-inverse)',
        }}
        type="button"
      >
        Enable sound
      </button>
    </div>
  );
}
