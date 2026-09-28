'use client';

import { useCallback, useEffect, useState } from 'react';
import {
  THEME_STORAGE_KEY,
  type Theme,
  type ThemePreference,
} from './theme-script';

export type { Theme, ThemePreference };

function systemTheme(): Theme {
  if (typeof window === 'undefined' || !window.matchMedia) return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light';
}

function readStoredPreference(): ThemePreference {
  try {
    const stored = localStorage.getItem(THEME_STORAGE_KEY);
    return stored === 'light' || stored === 'dark' ? stored : 'system';
  } catch {
    // Same reasoning as the bootstrap script: blocked storage throws.
    return 'system';
  }
}

/**
 * Reads and writes the dashboard theme.
 *
 * `preference` is what the user chose ('system' until they choose otherwise);
 * `theme` is what that currently resolves to. Both are needed — a settings
 * control has to be able to show "System" as distinct from "Light", even when
 * the two happen to render identically.
 *
 * `mounted` mirrors the `hydrated` convention in useAuth: it starts false and
 * flips after the first client read. Any UI that renders differently per theme
 * (a sun/moon icon, an aria-label) must wait for it, because the server has no
 * idea which theme the bootstrap script picked and would otherwise emit markup
 * the client immediately contradicts.
 */
export function useTheme() {
  const [preference, setPreference] = useState<ThemePreference>('system');
  const [theme, setTheme] = useState<Theme>('light');
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    const stored = readStoredPreference();
    setPreference(stored);
    setTheme(stored === 'system' ? systemTheme() : stored);
    setMounted(true);
  }, []);

  // Follow the OS while — and only while — the user is on 'system'. Without
  // this, someone whose machine flips to dark at sunset keeps a white
  // dashboard until they reload.
  useEffect(() => {
    if (preference !== 'system') return;
    if (typeof window === 'undefined' || !window.matchMedia) return;

    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (e: MediaQueryListEvent) => {
      setTheme(e.matches ? 'dark' : 'light');
    };
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [preference]);

  // Single writer for the DOM. Keeping the class toggle here rather than in
  // each caller means the <html> state can never drift from `theme`.
  useEffect(() => {
    if (!mounted) return;
    const root = document.documentElement;
    root.classList.toggle('dark', theme === 'dark');
    root.style.colorScheme = theme;
  }, [theme, mounted]);

  const applyPreference = useCallback((next: ThemePreference) => {
    setPreference(next);
    setTheme(next === 'system' ? systemTheme() : next);
    try {
      if (next === 'system') localStorage.removeItem(THEME_STORAGE_KEY);
      else localStorage.setItem(THEME_STORAGE_KEY, next);
    } catch {
      // Preference won't persist across reloads in a hardened context. The
      // in-memory theme still applies for this session, which is the best
      // available outcome — swallowing is correct here, not lazy.
    }
  }, []);

  const toggle = useCallback(() => {
    applyPreference(theme === 'dark' ? 'light' : 'dark');
  }, [theme, applyPreference]);

  return { theme, preference, mounted, setPreference: applyPreference, toggle };
}
