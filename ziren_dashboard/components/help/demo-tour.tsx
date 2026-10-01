'use client';

/**
 * Ziren's demos on the console: the page dims, the part being explained is
 * lit, and the mascot — from a speech bubble beside it — points at it and says
 * what it is for. The same idea as the mobile app's demo (demo_tour.dart),
 * with the onboarding's mascot-and-bubble look.
 *
 * DemoProvider sits in the dashboard layout. `start(script)` goes to the
 * script's page if it is not the current one, waits for the page to draw, and
 * runs the tour. While it runs the page underneath cannot be clicked: a demo
 * never presses anything for real.
 */

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import Image from 'next/image';
import { usePathname, useRouter } from 'next/navigation';
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion';
import { ArrowLeft, ArrowRight, Check } from 'lucide-react';
import type { DemoPose, DemoScript } from '@/lib/help/demo-types';
import { cn } from '@/lib/utils';

// ── Context ─────────────────────────────────────────────────────────────────

interface DemoContextValue {
  start: (script: DemoScript) => void;
  /** True while a demo is running or about to. */
  active: boolean;
}

const DemoContext = createContext<DemoContextValue>({ start: () => {}, active: false });

export function useDemo() {
  return useContext(DemoContext);
}

export function DemoProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [pending, setPending] = useState<DemoScript | null>(null);
  const [running, setRunning] = useState<DemoScript | null>(null);

  const start = useCallback(
    (script: DemoScript) => {
      setRunning(null);
      setPending(script);
      if (pathname !== script.href) router.push(script.href);
    },
    [pathname, router],
  );

  // On the right page: wait until any of the script's parts is drawn (data
  // pages render a skeleton first), then begin. Gives up waiting after ~4 s
  // and runs anyway — a part that never appears is explained from the middle.
  useEffect(() => {
    if (!pending || pathname !== pending.href) return;
    const targets = pending.steps.map(s => s.target).filter((t): t is string => Boolean(t));
    let cancelled = false;
    let tries = 0;
    let timer: ReturnType<typeof setTimeout>;
    const tick = () => {
      if (cancelled) return;
      if (targets.length === 0 || targets.some(t => findTarget(t)) || tries++ > 40) {
        setRunning(pending);
        setPending(null);
        return;
      }
      timer = setTimeout(tick, 100);
    };
    timer = setTimeout(tick, 250);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [pending, pathname]);

  const value = useMemo(() => ({ start, active: Boolean(running || pending) }), [start, running, pending]);

  return (
    <DemoContext.Provider value={value}>
      {children}
      {running && <DemoTour key={running.id} onEnd={() => setRunning(null)} script={running} />}
    </DemoContext.Provider>
  );
}

// ── Dialogs a demo walks through ────────────────────────────────────────────

/** Open (true) or close (false); returns false when there is nothing to open. */
type DialogHandler = (open: boolean) => boolean;

const dialogs = new Map<string, DialogHandler>();

/**
 * Lets a demo open one of this page's dialogs, e.g. the queue's incident
 * report, to walk through it. The handler opens it without the side effects a
 * real open has (a demo never presses anything for real) and returns false
 * when there is nothing to show.
 */
export function useDemoDialog(name: string, handler: DialogHandler) {
  const ref = useRef(handler);
  ref.current = handler;
  useEffect(() => {
    const call: DialogHandler = open => ref.current(open);
    dialogs.set(name, call);
    return () => {
      if (dialogs.get(name) === call) dialogs.delete(name);
    };
  }, [name]);
}

function setDialog(name: string, open: boolean): boolean {
  return dialogs.get(name)?.(open) ?? false;
}

// ── Finding and measuring a part of the page ────────────────────────────────

interface Box {
  top: number;
  left: number;
  width: number;
  height: number;
}

/** The first element marked `data-demo="<id>"` that is actually drawn. */
export function findTarget(id: string): HTMLElement | null {
  const all = document.querySelectorAll<HTMLElement>(`[data-demo="${CSS.escape(id)}"]`);
  for (const el of all) {
    if (measure(el)) return el;
  }
  return null;
}

/**
 * The element's box on screen. A `display: contents` wrapper (DemoTarget) has
 * no box of its own, so its children's boxes are joined instead.
 */
function measure(el: Element): Box | null {
  const r = el.getBoundingClientRect();
  if (r.width > 0 || r.height > 0) return { top: r.top, left: r.left, width: r.width, height: r.height };
  let top = Infinity;
  let left = Infinity;
  let right = -Infinity;
  let bottom = -Infinity;
  for (const child of el.children) {
    const b = measure(child);
    if (!b) continue;
    top = Math.min(top, b.top);
    left = Math.min(left, b.left);
    right = Math.max(right, b.left + b.width);
    bottom = Math.max(bottom, b.top + b.height);
  }
  return top === Infinity ? null : { top, left, width: right - left, height: bottom - top };
}

/** The element itself if it has a box, else its first descendant that does. */
function firstBoxed(el: Element): Element | null {
  const r = el.getBoundingClientRect();
  if (r.width > 0 || r.height > 0) return el;
  for (const child of el.children) {
    const b = firstBoxed(child);
    if (b) return b;
  }
  return null;
}

function sameBox(a: Box | null, b: Box | null) {
  if (!a || !b) return a === b;
  return (
    Math.abs(a.top - b.top) < 0.5 &&
    Math.abs(a.left - b.left) < 0.5 &&
    Math.abs(a.width - b.width) < 0.5 &&
    Math.abs(a.height - b.height) < 0.5
  );
}

// ── The tour ────────────────────────────────────────────────────────────────

type Placement = 'below' | 'above' | 'right' | 'left' | 'middle';

const GAP = 18;
const EDGE = 16;
const PAD = 8;

function DemoTour({ script, onEnd }: { script: DemoScript; onEnd: () => void }) {
  const reduceMotion = useReducedMotion();
  const [index, setIndex] = useState(0);
  const [box, setBox] = useState<Box | null>(null);
  const [moving, setMoving] = useState(true);
  const [viewport, setViewport] = useState({ w: 1280, h: 800 });
  const [card, setCard] = useState({ w: 440, h: 230 });
  const cardRef = useRef<HTMLDivElement>(null);
  const nextRef = useRef<HTMLButtonElement>(null);
  const step = script.steps[index];
  const last = index === script.steps.length - 1;

  // Whether the script's dialog is open now (the demo opened it).
  const dialogOpen = useRef(false);
  const dialogOpenedAt = useRef(0);
  const inDialog = Boolean(script.dialog && step.dialog);

  // Go to a step: open or close the script's dialog if this step needs it,
  // scroll its part into view, then measure once it has landed.
  useEffect(() => {
    setMoving(true);
    let cancelled = false;
    const timers: ReturnType<typeof setTimeout>[] = [];
    const wait = (ms: number) => new Promise<void>(done => timers.push(setTimeout(done, ms)));
    void (async () => {
      const id = step.target;
      if (script.dialog && inDialog !== dialogOpen.current) {
        const shown = setDialog(script.dialog, inDialog);
        dialogOpen.current = inDialog && shown;
        if (dialogOpen.current) dialogOpenedAt.current = Date.now();
        // The dialog fades in or out first.
        if (shown) await wait(260);
        if (cancelled) return;
      }
      let el = id ? findTarget(id) : null;
      // A dialog that has just opened loads its content: wait for the part,
      // for up to 3 s after it opened. (A part this report does not have is
      // then said from the middle, like on a page.)
      while (inDialog && dialogOpen.current && id && !el && Date.now() - dialogOpenedAt.current < 3000) {
        await wait(100);
        if (cancelled) return;
        el = findTarget(id);
      }
      if (cancelled) return;
      // A DemoTarget wrapper has no box, and scrollIntoView on it does nothing:
      // scroll its first drawn descendant instead. A part taller than most of
      // the screen is brought in by its top, so its heading is what shows.
      const boxed = el ? firstBoxed(el) : null;
      if (boxed) {
        const tall = boxed.getBoundingClientRect().height > window.innerHeight * 0.6;
        boxed.scrollIntoView({ block: tall ? 'start' : 'center', inline: 'nearest', behavior: reduceMotion ? 'auto' : 'smooth' });
      }
      await wait(el && !reduceMotion ? 420 : 30);
      if (cancelled) return;
      setBox(el ? measure(el) : null);
      setMoving(false);
    })();
    return () => {
      cancelled = true;
      timers.forEach(clearTimeout);
    };
  }, [index, step.target, inDialog, script.dialog, reduceMotion]);

  // Ending the demo — Done, Skip, Esc, or leaving the page — closes the dialog.
  useEffect(
    () => () => {
      if (script.dialog && dialogOpen.current) setDialog(script.dialog, false);
    },
    [script.dialog],
  );

  // Keep the light on the part while the page scrolls, resizes or loads.
  useEffect(() => {
    const update = () => {
      setViewport({ w: window.innerWidth, h: window.innerHeight });
      if (moving || !step.target) return;
      const el = findTarget(step.target);
      const next = el ? measure(el) : null;
      setBox(prev => (sameBox(prev, next) ? prev : next));
    };
    update();
    window.addEventListener('resize', update);
    window.addEventListener('scroll', update, true);
    const every = setInterval(update, 400);
    return () => {
      window.removeEventListener('resize', update);
      window.removeEventListener('scroll', update, true);
      clearInterval(every);
    };
  }, [moving, step.target]);

  useLayoutEffect(() => {
    const el = cardRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setCard({ w: el.offsetWidth, h: el.offsetHeight }));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  useEffect(() => {
    nextRef.current?.focus({ preventScroll: true });
  }, [index, moving]);

  const next = useCallback(() => (last ? onEnd() : setIndex(i => i + 1)), [last, onEnd]);
  const back = useCallback(() => setIndex(i => Math.max(0, i - 1)), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        // Not also to a dialog the demo opened: the demo closes that itself.
        e.preventDefault();
        e.stopPropagation();
        onEnd();
      } else if (e.key === 'ArrowRight') {
        e.preventDefault();
        next();
      } else if (e.key === 'ArrowLeft') {
        e.preventDefault();
        back();
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [next, back, onEnd]);

  // Only what is on screen is lit and pointed at: a part bigger than the
  // window (the map) is outlined where it can be seen, not past its edges.
  const lit = moving ? null : visible(box, viewport);
  const { placement, top, left } = place(lit, viewport, card);
  const pose = step.pose ?? (lit ? poseToward(lit, mascotBox(placement, top, left, viewport, card)) : 'point_you');

  return createPortal(
    // z-[1045]: over the map's own controls (up to z-[1000]), under an incident
    // dialog (z-[1100]) and the emergency alert cards (z-[1900]+) — an alert
    // that lands mid-demo is still seen and answered. Over a dialog the demo
    // opened itself (z-[1150]), still under the alert cards.
    <div
      aria-label={`Demo: ${script.title}`}
      aria-modal="true"
      // pointer-events-auto: an open dialog turns pointer events off on <body>.
      // data-demo-tour: so clicking Next does not count as clicking away from
      // a dialog the demo is explaining (lib/utils/top-layer.ts).
      className={cn('pointer-events-auto fixed inset-0 print:hidden', inDialog ? 'z-[1150]' : 'z-[1045]')}
      data-demo-tour=""
      data-testid="demo-tour"
      role="dialog"
    >
      {/* Clicks on the dimmed page go nowhere. */}
      <div className="absolute inset-0" onClick={e => e.stopPropagation()} />

      {lit ? (
        <>
          <div
            aria-hidden="true"
            className="pointer-events-none absolute rounded-[14px] border-[3px] border-[var(--color-brand)]"
            style={{
              ...ring(lit, viewport, 0),
              boxShadow: '0 0 0 9999px rgba(10, 10, 12, 0.62)',
              transition: reduceMotion ? undefined : 'top 260ms ease, left 260ms ease, width 260ms ease, height 260ms ease',
            }}
          />
          {/* Breathes in place (opacity only): a scaling ring grows with the
              target, and around a whole chart it swelled far past it. */}
          <motion.div
            animate={reduceMotion ? { opacity: 0.6 } : { opacity: [0.75, 0.15, 0.75] }}
            aria-hidden="true"
            className="pointer-events-none absolute rounded-[18px] border-2 border-[var(--color-brand)]"
            style={ring(lit, viewport, 5)}
            transition={reduceMotion ? undefined : { duration: 1.6, repeat: Infinity, ease: 'easeInOut' }}
          />
        </>
      ) : (
        <div aria-hidden="true" className="pointer-events-none absolute inset-0 bg-[rgba(10,10,12,0.62)]" />
      )}

      <div
        className="absolute"
        data-placement={placement}
        ref={cardRef}
        style={{
          top,
          left,
          width: Math.min(460, viewport.w - EDGE * 2),
          transition: reduceMotion ? undefined : 'top 260ms ease, left 260ms ease',
        }}
      >
        <AnimatePresence mode="wait">
          <motion.div
            animate={{ opacity: 1, y: 0, scale: 1 }}
            className={cn('flex items-end gap-1', placement === 'left' && 'flex-row-reverse')}
            exit={{ opacity: 0, y: 6, scale: 0.98 }}
            initial={reduceMotion ? false : { opacity: 0, y: 8, scale: 0.97 }}
            key={index}
            transition={{ duration: 0.18 }}
          >
            <Mascot pose={pose} />
            <Bubble
              count={script.steps.length}
              index={index}
              last={last}
              nextRef={nextRef}
              onBack={index > 0 ? back : undefined}
              onNext={next}
              onSkip={onEnd}
              tail={placement === 'left' ? 'right' : 'left'}
              text={step.text}
              title={script.title}
            />
          </motion.div>
        </AnimatePresence>
      </div>
    </div>,
    document.body,
  );
}

/**
 * Where the bubble goes: beside a tall target at the screen's edge (the
 * sidebar), else below or above it — whichever has room — and in the middle
 * when there is nothing to point at.
 */
function place(
  box: Box | null,
  viewport: { w: number; h: number },
  card: { w: number; h: number },
): { placement: Placement; top: number; left: number } {
  const { w: W, h: H } = viewport;
  const cw = Math.min(card.w, W - EDGE * 2);
  const ch = card.h;
  const clampX = (x: number) => Math.max(EDGE, Math.min(x, W - cw - EDGE));
  const clampY = (y: number) => Math.max(EDGE, Math.min(y, H - ch - EDGE));
  if (!box) return { placement: 'middle', top: clampY(H * 0.38 - ch / 2), left: clampX(W / 2 - cw / 2) };

  const right = W - (box.left + box.width);
  const below = H - (box.top + box.height);
  const tall = box.height > H * 0.45;
  const sideFirst = tall || box.width < W * 0.25;

  const beside = (): { placement: Placement; top: number; left: number } | null => {
    const y = clampY(box.top + box.height / 2 - ch / 2);
    if (right >= cw + GAP + PAD + EDGE) return { placement: 'right', top: y, left: box.left + box.width + PAD + GAP };
    if (box.left >= cw + GAP + PAD + EDGE) return { placement: 'left', top: y, left: box.left - PAD - GAP - cw };
    return null;
  };
  const stacked = (): { placement: Placement; top: number; left: number } | null => {
    const x = clampX(box.left + box.width / 2 - cw * 0.3);
    if (below >= ch + GAP + PAD) return { placement: 'below', top: box.top + box.height + PAD + GAP, left: x };
    if (box.top >= ch + GAP + PAD) return { placement: 'above', top: box.top - PAD - GAP - ch, left: x };
    return null;
  };

  const chosen = sideFirst ? (beside() ?? stacked()) : (stacked() ?? beside());
  // Never off the screen, whatever the target does (a part still scrolling in,
  // or one taller than the window).
  if (chosen) return { ...chosen, top: clampY(chosen.top), left: Math.max(EDGE, Math.min(chosen.left, W - cw - EDGE)) };
  // No clean room anywhere (a target filling the screen): over its lower part.
  return { placement: 'above', top: clampY(H - ch - EDGE), left: clampX(W / 2 - cw / 2) };
}

/** The part of [box] inside the window, or null when none of it is. */
function visible(box: Box | null, viewport: { w: number; h: number }): Box | null {
  if (!box) return null;
  const top = Math.max(box.top, 0);
  const left = Math.max(box.left, 0);
  const bottom = Math.min(box.top + box.height, viewport.h);
  const right = Math.min(box.left + box.width, viewport.w);
  if (bottom - top < 4 || right - left < 4) return null;
  return { top, left, width: right - left, height: bottom - top };
}

/**
 * The outline around [lit], [grow] px further out, kept inside the window so
 * all four sides of it show — around a part that fills the screen too.
 */
function ring(lit: Box, viewport: { w: number; h: number }, grow: number) {
  const m = 6 - grow;
  const top = Math.max(lit.top - PAD - grow, m);
  const left = Math.max(lit.left - PAD - grow, m);
  const bottom = Math.min(lit.top + lit.height + PAD + grow, viewport.h - m);
  const right = Math.min(lit.left + lit.width + PAD + grow, viewport.w - m);
  return { top, left, width: right - left, height: bottom - top };
}

const MASCOT_W = 118;
const MASCOT_H = 150;

/** Where the mascot stands on screen: the bubble's left end, or its right end when the card is flipped. */
function mascotBox(
  placement: Placement,
  top: number,
  left: number,
  viewport: { w: number; h: number },
  card: { w: number; h: number },
): Box {
  const cw = Math.min(card.w, viewport.w - EDGE * 2);
  return {
    top: top + Math.max(card.h, MASCOT_H) - MASCOT_H,
    left: placement === 'left' ? left + cw - MASCOT_W : left,
    width: MASCOT_W,
    height: MASCOT_H,
  };
}

/**
 * The pointing pose from where the mascot really ended up: towards the
 * nearest edge of the part, along whichever way is further. Taken from the
 * finished position rather than the side the bubble was meant to go — a
 * bubble pushed back on screen, or laid over a part that fills the window,
 * used to point down at a part that was above it.
 */
function poseToward(target: Box, mascot: Box): DemoPose {
  const mx = mascot.left + mascot.width / 2;
  const my = mascot.top + mascot.height / 2;
  const tx = Math.max(target.left, Math.min(mx, target.left + target.width));
  const ty = Math.max(target.top, Math.min(my, target.top + target.height));
  // Standing over the part (the map): up or down towards its middle, never
  // sideways — sideways is into the mascot's own bubble.
  if (tx === mx && ty === my) {
    return target.top + target.height / 2 <= my ? 'point_up' : 'point_down';
  }
  const dx = tx - mx;
  const dy = ty - my;
  if (Math.abs(dx) < 2 && Math.abs(dy) < 2) return 'point_you';
  if (Math.abs(dy) >= Math.abs(dx)) return dy < 0 ? 'point_up' : 'point_down';
  return dx < 0 ? 'point_left' : 'point_right';
}

function Mascot({ pose }: { pose: DemoPose }) {
  return (
    <span className="relative flex h-[150px] w-[118px] shrink-0 items-end justify-center">
      <span
        aria-hidden="true"
        className="absolute bottom-1 left-1/2 size-[112px] -translate-x-1/2 rounded-full"
        style={{ background: 'radial-gradient(circle, rgba(255,255,255,0.92) 0%, rgba(255,231,217,0.75) 45%, rgba(255,231,217,0) 72%)' }}
      />
      <span className="ziren-float relative block">
        <Image
          alt="Ziren"
          className="h-[138px] w-auto max-w-none select-none object-contain drop-shadow-[0_6px_10px_rgba(0,0,0,0.35)]"
          draggable={false}
          height={276}
          key={pose}
          priority
          src={`/demo/${pose}.png`}
          width={220}
        />
      </span>
    </span>
  );
}

function Bubble({
  title,
  text,
  index,
  count,
  last,
  tail,
  nextRef,
  onSkip,
  onBack,
  onNext,
}: {
  title: string;
  text: string;
  index: number;
  count: number;
  last: boolean;
  tail: 'left' | 'right';
  nextRef: React.RefObject<HTMLButtonElement | null>;
  onSkip: () => void;
  onBack?: () => void;
  onNext: () => void;
}) {
  return (
    <div className="relative mb-3 min-w-0 flex-1 rounded-2xl border-2 border-[color-mix(in_srgb,var(--color-brand)_55%,transparent)] bg-[var(--color-surface-card)] px-4 pb-3 pt-3 shadow-[0_14px_36px_rgba(0,0,0,0.28)]">
      <span
        aria-hidden="true"
        className={cn(
          'absolute bottom-5 size-3.5 rotate-45 rounded-[2px] bg-[var(--color-surface-card)]',
          tail === 'left'
            ? '-left-[9px] border-b-2 border-l-2 border-[color-mix(in_srgb,var(--color-brand)_55%,transparent)]'
            : '-right-[9px] border-r-2 border-t-2 border-[color-mix(in_srgb,var(--color-brand)_55%,transparent)]',
        )}
      />
      <div className="flex items-center gap-2">
        <span className="rounded bg-[var(--color-brand)] px-1.5 py-0.5 text-[10px] font-black tracking-[0.12em] text-white">DEMO</span>
        <span className="min-w-0 flex-1 truncate text-[12.5px] font-extrabold text-[var(--color-brand)]">{title}</span>
        <span className="font-mono text-[11.5px] font-semibold text-muted-foreground">
          {index + 1} / {count}
        </span>
      </div>
      <p aria-live="polite" className="mt-2 text-[14.5px] font-semibold leading-relaxed text-foreground">
        {text}
      </p>
      <div aria-hidden="true" className="mt-3 flex gap-1">
        {Array.from({ length: count }).map((_, i) => (
          <span
            className={cn('h-1 flex-1 rounded-full', i <= index ? 'bg-[var(--color-brand)]' : 'bg-[var(--color-surface-border)]')}
            key={i}
          />
        ))}
      </div>
      <div className="mt-2.5 flex items-center gap-2">
        {!last && (
          <button
            className="rounded-lg px-2 py-1.5 text-[13px] font-semibold text-muted-foreground hover:bg-[var(--color-surface-raised)] hover:text-foreground"
            onClick={onSkip}
            type="button"
          >
            Skip
          </button>
        )}
        <span className="flex-1" />
        {onBack && (
          <button
            aria-label="Back"
            className="flex size-9 items-center justify-center rounded-lg border border-[var(--color-surface-border)] text-muted-foreground hover:bg-[var(--color-surface-raised)] hover:text-foreground"
            onClick={onBack}
            type="button"
          >
            <ArrowLeft className="size-4" />
          </button>
        )}
        <button
          className="flex h-9 items-center gap-1.5 rounded-lg bg-[var(--color-brand)] px-4 text-[13.5px] font-extrabold text-white shadow-[0_4px_12px_rgba(252,90,5,0.35)] hover:brightness-110 focus-visible:outline-none focus-visible:ring-4 focus-visible:ring-[color-mix(in_srgb,var(--color-brand)_35%,transparent)]"
          onClick={onNext}
          ref={nextRef}
          type="button"
        >
          {last ? 'Done' : 'Next'}
          {last ? <Check className="size-4" /> : <ArrowRight className="size-4" />}
        </button>
      </div>
    </div>
  );
}
