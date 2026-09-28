'use client';

/**
 * One assist request, in full: who asked whom, the situation, the answer,
 * and the conversation between the two stations.
 *
 * Built from what stations testing the first version said they could not
 * tell from it: whether they were the one asking or the one asked, what the
 * emergency actually was, whether the other side had answered, and what they
 * were supposed to do next. So the top of the panel says all four in words —
 * a direction line, a situation card, a two-step status track, and (for the
 * station that was asked, while it is still waiting) one clear pair of
 * buttons — before the chat starts.
 *
 * The station that was asked never gets the report itself; the situation
 * card is the read-only snapshot the backend hands both sides (see
 * assist_request_service's module docstring).
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import {
  ArrowDownLeft, ArrowUpRight, Check, Clock, ExternalLink, Eye, Loader2, MapPin, Phone, Send, X,
} from 'lucide-react';
import { useAssistThread } from '@/lib/hooks/useAssistThread';
import {
  counterpart, postAssistMessage, setAssistStatus,
  type AssistMessage, type AssistRequestSummary,
} from '@/lib/api/assist-requests';
import { AG_COLOR, AGENCY_ICON, CATEGORY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { cn } from '@/lib/utils';
import { ASSIST_STATUS, ASSIST_TINT, stamp } from './assist-vocabulary';

const QUICK_REPLIES_INCOMING = ['On our way.', 'Our team will arrive in about 10 minutes.', 'Please send the exact location.', 'We have arrived on scene.'];
const QUICK_REPLIES_OUTGOING = ['Thank you!', 'Please proceed to the location.', 'Situation is under control, you may stand down.', 'Please call our station.'];

export function AssistConversation({
  requestId,
  token,
  onChanged,
  onSeen,
  readOnly = false,
  className,
}: {
  requestId: string;
  token: string;
  /** After an accept/decline or a sent message, so lists can refresh. */
  onChanged?: () => void;
  /** Whenever the thread is on screen with new messages — marks it read. */
  onSeen?: (id: string) => void;
  /** Provincial Admin oversight: no answer buttons, no compose box. */
  readOnly?: boolean;
  className?: string;
}) {
  const { thread, loading, error, refresh } = useAssistThread(requestId, token);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [responding, setResponding] = useState<'acknowledged' | 'declined' | null>(null);
  const [declining, setDeclining] = useState(false);
  const [reason, setReason] = useState('');
  const [actionError, setActionError] = useState<string | null>(null);
  const scrollBox = useRef<HTMLDivElement>(null);

  // Where the panel opens: at the top — the situation and the answer buttons —
  // while the request still waits for OUR answer, at the latest message
  // otherwise. After that, a new message always scrolls into view.
  const count = thread?.messages.length ?? 0;
  const seenCount = useRef<number | null>(null);
  const waitingOnUs = Boolean(thread?.request.can_respond);
  useEffect(() => {
    const box = scrollBox.current;
    if (!box || !count) return;
    const first = seenCount.current === null;
    seenCount.current = count;
    if (first && waitingOnUs) return;
    box.scrollTo({ top: box.scrollHeight, behavior: first ? 'auto' : 'smooth' });
  }, [count, waitingOnUs]);

  useEffect(() => {
    if (thread) onSeen?.(requestId);
    // onSeen is a stable callback from the inbox; re-run only on new messages.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [requestId, count, Boolean(thread)]);

  useEffect(() => { setDeclining(false); setReason(''); setDraft(''); setActionError(null); }, [requestId]);

  if (loading && !thread) {
    return (
      <div className={cn('flex items-center justify-center gap-2 p-10 text-[13px] text-muted-foreground', className)}>
        <Loader2 aria-hidden="true" className="size-4 animate-spin" /> Loading conversation…
      </div>
    );
  }
  if (error && !thread) {
    return <div className={cn('p-6 text-[13px] text-[var(--color-system-error)]', className)}>{error}</div>;
  }
  if (!thread) return null;

  const { request, messages } = thread;
  const closed = request.incident_status === 'resolved' || request.incident_status === 'cancelled';
  const canWrite = !readOnly && !closed && request.direction !== 'oversight';

  async function send(text: string) {
    const body = text.trim();
    if (!body || !canWrite) return;
    setSending(true);
    setActionError(null);
    try {
      await postAssistMessage(requestId, body, token);
      setDraft('');
      refresh();
      onChanged?.();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Could not send the message.');
    } finally {
      setSending(false);
    }
  }

  async function respond(newStatus: 'acknowledged' | 'declined') {
    setResponding(newStatus);
    setActionError(null);
    try {
      if (newStatus === 'declined' && reason.trim()) {
        await postAssistMessage(requestId, reason.trim(), token);
      }
      await setAssistStatus(requestId, newStatus, token);
      setDeclining(false);
      setReason('');
      refresh();
      onChanged?.();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Could not send your answer.');
    } finally {
      setResponding(null);
    }
  }

  const quick = request.direction === 'incoming' ? QUICK_REPLIES_INCOMING : QUICK_REPLIES_OUTGOING;

  return (
    <div className={cn('flex min-h-0 flex-col', className)}>
      <DirectionHeader request={request} />

      <div className="min-h-0 flex-1 overflow-y-auto" ref={scrollBox}>
        <div className="flex flex-col gap-4 px-5 py-4">
          <SituationCard request={request} />
          <StatusTrack request={request} />

          {request.can_respond && !readOnly && (
            <div
              className="rounded-2xl border-2 p-4"
              style={{ borderColor: `color-mix(in srgb, var(--color-system-warning) 55%, transparent)`, backgroundColor: 'var(--color-system-warning-bg)' }}
            >
              <p className="text-[14px] font-bold text-foreground">Can your station help?</p>
              <p className="mt-1 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
                {request.requesting_agency_name ?? 'The other station'} keeps this report — you are only being asked to support them.
                Your answer is sent to them right away.
              </p>
              {declining ? (
                <div className="mt-3 flex flex-col gap-2">
                  <textarea
                    aria-label="Reason for declining (optional)"
                    className="w-full resize-none rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2.5 text-[13px]"
                    onChange={e => setReason(e.target.value)}
                    placeholder="Tell them why (optional) — e.g. All our units are deployed."
                    rows={2}
                    value={reason}
                  />
                  <div className="grid grid-cols-2 gap-2">
                    <button
                      className="h-11 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[13.5px] font-semibold text-foreground hover:bg-[var(--color-surface-hover)]"
                      disabled={responding !== null}
                      onClick={() => setDeclining(false)}
                      type="button"
                    >
                      Back
                    </button>
                    <button
                      className="flex h-11 items-center justify-center gap-2 rounded-xl bg-[var(--color-text-primary)] text-[13.5px] font-bold text-[var(--color-text-inverse)] hover:opacity-90 disabled:opacity-50"
                      disabled={responding !== null}
                      onClick={() => void respond('declined')}
                      type="button"
                    >
                      {responding === 'declined' ? <Loader2 className="size-4 animate-spin" /> : <X className="size-4" />}
                      Decline request
                    </button>
                  </div>
                </div>
              ) : (
                <div className="mt-3 grid grid-cols-[1fr_1.4fr] gap-2">
                  <button
                    className="flex h-11 items-center justify-center gap-2 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[13.5px] font-semibold text-foreground hover:bg-[var(--color-surface-hover)] disabled:opacity-50"
                    disabled={responding !== null}
                    onClick={() => setDeclining(true)}
                    type="button"
                  >
                    <X aria-hidden="true" className="size-4" /> Can’t assist
                  </button>
                  <button
                    className="flex h-11 items-center justify-center gap-2 rounded-xl bg-[var(--color-system-success)] text-[13.5px] font-bold text-white shadow-sm hover:brightness-110 disabled:opacity-50"
                    disabled={responding !== null}
                    onClick={() => void respond('acknowledged')}
                    type="button"
                  >
                    {responding === 'acknowledged' ? <Loader2 className="size-4 animate-spin" /> : <Check className="size-4" />}
                    Accept — we’re responding
                  </button>
                </div>
              )}
            </div>
          )}

          <div className="flex items-center gap-3 pt-1">
            <span className="h-px flex-1 bg-[var(--color-surface-border)]" />
            <span className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">
              Conversation · {messages.length} message{messages.length === 1 ? '' : 's'}
            </span>
            <span className="h-px flex-1 bg-[var(--color-surface-border)]" />
          </div>

          <MessageList messages={messages} request={request} />
        </div>
      </div>

      {actionError && (
        <p className="border-t border-[var(--color-surface-border)] bg-[var(--color-system-error-bg)] px-5 py-2 text-[12.5px] font-medium text-[var(--color-system-error)]">
          {actionError}
        </p>
      )}

      {closed ? (
        <p className="border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-5 py-3 text-[12.5px] text-muted-foreground">
          This incident is closed, so the conversation is read-only.
        </p>
      ) : readOnly || request.direction === 'oversight' ? (
        <p className="flex items-center gap-2 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-5 py-3 text-[12.5px] text-muted-foreground">
          <Eye aria-hidden="true" className="size-3.5" /> Oversight view — only the two stations can reply.
        </p>
      ) : (
        <div className="border-t border-[var(--color-surface-border)] px-4 pb-4 pt-3">
          <div className="mb-2 flex gap-1.5 overflow-x-auto pb-0.5">
            {quick.map(q => (
              <button
                className="shrink-0 rounded-full border border-[var(--color-surface-border)] px-3 py-1 text-[12px] font-medium text-[var(--color-text-secondary)] transition-colors hover:border-[var(--color-brand)] hover:text-foreground disabled:opacity-50"
                disabled={sending}
                key={q}
                onClick={() => void send(q)}
                type="button"
              >
                {q}
              </button>
            ))}
          </div>
          <div className="flex items-end gap-2">
            <textarea
              aria-label={`Message ${counterpart(request).name ?? 'the other station'}`}
              className="max-h-32 min-h-11 flex-1 resize-none rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3.5 py-2.5 text-[13.5px] focus:border-[var(--color-brand)] focus:outline-none"
              disabled={sending}
              onChange={e => setDraft(e.target.value)}
              onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(draft); } }}
              placeholder={`Message ${counterpart(request).name ?? 'the other station'}…`}
              rows={1}
              value={draft}
            />
            <button
              aria-label="Send message"
              className="flex h-11 shrink-0 items-center gap-1.5 rounded-xl bg-[var(--color-brand)] px-4 text-[13.5px] font-bold text-white transition-[filter] hover:brightness-110 disabled:opacity-50"
              disabled={sending || !draft.trim()}
              onClick={() => void send(draft)}
              type="button"
            >
              {sending ? <Loader2 className="size-4 animate-spin" /> : <Send className="size-4" />}
              Send
            </button>
          </div>
          <p className="mt-1.5 text-[11px] text-muted-foreground">Enter to send · Shift+Enter for a new line</p>
        </div>
      )}
    </div>
  );
}

function DirectionHeader({ request }: { request: AssistRequestSummary }) {
  const other = counterpart(request);
  const st = ASSIST_STATUS[request.status];
  const StIcon = st.icon;
  const AgIcon = other.type ? AGENCY_ICON[other.type] : undefined;
  const hue = other.type ? AG_COLOR[other.type] : ASSIST_TINT;
  const incoming = request.direction === 'incoming';
  const title = request.direction === 'oversight'
    ? `${request.requesting_agency_name ?? 'A station'} asked ${request.requested_agency_name ?? 'another station'}`
    : incoming ? `${other.name ?? 'Another station'} is asking you for help` : `You asked ${other.name ?? 'another station'} for help`;

  return (
    <div className="flex flex-wrap items-center gap-3 border-b border-[var(--color-surface-border)] px-5 py-4">
      <span
        aria-hidden="true"
        className="relative flex size-11 shrink-0 items-center justify-center rounded-xl"
        style={{ backgroundColor: `color-mix(in srgb, ${hue} 14%, transparent)`, color: hue }}
      >
        {AgIcon && <AgIcon className="size-5" />}
        {request.direction !== 'oversight' && (
          <span className="absolute -bottom-1 -right-1 flex size-5 items-center justify-center rounded-full border-2 border-[var(--color-surface-card)] text-white" style={{ backgroundColor: ASSIST_TINT }}>
            {incoming ? <ArrowDownLeft className="size-3" /> : <ArrowUpRight className="size-3" />}
          </span>
        )}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[11px] font-bold uppercase tracking-[0.08em]" style={{ color: ASSIST_TINT }}>
          {request.direction === 'oversight' ? 'Assist request' : incoming ? 'Incoming request' : 'Your request'}
        </p>
        <h2 className="text-[16px] font-bold leading-snug text-foreground">{title}</h2>
        <p className="text-[12px] text-muted-foreground">
          {[other.type, other.municipality].filter(Boolean).join(' · ')}
        </p>
      </div>
      <div className="flex items-center gap-2">
        {other.contact && request.direction !== 'oversight' && (
          <a
            className="inline-flex h-9 items-center gap-1.5 rounded-xl border border-[var(--color-surface-border)] px-3 text-[12.5px] font-semibold tabular-nums text-foreground hover:bg-[var(--color-surface-hover)]"
            href={`tel:${other.contact.replace(/[^\d+]/g, '')}`}
            title={`Call ${other.name ?? 'the other station'}`}
          >
            <Phone aria-hidden="true" className="size-3.5" /> {other.contact}
          </a>
        )}
        <span className="inline-flex h-9 items-center gap-1.5 rounded-xl px-3 text-[12.5px] font-bold" style={{ backgroundColor: st.bg, color: st.fg }}>
          <StIcon aria-hidden="true" className="size-3.5" />
          {request.direction === 'incoming' ? st.incoming : request.direction === 'outgoing' ? st.outgoing : st.label}
        </span>
      </div>
    </div>
  );
}

function SituationCard({ request: r }: { request: AssistRequestSummary }) {
  const SevIcon = r.severity ? SEV_ICON[r.severity] : undefined;
  const CatIcon = r.incident_category ? CATEGORY_ICON[r.incident_category] : undefined;
  const sevColor = r.severity ? SEV_COLOR[r.severity] : 'var(--color-text-tertiary)';
  const category = r.incident_category ? CATEGORY_LABELS[r.incident_category] ?? r.incident_category : 'Incident';
  const hasPoint = r.latitude != null && r.longitude != null;

  return (
    <section aria-label="Situation" className="rounded-2xl border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-[11px] font-bold uppercase tracking-[0.08em] text-muted-foreground">The situation</p>
        {r.direction === 'outgoing' ? (
          <Link className="text-[12px] font-semibold text-[var(--color-brand)] hover:underline" href={`/incidents/${r.incident_id}`}>
            Open full incident
          </Link>
        ) : r.direction === 'incoming' ? (
          <span className="text-[11.5px] text-muted-foreground">Report handled by {r.requesting_agency_name ?? 'the other station'}</span>
        ) : null}
      </div>

      <div className="mt-2.5 flex items-start gap-3">
        <span
          aria-hidden="true"
          className="flex size-10 shrink-0 items-center justify-center rounded-xl"
          style={{ backgroundColor: `color-mix(in srgb, ${sevColor} 14%, transparent)`, color: sevColor }}
        >
          {CatIcon ? <CatIcon className="size-5" /> : SevIcon ? <SevIcon className="size-5" /> : null}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[15px] font-bold text-foreground">{category}</p>
          <p className="mt-0.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-[12.5px] text-[var(--color-text-secondary)]">
            {SevIcon && r.severity && (
              <span className="inline-flex items-center gap-1 font-semibold" style={{ color: sevColor }}>
                <SevIcon aria-hidden="true" className="size-3.5" />
                {r.severity[0].toUpperCase() + r.severity.slice(1)} severity
              </span>
            )}
            {r.record_number && <span className="font-mono text-[12px]">{r.record_number}</span>}
            <span className="inline-flex items-center gap-1"><Clock aria-hidden="true" className="size-3.5" />Reported {stamp(r.incident_created_at)}</span>
          </p>
        </div>
      </div>

      <dl className="mt-3 grid gap-2.5 text-[13px]">
        <div className="flex items-start gap-2">
          <MapPin aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
          <div className="min-w-0">
            <dt className="sr-only">Location</dt>
            <dd className="text-foreground">{r.location_address ?? 'No address on the report'}</dd>
            {hasPoint && (
              <a
                className="mt-0.5 inline-flex items-center gap-1 text-[12px] font-semibold text-[var(--color-brand)] hover:underline"
                href={`https://www.google.com/maps/search/?api=1&query=${r.latitude},${r.longitude}`}
                rel="noreferrer"
                target="_blank"
              >
                Open location in Maps <ExternalLink aria-hidden="true" className="size-3" />
              </a>
            )}
          </div>
        </div>
        {r.report_text && (
          <div>
            <dt className="mb-1 text-[11px] font-bold uppercase tracking-[0.06em] text-muted-foreground">What the reporter said</dt>
            <dd className="rounded-xl border-l-[3px] bg-[var(--color-surface-card)] px-3 py-2 italic leading-relaxed text-foreground" style={{ borderColor: sevColor }}>
              {r.report_text}
            </dd>
          </div>
        )}
      </dl>
    </section>
  );
}

function StatusTrack({ request: r }: { request: AssistRequestSummary }) {
  const answered = r.status !== 'pending';
  const st = ASSIST_STATUS[r.status];
  const steps = [
    { label: 'Requested', detail: `${r.requesting_agency_name ?? 'Station'} · ${stamp(r.created_at)}`, done: true, color: ASSIST_TINT },
    {
      label: answered ? st.label : 'Waiting for answer',
      detail: answered ? `${r.requested_agency_name ?? 'Station'} · ${stamp(r.responded_at)}` : `${r.requested_agency_name ?? 'The other station'} has not answered yet`,
      done: answered,
      color: answered ? st.fg : 'var(--color-system-warning)',
    },
  ];
  return (
    <ol aria-label="Request status" className="grid grid-cols-2 gap-2">
      {steps.map((s, i) => (
        <li
          className="rounded-xl border px-3 py-2.5"
          key={i}
          style={{
            borderColor: s.done ? `color-mix(in srgb, ${s.color} 40%, var(--color-surface-border))` : 'var(--color-surface-border)',
            borderStyle: s.done ? 'solid' : 'dashed',
          }}
        >
          <p className="flex items-center gap-1.5 text-[12.5px] font-bold" style={{ color: s.color }}>
            <span className="flex size-4 items-center justify-center rounded-full text-[10px] text-white" style={{ backgroundColor: s.color }}>{i + 1}</span>
            {s.label}
          </p>
          <p className="mt-0.5 truncate text-[11.5px] text-muted-foreground">{s.detail}</p>
        </li>
      ))}
    </ol>
  );
}

function MessageList({ messages, request }: { messages: AssistMessage[]; request: AssistRequestSummary }) {
  const groups = useMemo(() => {
    const out: { day: string; items: AssistMessage[] }[] = [];
    for (const m of messages) {
      const day = new Date(m.created_at).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', weekday: 'short', month: 'short', day: 'numeric' });
      const last = out[out.length - 1];
      if (last && last.day === day) last.items.push(m); else out.push({ day, items: [m] });
    }
    return out;
  }, [messages]);

  if (!messages.length) {
    return <p className="py-6 text-center text-[13px] text-muted-foreground">No messages yet.</p>;
  }

  const nameOf = (m: AssistMessage) =>
    m.sender_agency_id === request.requesting_agency_id ? request.requesting_agency_name : request.requested_agency_name;

  return (
    <div className="flex flex-col gap-3">
      {groups.map(g => (
        <div className="flex flex-col gap-2.5" key={g.day}>
          <p className="self-center rounded-full bg-[var(--color-surface-raised)] px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">{g.day}</p>
          {g.items.map((m, i) => {
            const first = i === 0 && g === groups[0];
            return (
              <div className={cn('flex flex-col', m.mine ? 'items-end' : 'items-start')} key={m.id}>
                <span className="mb-0.5 px-1 text-[11px] font-semibold text-muted-foreground">
                  {m.mine ? 'You' : nameOf(m) ?? 'Other station'}
                  {m.sender_name ? ` · ${m.sender_name}` : ''}
                  {first ? ' · opening request' : ''}
                </span>
                <div
                  className={cn(
                    'max-w-[85%] whitespace-pre-wrap rounded-2xl px-3.5 py-2.5 text-[13.5px] leading-snug',
                    m.mine
                      ? 'rounded-br-md bg-[var(--color-brand)] text-white'
                      : 'rounded-bl-md border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-foreground',
                  )}
                >
                  {m.body}
                </div>
                <span className="mt-0.5 px-1 text-[10.5px] text-muted-foreground">
                  {new Date(m.created_at).toLocaleTimeString('en-PH', { timeZone: 'Asia/Manila', hour: 'numeric', minute: '2-digit' })}
                </span>
              </div>
            );
          })}
        </div>
      ))}
    </div>
  );
}
