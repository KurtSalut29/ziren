'use client';

/**
 * The right-hand rail of the Announcements page.
 *
 * WaitingForHelp - every resident who answered "I need help" and has not been
 * reached yet, across every live alert, longest wait on top. Before this the
 * calls sat inside each alert's own board, so with two alerts out a station had
 * to open both to find who to call first. Here they are one list with the
 * number and a Reached button.
 *
 * QuickSend - the four alerts a Provincial Admin sends in a hurry, one click
 * from the page, opening the composer already on that kind.
 */

import { useEffect, useMemo, useState } from 'react';
import { Check, Loader2, Phone, Plus, ShieldCheck } from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  fetchResponses, markReached,
  type Announcement, type AnnouncementCategory, type ResponseItem,
} from '@/lib/api/announcements';
import { signOut } from '@/lib/hooks/useAuth';
import { useNotice } from '@/lib/toast';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { KINDS, kindOf, mayIssue } from './kinds';

const HELP = 'var(--color-severity-critical)';

type Waiting = ResponseItem & { alert: Announcement };

function waitingFor(iso: string | null, now: number): string {
  if (!iso) return '';
  const m = Math.max(0, Math.floor((now - new Date(iso).getTime()) / 60_000));
  if (m < 1) return 'just now';
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60);
  return `${h} h ${m % 60} min`;
}

export function WaitingForHelp({ token, alerts, now, onChanged, onOpenBoard }: {
  token: string;
  /** Every alert on the page; the ones with open calls are read. */
  alerts: Announcement[];
  now: number;
  onChanged: () => void;
  onOpenBoard: (id: string) => void;
}) {
  const notice = useNotice();
  const withCalls = useMemo(
    () => alerts.filter(a => a.asks_response && (a.response_counts?.need_help_open ?? 0) > 0),
    [alerts],
  );
  // Read the boards again only when an open-call count actually changes.
  const key = withCalls.map(a => `${a.id}:${a.response_counts?.need_help_open}`).join('|');
  const [people, setPeople] = useState<Waiting[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    if (withCalls.length === 0) { setPeople([]); return; }
    Promise.all(withCalls.map(a => fetchResponses(token, a.id).then(b => ({ a, b }))))
      .then(boards => {
        if (!alive) return;
        const list = boards.flatMap(({ a, b }) =>
          b.items.filter(i => i.status === 'need_help' && !i.handled_at).map(i => ({ ...i, alert: a })));
        list.sort((x, y) => String(x.responded_at).localeCompare(String(y.responded_at)));
        setPeople(list);
      })
      .catch(e => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        if (alive) setPeople([]);
      });
    return () => { alive = false; };
  }, [key, token]); // eslint-disable-line react-hooks/exhaustive-deps

  async function reach(p: Waiting) {
    setBusy(p.user_id + p.alert.id);
    try {
      await markReached(token, p.alert.id, p.user_id, true);
      setPeople(list => (list ?? []).filter(x => !(x.user_id === p.user_id && x.alert.id === p.alert.id)));
      notice({ type: 'success', text: `${p.full_name ?? 'The resident'} was told their call was received.` });
      onChanged();
    } catch (e) {
      notice({ type: 'error', text: e instanceof Error ? e.message : 'That could not be saved.' });
    } finally {
      setBusy(null);
    }
  }

  const count = people?.length ?? 0;

  return (
    <section
      className="overflow-hidden rounded-[var(--radius-card)] border bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]"
      data-testid="waiting-for-help"
      style={{ borderColor: count > 0 ? `color-mix(in srgb, ${HELP} 35%, var(--color-surface-border))` : 'var(--color-surface-border)' }}
    >
      <header
        className="flex items-center justify-between gap-2 border-b px-4 py-3"
        style={count > 0
          ? { borderColor: `color-mix(in srgb, ${HELP} 22%, var(--color-surface-border))`, backgroundColor: `color-mix(in srgb, ${HELP} 7%, var(--color-surface-card))` }
          : { borderColor: 'var(--color-surface-border)' }}
      >
        <h2 className="flex items-center gap-2 text-[13.5px] font-semibold" style={{ color: count > 0 ? HELP : 'var(--color-text-primary)' }}>
          {count > 0 && (
            <span className="relative flex size-2">
              <span className="absolute inline-flex size-full rounded-full opacity-60 motion-safe:animate-ping" style={{ backgroundColor: HELP }} />
              <span className="relative inline-flex size-2 rounded-full" style={{ backgroundColor: HELP }} />
            </span>
          )}
          Waiting for help
        </h2>
        <span
          className="rounded-full px-2 py-0.5 text-[11.5px] font-bold tabular-nums"
          style={count > 0 ? { color: '#fff', backgroundColor: `color-mix(in srgb, ${HELP} 84%, black)` } : { color: 'var(--color-text-muted)', backgroundColor: 'var(--color-surface-raised)' }}
        >
          {count}
        </span>
      </header>

      {people === null ? (
        <div className="flex flex-col gap-2 p-4"><Skeleton className="h-16 rounded-[10px]" /><Skeleton className="h-16 rounded-[10px]" /></div>
      ) : count === 0 ? (
        <div className="flex flex-col items-center gap-1.5 px-4 py-7 text-center">
          <span className="flex size-10 items-center justify-center rounded-full" style={{ color: 'var(--color-system-success)', backgroundColor: 'var(--color-system-success-bg)' }}>
            <ShieldCheck size={19} />
          </span>
          <p className="text-[13px] font-semibold text-foreground">Nobody is waiting</p>
          <p className="max-w-[240px] text-[12px] text-muted-foreground">When a resident answers an alert with “I need help”, they appear here at once.</p>
        </div>
      ) : (
        <ul className="scroll-slim flex max-h-[430px] flex-col divide-y divide-[var(--color-surface-border)] overflow-y-auto">
          {people!.map(p => {
            const k = kindOf(p.alert.category);
            const id = p.user_id + p.alert.id;
            return (
              <li className="flex flex-col gap-2 px-4 py-3" data-waiting={p.user_id} key={id}>
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0">
                    <p className="truncate text-[13px] font-semibold text-foreground">{p.full_name ?? 'Unnamed resident'}</p>
                    <p className="truncate text-[12px] text-[var(--color-text-secondary)]">
                      {[p.barangay ? `Brgy. ${p.barangay}` : null, p.municipality].filter(Boolean).join(', ') || 'Address not given'}
                    </p>
                  </div>
                  <span className="shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold tabular-nums" style={{ color: HELP, backgroundColor: `color-mix(in srgb, ${HELP} 10%, transparent)` }}>
                    {waitingFor(p.responded_at, now)}
                  </span>
                </div>
                {p.note && <p className="line-clamp-2 rounded-[8px] bg-[var(--color-surface-raised)] px-2.5 py-1.5 text-[12px] text-foreground">“{p.note}”</p>}
                <button
                  className="flex min-w-0 items-center gap-1.5 text-left text-[11.5px] text-muted-foreground hover:text-foreground"
                  onClick={() => onOpenBoard(p.alert.id)}
                  type="button"
                >
                  <k.Icon aria-hidden="true" className="size-3.5 shrink-0" style={{ color: k.color }} />
                  <span className="truncate">{p.alert.title}</span>
                </button>
                <div className="flex gap-1.5">
                  {p.phone_number && (
                    <Button asChild className="flex-1" size="sm" variant="outline">
                      <a href={`tel:${p.phone_number.replace(/[^\d+]/g, '')}`}><Phone data-icon="inline-start" /> Call</a>
                    </Button>
                  )}
                  <Button className="flex-1" disabled={busy === id} onClick={() => void reach(p)} size="sm">
                    {busy === id ? <Loader2 className="animate-spin" data-icon="inline-start" /> : <Check data-icon="inline-start" />}
                    Reached
                  </Button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

// The four most urgent kinds this office may issue: MDRRMO gets evacuation,
// weather, hazard, road closure; PNP gets missing person first.
const QUICK: AnnouncementCategory[] = ['evacuation', 'weather', 'hazard', 'missing_person', 'road_closure', 'emergency', 'drill'];

export function QuickSend({ onPick, onNew, agencyType }: { onPick: (category: AnnouncementCategory) => void; onNew: () => void; agencyType: string | null }) {
  const quick = QUICK.filter(k => mayIssue(k, agencyType)).slice(0, 4);
  return (
    <section className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4 shadow-[var(--shadow-card)]" data-testid="quick-send">
      <Button className="mb-4 w-full" onClick={onNew}>
        <Plus data-icon="inline-start" /> New announcement
      </Button>
      <h2 className="text-[13.5px] font-semibold text-foreground">Or send an alert straight away</h2>
      <p className="mb-3 text-[12px] text-muted-foreground">Opens on that kind, with the usual text filled in.</p>
      <div className="grid grid-cols-2 gap-2">
        {quick.map(key => {
          const k = KINDS[key];
          return (
            <button
              className="group flex flex-col items-start gap-2 rounded-[12px] border border-[var(--color-surface-border)] p-3 text-left transition-colors hover:border-[color-mix(in_srgb,var(--k)_45%,var(--color-surface-border))] hover:bg-[color-mix(in_srgb,var(--k)_6%,transparent)]"
              data-quick={key}
              key={key}
              onClick={() => onPick(key)}
              style={{ ['--k' as string]: k.color }}
              type="button"
            >
              <span className="flex size-8 items-center justify-center rounded-[9px]" style={{ color: k.color, backgroundColor: `color-mix(in srgb, ${k.color} 13%, transparent)` }}>
                <k.Icon size={16} />
              </span>
              <span className="text-[12.5px] leading-tight font-semibold text-foreground">{k.label}</span>
            </button>
          );
        })}
      </div>
    </section>
  );
}
