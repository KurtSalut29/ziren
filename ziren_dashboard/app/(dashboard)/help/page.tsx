'use client';

/**
 * Help — "How to use Ziren", for the signed-in role.
 *
 * Asked for by the stations after testing: someone new at the console should
 * be able to find their way without a colleague beside them. Short topics,
 * grouped by what the person is trying to do, each with numbered steps that
 * name buttons by their on-screen labels and a link to the page itself.
 * Content lives in lib/help/help-content.ts.
 */

import { useMemo, useState } from 'react';
import Link from 'next/link';
import { Keyboard, LifeBuoy, Search } from 'lucide-react';
import { useAuth } from '@/lib/hooks/useAuth';
import { helpFor } from '@/lib/help/help-content';
import { HelpTopicItem, filterHelp } from '@/components/help/help-topic';
import { DemoList, HelpModeSwitch, type HelpMode } from '@/components/help/demo-list';
import { useDemo } from '@/components/help/demo-tour';
import { demosFor } from '@/lib/help/demo-content';
import { Button } from '@/components/efferd/ui/button';

export default function HelpPage() {
  const { isProvincialAdmin } = useAuth();
  const groups = helpFor(Boolean(isProvincialAdmin));
  const [open, setOpen] = useState<string | null>(groups[0]?.topics[0]?.id ?? null);
  const [query, setQuery] = useState('');
  const [mode, setMode] = useState<HelpMode>('steps');
  const demo = useDemo();

  const q = query.trim().toLowerCase();
  const filtered = useMemo(() => filterHelp(groups, query), [groups, query]);

  return (
    <div className="mx-auto flex w-full max-w-[1100px] flex-col gap-5 lg:flex-row lg:items-start">
      <div className="min-w-0 flex-1">
        <div className="mb-4 flex items-start gap-3 rounded-[14px] border border-[color-mix(in_srgb,var(--color-brand)_30%,transparent)] bg-[color-mix(in_srgb,var(--color-brand)_7%,transparent)] p-4">
          <LifeBuoy aria-hidden="true" className="mt-0.5 size-6 shrink-0 text-[var(--color-brand)]" />
          <div>
            <h2 className="text-[16px] font-semibold text-foreground">How to use Ziren</h2>
            <p className="mt-0.5 text-[13.5px] leading-relaxed text-[var(--color-text-secondary)]">
              {isProvincialAdmin
                ? 'Guides for Provincial Admins: watching the province, managing accounts and stations, and communicating.'
                : 'Guides for station dispatchers: handling a report from the alarm to resolved, asking other stations for help, and paperwork.'}
              {' '}Open a topic to see its steps, or choose Demo and Ziren will show you a page.
            </p>
          </div>
        </div>

        <div className="mb-4">
          <HelpModeSwitch mode={mode} onChange={setMode} />
        </div>

        {mode === 'demo' ? (
          <DemoList demos={demosFor(Boolean(isProvincialAdmin))} onStart={d => demo.start(d)} />
        ) : (
        <>
        <label className="relative mb-4 block">
          <span className="sr-only">Search help</span>
          <Search aria-hidden="true" className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <input
            className="h-10 w-full rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] pl-9 pr-3 text-[13.5px] text-foreground focus:border-[var(--color-brand)] focus:outline-none"
            onChange={e => setQuery(e.target.value)}
            placeholder="Search help — e.g. dispatch, landmark, export"
            type="search"
            value={query}
          />
        </label>

        {filtered.length === 0 && (
          <p className="rounded-xl border border-dashed border-[var(--color-surface-border)] p-6 text-center text-[13.5px] text-muted-foreground">
            Nothing in the guides matches “{query.trim()}”.
          </p>
        )}

        {filtered.map(group => (
          <section className="mb-5" key={group.label}>
            <h3 className="mb-2 text-[11.5px] font-semibold uppercase tracking-wider text-muted-foreground">{group.label}</h3>
            <ul className="flex flex-col gap-2">
              {group.topics.map(topic => (
                <HelpTopicItem
                  key={topic.id}
                  onToggle={() => setOpen(open === topic.id ? null : topic.id)}
                  open={open === topic.id || q.length > 0}
                  topic={topic}
                />
              ))}
            </ul>
          </section>
        ))}
        </>
        )}
      </div>

      <aside className="flex w-full shrink-0 flex-col gap-3 lg:sticky lg:top-4 lg:w-[300px]">
        <div className="rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4">
          <p className="mb-2 flex items-center gap-2 text-[13.5px] font-semibold text-foreground">
            <Keyboard aria-hidden="true" className="size-4 text-muted-foreground" /> Shortcuts
          </p>
          <dl className="grid grid-cols-[auto_1fr] items-center gap-x-3 gap-y-2 text-[12.5px]">
            <dt><Kbd>/</Kbd></dt><dd className="text-[var(--color-text-secondary)]">Search everything</dd>
            <dt><Kbd>Ctrl</Kbd> + <Kbd>B</Kbd></dt><dd className="text-[var(--color-text-secondary)]">Show or hide the sidebar</dd>
            <dt><Kbd>Esc</Kbd></dt><dd className="text-[var(--color-text-secondary)]">Close a panel or dialog</dd>
          </dl>
        </div>
        <div className="rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4">
          <p className="text-[13.5px] font-semibold text-foreground">Still stuck?</p>
          <p className="mt-1 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
            Settings → Support has who to contact and a problem report that includes what the system needs to diagnose it.
          </p>
          <Button asChild className="mt-3 w-full" size="sm" variant="outline">
            <Link href="/settings?tab=support">Open Support</Link>
          </Button>
        </div>
      </aside>
    </div>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="rounded border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-1.5 py-0.5 font-mono text-[11px] text-foreground">
      {children}
    </kbd>
  );
}
