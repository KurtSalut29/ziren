'use client';

/**
 * ShellSearch — the console's search field, now backed by real results
 * (spec Section 18). Was a plain controlled input with no query logic
 * behind it; GET /search/ exists now, so this either had to become a real
 * global search or be removed per the spec's own rule ("should only remain
 * if properly implemented").
 *
 * Lives in the topbar's right cluster at md and up, and inside the nav
 * drawer below it. Two placements, one component: the drawer is the only
 * chrome that exists at phone width, and dropping the field there would
 * have removed search from mobile entirely rather than moving it. Both
 * instances mount at once and CSS decides which is visible, so the ⌘K
 * handler has to pick a target — it focuses the one that is actually
 * rendered (the offsetParent check below) instead of racing two listeners
 * for the same shortcut. Each instance also runs its own fetch when it has
 * focus; the hidden one's results are simply never shown, since nothing
 * ever asks it to render its dropdown.
 */

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { SearchInput } from '@/components/ui/search-input';
import { useAuth } from '@/lib/hooks/useAuth';
import { globalSearch, GROUP_LABELS, type SearchResults } from '@/lib/api/search';

export interface ShellSearchProps {
  value: string;
  onChange: (v: string) => void;
  /** Extra classes for the wrapper — width is the caller's decision. */
  className?: string;
}

const DEBOUNCE_MS = 250;

export function ShellSearch({ value, onChange, className = '' }: ShellSearchProps) {
  /**
   * `?? ''` is not redundant with the `string` type above.
   *
   * React decides controlled-vs-uncontrolled from the value at the FIRST
   * commit and warns for the rest of the component's life if that answer ever
   * changes. TypeScript cannot protect the first commit: a caller that has not
   * yet been updated to pass the prop, an HMR round where this file compiled
   * before its parent did, or any JS consumer all deliver `undefined` at
   * runtime with a clean typecheck — and the warning then points here rather
   * than at the caller that actually caused it.
   *
   * Two shells render this component, so "the caller forgot the prop" is a
   * real state this file should survive rather than diagnose.
   */
  const controlledValue = value ?? '';
  const inputRef = useRef<HTMLInputElement>(null);
  const wrapperRef = useRef<HTMLDivElement>(null);
  const [isMac, setIsMac] = useState(false);
  const { token } = useAuth();
  const router = useRouter();

  const [open, setOpen] = useState(false);
  const [results, setResults] = useState<SearchResults | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // navigator is browser-only; reading it during render would break SSR and
    // produce a hydration mismatch on the shortcut hint.
    setIsMac(/Mac|iPhone|iPad/.test(navigator.platform ?? ''));
  }, []);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key.toLowerCase() !== 'k' || !(e.metaKey || e.ctrlKey)) return;
      // The hidden instance has no offset parent (its ancestor is display:none),
      // so it declines the shortcut and lets the visible one take it. Without
      // this both instances call focus() and the off-screen one wins by being
      // second, which silently swallows the keystroke.
      if (inputRef.current?.offsetParent === null) return;
      e.preventDefault();
      inputRef.current?.focus();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  // Debounced fetch — a query per keystroke would hammer the endpoint on a
  // fast typist and mostly fetch results for a query nobody is looking at
  // half a second later.
  useEffect(() => {
    const q = controlledValue.trim();
    if (!token || q.length < 2) {
      setResults(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    const id = setTimeout(() => {
      globalSearch(token, q)
        .then(r => setResults(r))
        .catch(() => setResults(null))
        .finally(() => setLoading(false));
    }, DEBOUNCE_MS);
    return () => clearTimeout(id);
  }, [controlledValue, token]);

  // Close the dropdown on an outside click — a plain input with no popover
  // semantics of its own needs this done by hand.
  useEffect(() => {
    if (!open) return;
    const onClick = (e: MouseEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, [open]);

  function goTo(link: string) {
    setOpen(false);
    onChange('');
    router.push(link);
  }

  const hasAnyResults = results && Object.values(results).some(group => group.length > 0);
  const showDropdown = open && controlledValue.trim().length >= 2;

  return (
    <div className={`relative ${className}`} ref={wrapperRef}>
      <SearchInput
        hint={
          <kbd className="rounded-[6px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-1.5 py-0.5 text-[11px] font-medium text-[var(--color-text-muted)]">
            {isMac ? '⌘K' : 'Ctrl K'}
          </kbd>
        }
        label="Search residents, responders, stations, incidents, and places"
        onFocus={() => setOpen(true)}
        onValueChange={v => { onChange(v); setOpen(true); }}
        placeholder="Search"
        ref={inputRef}
        value={controlledValue}
      />

      {showDropdown && (
        <div className="absolute left-0 right-0 top-full z-50 mt-1.5 max-h-[70vh] overflow-y-auto rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-md)]">
          {loading && !results ? (
            <p className="px-4 py-6 text-center text-[12.5px] text-muted-foreground">Searching…</p>
          ) : !hasAnyResults ? (
            <p className="px-4 py-6 text-center text-[12.5px] text-muted-foreground">
              No matches for &quot;{controlledValue.trim()}&quot;
            </p>
          ) : (
            (Object.keys(GROUP_LABELS) as (keyof SearchResults)[]).map(group => {
              const hits = results?.[group] ?? [];
              if (hits.length === 0) return null;
              return (
                <div className="border-b border-[var(--color-surface-border)] py-1.5 last:border-b-0" key={group}>
                  <p className="px-4 py-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    {GROUP_LABELS[group]}
                  </p>
                  {hits.map(hit => (
                    <button
                      className="flex w-full flex-col items-start gap-0.5 px-4 py-1.5 text-left hover:bg-[var(--color-surface-hover)]"
                      key={hit.id}
                      onClick={() => goTo(hit.link)}
                      type="button"
                    >
                      <span className="text-[13px] text-foreground">{hit.label || '(untitled)'}</span>
                      {hit.sublabel && (
                        <span className="text-[11.5px] text-muted-foreground">{hit.sublabel}</span>
                      )}
                    </button>
                  ))}
                </div>
              );
            })
          )}
        </div>
      )}
    </div>
  );
}
