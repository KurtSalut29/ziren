'use client';

/**
 * One announcement in the list.
 *
 *   ┌ tinted band: [icon] KIND · ● Live · Forced        52m ago · MDRRMO   [All clear] [⋯] ┐
 *   │ Title                                                                                 │
 *   │ Message                                                                               │
 *   │ [Go to  Naval Central School] [Bring  Go-bag…]           fact tiles                   │
 *   │ (📍 Naval · Atipolo, Caraycaray) (👥 Residents) (⏱ Until 1 Oct, 9:57 PM)             │
 *   ├ Answers ████████████░░░░  44 of 57 answered    ● 2 need help ● 41 safe ● 13 silent  [Open answers] ┤
 *
 * The answer strip is why the card is shaped like this. After an evacuation
 * order the question a station has is "who is still out there?" - the strip
 * answers it with a number against the number asked, one click from the names.
 */

import { useState } from 'react';
import {
  ArrowRight, CalendarClock, ChevronDown, ChevronUp, CircleDot, DoorOpen, EyeOff, LifeBuoy,
  MapPin, MoreHorizontal, Package, Phone, Route, ShieldCheck, TriangleAlert, User, Users,
  type LucideIcon,
} from 'lucide-react';
import type { Announcement } from '@/lib/api/announcements';
import { formatDateTime } from '@/lib/format/datetime';
import { relativeTime } from '@/lib/format/relative-time';
import { cn } from '@/lib/utils';
import { Button } from '@/components/efferd/ui/button';
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger,
} from '@/components/efferd/ui/dropdown-menu';
import { factChips, kindOf, mayEnd, placeLine, TARGET_LABEL } from './kinds';

export type CardState = 'active' | 'ended' | 'expired' | 'inactive';

export function stateOf(a: Announcement, now = Date.now()): CardState {
  if (a.ended_at || (!a.is_active && a.ended_by_announcement_id)) return 'ended';
  if (!a.is_active) return 'inactive';
  if (a.expires_at && new Date(a.expires_at).getTime() <= now) return 'expired';
  return 'active';
}

const STATE_LABEL: Record<Exclude<CardState, 'active'>, string> = {
  ended: 'Ended by all clear',
  expired: 'Expired',
  inactive: 'Taken down',
};

export const HELP = 'var(--color-severity-critical)';
export const SAFE = 'var(--color-system-success)';

export function AnnouncementCard({
  a, now, audienceName, canManage: isManager, agencyType, highlight, onAnswers, onAllClear, onTakeDown,
}: {
  a: Announcement;
  now: number;
  /** "One agency" resolved to its name. */
  audienceName?: string;
  /** Provincial Admin: may end and take down - their own office's. */
  canManage: boolean;
  agencyType?: string | null;
  highlight?: boolean;
  onAnswers: () => void;
  onAllClear: () => void;
  onTakeDown: () => void;
}) {
  const kind = kindOf(a.category);
  // Only the office that issued it ends it or takes it down (the server says so too).
  const canManage = isManager && mayEnd(a.issuer_agency_type, agencyType);
  const state = stateOf(a, now);
  const live = state === 'active';
  const [open, setOpen] = useState(false);
  const long = a.body.length > 260;
  const chips = factChips(a.category, a.details);
  const d = a.details ?? {};
  const tone = live ? kind.color : 'var(--color-text-muted)';
  const canClear = canManage && live && kind.group === 'safety' && a.category !== 'all_clear';

  return (
    <article
      className={cn(
        'overflow-hidden rounded-[var(--radius-card)] border bg-[var(--color-surface-card)] shadow-[var(--shadow-card)] transition-shadow',
        highlight ? 'border-[var(--color-brand)] ring-2 ring-[var(--color-brand)]/25' : 'border-[var(--color-surface-border)]',
      )}
      data-announcement={a.id}
      data-kind={a.category}
      data-state={state}
    >
      {/* ── Band: what kind, is it live, who sent it ───────────── */}
      <header
        className="flex flex-wrap items-center gap-x-3 gap-y-2 border-b px-4 py-3 sm:px-5"
        style={{
          borderColor: live ? `color-mix(in srgb, ${kind.color} 18%, var(--color-surface-border))` : 'var(--color-surface-border)',
          background: live
            ? `linear-gradient(90deg, color-mix(in srgb, ${kind.color} 11%, var(--color-surface-card)), color-mix(in srgb, ${kind.color} 3%, var(--color-surface-card)))`
            : 'var(--color-surface-raised)',
        }}
      >
        <span
          aria-hidden="true"
          className="flex size-9 shrink-0 items-center justify-center rounded-[10px]"
          style={live
            ? { color: '#fff', backgroundColor: `color-mix(in srgb, ${kind.color} 84%, black)` }
            : { color: 'var(--color-text-muted)', backgroundColor: 'var(--color-surface-card)', boxShadow: 'inset 0 0 0 1px var(--color-surface-border)' }}
        >
          <kind.Icon size={18} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <span className="text-[12px] font-bold tracking-wide uppercase" style={{ color: tone }}>{kind.label}</span>
            {live ? (
              <span className="inline-flex items-center gap-1.5 rounded-full bg-[var(--color-surface-card)] px-2 py-0.5 text-[11px] font-semibold text-foreground shadow-[inset_0_0_0_1px_var(--color-surface-border)]" data-testid="live-pill">
                <span className="relative flex size-2">
                  <span className="absolute inline-flex size-full rounded-full opacity-60 motion-safe:animate-ping" style={{ backgroundColor: kind.color }} />
                  <span className="relative inline-flex size-2 rounded-full" style={{ backgroundColor: kind.color }} />
                </span>
                Live
              </span>
            ) : (
              <span className="rounded-full bg-[var(--color-surface-card)] px-2 py-0.5 text-[11px] font-semibold text-[var(--color-text-secondary)] shadow-[inset_0_0_0_1px_var(--color-surface-border)]">
                {STATE_LABEL[state]}
              </span>
            )}
            {chips.map(f => (
              <span
                className="rounded-full px-2 py-0.5 text-[11px] font-semibold"
                key={f.label}
                style={f.color && live
                  ? { color: f.color, backgroundColor: `color-mix(in srgb, ${f.color} 12%, var(--color-surface-card))` }
                  : { color: 'var(--color-text-secondary)', backgroundColor: 'var(--color-surface-card)', boxShadow: 'inset 0 0 0 1px var(--color-surface-border)' }}
              >
                {f.label}
              </span>
            ))}
            {a.for_you === false && (
              <span className="rounded-full px-2 py-0.5 text-[11px] font-medium text-muted-foreground shadow-[inset_0_0_0_1px_var(--color-surface-border)]" title="Sent to people in your town, not to agency admins. Shown so your station knows.">
                Announced to your town
              </span>
            )}
          </div>
          <p className="mt-0.5 text-[12px] text-[var(--color-text-secondary)]">
            <span title={formatDateTime(a.created_at)}>{relativeTime(a.created_at, now, { absoluteAfterDays: 6 })}</span>
            {a.issuer_agency_type ? ` · ${a.issuer_agency_type} provincial office` : ''}
          </p>
        </div>
        {(canClear || (canManage && live)) && (
          <div className="flex items-center gap-1.5">
            {canClear && (
              <Button className="bg-[var(--color-surface-card)]" onClick={onAllClear} size="sm" variant="outline">
                <ShieldCheck data-icon="inline-start" style={{ color: SAFE }} />
                Send all clear
              </Button>
            )}
            {canManage && live && (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button aria-label={`More for ${a.title}`} className="bg-[var(--color-surface-card)]" size="icon-sm" variant="outline">
                    <MoreHorizontal />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuItem onSelect={onTakeDown} variant="destructive">
                    <EyeOff /> Take down
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            )}
          </div>
        )}
      </header>

      {/* ── What it says ────────────────────────────────────────── */}
      <div className="flex flex-col gap-3.5 px-4 py-4 sm:px-5">
        <div>
          <h3 className="text-[16.5px] leading-snug font-semibold text-foreground">{a.title}</h3>
          {a.category === 'all_clear' && d.ends_title && (
            <p className="mt-1 flex items-center gap-1.5 text-[12.5px] text-[var(--color-text-secondary)]">
              <ShieldCheck aria-hidden="true" className="size-3.5" style={{ color: SAFE }} />
              Ends <span className="font-medium text-foreground">{d.ends_title}</span>
            </p>
          )}
          <p className={cn('mt-1.5 text-[13.5px] leading-relaxed whitespace-pre-line text-[var(--color-text-secondary)]', !open && long && 'line-clamp-3')}>
            {a.body}
          </p>
          {long && (
            <button
              className="mt-1 inline-flex items-center gap-1 text-[12px] font-semibold text-[var(--color-brand)]"
              onClick={() => setOpen(o => !o)}
              type="button"
            >
              {open ? <>Show less <ChevronUp size={13} /></> : <>Read all <ChevronDown size={13} /></>}
            </button>
          )}
        </div>

        <_FactTiles a={a} color={tone} />

        <div className="flex flex-wrap gap-1.5">
          <_Meta Icon={MapPin} testid="announcement-place">{placeLine(a.target_municipalities, a.target_barangays)}</_Meta>
          <_Meta Icon={Users}>{a.target_type === 'agency' ? (audienceName ?? 'One agency') : TARGET_LABEL[a.target_type]}</_Meta>
          {a.expires_at && (
            <_Meta Icon={CalendarClock}>{state === 'expired' ? 'Ended' : 'Until'} {formatDateTime(a.expires_at)}</_Meta>
          )}
        </div>
      </div>

      {a.asks_response && <_Answers counts={a.response_counts} live={live} onOpen={onAnswers} />}
    </article>
  );
}

function _Meta({ Icon, children, testid }: { Icon: LucideIcon; children: React.ReactNode; testid?: string }) {
  return (
    <span className="inline-flex max-w-full min-w-0 items-center gap-1.5 rounded-full bg-[var(--color-surface-raised)] px-2.5 py-1 text-[12px] text-[var(--color-text-secondary)]">
      <Icon aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
      <span className="min-w-0 truncate" data-testid={testid}>{children}</span>
    </span>
  );
}

/** The answers against the number asked - and the way in to the names. */
function _Answers({ counts, live, onOpen }: { counts?: Announcement['response_counts']; live: boolean; onOpen: () => void }) {
  const safe = counts?.safe ?? 0;
  const help = counts?.need_help ?? 0;
  const open = counts?.need_help_open ?? 0;
  const asked = counts?.audience ?? null;
  const answered = safe + help;
  const silent = asked == null ? null : Math.max(0, asked - answered);
  const total = Math.max(1, asked ?? answered);
  const pct = (n: number) => `${Math.min(100, (n / total) * 100)}%`;

  return (
    <footer
      className="flex flex-col gap-3 border-t border-[var(--color-surface-border)] bg-[color-mix(in_srgb,var(--color-surface-raised)_55%,transparent)] px-4 py-3.5 sm:flex-row sm:items-center sm:gap-5 sm:px-5"
      data-testid="announcement-tally"
    >
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-3">
          <p className="text-[12.5px] font-semibold text-foreground">
            {open > 0 ? (
              <span className="inline-flex items-center gap-1.5" style={{ color: HELP }}>
                <LifeBuoy aria-hidden="true" className="size-3.5" />
                {open} {open === 1 ? 'person needs' : 'people need'} help now
              </span>
            ) : live ? 'Are they safe?' : 'Answers'}
          </p>
          <p className="shrink-0 text-[12px] tabular-nums text-muted-foreground" data-testid="answered-of">
            {asked != null ? `${answered} of ${asked} answered` : `${answered} answered`}
          </p>
        </div>
        <div aria-hidden="true" className="mt-2 flex h-2 overflow-hidden rounded-full bg-[var(--color-surface-border)]">
          <span className="h-full" style={{ width: pct(help), backgroundColor: HELP }} />
          <span className="h-full" style={{ width: pct(safe), backgroundColor: SAFE }} />
        </div>
        <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[12px] text-[var(--color-text-secondary)]">
          <_Dot color={HELP}>{help} need help{help > open ? ` (${help - open} reached)` : ''}</_Dot>
          <_Dot color={SAFE}>{safe} safe</_Dot>
          {silent != null && <_Dot color="var(--color-text-muted)">{silent} not answered</_Dot>}
        </div>
      </div>
      <Button className="shrink-0 self-start sm:self-center" onClick={onOpen} size="sm" variant={open > 0 ? 'default' : 'outline'}>
        See answers <ArrowRight data-icon="inline-end" />
      </Button>
    </footer>
  );
}

function _Dot({ color, children }: { color: string; children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1.5 tabular-nums">
      <span aria-hidden="true" className="size-2 rounded-full" style={{ backgroundColor: color }} />
      {children}
    </span>
  );
}

/** The facts that are sentences - where to go, which road, who is missing - as tiles. */
function _FactTiles({ a, color }: { a: Announcement; color: string }) {
  const d = a.details ?? {};
  const tiles: { Icon: LucideIcon; label: string; value: string; strong?: boolean }[] = [];
  if (a.category === 'evacuation') {
    for (const c of d.centers ?? []) tiles.push({ Icon: DoorOpen, label: 'Go to', value: c.place ? `${c.name} — ${c.place}` : c.name, strong: true });
    if (d.bring) tiles.push({ Icon: Package, label: 'Bring', value: d.bring });
  }
  if (a.category === 'hazard' && d.area) tiles.push({ Icon: TriangleAlert, label: 'Area at risk', value: d.area, strong: true });
  if (a.category === 'road_closure') {
    if (d.road) tiles.push({ Icon: CircleDot, label: 'Closed', value: d.road, strong: true });
    if (d.alternate) tiles.push({ Icon: Route, label: 'Use instead', value: d.alternate });
  }
  if (a.category === 'missing_person') {
    if (d.name) tiles.push({ Icon: User, label: 'Name', value: d.name, strong: true });
    if (d.last_seen) tiles.push({ Icon: MapPin, label: 'Last seen', value: d.last_seen });
    if (d.description) tiles.push({ Icon: User, label: 'Looks like', value: d.description });
    if (d.contact) tiles.push({ Icon: Phone, label: 'Call', value: d.contact });
  }
  if (a.category === 'relief') {
    if (d.where) tiles.push({ Icon: MapPin, label: 'Where', value: d.where, strong: true });
    if (d.bring) tiles.push({ Icon: Package, label: 'Bring', value: d.bring });
  }
  if (a.category === 'utility' && d.provider) tiles.push({ Icon: Package, label: 'From', value: d.provider });
  if (tiles.length === 0) return null;
  return (
    <div className="grid gap-2 sm:grid-cols-2">
      {tiles.map((t, i) => (
        <div
          className="flex items-start gap-2.5 rounded-[10px] border px-3 py-2.5"
          key={i}
          style={t.strong
            ? { borderColor: `color-mix(in srgb, ${color} 28%, var(--color-surface-border))`, backgroundColor: `color-mix(in srgb, ${color} 5%, var(--color-surface-card))` }
            : { borderColor: 'var(--color-surface-border)' }}
        >
          <t.Icon aria-hidden="true" className="mt-0.5 size-4 shrink-0" style={{ color: t.strong ? color : 'var(--color-text-muted)' }} />
          <div className="min-w-0">
            <p className="text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">{t.label}</p>
            <p className="text-[13px] leading-snug font-medium text-foreground">{t.value}</p>
          </div>
        </div>
      ))}
    </div>
  );
}
