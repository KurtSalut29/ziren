'use client';

/**
 * The conversation with the resident, as a window of its own.
 *
 * It used to be a card drawn inside the report, between "What" and "Who". That
 * put a chat in the middle of a document a dispatcher is reading to decide
 * something, and made the report longer for every incident whether or not
 * anyone had said a word. It is a modal now: the report stays a report, and the
 * Chat button (with a count of unread replies) opens the conversation on its
 * own.
 *
 * One composer, and it does the right thing underneath. While the report is
 * still undecided (`canRequestClarification`) a message is sent as a request for
 * clarification - the resident's phone shows it as a question with a Reply
 * button, and the report waits on the answer. Once the report is decided the same
 * box sends a plain note. The agency never has to choose which of two boxes to
 * type into.
 *
 * Only an Agency Admin can write. A Provincial Admin oversees every incident of
 * their agency type and has no seat in the conversation, so they get the same
 * window read-only.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { CircleHelp, MessageSquare, MessageSquareReply, Send } from 'lucide-react';
import {
  addIncidentNote, requestClarification, type IncidentNote, type ReviewStatus,
} from '@/lib/api/dispatch';
import { toast } from '@/lib/toast';
import { relativeTime } from '@/lib/format/relative-time';
import type { IncidentThread } from '@/lib/hooks/useIncidentThread';
import {
  Dialog, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';

const ROLE_LABEL: Record<IncidentNote['author_role'], string> = {
  agency_admin: 'Agency Admin',
  responder: 'Responder',
  provincial_admin: 'Provincial Admin',
  resident: 'Resident',
};

/**
 * What the agency asked the resident, if it asked.
 *
 * The question lives on the incident row (clarification_note) and the answer
 * lives in the thread; this window's job is to put the two next to each other.
 */
export interface ClarificationState {
  status?: ReviewStatus;
  note?: string | null;
  requestedAt?: string | null;
}

/** "Today", "Yesterday", or a short date - the divider above a run of messages. */
function dayLabel(iso: string, now = new Date()): string {
  const d = new Date(iso);
  const startOf = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diffDays = Math.round((startOf(now) - startOf(d)) / 86_400_000);
  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: d.getFullYear() === now.getFullYear() ? undefined : 'numeric' });
}

export function IncidentChatModal({
  open,
  onClose,
  incidentId,
  token,
  thread,
  canCompose,
  canRequestClarification = false,
  clarification,
  onClarificationRequested,
  reporterName,
  recordNo,
}: {
  open: boolean;
  onClose: () => void;
  incidentId: string;
  token: string | null;
  thread: IncidentThread;
  canCompose: boolean;
  /** True while this report's fate is still undecided - see the file comment. */
  canRequestClarification?: boolean;
  clarification?: ClarificationState;
  /** A message was sent as a clarification request: the report's own
   * review_status just changed server-side and the caller should re-read it. */
  onClarificationRequested?: () => void;
  reporterName?: string | null;
  recordNo?: string | null;
}) {
  const { notes, error, reload, markSeen, setError } = thread;
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Opening the window is reading it: clear the unread count and take the latest
  // messages now rather than at the next poll. (The cursor goes into the box in
  // onOpenAutoFocus below, the moment the window mounts.)
  useEffect(() => {
    if (!open) return;
    markSeen();
    void reload();
  }, [open, markSeen, reload]);

  // A message that arrives while the window is open is seen as it lands, and the
  // list follows the newest one.
  const count = notes?.length ?? 0;
  useEffect(() => {
    if (!open) return;
    markSeen();
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [open, count, markSeen]);

  // The resident's answer to the current question: their latest message after
  // the question was asked.
  const reply = useMemo(() => {
    if (!clarification?.requestedAt || !notes) return null;
    const asked = new Date(clarification.requestedAt).getTime();
    const answers = notes.filter(
      n => n.author_role === 'resident' && new Date(n.created_at).getTime() >= asked,
    );
    return answers.length > 0 ? answers[answers.length - 1] : null;
  }, [clarification?.requestedAt, notes]);

  const asked = Boolean(clarification?.requestedAt && clarification.note);
  const waiting = asked && clarification?.status === 'clarification_requested' && !reply;

  async function send() {
    const text = draft.trim();
    if (!token || !text || sending) return;
    setSending(true);
    setError(null);
    try {
      if (canRequestClarification) {
        await requestClarification(incidentId, text, token);
        onClarificationRequested?.();
      } else {
        await addIncidentNote(incidentId, text, token);
      }
      setDraft('');
      await reload();
      inputRef.current?.focus();
    } catch (e) {
      const msg = e instanceof Error ? e.message : 'The message could not be sent.';
      setError(msg);
      toast.error(msg);
    } finally {
      setSending(false);
    }
  }

  // Newest at the bottom, with a divider whenever the day changes.
  const rows = useMemo(() => {
    const out: ({ kind: 'day'; label: string; key: string } | { kind: 'note'; note: IncidentNote })[] = [];
    let last = '';
    for (const n of notes ?? []) {
      const label = dayLabel(n.created_at);
      if (label !== last) { out.push({ kind: 'day', label, key: `day-${n.id}` }); last = label; }
      out.push({ kind: 'note', note: n });
    }
    return out;
  }, [notes]);

  const title = canCompose ? 'Chat with the resident' : 'Messages';
  const subtitle = [recordNo, reporterName].filter(Boolean).join(' · ');

  return (
    <Dialog onOpenChange={o => { if (!o && !sending) onClose(); }} open={open}>
      <DialogContent
        className="flex h-[min(680px,86vh)] w-full flex-col gap-0 overflow-hidden p-0 sm:max-w-[520px]"
        // Where a person opening the chat wants to be: in the box, ready to type.
        // A reader with nothing to write gets the dialog's own default focus.
        onOpenAutoFocus={e => {
          if (!canCompose) return;
          e.preventDefault();
          inputRef.current?.focus();
        }}
      >
        {/* ── Who this is with ── */}
        <div className="flex shrink-0 items-center gap-3 border-b border-[var(--color-surface-border)] px-5 py-4 pr-14">
          <div
            className="flex size-10 shrink-0 items-center justify-center rounded-full"
            style={{ backgroundColor: 'color-mix(in srgb, var(--color-brand) 12%, transparent)', color: 'var(--color-brand)' }}
          >
            <MessageSquare className="size-5" />
          </div>
          <div className="min-w-0">
            <DialogTitle className="text-[15px] font-semibold leading-tight">{title}</DialogTitle>
            <DialogDescription className="mt-1 truncate text-[12px]">
              {subtitle || 'Messages on this report'}
            </DialogDescription>
          </div>
        </div>

        {/* ── The question the agency asked, and whether it was answered ── */}
        {asked && (
          <div
            className="mx-4 mt-3 flex shrink-0 items-start gap-2.5 rounded-[var(--radius-card)] border px-3.5 py-3"
            role="status"
            style={{
              borderColor: waiting ? 'var(--color-system-warning)' : 'var(--color-system-info)',
              backgroundColor: waiting ? 'var(--color-system-warning-bg)' : 'var(--color-system-info-bg)',
            }}
          >
            {waiting
              ? <CircleHelp className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-system-warning)' }} />
              : <MessageSquareReply className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-system-info)' }} />}
            <div className="min-w-0">
              <p className="text-[12.5px] font-semibold text-[var(--color-text-primary)]">
                {waiting ? 'Waiting for the resident' : reply ? 'The resident replied' : 'Clarification was requested'}
                {clarification?.requestedAt && (
                  <span className="ml-2 font-normal text-[var(--color-text-muted)]">
                    asked {relativeTime(clarification.requestedAt)}
                  </span>
                )}
              </p>
              <p className="mt-0.5 break-words text-[12.5px] text-[var(--color-text-secondary)]">
                <span className="font-medium">You asked:</span> {clarification?.note}
              </p>
              {waiting && (
                <p className="mt-1 text-[11.5px] text-[var(--color-text-muted)]">
                  It is on their phone now. Their answer appears here.
                </p>
              )}
            </div>
          </div>
        )}

        {/* ── The messages ── */}
        <div
          aria-live="polite"
          className="min-h-0 flex-1 overflow-y-auto px-4 py-3"
          data-chat-list
          ref={listRef}
        >
          {error && (
            <p className="mb-2 rounded-md px-3 py-2 text-[12.5px]" role="alert" style={{
              color: 'var(--color-severity-critical)',
              backgroundColor: 'var(--color-severity-critical-bg)',
            }}>
              {error}
            </p>
          )}

          {notes === null ? (
            <p className="py-8 text-center text-[12.5px] text-[var(--color-text-muted)]">Loading messages…</p>
          ) : rows.length === 0 ? (
            <div className="flex h-full flex-col items-center justify-center gap-2 px-6 text-center">
              <div className="flex size-12 items-center justify-center rounded-full bg-[var(--color-surface-raised)]">
                <MessageSquare className="size-5 text-[var(--color-text-muted)]" />
              </div>
              <p className="text-[13.5px] font-semibold text-[var(--color-text-primary)]">No messages yet</p>
              <p className="text-[12.5px] leading-relaxed text-[var(--color-text-muted)]">
                {canCompose
                  ? 'Send the first message below. It goes straight to the resident’s phone.'
                  : 'When the agency and the resident write to each other, it appears here.'}
              </p>
            </div>
          ) : (
            <ul className="flex flex-col gap-2.5">
              {rows.map(row => {
                if (row.kind === 'day') {
                  return (
                    <li className="my-1 flex justify-center" key={row.key}>
                      <span className="rounded-full bg-[var(--color-surface-raised)] px-2.5 py-0.5 text-[10.5px] font-semibold text-[var(--color-text-muted)]">
                        {row.label}
                      </span>
                    </li>
                  );
                }
                const n = row.note;
                const fromResident = n.author_role === 'resident';
                return (
                  <li className={`flex ${fromResident ? 'justify-start' : 'justify-end'}`} key={n.id}>
                    <div
                      className={`max-w-[80%] px-3.5 py-2.5 ${
                        fromResident
                          ? 'rounded-tl-[16px] rounded-tr-[16px] rounded-br-[16px] rounded-bl-[4px]'
                          : 'rounded-tl-[16px] rounded-tr-[16px] rounded-bl-[16px] rounded-br-[4px]'
                      }`}
                      style={{
                        backgroundColor: fromResident
                          ? 'var(--color-surface-raised)'
                          : 'color-mix(in srgb, var(--color-brand) 10%, transparent)',
                      }}
                    >
                      <span
                        className="text-[11px] font-bold"
                        style={{ color: fromResident ? 'var(--color-text-secondary)' : 'var(--color-brand)' }}
                      >
                        {n.users?.full_name ?? ROLE_LABEL[n.author_role] ?? n.author_role}
                      </span>
                      <p className="mt-0.5 whitespace-pre-wrap break-words text-[13px] leading-relaxed text-[var(--color-text-primary)]">
                        {n.body}
                      </p>
                      <p className="mt-1 text-[10.5px] text-[var(--color-text-muted)]">
                        {new Date(n.created_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
                      </p>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </div>

        {/* ── Writing ── */}
        {canCompose ? (
          <div className="shrink-0 border-t border-[var(--color-surface-border)] px-4 py-3">
            <div className="flex items-end gap-2">
              <textarea
                aria-label="Message to the resident"
                className="max-h-32 min-h-[40px] w-full flex-1 rounded-[20px] px-4 py-2.5 text-[13px]"
                disabled={sending}
                onChange={e => setDraft(e.target.value)}
                onKeyDown={e => {
                  if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                    e.preventDefault();
                    void send();
                  }
                }}
                placeholder="Write to the resident…"
                ref={inputRef}
                rows={1}
                style={{ resize: 'none' }}
                value={draft}
              />
              <button
                aria-label="Send message"
                className="flex size-10 shrink-0 items-center justify-center rounded-full transition-opacity hover:opacity-90 disabled:opacity-40"
                disabled={!draft.trim() || sending}
                onClick={() => void send()}
                style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
                type="button"
              >
                <Send className="size-4" />
              </button>
            </div>
            <p className="mt-2 text-[11px] leading-snug text-[var(--color-text-muted)]">
              {canRequestClarification
                ? 'Sent to the resident’s phone as a question. The report waits for their answer before you decide.'
                : 'Sent to the resident’s phone. Press Enter to send, Shift+Enter for a new line.'}
            </p>
          </div>
        ) : (
          <div className="shrink-0 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3 text-[12px] text-[var(--color-text-muted)]">
            You can read this conversation. Only the agency handling the report can write in it.
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}
