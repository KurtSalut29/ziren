'use client';

/**
 * Toasts — the one place a "that worked" or "that failed" message is shown.
 *
 * WHY THIS IS A MODULE-LEVEL STORE AND NOT A CONTEXT
 *
 * Messages used to be rendered inline by whichever page raised them, and that
 * is exactly why they went missing: an <Alert> drawn at the top of a scrolling
 * card is off-screen when the button that caused it is at the bottom, and one
 * drawn inside a dialog disappears the moment the dialog closes. The people
 * using the console never saw a confirmation for a change they had just made.
 *
 * A store that lives outside React lets ANY code raise a toast - a page, a
 * dialog, a hook, a plain callback - without the caller having to be under the
 * right provider, and the single <Toaster /> in the root layout renders them
 * above everything else, including dialogs and the incident alert.
 *
 * The timer lives here too, not in the component: a toast has to leave after
 * exactly TOAST_MS whether or not the component that showed it re-rendered,
 * remounted or was unmounted by a route change in the meantime.
 */

import { useCallback, useSyncExternalStore } from 'react';

export type ToastKind = 'success' | 'error' | 'info' | 'warning';

export interface ToastItem {
  id: number;
  kind: ToastKind;
  message: string;
  /** Optional second line - e.g. the reason behind an error. */
  detail?: string;
  /** Milliseconds on screen. Also drives the countdown bar. */
  duration: number;
  /** A click target for a toast that points somewhere ("Open incident"). */
  action?: { label: string; onClick: () => void };
  /** Bumped when the same message is raised again, so the countdown restarts. */
  stamp: number;
}

/** Every toast leaves after five seconds. */
export const TOAST_MS = 5_000;

/** More than this at once and the screen is all toast; the oldest goes first. */
const MAX_VISIBLE = 4;

type Listener = () => void;

let items: ToastItem[] = [];
let nextId = 1;
let nextStamp = 1;
const listeners = new Set<Listener>();
const timers = new Map<number, ReturnType<typeof setTimeout>>();

const EMPTY: ToastItem[] = [];

function emit() {
  for (const l of listeners) l();
}

function subscribe(l: Listener) {
  listeners.add(l);
  return () => { listeners.delete(l); };
}

function dismiss(id: number) {
  const t = timers.get(id);
  if (t) { clearTimeout(t); timers.delete(id); }
  const next = items.filter(i => i.id !== id);
  if (next.length !== items.length) {
    items = next;
    emit();
  }
}

function clear() {
  for (const t of timers.values()) clearTimeout(t);
  timers.clear();
  items = [];
  emit();
}

interface ToastOptions {
  detail?: string;
  duration?: number;
  action?: ToastItem['action'];
}

function push(kind: ToastKind, message: string, opts: ToastOptions = {}): number {
  const text = message.trim();
  if (!text) return -1;

  // The same message raised twice in a row (a double-click on Save) is one
  // toast with its clock restarted, not two stacked copies of it.
  const twin = items.find(i => i.kind === kind && i.message === text && i.detail === opts.detail);
  if (twin) {
    const t = timers.get(twin.id);
    if (t) clearTimeout(t);
    timers.set(twin.id, setTimeout(() => dismiss(twin.id), twin.duration));
    // A new stamp so the countdown bar restarts with it.
    items = items.map(i => (i.id === twin.id ? { ...i, stamp: nextStamp++ } : i));
    emit();
    return twin.id;
  }

  const id = nextId++;
  const item: ToastItem = {
    id, kind, message: text,
    detail: opts.detail,
    duration: opts.duration ?? TOAST_MS,
    action: opts.action,
    stamp: nextStamp++,
  };
  items = [...items, item].slice(-MAX_VISIBLE);
  // Anything trimmed off the front must not leave a timer behind.
  for (const [tid, t] of timers) {
    if (!items.some(i => i.id === tid)) { clearTimeout(t); timers.delete(tid); }
  }
  timers.set(id, setTimeout(() => dismiss(id), item.duration));
  emit();
  return id;
}

export const toast = {
  success: (message: string, opts?: ToastOptions) => push('success', message, opts),
  error:   (message: string, opts?: ToastOptions) => push('error', message, opts),
  info:    (message: string, opts?: ToastOptions) => push('info', message, opts),
  warning: (message: string, opts?: ToastOptions) => push('warning', message, opts),
  dismiss,
  clear,
};

/** The toasts on screen right now. */
export function useToasts(): ToastItem[] {
  return useSyncExternalStore(subscribe, () => items, () => EMPTY);
}

// ── Adapter for the pages that already held a { type, text } notice ──────────
//
// Fifteen screens kept a `{ type: 'success' | 'error'; text }` (or, in
// Settings, `{ tone: 'success' | 'danger'; text }`) in local state and drew it
// inline. This keeps their call sites as they were - `setMsg({ type, text })` -
// while the message goes to the toaster instead of into the page.

export type Notice =
  | { type: 'success' | 'error' | 'info' | 'warning'; text: string }
  | { tone: 'success' | 'danger'; text: string };

/** Same shape as a state setter, so `setMsg(null)` at the start of an action still works. */
export function useNotice(): (notice: Notice | null) => void {
  return useCallback((notice: Notice | null) => {
    if (!notice) return;
    const kind: ToastKind =
      'type' in notice ? notice.type : notice.tone === 'danger' ? 'error' : 'success';
    toast[kind](notice.text);
  }, []);
}
