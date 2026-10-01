'use client';

/**
 * Announcements — spec Section 14, rebuilt 2026-10-01 around safety alerts.
 *
 * Provincial Admin: publishes (the composer), sends the all clear that ends a
 * warning, takes one down, and reads the answers. Agency Admin: sees
 * everything announced to their town - not only what was addressed to agency
 * admins, because an evacuation order for Naval's residents is the Naval
 * stations' work - and reads the answers of their own town's residents.
 *
 *   [ Live alerts ][ Waiting for help ][ Answered ][ Sent this week ]
 *   [ filters · kind · search · New ]              | Waiting for help (every
 *   TODAY                                           | open call, longest first,
 *   [ alert card ]                                  | Call / Reached)
 *   [ alert card ]                                  | Send an alert (shortcuts)
 *   EARLIER THIS WEEK ...                           |
 *
 * Deep links, from the notification bell:
 *   ?id=<id>          scrolls to that announcement
 *   ?responses=<id>   opens its answer board ("Needs help: …")
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import { CheckCheck, LifeBuoy, Megaphone, Radio, Send } from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import {
  deactivateAnnouncement, fetchAnnouncements, fetchBarangays,
  type Announcement, type BarangayRef,
} from '@/lib/api/announcements';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { OptionPicker } from '@/components/ui/option-picker';
import { SearchInput } from '@/components/ui/search-input';
import { StatCell, StatStrip } from '@/components/ui/stat-strip';
import { useNotice } from '@/lib/toast';
import { cn } from '@/lib/utils';
import { AnnouncementCard, stateOf } from '@/components/announcements/announcement-card';
import { ComposerDialog, type AgencyOption, type ComposerMode } from '@/components/announcements/composer-dialog';
import { QuickSend, WaitingForHelp } from '@/components/announcements/help-rail';
import { ResponsesDialog } from '@/components/announcements/responses-dialog';
import { isSafety, KINDS, kindOf } from '@/components/announcements/kinds';

import { DemoTarget } from '@/components/help/demo-target';
type Filter = 'active' | 'safety' | 'ended' | 'all';

const DAY = 86_400_000;

/** "Today", "Yesterday", "Earlier this week", "Older". */
function dayGroup(iso: string, now: number): string {
  const start = new Date(now); start.setHours(0, 0, 0, 0);
  const t = new Date(iso).getTime();
  if (t >= start.getTime()) return 'Today';
  if (t >= start.getTime() - DAY) return 'Yesterday';
  if (t >= start.getTime() - 6 * DAY) return 'Earlier this week';
  return 'Older';
}

export default function AnnouncementsPage() {
  const { token, isProvincialAdmin, agencyType } = useAuth();
  const [items, setItems] = useState<Announcement[] | null>(null);
  const [agencies, setAgencies] = useState<AgencyOption[]>([]);
  const [barangays, setBarangays] = useState<BarangayRef[]>([]);
  const [filter, setFilter] = useState<Filter>('active');
  const [kindFilter, setKindFilter] = useState('any');
  const [q, setQ] = useState('');
  const [composer, setComposer] = useState<ComposerMode | null>(null);
  const [board, setBoard] = useState<string | null>(null);
  const [takeDown, setTakeDown] = useState<Announcement | null>(null);
  const [focus, setFocus] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const notice = useNotice();

  const load = useCallback((quiet = false) => {
    if (!token) return;
    fetchAnnouncements(token, !isProvincialAdmin)
      .then(rows => { setItems(rows); setNow(Date.now()); })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        if (!quiet) notice({ type: 'error', text: e instanceof Error ? e.message : 'Announcements could not be loaded.' });
      });
  }, [token, isProvincialAdmin, notice]);

  useEffect(() => { load(); }, [load]);
  // Answers keep arriving after an alert goes out; the counts on the cards follow.
  useEffect(() => {
    const t = setInterval(() => load(true), 30_000);
    return () => clearInterval(t);
  }, [load]);

  useEffect(() => {
    if (!token || !isProvincialAdmin) return;
    apiClient.get<AgencyOption[]>('/users/agencies-list', token).then(setAgencies).catch(() => {});
    fetchBarangays(token).then(setBarangays).catch(() => {});
  }, [token, isProvincialAdmin]);

  // Deep links from the bell. Read once, from the address itself (no
  // useSearchParams: it would need a Suspense boundary around the whole page).
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    const r = params.get('responses');
    const id = params.get('id');
    if (r) { setBoard(r); setFocus(r); }
    else if (id) setFocus(id);
  }, []);
  useEffect(() => {
    // Wait until the list actually holds it: right after publishing, the new
    // row is not loaded yet, and "not on screen" must not be read as "filtered
    // out" (that flipped the page to All after every publish).
    if (!focus || !items || !items.some(a => a.id === focus)) return;
    const el = document.querySelector(`[data-announcement="${CSS.escape(focus)}"]`);
    if (el) el.scrollIntoView({ block: 'center', behavior: 'smooth' });
    else if (filter !== 'all' || kindFilter !== 'any') { setFilter('all'); setKindFilter('any'); }
  }, [focus, items, filter, kindFilter]);

  const list = useMemo(() => items ?? [], [items]);

  // ── The overview ────────────────────────────────────────────────────────
  const stats = useMemo(() => {
    const live = list.filter(a => stateOf(a, now) === 'active');
    const asking = live.filter(a => a.asks_response);
    return {
      liveSafety: live.filter(a => isSafety(a.category) && a.category !== 'all_clear').length,
      evacuations: live.filter(a => a.category === 'evacuation').length,
      waiting: list.reduce((s, a) => s + (a.response_counts?.need_help_open ?? 0), 0),
      waitingAlerts: list.filter(a => (a.response_counts?.need_help_open ?? 0) > 0).length,
      answered: asking.reduce((s, a) => s + (a.response_counts ? a.response_counts.safe + a.response_counts.need_help : 0), 0),
      asked: asking.reduce((s, a) => s + (a.response_counts?.audience ?? 0), 0),
      askingCount: asking.length,
      week: list.filter(a => now - new Date(a.created_at).getTime() < 7 * DAY).length,
      weekSafety: list.filter(a => now - new Date(a.created_at).getTime() < 7 * DAY && isSafety(a.category)).length,
    };
  }, [list, now]);

  const counts = useMemo(() => ({
    active: list.filter(a => stateOf(a, now) === 'active').length,
    safety: list.filter(a => stateOf(a, now) === 'active' && isSafety(a.category)).length,
    ended: list.filter(a => stateOf(a, now) !== 'active').length,
    all: list.length,
  }), [list, now]);

  const kindOptions = useMemo(() => {
    const present = [...new Set(list.map(a => a.category))];
    return [
      { value: 'any', label: 'Every kind', icon: Megaphone },
      ...Object.values(KINDS).filter(k => present.includes(k.key)).map(k => ({ value: k.key, label: k.label, icon: k.Icon, color: k.color })),
    ];
  }, [list]);

  const visible = useMemo(() => {
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    return list.filter(a => {
      const s = stateOf(a, now);
      if (filter === 'active' && s !== 'active') return false;
      if (filter === 'safety' && (s !== 'active' || !isSafety(a.category))) return false;
      if (filter === 'ended' && s === 'active') return false;
      if (kindFilter !== 'any' && a.category !== kindFilter) return false;
      if (!words.length) return true;
      const hay = [a.title, a.body, kindOf(a.category).label, ...(a.target_municipalities ?? []), ...(a.target_barangays ?? []).map(b => b.name)]
        .join(' ').toLowerCase();
      return words.every(w => hay.includes(w));
    }).sort((x, y) => {
      // Live safety alerts first - they are what someone opens this page for
      // during a storm - then newest first.
      const rank = (a: Announcement) => (stateOf(a, now) === 'active' ? (isSafety(a.category) ? 0 : 1) : 2);
      return rank(x) - rank(y) || y.created_at.localeCompare(x.created_at);
    });
  }, [list, filter, kindFilter, q, now]);

  // Live safety alerts stay together at the top under their own heading; the
  // rest fall into days.
  const groups = useMemo(() => {
    const out: { name: string; rows: Announcement[] }[] = [];
    for (const a of visible) {
      const name = stateOf(a, now) === 'active' && isSafety(a.category) ? 'Live safety alerts' : dayGroup(a.created_at, now);
      const last = out[out.length - 1];
      if (last && last.name === name) last.rows.push(a); else out.push({ name, rows: [a] });
    }
    return out;
  }, [visible, now]);

  async function doTakeDown(a: Announcement) {
    if (!token) return;
    setTakeDown(null);
    try {
      await deactivateAnnouncement(token, a.id);
      notice({ type: 'success', text: `“${a.title}” was taken down.` });
      load();
    } catch (e) {
      notice({ type: 'error', text: e instanceof Error ? e.message : 'It could not be taken down.' });
    }
  }

  const agencyName = (id: string | null) => agencies.find(g => g.id === id)?.name;

  return (
    <div className="flex flex-col gap-5 px-6 py-5 md:px-7">
      {/* ── Overview ───────────────────────────────────────────── */}
      <DemoTarget id="ann:stats"><StatStrip>
        <StatCell
          bg="var(--color-system-info-bg)" color="var(--color-system-info)" icon={<Radio />}
          label="Live safety alerts"
          trend={stats.evacuations > 0 ? `${stats.evacuations} evacuation order${stats.evacuations === 1 ? '' : 's'} in force` : 'No evacuation order in force'}
          value={items === null ? '–' : stats.liveSafety}
        />
        <StatCell
          bg={stats.waiting > 0 ? 'var(--color-severity-critical-bg)' : 'var(--color-system-success-bg)'}
          color={stats.waiting > 0 ? 'var(--color-severity-critical)' : 'var(--color-system-success)'}
          icon={<LifeBuoy />}
          label="Waiting for help"
          trend={stats.waiting > 0 ? `across ${stats.waitingAlerts} alert${stats.waitingAlerts === 1 ? '' : 's'} - not yet reached` : 'Nobody is waiting'}
          value={items === null ? '–' : stats.waiting}
        />
        <StatCell
          bg="var(--color-system-success-bg)" color="var(--color-system-success)" icon={<CheckCheck />}
          label="Residents answered"
          trend={stats.askingCount === 0 ? 'No alert is asking right now' : `on ${stats.askingCount} live alert${stats.askingCount === 1 ? '' : 's'}`}
          value={items === null ? '–' : stats.answered}
          whole={stats.asked || undefined}
          wholeLabel="asked"
        />
        <StatCell
          bg="var(--color-brand-subtle)" color="var(--color-brand)" icon={<Send />}
          label="Sent this week"
          trend={`${stats.weekSafety} of them safety alerts`}
          value={items === null ? '–' : stats.week}
        />
      </StatStrip></DemoTarget>

      <div className="grid items-start gap-5 xl:grid-cols-[minmax(0,1fr)_340px]">
        {/* ── The feed ─────────────────────────────────────────── */}
        <section data-demo="ann:feed" className="flex min-w-0 flex-col gap-4">
          <div data-demo="ann:filters" className="flex flex-wrap items-center gap-2 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-2.5 shadow-[var(--shadow-card)]">
            <div className="flex flex-wrap gap-1 rounded-[10px] bg-[var(--color-surface-raised)] p-1" role="tablist">
              {([
                ['active', 'Active'],
                ['safety', 'Safety alerts'],
                ['ended', 'Ended'],
                ['all', 'All'],
              ] as const).map(([key, label]) => (
                <button
                  aria-selected={filter === key}
                  className={cn(
                    'flex h-7 items-center gap-1.5 rounded-[8px] px-2.5 text-[12.5px] font-semibold transition-colors',
                    filter === key
                      ? 'bg-[var(--color-surface-card)] text-foreground shadow-[0_1px_2px_rgba(16,24,40,0.08),inset_0_0_0_1px_var(--color-surface-border)]'
                      : 'text-[var(--color-text-secondary)] hover:text-foreground',
                  )}
                  data-filter={key}
                  key={key}
                  onClick={() => setFilter(key)}
                  role="tab"
                  type="button"
                >
                  {label}
                  <span className={cn('rounded-full px-1.5 text-[11px] tabular-nums', filter === key ? 'bg-[var(--color-brand-subtle)] text-[var(--color-brand)]' : 'opacity-70')}>
                    {counts[key]}
                  </span>
                </button>
              ))}
            </div>
            <OptionPicker
              className="w-auto min-w-[168px]"
              label="Show which kind"
              onChange={setKindFilter}
              options={kindOptions}
              placeholder="Every kind"
              size="sm"
              value={kindFilter}
            />
            <SearchInput
              className="min-w-[180px] flex-1"
              label="Search announcements"
              onValueChange={setQ}
              placeholder="Title, place, kind…"
              size="sm"
              value={q}
            />
          </div>

          {items === null ? (
            <div className="flex flex-col gap-3">
              <Skeleton className="h-48 rounded-[var(--radius-card)]" />
              <Skeleton className="h-48 rounded-[var(--radius-card)]" />
            </div>
          ) : visible.length === 0 ? (
            <div className="flex flex-col items-center gap-2 rounded-[var(--radius-card)] border border-dashed border-[var(--color-surface-border)] bg-[var(--color-surface-card)] py-16 text-center">
              <span className="flex size-12 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-muted-foreground">
                <Megaphone size={22} />
              </span>
              <p className="text-[14px] font-semibold text-foreground">
                {q || kindFilter !== 'any' ? 'Nothing matches' : filter === 'active' || filter === 'safety' ? 'Nothing is announced right now' : 'No announcements'}
              </p>
              <p className="max-w-[420px] text-[12.5px] text-muted-foreground">
                {isProvincialAdmin
                  ? 'Evacuation orders, weather advisories and hazard warnings can be aimed at a town or a few barangays, and can ask residents if they are safe.'
                  : 'Announcements for your town appear here - including safety alerts sent to its residents, with their answers.'}
              </p>
            </div>
          ) : (
            <div className="flex flex-col gap-5" data-testid="announcement-list">
              {groups.map(g => (
                <div className="flex flex-col gap-3" data-group={g.name} key={g.name}>
                  <h2 className="flex items-center gap-2 text-[11.5px] font-semibold tracking-wide text-muted-foreground uppercase">
                    {g.name === 'Live safety alerts' && (
                      <span className="size-1.5 rounded-full" style={{ backgroundColor: 'var(--color-severity-critical)' }} />
                    )}
                    {g.name}
                    <span className="h-px flex-1 bg-[var(--color-surface-border)]" />
                    <span className="tabular-nums">{g.rows.length}</span>
                  </h2>
                  {g.rows.map(a => (
                    <AnnouncementCard
                      a={a}
                      audienceName={agencyName(a.target_agency_id)}
                      agencyType={agencyType}
                      canManage={isProvincialAdmin}
                      highlight={focus === a.id}
                      key={a.id}
                      now={now}
                      onAllClear={() => setComposer({ kind: 'all_clear', of: a })}
                      onAnswers={() => setBoard(a.id)}
                      onTakeDown={() => setTakeDown(a)}
                    />
                  ))}
                </div>
              ))}
            </div>
          )}
        </section>

        {/* ── The rail: who to call, and what to send ─────────────
            Before the feed on narrow screens - a call for help is the most
            urgent thing on the page. */}
        <aside className="order-first flex flex-col gap-4 xl:sticky xl:top-5 xl:order-none">
          {token && (
            <DemoTarget id="ann:waiting"><WaitingForHelp alerts={list} now={now} onChanged={() => load(true)} onOpenBoard={setBoard} token={token} /></DemoTarget>
          )}
          {isProvincialAdmin && (
            <DemoTarget id="ann:send"><QuickSend agencyType={agencyType} onNew={() => setComposer({ kind: 'new' })} onPick={category => setComposer({ kind: 'new', category })} /></DemoTarget>
          )}
        </aside>
      </div>

      {composer && token && (
        <ComposerDialog
          agencies={agencies}
          agencyType={agencyType}
          barangays={barangays}
          mode={composer}
          onClose={() => setComposer(null)}
          onPublished={row => {
            setComposer(null);
            notice({
              type: 'success',
              text: row.category === 'all_clear'
                ? `All clear sent to ${row.reach.total.toLocaleString()} ${row.reach.total === 1 ? 'person' : 'people'}.`
                : `Published to ${row.reach.total.toLocaleString()} ${row.reach.total === 1 ? 'person' : 'people'}.`,
            });
            setFilter('active');
            setKindFilter('any');
            setFocus(row.id);
            load();
          }}
          token={token}
        />
      )}

      {board && token && (
        <ResponsesDialog id={board} onChanged={() => load(true)} onClose={() => setBoard(null)} token={token} />
      )}

      <AlertDialog open={takeDown !== null} onOpenChange={o => { if (!o) setTakeDown(null); }}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Take down “{takeDown?.title}”?</AlertDialogTitle>
            <AlertDialogDescription>
              It leaves every feed, and nobody is told. {takeDown && isSafety(takeDown.category) && takeDown.category !== 'all_clear'
                ? 'If the danger is over, send an all clear instead - that tells the people it reached that they are safe.'
                : ''}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep it up</AlertDialogCancel>
            {takeDown && isSafety(takeDown.category) && takeDown.category !== 'all_clear' && (
              <Button onClick={() => { const a = takeDown; setTakeDown(null); setComposer({ kind: 'all_clear', of: a }); }} variant="outline">
                Send all clear
              </Button>
            )}
            <AlertDialogAction onClick={() => { if (takeDown) void doTakeDown(takeDown); }} variant="destructive">
              Take down
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
