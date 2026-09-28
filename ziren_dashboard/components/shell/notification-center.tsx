'use client';

/**
 * NotificationCenter - the header bell, as a real inbox.
 *
 * It used to be a 320px dropdown of plain text rows with a dot on the bell.
 * That is enough for "a station was created" and not enough for what now lands
 * here: a new report for your agency, another agency asking for help, a
 * resident answering the question you asked, a responder escalating. Those are
 * things an operator acts on, so the centre does what an inbox does:
 *
 *   - a COUNT on the bell, not just a dot, that pulses when something arrives;
 *   - grouped by day, with a tile per kind of event so a list can be scanned by
 *     shape before it is read;
 *   - All / Unread / Important, because "what still needs me" is the question;
 *   - a row that opens the thing it is about, and marks itself read doing so;
 *   - "Mark all read", and "Show older" instead of a silent cap of twenty.
 *
 * NEW ARRIVALS also raise a toast (see lib/toast.ts) - the panel is closed most
 * of the time, and an "assist request" that only changes a number on an icon
 * is one nobody notices. New INCIDENTS are excluded on purpose: the incident
 * alert already takes the whole screen for those, and a toast stacked on top of
 * it is the same news twice.
 *
 * Colour follows the console's rules. Red appears only for a critical incident;
 * "important" is an amber word and a bar, never red. Every row carries an icon
 * and, where it matters, a word - never colour alone.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Popover as PopoverPrimitive } from 'radix-ui';
import { AnimatePresence, motion } from 'framer-motion';
import {
  AlertCircle, Bell, BellRing, Building2, Check, CheckCheck, Handshake, Inbox,
  Loader2, Megaphone, RefreshCw, Settings2, ShieldCheck, Siren, UserPlus, UserRound,
} from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';
import { useNotifications } from '@/lib/hooks/useNotifications';
import type { NotificationItem } from '@/lib/api/notifications';
import { toast } from '@/lib/toast';
import { relativeTime } from '@/lib/format/relative-time';

// ── What kind of event is this? ──────────────────────────────────────────────

interface Kind {
  Icon: typeof Bell;
  color: string;
  bg: string;
  /** Shown as a word next to the time, so a tile is never the only cue. */
  label: string;
}

const NEUTRAL: Kind = {
  Icon: Bell, color: 'var(--color-text-secondary)', bg: 'var(--color-surface-raised)', label: 'Update',
};

function kindOf(n: NotificationItem): Kind {
  const t = n.type;
  // A critical report is the one place red is allowed: incident.received is
  // flagged important by the backend only when severity is critical.
  if (t === 'incident.received') {
    return n.is_important
      ? { Icon: Siren, color: 'var(--color-severity-critical)', bg: 'var(--color-severity-critical-bg)', label: 'Critical report' }
      : { Icon: Siren, color: 'var(--color-status-dispatched)', bg: 'var(--color-status-dispatched-bg)', label: 'New report' };
  }
  if (t === 'incident.clarification_answered' || t === 'incident.note_added') {
    return { Icon: UserRound, color: 'var(--color-system-info)', bg: 'var(--color-system-info-bg)', label: 'Resident replied' };
  }
  if (t === 'responder.escalated') {
    return { Icon: AlertCircle, color: 'var(--color-system-warning)', bg: 'var(--color-system-warning-bg)', label: 'Escalated' };
  }
  if (t.startsWith('incident.') || t.startsWith('responder.accepted')) {
    return { Icon: ShieldCheck, color: 'var(--color-system-success)', bg: 'var(--color-system-success-bg)', label: 'Incident' };
  }
  if (t === 'assist_request' || t === 'assist_response') {
    return { Icon: Handshake, color: 'var(--color-system-info)', bg: 'var(--color-system-info-bg)', label: 'Assist' };
  }
  if (t.startsWith('responder.')) {
    return { Icon: UserPlus, color: 'var(--color-status-processing)', bg: 'var(--color-status-processing-bg)', label: 'Responder' };
  }
  if (t.startsWith('station.') || t.startsWith('agency_admin.') || t.startsWith('account.') || t.startsWith('verification.')) {
    return { Icon: Building2, color: 'var(--color-status-processing)', bg: 'var(--color-status-processing-bg)', label: 'Accounts' };
  }
  if (t.startsWith('announcement.')) {
    return { Icon: Megaphone, color: 'var(--color-text-secondary)', bg: 'var(--color-surface-raised)', label: 'Announcement' };
  }
  if (t.startsWith('rubric.') || t.startsWith('system_config.')) {
    return { Icon: Settings2, color: 'var(--color-text-secondary)', bg: 'var(--color-surface-raised)', label: 'System' };
  }
  return NEUTRAL;
}

// ── Time ─────────────────────────────────────────────────────────────────────

type DayGroup = 'Today' | 'Yesterday' | 'Earlier';

function dayGroup(iso: string, now: number): DayGroup {
  const d = new Date(iso);
  const start = new Date(now); start.setHours(0, 0, 0, 0);
  if (d >= start) return 'Today';
  const yesterday = new Date(start); yesterday.setDate(yesterday.getDate() - 1);
  return d >= yesterday ? 'Yesterday' : 'Earlier';
}

// ── The centre ───────────────────────────────────────────────────────────────

type Tab = 'all' | 'unread' | 'important';

export function NotificationCenter({ token }: { token: string | null }) {
  const router = useRouter();
  const nc = useNotifications(token);
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<Tab>('all');
  const [now, setNow] = useState(() => Date.now());
  const [pulse, setPulse] = useState(false);

  // Relative times must not freeze while the panel sits open.
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(id);
  }, []);

  // Open means "look now": refresh so the list is not up to fifteen seconds old.
  useEffect(() => { if (open) { nc.refresh(); setNow(Date.now()); } }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  // New arrivals: pulse the bell, and toast anything that is not a new report.
  const lastArrival = useRef<string>('');
  useEffect(() => {
    if (nc.arrived.length === 0) return;
    const key = nc.arrived.map(n => n.id).join(',');
    if (key === lastArrival.current) return;
    lastArrival.current = key;

    setPulse(true);
    const off = setTimeout(() => setPulse(false), 2400);

    const toasted = nc.arrived.filter(n => n.type !== 'incident.received');
    const go = (n: NotificationItem) => () => { nc.markRead(n.id); if (n.link) router.push(n.link); };
    if (toasted.length === 1) {
      const n = toasted[0];
      toast.info(n.title, { detail: n.body ?? undefined, action: n.link ? { label: 'Open', onClick: go(n) } : undefined });
    } else if (toasted.length > 1) {
      toast.info(`${toasted.length} new notifications`, { detail: toasted[toasted.length - 1].title });
    }
    return () => clearTimeout(off);
  }, [nc.arrived]); // eslint-disable-line react-hooks/exhaustive-deps

  const importantUnread = useMemo(() => nc.items.filter(n => n.is_important && !n.is_read).length, [nc.items]);

  const visible = useMemo(() => {
    if (tab === 'unread') return nc.items.filter(n => !n.is_read);
    if (tab === 'important') return nc.items.filter(n => n.is_important);
    return nc.items;
  }, [nc.items, tab]);

  const groups = useMemo(() => {
    const out: { name: DayGroup; rows: NotificationItem[] }[] = [];
    for (const n of visible) {
      const name = dayGroup(n.created_at, now);
      const last = out[out.length - 1];
      if (last && last.name === name) last.rows.push(n); else out.push({ name, rows: [n] });
    }
    return out;
  }, [visible, now]);

  const openItem = (n: NotificationItem) => {
    if (!n.is_read) nc.markRead(n.id);
    setOpen(false);
    if (n.link) router.push(n.link);
  };

  const count = nc.unreadCount;
  const badge = count > 9 ? '9+' : String(count);

  return (
    <PopoverPrimitive.Root onOpenChange={setOpen} open={open}>
      <PopoverPrimitive.Trigger asChild>
        <Button
          aria-label={count > 0 ? `Notifications, ${count} unread` : 'Notifications'}
          className="relative"
          size="icon-sm"
          variant="outline"
        >
          {/* The ring is the arrival cue; motion is skipped for anyone who has
              asked for less of it (see the reduced-motion rule in globals.css). */}
          {pulse ? <BellRing className="motion-safe:animate-[wiggle_0.6s_ease-in-out_2]" /> : <Bell />}
          {count > 0 && (
            <span
              aria-hidden="true"
              className="absolute -right-1.5 -top-1.5 flex h-4 min-w-4 items-center justify-center rounded-full px-1 text-[10px] font-bold leading-none tabular-nums ring-2 ring-[var(--color-frame)]"
              style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
            >
              {badge}
            </span>
          )}
        </Button>
      </PopoverPrimitive.Trigger>

      <PopoverPrimitive.Portal>
        <PopoverPrimitive.Content
          align="end"
          className="z-[1100] w-[min(420px,calc(100vw-1.5rem))] origin-(--radix-popover-content-transform-origin) overflow-hidden rounded-xl bg-popover text-popover-foreground shadow-lg ring-1 ring-foreground/10 outline-none data-open:animate-in data-open:fade-in-0 data-open:zoom-in-95 data-closed:animate-out data-closed:fade-out-0 data-closed:zoom-out-95"
          collisionPadding={12}
          sideOffset={8}
        >
          {/* ── Header ─────────────────────────────────────────── */}
          <div className="flex items-center justify-between gap-2 px-4 pt-3.5 pb-2.5">
            <div className="flex items-center gap-2">
              <h2 className="text-[14px] font-semibold">Notifications</h2>
              {count > 0 && (
                <span
                  className="rounded-full px-2 py-0.5 text-[11px] font-semibold tabular-nums"
                  style={{ backgroundColor: 'var(--color-brand-subtle)', color: 'var(--color-brand)' }}
                >
                  {count} new
                </span>
              )}
            </div>
            <div className="flex items-center gap-1">
              <button
                className="flex items-center gap-1 rounded-md px-2 py-1 text-[12px] font-medium text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground disabled:pointer-events-none disabled:opacity-40"
                disabled={count === 0}
                onClick={nc.markAllRead}
                type="button"
              >
                <CheckCheck size={13} /> Mark all read
              </button>
            </div>
          </div>

          {/* ── Tabs ───────────────────────────────────────────── */}
          <div className="flex gap-1 border-b px-3 pb-2" role="tablist">
            {([
              ['all', 'All', null],
              ['unread', 'Unread', count],
              ['important', 'Important', importantUnread],
            ] as const).map(([key, label, n]) => (
              <button
                aria-selected={tab === key}
                className="flex items-center gap-1.5 rounded-md px-2.5 py-1 text-[12.5px] font-medium transition-colors"
                key={key}
                onClick={() => setTab(key)}
                role="tab"
                style={tab === key
                  ? { backgroundColor: 'var(--color-surface-raised)', color: 'var(--color-text-primary)' }
                  : { color: 'var(--color-text-muted)' }}
                type="button"
              >
                {label}
                {n !== null && n > 0 && (
                  <span className="rounded-full bg-[var(--color-surface-border)] px-1.5 text-[10.5px] font-semibold tabular-nums">
                    {n}
                  </span>
                )}
              </button>
            ))}
          </div>

          {/* ── List ───────────────────────────────────────────── */}
          <div className="max-h-[min(460px,60vh)] overflow-y-auto overscroll-contain" role="tabpanel">
            {nc.loading ? (
              <ListSkeleton />
            ) : nc.error ? (
              <Empty
                action={<button className="mt-3 inline-flex items-center gap-1.5 text-[12.5px] font-semibold text-[var(--color-brand)]" onClick={nc.refresh} type="button"><RefreshCw size={13} /> Try again</button>}
                Icon={AlertCircle}
                text="The list could not be loaded. Check your connection."
                title="Notifications unavailable"
              />
            ) : visible.length === 0 ? (
              <Empty
                Icon={tab === 'all' ? Inbox : CheckCheck}
                text={tab === 'unread' ? 'Nothing is waiting on you.' : tab === 'important' ? 'No important notifications.' : 'New reports, assist requests and replies will show up here.'}
                title={tab === 'all' ? 'No notifications yet' : 'All caught up'}
              />
            ) : (
              <AnimatePresence initial={false}>
                {groups.map(g => (
                  <section key={g.name}>
                    <h3 className="sticky top-0 z-10 bg-popover/95 px-4 py-1.5 text-[11px] font-semibold tracking-wide text-muted-foreground uppercase backdrop-blur">
                      {g.name}
                    </h3>
                    <ul>
                      {g.rows.map(n => (
                        <Row key={n.id} n={n} now={now} onMarkRead={() => nc.markRead(n.id)} onOpen={() => openItem(n)} />
                      ))}
                    </ul>
                  </section>
                ))}
              </AnimatePresence>
            )}

            {!nc.loading && !nc.error && nc.hasMore && tab === 'all' && (
              <div className="border-t p-2">
                <button
                  className="flex w-full items-center justify-center gap-2 rounded-md py-2 text-[12.5px] font-medium text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground disabled:opacity-60"
                  disabled={nc.loadingMore}
                  onClick={nc.loadMore}
                  type="button"
                >
                  {nc.loadingMore && <Loader2 className="animate-spin" size={13} />}
                  Show older
                </button>
              </div>
            )}
          </div>

          {/* ── Footer ─────────────────────────────────────────── */}
          <div className="flex items-center justify-between border-t px-4 py-2.5 text-[12px] text-muted-foreground">
            <span>{nc.items.length > 0 ? `${nc.items.length} shown` : 'Updates every 15 seconds'}</span>
            <button
              className="font-medium hover:text-foreground"
              onClick={() => { setOpen(false); router.push('/announcements'); }}
              type="button"
            >
              View announcements
            </button>
          </div>
        </PopoverPrimitive.Content>
      </PopoverPrimitive.Portal>
    </PopoverPrimitive.Root>
  );
}

// ── One notification ─────────────────────────────────────────────────────────

function Row({
  n, now, onOpen, onMarkRead,
}: {
  n: NotificationItem; now: number; onOpen: () => void; onMarkRead: () => void;
}) {
  const kind = kindOf(n);
  const { Icon } = kind;
  const unread = !n.is_read;

  return (
    <motion.li
      animate={{ opacity: 1 }}
      className="group/row relative"
      exit={{ opacity: 0 }}
      initial={{ opacity: 0 }}
      layout="position"
    >
      {/* An important, unread notification carries a bar as well as a word. */}
      {n.is_important && unread && (
        <span
          aria-hidden="true"
          className="absolute inset-y-0 left-0 w-[3px]"
          style={{ backgroundColor: n.type === 'incident.received' ? 'var(--color-severity-critical)' : 'var(--color-system-warning)' }}
        />
      )}
      <button
        className="flex w-full items-start gap-3 px-4 py-3 text-left transition-colors hover:bg-[var(--color-surface-hover)] focus-visible:bg-[var(--color-surface-hover)] focus-visible:outline-none"
        onClick={onOpen}
        style={unread ? { backgroundColor: 'var(--color-brand-subtle)' } : undefined}
        type="button"
      >
        <span
          aria-hidden="true"
          className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full"
          style={{ backgroundColor: kind.bg, color: kind.color }}
        >
          <Icon size={15} />
        </span>

        <span className="min-w-0 flex-1">
          <span className="flex items-start justify-between gap-2">
            <span className={`text-[13px] leading-snug ${unread ? 'font-semibold text-foreground' : 'font-medium text-muted-foreground'}`}>
              {n.title}
            </span>
            {unread && <span aria-label="Unread" className="mt-1.5 size-2 shrink-0 rounded-full" style={{ backgroundColor: 'var(--color-brand)' }} />}
          </span>
          {n.body && (
            <span className="mt-0.5 line-clamp-2 block text-[12.5px] leading-snug text-muted-foreground">{n.body}</span>
          )}
          <span className="mt-1 flex items-center gap-1.5 text-[11.5px] text-muted-foreground">
            <span style={{ color: kind.color }} className="font-semibold">{kind.label}</span>
            {n.is_important && unread && n.type !== 'incident.received' && (
              <>
                <span aria-hidden="true">·</span>
                <span className="font-semibold" style={{ color: 'var(--color-system-warning)' }}>Important</span>
              </>
            )}
            <span aria-hidden="true">·</span>
            <time dateTime={n.created_at}>{relativeTime(n.created_at, now, { absoluteAfterDays: 7 })}</time>
          </span>
        </span>
      </button>

      {unread && (
        <button
          aria-label="Mark as read"
          className="absolute right-3 bottom-2.5 hidden size-6 items-center justify-center rounded-full bg-popover text-muted-foreground shadow-sm ring-1 ring-foreground/10 transition-colors group-hover/row:flex hover:text-foreground focus-visible:flex"
          onClick={onMarkRead}
          title="Mark as read"
          type="button"
        >
          <Check size={13} />
        </button>
      )}
    </motion.li>
  );
}

// ── States ───────────────────────────────────────────────────────────────────

function Empty({
  Icon, title, text, action,
}: {
  Icon: typeof Bell; title: string; text: string; action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center px-8 py-12 text-center">
      <span className="mb-3 flex size-11 items-center justify-center rounded-full" style={{ backgroundColor: 'var(--color-surface-raised)', color: 'var(--color-text-muted)' }}>
        <Icon size={20} />
      </span>
      <p className="text-[13.5px] font-semibold">{title}</p>
      <p className="mt-1 text-[12.5px] leading-snug text-muted-foreground">{text}</p>
      {action}
    </div>
  );
}

function ListSkeleton() {
  return (
    <div aria-busy="true" aria-label="Loading notifications">
      {Array.from({ length: 4 }).map((_, i) => (
        <div className="flex gap-3 px-4 py-3" key={i}>
          <div className="size-8 shrink-0 animate-pulse rounded-full bg-muted" />
          <div className="flex-1 space-y-2 pt-0.5">
            <div className="h-3 w-3/4 animate-pulse rounded bg-muted" />
            <div className="h-3 w-1/2 animate-pulse rounded bg-muted" />
          </div>
        </div>
      ))}
    </div>
  );
}
