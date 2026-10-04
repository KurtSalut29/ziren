'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Loader2, Search } from 'lucide-react';
import { apiClient } from '@/lib/api/client';
import { Button } from '@/components/efferd/ui/button';
import { Dialog, DialogContent, DialogTitle } from '@/components/efferd/ui/dialog';

interface Hit { id: string; label: string; sublabel: string | null; link: string }
type Results = Record<string, Hit[]>;

const GROUPS: { key: string; label: string }[] = [
  { key: 'incidents', label: 'Incidents' },
  { key: 'residents', label: 'Residents' },
  { key: 'responders', label: 'Responders' },
  { key: 'agency_admins', label: 'Agency admins' },
  { key: 'stations', label: 'Stations' },
  { key: 'barangays', label: 'Barangays' },
  { key: 'municipalities', label: 'Municipalities' },
];

/** True while the person is typing somewhere, so "/" is a character, not a shortcut. */
function typing(target: EventTarget | null): boolean {
  const t = target as HTMLElement | null;
  return Boolean(t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)));
}

/**
 * Search everything — incidents, people, stations, places — from the header.
 *
 * Evaluator finding #34 (2026-10-05): Help and Settings told admins to press
 * Ctrl+K, which no code here ever handled; the browser took it (in Chrome it
 * jumps to the address bar's search). The shortcut is now "/", the convention
 * of the tools people already use, which no browser binds; it is ignored while
 * typing in a field and on a page with its own search box (Settings), where "/"
 * already means that box.
 */
export function GlobalSearch({ token }: { token: string | null }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Results | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [active, setActive] = useState(0);
  const seq = useRef(0);

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey || typing(e.target)) return;
      if (document.querySelector('[data-page-search="true"]')) return;
      e.preventDefault();
      setOpen(true);
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  useEffect(() => {
    const q = query.trim();
    if (!open || !token || q.length < 2) { setResults(null); setError(null); return; }
    const mine = ++seq.current;
    setLoading(true);
    const timer = window.setTimeout(() => {
      apiClient.get<Results>(`/search/?q=${encodeURIComponent(q)}`, token)
        .then(r => { if (mine === seq.current) { setResults(r); setError(null); setActive(0); } })
        .catch(e => { if (mine === seq.current) setError(e instanceof Error ? e.message : 'Search failed.'); })
        .finally(() => { if (mine === seq.current) setLoading(false); });
    }, 250);
    return () => window.clearTimeout(timer);
  }, [query, open, token]);

  const flat = useMemo(
    () => GROUPS.flatMap(g => (results?.[g.key] ?? []).map(h => ({ ...h, group: g.label }))),
    [results],
  );

  function go(hit: Hit) {
    setOpen(false);
    setQuery('');
    router.push(hit.link);
  }

  return (
    <>
      <Button
        aria-keyshortcuts="/"
        aria-label="Search everything"
        className="hidden gap-2 text-muted-foreground sm:inline-flex"
        onClick={() => setOpen(true)}
        size="sm"
        type="button"
        variant="outline"
      >
        <Search className="size-3.5" />
        Search
        <kbd className="rounded border border-[var(--color-surface-border)] px-1.5 font-mono text-[10.5px]">/</kbd>
      </Button>
      <Button
        aria-label="Search everything"
        className="sm:hidden"
        onClick={() => setOpen(true)}
        size="icon-sm"
        type="button"
        variant="outline"
      >
        <Search />
      </Button>

      <Dialog onOpenChange={o => { setOpen(o); if (!o) setQuery(''); }} open={open}>
        <DialogContent className="gap-0 p-0 sm:max-w-xl" showCloseButton={false}>
          <DialogTitle className="sr-only">Search everything</DialogTitle>
          <div className="flex items-center gap-2 border-b border-[var(--color-surface-border)] px-4">
            {loading ? <Loader2 className="size-4 animate-spin text-muted-foreground" /> : <Search className="size-4 text-muted-foreground" />}
            <input
              aria-label="Search incidents, people, stations and places"
              autoFocus
              className="h-12 w-full bg-transparent text-[14.5px] outline-none"
              onChange={e => setQuery(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'ArrowDown') { e.preventDefault(); setActive(a => Math.min(a + 1, flat.length - 1)); }
                if (e.key === 'ArrowUp') { e.preventDefault(); setActive(a => Math.max(a - 1, 0)); }
                if (e.key === 'Enter' && flat[active]) { e.preventDefault(); go(flat[active]); }
              }}
              placeholder="Search incidents, people, stations, barangays…"
              value={query}
            />
          </div>
          <div className="max-h-[60vh] overflow-y-auto p-2" role="listbox">
            {query.trim().length < 2 ? (
              <p className="px-3 py-6 text-center text-[13px] text-muted-foreground">Type at least two letters.</p>
            ) : error ? (
              <p className="px-3 py-6 text-center text-[13px] text-[var(--color-system-error)]">{error}</p>
            ) : results && flat.length === 0 && !loading ? (
              <p className="px-3 py-6 text-center text-[13px] text-muted-foreground">Nothing matches “{query.trim()}”.</p>
            ) : (
              GROUPS.map(g => {
                const hits = results?.[g.key] ?? [];
                if (hits.length === 0) return null;
                return (
                  <div className="mb-1" key={g.key}>
                    <p className="px-3 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">{g.label}</p>
                    {hits.map(h => {
                      const index = flat.findIndex(f => f.group === g.label && f.id === h.id);
                      const selected = index === active;
                      return (
                        <button
                          aria-selected={selected}
                          className={`flex w-full items-baseline gap-2 rounded-[var(--radius-md)] px-3 py-2 text-left text-[13.5px] ${selected ? 'bg-[var(--color-surface-raised)]' : 'hover:bg-[var(--color-surface-raised)]'}`}
                          key={`${g.key}-${h.id}`}
                          onClick={() => go(h)}
                          onMouseEnter={() => setActive(index)}
                          role="option"
                          type="button"
                        >
                          <span className="truncate text-foreground">{h.label || '(untitled)'}</span>
                          {h.sublabel && <span className="shrink-0 text-[12px] text-muted-foreground">{h.sublabel}</span>}
                        </button>
                      );
                    })}
                  </div>
                );
              })
            )}
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}
