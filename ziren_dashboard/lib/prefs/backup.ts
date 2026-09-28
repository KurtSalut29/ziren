/**
 * Export, import and reset every per-browser preference at once.
 *
 * Useful for the operator who sets up a second workstation, or hands a console
 * to a colleague, or wants to put a browser back to how it shipped. Covers the
 * preference stores (lib/prefs/definitions.ts) and the theme, which lives under
 * its own key because the page's bootstrap script reads it before React exists.
 */

import { THEME_STORAGE_KEY } from '@/lib/theme/theme-script';
import { ALL_PREF_STORES } from './definitions';

export interface PreferenceBackup {
  app: 'ziren-dashboard';
  version: 1;
  exported_at: string;
  theme: 'light' | 'dark' | 'system';
  /** store key -> its values */
  stores: Record<string, unknown>;
}

function readTheme(): PreferenceBackup['theme'] {
  try {
    const v = window.localStorage.getItem(THEME_STORAGE_KEY);
    return v === 'light' || v === 'dark' ? v : 'system';
  } catch {
    return 'system';
  }
}

/** Everything this browser has chosen, as a plain object. */
export function exportPreferences(): PreferenceBackup {
  const stores: Record<string, unknown> = {};
  for (const store of ALL_PREF_STORES) stores[store.key] = store.get();
  return {
    app: 'ziren-dashboard',
    version: 1,
    exported_at: new Date().toISOString(),
    theme: readTheme(),
    stores,
  };
}

export type ImportResult =
  | { ok: true; applied: number }
  | { ok: false; reason: string };

/**
 * Apply a backup. Each store re-validates what it is given (unknown keys and
 * wrong types are dropped, out-of-range values are clamped), so a hand-edited or
 * out-of-date file cannot put the console in a state it has no code for.
 */
export function importPreferences(raw: unknown): ImportResult {
  if (!raw || typeof raw !== 'object') return { ok: false, reason: 'That file is not a Ziren settings backup.' };
  const b = raw as Partial<PreferenceBackup>;
  if (b.app !== 'ziren-dashboard' || typeof b.stores !== 'object' || b.stores === null) {
    return { ok: false, reason: 'That file is not a Ziren settings backup.' };
  }
  let applied = 0;
  for (const store of ALL_PREF_STORES) {
    const values = (b.stores as Record<string, unknown>)[store.key];
    if (values && typeof values === 'object') {
      store.set(values as never);
      applied += 1;
    }
  }
  try {
    if (b.theme === 'light' || b.theme === 'dark') window.localStorage.setItem(THEME_STORAGE_KEY, b.theme);
    else if (b.theme === 'system') window.localStorage.removeItem(THEME_STORAGE_KEY);
  } catch {
    /* blocked storage — the stores above still applied in memory */
  }
  return applied > 0 ? { ok: true, applied } : { ok: false, reason: 'That backup had no settings in it.' };
}

/** Back to how it shipped, on this browser only. */
export function resetAllPreferences(): void {
  for (const store of ALL_PREF_STORES) store.reset();
  try {
    window.localStorage.removeItem(THEME_STORAGE_KEY);
  } catch {
    /* nothing to remove */
  }
}

/** Offer a JSON object to the user as a file download. */
export function downloadJson(filename: string, data: unknown): void {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
