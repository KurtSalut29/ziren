/**
 * A tiny typed store for per-browser preferences.
 *
 * WHY THIS EXISTS
 *
 * Settings used to be one hook per concern, each owning its own state, its own
 * localStorage key and its own DOM effect. That pattern has a failure baked in:
 * the effect that applies a preference to the page lives inside the hook, so it
 * only runs while some component using the hook is mounted. The accessibility
 * hook was mounted on the Settings page and nowhere else, so font size, high
 * contrast and reduced motion were saved faithfully and then never applied
 * anywhere but Settings — after a reload, on any other screen, they did nothing.
 *
 * A preference has two halves that must not be coupled: WHAT IS CHOSEN (state
 * that a settings panel edits) and WHAT IT DOES (an effect that must run on
 * every page). This store owns the first half and is readable from anywhere,
 * including outside React (the alert hook reads its sound settings inside timer
 * callbacks); the second half is applied once, at the root, by PrefsApplier.
 *
 * WHAT IS STORED, AND WHERE
 *
 * localStorage, per browser — deliberately not per account. These are properties
 * of the screen in front of you (a night-shift wall display, a shared dispatch
 * terminal), so they follow the device. Facts about the ACCOUNT or the AGENCY
 * live on the server and never go through here.
 *
 * SAFETY
 *
 *  - Values read back from storage are checked against the defaults' shapes: a
 *    key must exist in the defaults and have the same type, and an optional
 *    `sanitize` clamps numbers and enums. A hand-edited or stale value can
 *    therefore never put the console in a state it has no code for.
 *  - Blocked storage (private window, hardened browser) throws on access. Every
 *    read and write is guarded; the store then simply lives in memory for the
 *    session, which is the best available outcome.
 *  - The server snapshot is always the defaults, so hydration cannot mismatch;
 *    the client re-renders with the stored values straight after.
 */

import { useSyncExternalStore } from 'react';

export interface PrefStore<T> {
  readonly key: string;
  readonly defaults: T;
  /** Current values. Safe to call anywhere, including inside timers. */
  get(): T;
  /** Merge a partial change, persist it, and tell every subscriber. */
  set(patch: Partial<T>): void;
  /** Back to the defaults, and forget what was stored. */
  reset(): void;
  subscribe(listener: () => void): () => void;
  /** React hook: re-renders when any value changes. */
  use(): T;
}

export function createPrefStore<T extends object>(
  key: string,
  defaults: T,
  sanitize?: (value: T) => T,
): PrefStore<T> {
  const listeners = new Set<() => void>();
  let cache: T | null = null;
  let storageHooked = false;

  function clean(raw: unknown): T {
    const next = { ...defaults } as Record<string, unknown>;
    if (raw && typeof raw === 'object') {
      for (const k of Object.keys(defaults)) {
        const v = (raw as Record<string, unknown>)[k];
        // Same key, same primitive type — anything else falls back to the
        // default rather than being trusted.
        if (v !== undefined && typeof v === typeof (defaults as Record<string, unknown>)[k]) {
          next[k] = v;
        }
      }
    }
    return sanitize ? sanitize(next as T) : (next as T);
  }

  function read(): T {
    if (typeof window === 'undefined') return defaults;
    try {
      const raw = window.localStorage.getItem(key);
      return clean(raw ? JSON.parse(raw) : null);
    } catch {
      return clean(null);
    }
  }

  function get(): T {
    if (cache === null) cache = read();
    return cache;
  }

  function emit() {
    listeners.forEach(l => l());
  }

  function hookStorageEvent() {
    if (storageHooked || typeof window === 'undefined') return;
    storageHooked = true;
    // Another tab changed it: pick that up so two open consoles agree.
    window.addEventListener('storage', e => {
      if (e.key !== key) return;
      cache = read();
      emit();
    });
  }

  const store: PrefStore<T> = {
    key,
    defaults,
    get,
    set(patch) {
      const next = clean({ ...get(), ...patch });
      cache = next;
      try {
        window.localStorage.setItem(key, JSON.stringify(next));
      } catch {
        /* in-memory for this session — see the note at the top */
      }
      emit();
    },
    reset() {
      cache = clean(null);
      try {
        window.localStorage.removeItem(key);
      } catch {
        /* nothing stored to remove */
      }
      emit();
    },
    subscribe(listener) {
      hookStorageEvent();
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    use() {
      return useSyncExternalStore(store.subscribe, get, () => defaults);
    },
  };
  return store;
}

/** Keep a number inside [min, max]; a non-finite value becomes `fallback`. */
export function clamp(n: number, min: number, max: number, fallback: number): number {
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

/** Keep a value inside an allowed list; anything else becomes `fallback`. */
export function oneOf<V extends string | number>(v: V, allowed: readonly V[], fallback: V): V {
  return allowed.includes(v) ? v : fallback;
}
