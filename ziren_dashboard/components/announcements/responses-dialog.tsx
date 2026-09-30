'use client';

/**
 * The answer board for one safety alert: who needs help, who has not answered,
 * who is safe - with a number to call and, when the phone sent one, where they
 * were. "Mark reached" closes a call and tells the resident their call was
 * received, so nobody is left wondering whether anyone saw it.
 *
 * Refreshes itself every 20 seconds while open: answers keep arriving during an
 * evacuation, and a board that only updates when reopened hides the newest
 * call for help.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Check, CircleHelp, ExternalLink, LifeBuoy, Loader2, MapPin, Phone, RotateCcw, ShieldCheck, Users,
  type LucideIcon,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import { fetchResponses, markReached, type ResponseBoard, type ResponseItem, type ResponseStatus } from '@/lib/api/announcements';
import { formatDateTime } from '@/lib/format/datetime';
import { relativeTime } from '@/lib/format/relative-time';
import { signOut } from '@/lib/hooks/useAuth';
import { useNotice } from '@/lib/toast';
import { cn } from '@/lib/utils';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { SearchInput } from '@/components/ui/search-input';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { kindOf, placeLine } from './kinds';

type View = 'need_help' | 'no_answer' | 'safe' | 'all';

const HELP = 'var(--color-severity-critical)';
const SAFE = 'var(--color-system-success)';
const QUIET = 'var(--color-text-secondary)';

export function ResponsesDialog({ id, token, onClose, onChanged }: {
  id: string;
  token: string;
  onClose: () => void;
  /** The counts on the card behind should follow. */
  onChanged?: () => void;
}) {
  const [board, setBoard] = useState<ResponseBoard | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [view, setView] = useState<View>('need_help');
  const [q, setQ] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());
  const notice = useNotice();

  const load = useCallback(async () => {
    try {
      const b = await fetchResponses(token, id);
      setBoard(b);
      setError(null);
      setNow(Date.now());
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'The answers could not be loaded.');
    }
  }, [token, id]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    const t = setInterval(() => void load(), 20_000);
    return () => clearInterval(t);
  }, [load]);

  // Open on the list that needs someone: calls for help while there are any
  // open, else whoever has not answered.
  const [pickedView, setPickedView] = useState(false);
  useEffect(() => {
    if (!board || pickedView) return;
    setView(board.tally.need_help > 0 ? 'need_help' : board.tally.no_answer > 0 ? 'no_answer' : 'all');
  }, [board, pickedView]);

  const rows = useMemo(() => {
    if (!board) return [];
    const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
    return board.items.filter(i => (view === 'all' || i.status === view) && words.every(w =>
      [i.full_name, i.barangay, i.municipality, i.phone_number, i.note].filter(Boolean).join(' ').toLowerCase().includes(w)));
  }, [board, view, q]);

  async function reach(item: ResponseItem, reached: boolean) {
    setBusy(item.user_id);
    try {
      await markReached(token, id, item.user_id, reached);
      await load();
      onChanged?.();
      notice({
        type: 'success',
        text: reached ? `${item.full_name ?? 'The resident'} was told their call was received.` : 'Marked as still needing help.',
      });
    } catch (e) {
      notice({ type: 'error', text: e instanceof Error ? e.message : 'That could not be saved.' });
    } finally {
      setBusy(null);
    }
  }

  const kind = kindOf(board?.announcement.category);
  const t = board?.tally;

  return (
    <Dialog onOpenChange={o => { if (!o) onClose(); }} open>
      <DialogContent className="flex max-h-[90vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[920px]" data-testid="responses-dialog">
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] py-4 pr-14 pl-5 text-left sm:pl-6">
          <div className="flex items-start gap-3">
            <span
              aria-hidden="true"
              className="flex size-10 shrink-0 items-center justify-center rounded-[11px]"
              style={{ color: kind.color, backgroundColor: `color-mix(in srgb, ${kind.color} 13%, transparent)` }}
            >
              <kind.Icon size={19} />
            </span>
            <div className="min-w-0">
              <DialogTitle className="text-[17px]">Answers: {board?.announcement.title ?? '…'}</DialogTitle>
              <DialogDescription className="mt-0.5">
                {board
                  ? `${board.scope === 'province' ? 'Every resident it reached' : `Residents of ${board.scope}`} · ${placeLine(board.announcement.target_municipalities, board.announcement.target_barangays)}`
                  : 'Loading…'}
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="flex min-h-0 flex-1 flex-col">
          {error && <div className="px-5 pt-4 sm:px-6"><Alert message={error} variant="error" /></div>}

          {!board && !error ? (
            <div className="flex flex-col gap-3 p-5 sm:p-6">
              <Skeleton className="h-20 rounded-[12px]" />
              <Skeleton className="h-64 rounded-[12px]" />
            </div>
          ) : board && t && (
            <>
              {/* ── Tally ────────────────────────────────────────── */}
              <div className="shrink-0 border-b border-[var(--color-surface-border)] px-5 py-4 sm:px-6">
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-4" data-testid="responses-tally">
                  <_Tile color={HELP} Icon={LifeBuoy} label="Need help" sub={t.need_help > t.need_help_open ? `${t.need_help - t.need_help_open} reached` : 'not yet reached'} value={t.need_help_open} />
                  <_Tile color={QUIET} Icon={CircleHelp} label="Not answered" sub="call to check" value={t.no_answer} />
                  <_Tile color={SAFE} Icon={ShieldCheck} label="Safe" sub="said they are safe" value={t.safe} />
                  <_Tile color={QUIET} Icon={Users} label="Reached by the alert" sub="residents" value={t.audience} />
                </div>
                <_Bar tally={t} />
              </div>

              {/* ── Filter ───────────────────────────────────────── */}
              <div className="flex shrink-0 flex-wrap items-center gap-2 px-5 pt-3 pb-2 sm:px-6">
                <div className="flex flex-wrap gap-1.5" role="tablist">
                  {([
                    ['need_help', 'Needs help', t.need_help],
                    ['no_answer', 'Not answered', t.no_answer],
                    ['safe', 'Safe', t.safe],
                    ['all', 'Everyone', t.audience],
                  ] as const).map(([key, label, n]) => (
                    <button
                      aria-selected={view === key}
                      className={cn(
                        'flex h-8 items-center gap-1.5 rounded-full border px-3 text-[12.5px] font-semibold transition-colors',
                        view === key
                          ? 'border-transparent bg-foreground text-background'
                          : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)]',
                      )}
                      data-view={key}
                      key={key}
                      onClick={() => { setView(key); setPickedView(true); }}
                      role="tab"
                      type="button"
                    >
                      {label}
                      <span className="tabular-nums opacity-70">{n}</span>
                    </button>
                  ))}
                </div>
                <SearchInput
                  className="ml-auto w-full sm:w-[240px]"
                  label="Search answers"
                  onValueChange={setQ}
                  placeholder="Name, barangay or number…"
                  size="sm"
                  value={q}
                />
              </div>

              {/* ── People ───────────────────────────────────────── */}
              <div className="scroll-slim min-h-[200px] flex-1 overflow-y-auto px-5 pb-5 sm:px-6">
                {rows.length === 0 ? (
                  <p className="py-12 text-center text-[13px] text-muted-foreground">
                    {q ? 'Nobody matches that search.' : view === 'need_help' ? 'Nobody has asked for help.' : view === 'no_answer' ? 'Everyone has answered.' : 'Nobody here yet.'}
                  </p>
                ) : (
                  <ul className="flex flex-col gap-2" data-testid="responses-list">
                    {rows.map(i => (
                      <_Person busy={busy === i.user_id} item={i} key={i.user_id} now={now} onReach={r => void reach(i, r)} />
                    ))}
                  </ul>
                )}
              </div>
            </>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function _Tile({ Icon, label, value, sub, color }: { Icon: LucideIcon; label: string; value: number; sub: string; color: string }) {
  return (
    <div className="rounded-[12px] border border-[var(--color-surface-border)] px-3 py-2.5">
      <p className="flex items-center gap-1.5 text-[12px] font-semibold" style={{ color }}>
        <Icon aria-hidden="true" className="size-3.5" /> {label}
      </p>
      <p className="mt-1 text-[22px] leading-none font-semibold tabular-nums text-foreground">{value}</p>
      <p className="mt-1 text-[11.5px] text-muted-foreground">{sub}</p>
    </div>
  );
}

function _Bar({ tally }: { tally: ResponseBoard['tally'] }) {
  const total = Math.max(1, tally.audience);
  const part = (n: number) => `${(n / total) * 100}%`;
  return (
    <div className="mt-3">
      <div aria-hidden="true" className="flex h-2 overflow-hidden rounded-full bg-[var(--color-surface-raised)]">
        <span style={{ width: part(tally.need_help), backgroundColor: HELP }} />
        <span style={{ width: part(tally.safe), backgroundColor: SAFE }} />
      </div>
      <p className="mt-1.5 text-[11.5px] text-muted-foreground">
        {tally.audience - tally.no_answer} of {tally.audience} have answered.
      </p>
    </div>
  );
}

const STATUS: Record<ResponseStatus, { label: string; color: string; Icon: LucideIcon }> = {
  need_help: { label: 'Needs help', color: HELP, Icon: LifeBuoy },
  safe: { label: 'Safe', color: SAFE, Icon: ShieldCheck },
  no_answer: { label: 'Not answered', color: QUIET, Icon: CircleHelp },
};

function _Person({ item: i, now, busy, onReach }: {
  item: ResponseItem; now: number; busy: boolean; onReach: (reached: boolean) => void;
}) {
  const s = STATUS[i.status];
  const openCall = i.status === 'need_help' && !i.handled_at;
  const where = [i.barangay ? `Brgy. ${i.barangay}` : null, i.municipality].filter(Boolean).join(', ');
  const initials = (i.full_name ?? '?').split(/\s+/).filter(Boolean).slice(0, 2).map(w => w[0]?.toUpperCase()).join('');
  return (
    <li
      className={cn(
        'flex flex-col gap-2 rounded-[12px] border px-3.5 py-3 sm:flex-row sm:items-center sm:gap-3',
        openCall ? 'border-[color-mix(in_srgb,var(--color-severity-critical)_35%,transparent)] bg-[color-mix(in_srgb,var(--color-severity-critical)_5%,transparent)]' : 'border-[var(--color-surface-border)]',
      )}
      data-person={i.user_id}
      data-status={i.status}
    >
      <div className="flex min-w-0 flex-1 items-start gap-3">
        <span aria-hidden="true" className="flex size-9 shrink-0 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[12px] font-semibold text-[var(--color-text-secondary)]">
          {initials || '?'}
        </span>
        <div className="min-w-0 flex-1">
          <p className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
            <span className="text-[13.5px] font-semibold text-foreground">{i.full_name ?? 'Unnamed resident'}</span>
            <span className="inline-flex items-center gap-1 text-[11.5px] font-semibold" style={{ color: s.color }}>
              <s.Icon aria-hidden="true" className="size-3.5" /> {s.label}
            </span>
            {i.responded_at && (
              <span className="text-[11.5px] text-muted-foreground" title={formatDateTime(i.responded_at)}>{relativeTime(i.responded_at, now)}</span>
            )}
          </p>
          <p className="mt-0.5 text-[12px] text-[var(--color-text-secondary)]">{where || 'Address not given'}</p>
          {i.note && <p className="mt-1.5 rounded-[8px] bg-[var(--color-surface-raised)] px-2.5 py-1.5 text-[12.5px] text-foreground">“{i.note}”</p>}
          {i.handled_at && (
            <p className="mt-1.5 flex items-center gap-1 text-[11.5px] font-medium" style={{ color: SAFE }}>
              <Check aria-hidden="true" className="size-3.5" />
              Reached{i.handled_by_name ? ` by ${i.handled_by_name}` : ''} · {relativeTime(i.handled_at, now)}
            </p>
          )}
        </div>
      </div>

      <div className="flex shrink-0 flex-wrap items-center gap-1.5 sm:justify-end">
        {i.phone_number && (
          <Button asChild size="sm" variant="outline">
            <a href={`tel:${i.phone_number.replace(/[^\d+]/g, '')}`}>
              <Phone data-icon="inline-start" /> {i.phone_number}
            </a>
          </Button>
        )}
        {i.latitude != null && i.longitude != null && (
          <Button asChild size="sm" variant="outline">
            <a href={`https://www.openstreetmap.org/?mlat=${i.latitude}&mlon=${i.longitude}#map=17/${i.latitude}/${i.longitude}`} rel="noreferrer" target="_blank" title="Where the phone was when they answered">
              <MapPin data-icon="inline-start" /> Location <ExternalLink className="size-3 opacity-60" />
            </a>
          </Button>
        )}
        {openCall && (
          <Button disabled={busy} onClick={() => onReach(true)} size="sm">
            {busy ? <Loader2 className="animate-spin" data-icon="inline-start" /> : <Check data-icon="inline-start" />}
            Mark reached
          </Button>
        )}
        {i.status === 'need_help' && i.handled_at && (
          <Button disabled={busy} onClick={() => onReach(false)} size="sm" title="They still need help" variant="ghost">
            <RotateCcw data-icon="inline-start" /> Reopen
          </Button>
        )}
      </div>
    </li>
  );
}
