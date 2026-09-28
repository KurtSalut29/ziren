'use client';

/**
 * "Request help" — ask one or more other stations to help on this incident.
 *
 * Rebuilt after station testing. The first version offered only the stations
 * in the incident's own municipality, asked for one station at a time, and
 * gave a bare message box with no word on what would happen next. Stations
 * wanted to reach anyone in Biliran, and could not tell from the dialog who
 * would see what. So:
 *
 *   1. Every active station in the province is listed, the incident's own
 *      municipality first, searchable and filterable by agency, and more than
 *      one can be picked. A station already asked about this incident says so
 *      instead of failing on send.
 *   2. The need is one tap (fire truck, ambulance, police …) plus an optional
 *      note, so the message the other side reads is never empty or vague.
 *   3. The footer says, in plain words, what happens on send: they are
 *      alerted, they see a summary, and the report stays with this station.
 *   4. After sending, a result screen names every station that was asked —
 *      and any that failed, with the reason — and points to where the
 *      conversation continues.
 *
 * Uses the triggerRef + onCloseAutoFocus/onOpenAutoFocus pattern
 * option-dialog.tsx established (Radix's own "restore previous focus" does
 * not reliably land back on a plain button that isn't a <Dialog.Trigger>).
 */

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import {
  ArrowRight, Check, CheckCircle2, Handshake, Info, Loader2, MapPin, Search, Send, X, XCircle,
} from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  createAssistRequest, fetchAssistCandidates, type AssistCandidate,
} from '@/lib/api/assist-requests';
import { AG_COLOR, AGENCY_ICON } from '@/components/incidents/incident-vocabulary';
import { ASSIST_NEEDS, ASSIST_STATUS, ASSIST_TINT, ASSIST_TINT_BG } from '@/components/assist/assist-vocabulary';
import { cn } from '@/lib/utils';

const OVERLAP_TO_AGENCY_TYPE: Record<string, string> = {
  fire: 'BFP',
  injuries: 'MDRRMO',
  flooding: 'MDRRMO',
  missing_person: 'PNP',
  // hazmat can mean either BFP or MDRRMO — BFP is the suggested default,
  // MDRRMO is one click away like every other suggestion here.
  hazmat: 'BFP',
};

const AGENCY_FILTERS = ['All', 'BFP', 'PNP', 'MDRRMO'] as const;

type SendResult = { agency: AssistCandidate; ok: boolean; error?: string };

export function AssistRequestDialog({
  token,
  incidentId,
  overlapFlags,
  triggerRef,
  onClose,
  onSuccess,
  onError,
}: {
  token: string;
  incidentId: string;
  /** The incident's own overlap_agencies, if any — drives the auto-suggested target. */
  overlapFlags: string[];
  triggerRef: React.RefObject<HTMLButtonElement | null>;
  onClose: () => void;
  /** At least one request went out — the caller refreshes its own list. */
  onSuccess: (sentCount: number) => void;
  onError: (m: string) => void;
}) {
  const [candidates, setCandidates] = useState<AssistCandidate[] | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [needs, setNeeds] = useState<Set<string>>(new Set());
  const [note, setNote] = useState('');
  const [query, setQuery] = useState('');
  const [agencyFilter, setAgencyFilter] = useState<(typeof AGENCY_FILTERS)[number]>('All');
  const [sending, setSending] = useState(false);
  const [results, setResults] = useState<SendResult[] | null>(null);

  const suggestedTypes = useMemo(
    () => new Set(overlapFlags.map(f => OVERLAP_TO_AGENCY_TYPE[f]).filter(Boolean)),
    [overlapFlags],
  );

  useEffect(() => {
    let live = true;
    fetchAssistCandidates(incidentId, token)
      .then(list => {
        if (!live) return;
        setCandidates(list);
        // Pre-pick only a LOCAL station of a suggested agency — never someone
        // across the province without the dispatcher choosing them.
        const suggested = list.find(a => a.same_municipality && suggestedTypes.has(a.agency_type) && a.existing_status !== 'pending');
        if (suggested) setPicked(new Set([suggested.id]));
      })
      .catch((e: unknown) => onError(e instanceof Error ? e.message : 'Could not load the stations.'));
    return () => { live = false; };
    // A fresh instance mounts per open — only re-fetch if the incident changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [incidentId, token]);

  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = (candidates ?? []).filter(a =>
      (agencyFilter === 'All' || a.agency_type === agencyFilter)
      && (!q || [a.name, a.municipality, a.agency_type].some(v => v?.toLowerCase().includes(q))));
    const out: { municipality: string; local: boolean; items: AssistCandidate[] }[] = [];
    for (const a of list) {
      const m = a.municipality ?? 'Other';
      const last = out[out.length - 1];
      if (last && last.municipality === m) last.items.push(a);
      else out.push({ municipality: m, local: a.same_municipality, items: [a] });
    }
    return out;
  }, [candidates, query, agencyFilter]);

  const pickedList = (candidates ?? []).filter(a => picked.has(a.id));
  const message = [
    ...ASSIST_NEEDS.filter(n => needs.has(n.key)).map(n => n.sentence),
    note.trim(),
  ].filter(Boolean).join(' ');
  const canSend = pickedList.length > 0 && message.length > 0 && !sending;

  function toggle(set: Set<string>, id: string): Set<string> {
    const next = new Set(set);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  }

  async function send() {
    if (!canSend) return;
    setSending(true);
    const flagFor = (a: AssistCandidate) =>
      overlapFlags.find(f => OVERLAP_TO_AGENCY_TYPE[f] === a.agency_type) ?? null;
    const out = await Promise.all(pickedList.map(async agency => {
      try {
        await createAssistRequest(incidentId, agency.id, message, flagFor(agency), token);
        return { agency, ok: true } as SendResult;
      } catch (e) {
        return { agency, ok: false, error: e instanceof Error ? e.message : 'Could not send.' } as SendResult;
      }
    }));
    setSending(false);
    setResults(out);
    const sent = out.filter(r => r.ok).length;
    if (sent > 0) onSuccess(sent);
  }

  return (
    <Dialog onOpenChange={open => { if (!open && !sending) onClose(); }} open>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[680px]"
        onCloseAutoFocus={e => { e.preventDefault(); triggerRef.current?.focus(); }}
        onOpenAutoFocus={e => { e.preventDefault(); }}
        showCloseButton={false}
      >
        {/* ── Header ─────────────────────────────────────────────────── */}
        <div className="flex items-start gap-3.5 border-b border-[var(--color-surface-border)] px-6 pb-4 pt-5">
          <span className="flex size-11 shrink-0 items-center justify-center rounded-xl" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>
            <Handshake aria-hidden="true" className="size-5" />
          </span>
          <div className="min-w-0 flex-1">
            <DialogTitle className="text-[18px] font-bold leading-tight tracking-tight text-foreground">
              {results ? 'Request sent' : 'Request help from another station'}
            </DialogTitle>
            <DialogDescription className="mt-1 text-[13px] leading-snug">
              {results
                ? 'The stations below have been alerted. Their answers and messages will appear in Assist Requests.'
                : 'Pick any station in Biliran. They get an alert and a summary of this incident — the report stays with your station.'}
            </DialogDescription>
          </div>
          <DialogClose aria-label="Close" className="-mr-1 -mt-1 flex size-9 shrink-0 items-center justify-center rounded-xl text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground">
            <X aria-hidden="true" className="size-4" />
          </DialogClose>
        </div>

        {results ? (
          <ResultView onClose={onClose} results={results} />
        ) : (
          <>
            <div className="min-h-0 flex-1 overflow-y-auto">
              {/* ── Step 1: stations ─────────────────────────────────── */}
              <section className="px-6 pb-2 pt-4">
                <StepTitle n={1} text="Which station(s) do you need?" trailing={pickedList.length > 0 ? `${pickedList.length} selected` : undefined} />
                <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                  <label className="relative flex-1">
                    <Search aria-hidden="true" className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
                    <input
                      className="h-10 w-full rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] pl-9 pr-3 text-[13.5px] focus:border-[var(--color-brand)] focus:outline-none"
                      onChange={e => setQuery(e.target.value)}
                      placeholder="Search station or town"
                      type="search"
                      value={query}
                    />
                  </label>
                  <div className="flex gap-1 rounded-xl bg-[var(--color-surface-raised)] p-1">
                    {AGENCY_FILTERS.map(f => (
                      <button
                        aria-pressed={agencyFilter === f}
                        className={cn(
                          'h-8 rounded-lg px-3 text-[12.5px] font-semibold transition-colors',
                          agencyFilter === f ? 'bg-[var(--color-surface-card)] text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
                        )}
                        key={f}
                        onClick={() => setAgencyFilter(f)}
                        type="button"
                      >
                        {f}
                      </button>
                    ))}
                  </div>
                </div>

                <div className="mt-3 max-h-[300px] overflow-y-auto rounded-xl border border-[var(--color-surface-border)]">
                  {candidates === null ? (
                    <p className="flex items-center gap-2 p-4 text-[13px] text-muted-foreground"><Loader2 className="size-4 animate-spin" /> Loading stations…</p>
                  ) : candidates.length === 0 ? (
                    <p className="p-4 text-[13px] text-muted-foreground">No other active station is registered in Ziren yet.</p>
                  ) : groups.length === 0 ? (
                    <p className="p-4 text-[13px] text-muted-foreground">No station matches that search.</p>
                  ) : (
                    groups.map(g => (
                      <div key={g.municipality}>
                        <p className="sticky top-0 z-10 flex items-center gap-2 border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3.5 py-1.5 text-[11px] font-bold uppercase tracking-[0.06em] text-muted-foreground">
                          <MapPin aria-hidden="true" className="size-3" />
                          {g.municipality}
                          {g.local && <span className="rounded-full px-1.5 py-px text-[10px] normal-case tracking-normal" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>Same town as this incident</span>}
                        </p>
                        <ul className="divide-y divide-[var(--color-surface-border)]">
                          {g.items.map(a => (
                            <li key={a.id}>
                              <StationOption
                                agency={a}
                                checked={picked.has(a.id)}
                                onToggle={() => setPicked(p => toggle(p, a.id))}
                                suggested={suggestedTypes.has(a.agency_type)}
                              />
                            </li>
                          ))}
                        </ul>
                      </div>
                    ))
                  )}
                </div>
              </section>

              {/* ── Step 2: what is needed ───────────────────────────── */}
              <section className="px-6 pb-5 pt-4">
                <StepTitle n={2} text="What do you need from them?" />
                <div className="mt-3 grid grid-cols-2 gap-2 sm:grid-cols-3">
                  {ASSIST_NEEDS.map(n => {
                    const on = needs.has(n.key);
                    return (
                      <button
                        aria-pressed={on}
                        className={cn(
                          'flex items-center gap-2 rounded-xl border px-3 py-2.5 text-left text-[12.5px] font-semibold transition-colors',
                          on
                            ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] text-foreground'
                            : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)]',
                        )}
                        key={n.key}
                        onClick={() => setNeeds(s => toggle(s, n.key))}
                        type="button"
                      >
                        <n.icon aria-hidden="true" className="size-4 shrink-0" style={{ color: on ? 'var(--color-brand)' : undefined }} />
                        <span className="min-w-0 flex-1">{n.label}</span>
                        {on && <Check aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-brand)]" />}
                      </button>
                    );
                  })}
                </div>
                <label className="mt-3 block">
                  <span className="mb-1.5 block text-[12px] font-semibold text-[var(--color-text-secondary)]">Details for them <span className="font-normal text-muted-foreground">(exact spot, how many, who to look for)</span></span>
                  <textarea
                    className="w-full resize-none rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3.5 py-2.5 text-[13.5px] focus:border-[var(--color-brand)] focus:outline-none"
                    onChange={e => setNote(e.target.value)}
                    placeholder="e.g. Two-storey house beside the chapel. Our crew is already on scene."
                    rows={3}
                    value={note}
                  />
                </label>
                {message && (
                  <div className="mt-3 rounded-xl border border-dashed border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3.5 py-2.5">
                    <p className="text-[11px] font-bold uppercase tracking-[0.06em] text-muted-foreground">They will read</p>
                    <p className="mt-1 text-[13px] leading-relaxed text-foreground">{message}</p>
                  </div>
                )}
              </section>
            </div>

            {/* ── Footer ────────────────────────────────────────────── */}
            <div className="flex flex-col gap-3 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-6 py-4 sm:flex-row sm:items-center">
              <p className="flex min-w-0 flex-1 items-start gap-2 text-[12px] leading-snug text-muted-foreground">
                <Info aria-hidden="true" className="mt-0.5 size-3.5 shrink-0" />
                {pickedList.length === 0
                  ? 'Select at least one station.'
                  : !message
                    ? 'Tap what you need, or write a note.'
                    : `${pickedList.map(a => a.name).join(', ')} will be alerted right away.`}
              </p>
              <div className="flex shrink-0 gap-2">
                <button
                  className="h-11 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-5 text-[13.5px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
                  disabled={sending}
                  onClick={onClose}
                  type="button"
                >
                  Cancel
                </button>
                <button
                  className="flex h-11 items-center gap-2 rounded-xl bg-[var(--color-brand)] px-5 text-[13.5px] font-bold text-white shadow-sm transition-[filter] hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                  disabled={!canSend}
                  onClick={() => void send()}
                  type="button"
                >
                  {sending ? <Loader2 aria-hidden="true" className="size-4 animate-spin" /> : <Send aria-hidden="true" className="size-4" />}
                  {sending ? 'Sending…' : pickedList.length > 1 ? `Send to ${pickedList.length} stations` : 'Send request'}
                </button>
              </div>
            </div>
          </>
        )}
      </DialogContent>
    </Dialog>
  );
}

function StepTitle({ n, text, trailing }: { n: number; text: string; trailing?: string }) {
  return (
    <div className="flex items-center gap-2.5">
      <span className="flex size-6 items-center justify-center rounded-full bg-[var(--color-text-primary)] text-[12px] font-bold text-[var(--color-text-inverse)]">{n}</span>
      <h3 className="text-[14px] font-bold text-foreground">{text}</h3>
      {trailing && <span className="ml-auto rounded-full bg-[var(--color-brand-subtle)] px-2.5 py-0.5 text-[11.5px] font-bold text-[var(--color-brand)]">{trailing}</span>}
    </div>
  );
}

function StationOption({
  agency: a, checked, suggested, onToggle,
}: { agency: AssistCandidate; checked: boolean; suggested: boolean; onToggle: () => void }) {
  const Icon = AGENCY_ICON[a.agency_type];
  const hue = AG_COLOR[a.agency_type] ?? ASSIST_TINT;
  const waiting = a.existing_status === 'pending';
  const earlier = a.existing_status && a.existing_status !== 'pending' ? ASSIST_STATUS[a.existing_status] : null;

  return (
    <button
      aria-checked={checked}
      className={cn(
        'flex w-full items-center gap-3 px-3.5 py-2.5 text-left transition-colors',
        waiting ? 'cursor-not-allowed opacity-60' : checked ? 'bg-[var(--color-brand-subtle)]' : 'hover:bg-[var(--color-surface-hover)]',
      )}
      disabled={waiting}
      onClick={onToggle}
      role="checkbox"
      type="button"
    >
      <span
        aria-hidden="true"
        className={cn(
          'flex size-5 shrink-0 items-center justify-center rounded-md border-2 transition-colors',
          checked ? 'border-[var(--color-brand)] bg-[var(--color-brand)] text-white' : 'border-[var(--color-surface-border)]',
        )}
      >
        {checked && <Check className="size-3.5" strokeWidth={3} />}
      </span>
      {Icon && (
        <span
          aria-hidden="true"
          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
          style={{ backgroundColor: `color-mix(in srgb, ${hue} 14%, transparent)`, color: hue }}
        >
          <Icon className="size-4" />
        </span>
      )}
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[13.5px] font-semibold text-foreground">{a.name}</span>
        <span className="block truncate text-[11.5px] text-muted-foreground">
          {a.agency_type}{a.contact_number ? ` · ${a.contact_number}` : ''}
        </span>
      </span>
      {waiting ? (
        <span className="shrink-0 rounded-full bg-[var(--color-system-warning-bg)] px-2 py-0.5 text-[10.5px] font-bold text-[var(--color-system-warning)]">Already asked · waiting</span>
      ) : earlier ? (
        <span className="shrink-0 rounded-full px-2 py-0.5 text-[10.5px] font-bold" style={{ backgroundColor: earlier.bg, color: earlier.fg }}>Asked before · {earlier.label}</span>
      ) : suggested ? (
        <span className="shrink-0 rounded-full px-2 py-0.5 text-[10.5px] font-bold" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>Suggested</span>
      ) : null}
    </button>
  );
}

function ResultView({ results, onClose }: { results: SendResult[]; onClose: () => void }) {
  const sent = results.filter(r => r.ok);
  return (
    <>
      <ul className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-6 py-5">
        {results.map(r => (
          <li
            className="flex items-start gap-3 rounded-xl border px-3.5 py-3"
            key={r.agency.id}
            style={{
              borderColor: r.ok ? 'color-mix(in srgb, var(--color-system-success) 35%, var(--color-surface-border))' : 'color-mix(in srgb, var(--color-system-error) 35%, var(--color-surface-border))',
              backgroundColor: r.ok ? 'var(--color-system-success-bg)' : 'var(--color-system-error-bg)',
            }}
          >
            {r.ok
              ? <CheckCircle2 aria-hidden="true" className="mt-0.5 size-5 shrink-0 text-[var(--color-system-success)]" />
              : <XCircle aria-hidden="true" className="mt-0.5 size-5 shrink-0 text-[var(--color-system-error)]" />}
            <span className="min-w-0">
              <span className="block text-[13.5px] font-bold text-foreground">{r.agency.name}</span>
              <span className="block text-[12.5px] text-[var(--color-text-secondary)]">
                {r.ok ? 'Alerted — waiting for their answer.' : r.error}
              </span>
            </span>
          </li>
        ))}
      </ul>
      <div className="flex justify-end gap-2 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-6 py-4">
        <button
          className="h-11 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-5 text-[13.5px] font-semibold text-foreground hover:bg-[var(--color-surface-hover)]"
          onClick={onClose}
          type="button"
        >
          Done
        </button>
        {sent.length > 0 && (
          <Link
            className="flex h-11 items-center gap-2 rounded-xl bg-[var(--color-brand)] px-5 text-[13.5px] font-bold text-white shadow-sm hover:brightness-110"
            href="/assist-requests"
            onClick={onClose}
          >
            Open Assist Requests <ArrowRight aria-hidden="true" className="size-4" />
          </Link>
        )}
      </div>
    </>
  );
}
