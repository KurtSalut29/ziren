'use client';

/**
 * "Ask Ziren for help" — the mascot's head, bottom-right of every page, and
 * the help dialog it opens.
 *
 * The same idea as the mobile app's ZirenHelpButton (mascot_home_header.dart):
 * the head is always there to press, and a label pops out of it to say what it
 * is for. Asked for on the console too (2026-09-30), for Agency Admins and
 * Provincial Admins, who each get their own topics (lib/help/help-content.ts).
 *
 * It is meant to be noticed (the user's words: "dapat noticeable siya"): the
 * head stands out of its disc, signal rings spread from it the way the arcs in
 * the artwork do, it floats a little, and a speech bubble pops out of it when
 * the console loads and every twenty seconds after. The loops are CSS
 * (globals.css, `ziren-*` keyframes), so both reduced-motion switches stop
 * them; the glow, the size and the "?" badge are what make it findable then.
 *
 * The dialog opens on what the dispatcher is looking at: topics about the
 * current page come first, under "On this page".
 *
 * It steps aside for the assist-request cards, which own the same corner and
 * matter more (see assist-alerts.tsx).
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { ArrowRight, Search } from 'lucide-react';
import { helpFor, type HelpTopic } from '@/lib/help/help-content';
import { HelpTopicItem, filterHelp } from '@/components/help/help-topic';
import { DemoList, HelpModeSwitch, type HelpMode } from '@/components/help/demo-list';
import { useDemo } from '@/components/help/demo-tour';
import { demoForPage, demosFor } from '@/lib/help/demo-content';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogTitle,
} from '@/components/efferd/ui/dialog';
import { cn } from '@/lib/utils';

const LABEL = 'Ask Ziren for help';

/** How long the label stays out, and how long until it pops out again. */
const LABEL_VISIBLE_MS = 7_000;
const LABEL_FIRST_MS = 1_200;
const LABEL_EVERY_MS = 20_000;

/**
 * Topics that are about a page without linking to it (a topic links to one
 * page at most, and "Accept or reject" happens on two).
 */
const PAGE_TOPICS: Record<string, string[]> = {
  '/incidents': ['new-report', 'accept-reject', 'dispatch'],
  '/queue': ['new-report', 'accept-reject', 'dispatch'],
};

/** The topics worth showing first on [pathname], in help-content order. */
export function topicsForPage(topics: HelpTopic[], pathname: string): HelpTopic[] {
  const named = PAGE_TOPICS[pathname] ?? [];
  return topics.filter(t => {
    if (named.includes(t.id)) return true;
    const page = t.href?.split('?')[0];
    return Boolean(page) && (pathname === page || pathname.startsWith(`${page}/`));
  });
}

export function ZirenHelp({
  isProvincialAdmin,
  pathname,
  pageTitle,
  hidden = false,
}: {
  isProvincialAdmin: boolean;
  pathname: string;
  /** The current page's name, for the "On this page" heading. */
  pageTitle?: string;
  /** True while something more urgent is using this corner. */
  hidden?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const demo = useDemo();

  // The Help page is the same guide at full size; a button to a smaller copy
  // of the page you are on would be noise.
  if (pathname === '/help') return null;

  return (
    <>
      <AnimatePresence>
        {!hidden && !open && !demo.active && (
          <motion.div
            animate={{ opacity: 1, y: 0 }}
            className="pointer-events-none fixed bottom-4 right-4 z-[60] flex items-center print:hidden md:bottom-6 md:right-6"
            exit={{ opacity: 0, y: 12 }}
            initial={{ opacity: 0, y: 12 }}
            transition={{ duration: 0.2 }}
          >
            <HelpButton onPress={() => setOpen(true)} />
          </motion.div>
        )}
      </AnimatePresence>

      <Dialog onOpenChange={setOpen} open={open}>
        {open && (
          <HelpDialog
            isProvincialAdmin={isProvincialAdmin}
            onNavigate={() => setOpen(false)}
            pageTitle={pageTitle}
            pathname={pathname}
          />
        )}
      </Dialog>
    </>
  );
}

// ── The head and its label ──────────────────────────────────────────────────

function HelpButton({ onPress }: { onPress: () => void }) {
  const reduceMotion = useReducedMotion();
  const [timed, setTimed] = useState(false);
  const [hovered, setHovered] = useState(false);
  const hide = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Pops out by itself now and then. Not at all with reduced motion: there it
  // shows only under the pointer or keyboard focus.
  useEffect(() => {
    if (reduceMotion) return;
    const show = () => {
      setTimed(true);
      if (hide.current) clearTimeout(hide.current);
      hide.current = setTimeout(() => setTimed(false), LABEL_VISIBLE_MS);
    };
    const first = setTimeout(show, LABEL_FIRST_MS);
    const every = setInterval(show, LABEL_EVERY_MS);
    return () => {
      clearTimeout(first);
      clearInterval(every);
      if (hide.current) clearTimeout(hide.current);
    };
  }, [reduceMotion]);

  const showLabel = timed || hovered;

  return (
    <button
      aria-label={LABEL}
      className="group pointer-events-auto flex items-center rounded-full outline-none"
      data-testid="ziren-help-button"
      onBlur={() => setHovered(false)}
      onClick={onPress}
      onFocus={() => setHovered(true)}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
      type="button"
    >
      {/* The speech bubble grows out of the mascot's side, tail towards it. */}
      <AnimatePresence>
        {showLabel && (
          <motion.span
            animate={{ opacity: 1, scale: 1, x: 0 }}
            aria-hidden="true"
            className="relative mr-3 flex flex-col items-start whitespace-nowrap rounded-2xl border border-[color-mix(in_srgb,var(--color-brand)_45%,transparent)] bg-[var(--color-surface-card)] px-4 py-2.5 text-left shadow-[0_10px_28px_rgba(252,90,5,0.22)]"
            exit={{ opacity: 0, scale: 0.4, x: 16 }}
            initial={{ opacity: 0, scale: 0.4, x: 16 }}
            style={{ originX: 1, originY: 0.5 }}
            transition={{ type: 'spring', stiffness: 420, damping: 24 }}
          >
            <span className="text-[14px] font-extrabold leading-tight text-foreground">Need help?</span>
            <span className="text-[12px] font-semibold leading-tight text-[var(--color-brand)]">{LABEL}</span>
            {/* The tail: a square turned 45 degrees, sharing the bubble's border. */}
            <span className="absolute -right-[6px] top-1/2 size-3 -translate-y-1/2 rotate-45 rounded-[2px] border-r border-t border-[color-mix(in_srgb,var(--color-brand)_45%,transparent)] bg-[var(--color-surface-card)]" />
          </motion.span>
        )}
      </AnimatePresence>

      <MascotBadge />
    </button>
  );
}

/** The light disc the head stands on. Light in both themes: the head is
 *  black, and on a dark disc it would vanish into a dark page. */
const DISC = 'radial-gradient(circle at 32% 26%, #ffffff 0%, #FFE7D9 55%, #FFC9A8 100%)';

/**
 * The mascot on its disc: rings, glow, the head standing out of the circle,
 * and the "?" that says what it is for even with no label showing.
 */
function MascotBadge() {
  return (
    <span className="relative block size-[84px] shrink-0 transition-transform duration-200 group-hover:scale-110 group-active:scale-95">
      {/* Signal rings, spreading the way the arcs in the artwork do. */}
      <span className="ziren-ring absolute inset-[10px] rounded-full border-2 border-[var(--color-brand)]" />
      <span className="ziren-ring ziren-ring-late absolute inset-[10px] rounded-full border-2 border-[var(--color-brand)]" />

      <span
        className={cn(
          'absolute inset-[10px] rounded-full border-[3px] border-[var(--color-brand)]',
          'shadow-[0_10px_30px_rgba(252,90,5,0.45),0_2px_6px_rgba(0,0,0,0.18)]',
          'group-focus-visible:ring-4 group-focus-visible:ring-[color-mix(in_srgb,var(--color-brand)_40%,transparent)]',
        )}
        style={{ background: DISC }}
      />

      {/* The head, wider than the disc so the pin and the arcs stand out of it. */}
      <span className="ziren-float absolute inset-x-0 bottom-[12px] flex justify-center">
        <span className="ziren-wiggle block">
          <MascotHead size={66} />
        </span>
      </span>

      <span className="absolute bottom-[6px] right-[4px] flex size-[24px] items-center justify-center rounded-full border-2 border-white bg-[var(--color-brand)] text-[14px] font-black leading-none text-white shadow-[0_2px_6px_rgba(0,0,0,0.25)]">
        ?
      </span>
    </span>
  );
}

function MascotHead({ size }: { size: number }) {
  return (
    <Image
      alt=""
      aria-hidden="true"
      className="max-w-none select-none object-contain drop-shadow-[0_3px_4px_rgba(0,0,0,0.25)]"
      draggable={false}
      height={size}
      src="/ziren-help.png"
      width={Math.round(size * (291 / 240))}
    />
  );
}

// ── The dialog ──────────────────────────────────────────────────────────────

function HelpDialog({
  isProvincialAdmin,
  pathname,
  pageTitle,
  onNavigate,
}: {
  isProvincialAdmin: boolean;
  pathname: string;
  pageTitle?: string;
  onNavigate: () => void;
}) {
  const groups = useMemo(() => helpFor(isProvincialAdmin), [isProvincialAdmin]);
  const here = useMemo(
    () => topicsForPage(groups.flatMap(g => g.topics), pathname),
    [groups, pathname],
  );
  const [query, setQuery] = useState('');
  const [mode, setMode] = useState<HelpMode>('steps');
  const demo = useDemo();
  const demos = useMemo(() => demosFor(isProvincialAdmin), [isProvincialAdmin]);
  const demoHere = demoForPage(isProvincialAdmin, pathname);
  // Opens on the first topic about this page, when there is one.
  const [openId, setOpenId] = useState<string | null>(here[0]?.id ?? null);

  const searching = query.trim().length > 0;
  const filtered = useMemo(() => filterHelp(groups, query), [groups, query]);
  const hereIds = new Set(here.map(t => t.id));

  const item = (topic: HelpTopic) => (
    <HelpTopicItem
      currentPath={pathname}
      key={topic.id}
      onNavigate={onNavigate}
      onToggle={() => setOpenId(openId === topic.id ? null : topic.id)}
      open={openId === topic.id || searching}
      topic={topic}
    />
  );

  return (
    <DialogContent
      className="flex max-h-[min(86vh,760px)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[600px]"
      data-testid="ziren-help-dialog"
    >
      {/* Header: the mascot says what this is, in a speech bubble. */}
      <div
        className="relative flex shrink-0 items-center gap-3 overflow-hidden border-b border-[var(--color-surface-border)] py-4 pl-4 pr-14 sm:gap-4 sm:pl-5"
        style={{ background: 'linear-gradient(120deg, color-mix(in srgb, var(--color-brand) 20%, var(--color-surface-card)) 0%, color-mix(in srgb, var(--color-brand) 5%, var(--color-surface-card)) 70%)' }}
      >
        {/* Faint signal arcs behind the mascot, echoing the artwork. */}
        <span aria-hidden="true" className="pointer-events-none absolute -left-10 top-1/2 size-[190px] -translate-y-1/2 rounded-full border border-[color-mix(in_srgb,var(--color-brand)_28%,transparent)]" />
        <span aria-hidden="true" className="pointer-events-none absolute -left-20 top-1/2 size-[270px] -translate-y-1/2 rounded-full border border-[color-mix(in_srgb,var(--color-brand)_16%,transparent)]" />

        <span className="relative hidden size-[88px] shrink-0 min-[420px]:block">
          <span
            className="absolute inset-[8px] rounded-full border-[3px] border-[var(--color-brand)] shadow-[0_8px_22px_rgba(252,90,5,0.35)]"
            style={{ background: DISC }}
          />
          <span className="ziren-float absolute inset-x-0 bottom-[10px] flex justify-center">
            <MascotHead size={72} />
          </span>
        </span>

        <div className="relative min-w-0 flex-1 rounded-2xl border border-[color-mix(in_srgb,var(--color-brand)_35%,transparent)] bg-[var(--color-surface-card)] px-4 py-3 shadow-[0_6px_18px_rgba(252,90,5,0.12)]">
          <span aria-hidden="true" className="absolute -left-[6px] top-1/2 hidden size-3 -translate-y-1/2 rotate-45 rounded-[2px] border-b border-l min-[420px]:block border-[color-mix(in_srgb,var(--color-brand)_35%,transparent)] bg-[var(--color-surface-card)]" />
          <span className="mb-1 inline-flex items-center rounded-full bg-[color-mix(in_srgb,var(--color-brand)_14%,transparent)] px-2 py-0.5 text-[10.5px] font-bold uppercase tracking-wider text-[var(--color-brand)]">
            {isProvincialAdmin ? 'Provincial Admin guide' : 'Agency Admin guide'}
          </span>
          <DialogTitle className="text-[17px] font-extrabold leading-snug text-foreground">
            Hi! I&apos;m Ziren. What do you need help with?
          </DialogTitle>
          <DialogDescription className="mt-0.5 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
            {mode === 'steps'
              ? 'Read the steps for a topic, or let me show you a page.'
              : 'Pick a page and I will walk you through it.'}
          </DialogDescription>
        </div>
      </div>

      {/* Two ways in: the written steps (unchanged), or a demo on the page itself. */}
      <div className="shrink-0 border-b border-[var(--color-surface-border)] px-4 py-3 sm:px-5">
        <HelpModeSwitch mode={mode} onChange={setMode} />
      </div>

      {mode === 'demo' ? (
        <div className="scroll-ziren min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-5">
          <DemoList
            demos={demos}
            here={demoHere}
            onStart={d => {
              onNavigate();
              demo.start(d);
            }}
          />
        </div>
      ) : (
      <>
      <div className="shrink-0 border-b border-[var(--color-surface-border)] px-4 py-3 sm:px-5">
        <label className="relative block">
          <span className="sr-only">Search help</span>
          <Search aria-hidden="true" className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <input
            className="h-10 w-full rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] pl-9 pr-3 text-[13.5px] text-foreground focus:border-[var(--color-brand)] focus:outline-none"
            onChange={e => setQuery(e.target.value)}
            placeholder="Search help, e.g. dispatch or export"
            type="search"
            value={query}
          />
        </label>
      </div>

      <div className="scroll-ziren min-h-0 flex-1 overflow-y-auto py-4 pl-4 pr-1 sm:pl-5 sm:pr-1.5">
        {searching && filtered.length === 0 && (
          <p className="rounded-xl border border-dashed border-[var(--color-surface-border)] p-6 text-center text-[13.5px] text-muted-foreground">
            Nothing in the guides matches “{query.trim()}”.
          </p>
        )}

        {!searching && here.length > 0 && (
          <section className="mb-5" data-testid="ziren-help-here">
            <h3 className="mb-2 text-[11.5px] font-semibold uppercase tracking-wider text-[var(--color-brand)]">
              On this page{pageTitle ? ` · ${pageTitle}` : ''}
            </h3>
            <ul className="flex flex-col gap-2">{here.map(item)}</ul>
          </section>
        )}

        {filtered.map(group => {
          // Already listed under "On this page"; not repeated below it.
          const topics = searching ? group.topics : group.topics.filter(t => !hereIds.has(t.id));
          if (topics.length === 0) return null;
          return (
            <section className="mb-5 last:mb-0" key={group.label}>
              <h3 className="mb-2 text-[11.5px] font-semibold uppercase tracking-wider text-muted-foreground">{group.label}</h3>
              <ul className="flex flex-col gap-2">{topics.map(item)}</ul>
            </section>
          );
        })}
      </div>
      </>
      )}

      <div className="flex shrink-0 flex-wrap items-center justify-between gap-2 border-t border-[var(--color-surface-border)] px-4 py-3 text-[12.5px] text-[var(--color-text-secondary)] sm:px-5">
        <span>
          <Kbd>Ctrl</Kbd> + <Kbd>K</Kbd> searches everything · <Kbd>Esc</Kbd> closes this
        </span>
        <Link
          className="inline-flex items-center gap-1 font-semibold text-[var(--color-brand)] hover:underline"
          href="/help"
          onClick={onNavigate}
        >
          Open the full Help page <ArrowRight aria-hidden="true" size={14} />
        </Link>
      </div>
    </DialogContent>
  );
}

function Kbd({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="rounded border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-1.5 py-0.5 font-mono text-[11px] text-foreground">
      {children}
    </kbd>
  );
}
