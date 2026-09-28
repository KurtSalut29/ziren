'use client';

/**
 * The chat for one cross-agency assist request — snapshot header, message
 * thread, compose box, and (only for the requested agency, only while
 * pending) Acknowledge/Decline. Shared by the incident detail modal (the
 * requesting side) and the Agencies tab's Assist requests panel (both
 * sides — the receiving agency never gets incident access, so this panel
 * is the only place their half of the thread exists). See
 * docs/superpowers/specs/2026-09-20-cross-agency-assist-requests-design.md.
 */

import { useEffect, useRef, useState } from 'react';
import { Check, Send, X } from 'lucide-react';
import { useAssistThread } from '@/lib/hooks/useAssistThread';
import { postAssistMessage, setAssistStatus, type AssistMessage, type AssistStatus } from '@/lib/api/assist-requests';
import { CATEGORY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { cn } from '@/lib/utils';

export function AssistThreadPanel({
  requestId,
  token,
  onStatusChange,
  className,
  readOnly = false,
}: {
  requestId: string;
  token: string;
  onStatusChange?: () => void;
  className?: string;
  /** provincial_admin oversight: hide the compose box. Ack/Decline already
   *  never render for that role — request.can_respond is server-computed
   *  and always false for it (see assist_request_service._hydrate_request). */
  readOnly?: boolean;
}) {
  const { thread, loading, error, refresh } = useAssistThread(requestId, token);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [responding, setResponding] = useState(false);
  const scrollEnd = useRef<HTMLDivElement>(null);

  useEffect(() => {
    scrollEnd.current?.scrollIntoView({ block: 'end' });
  }, [thread?.messages.length]);

  if (loading && !thread) {
    return <div className={cn('p-5 text-[13px] text-muted-foreground', className)}>Loading conversation…</div>;
  }
  if (error && !thread) {
    return <div className={cn('p-5 text-[13px] text-[var(--color-system-warning)]', className)}>{error}</div>;
  }
  if (!thread) return null;

  const { request, messages } = thread;
  const closed = request.incident_status === 'resolved' || request.incident_status === 'cancelled';
  const SevIcon = request.severity ? SEV_ICON[request.severity] : undefined;
  const CategoryIcon = request.incident_category ? CATEGORY_ICON[request.incident_category] : undefined;
  const tint = request.severity ? SEV_COLOR[request.severity] : 'var(--color-text-tertiary)';

  async function send() {
    if (!draft.trim() || closed) return;
    setSending(true);
    try {
      await postAssistMessage(requestId, draft.trim(), token);
      setDraft('');
      refresh();
    } finally {
      setSending(false);
    }
  }

  async function respond(newStatus: 'acknowledged' | 'declined') {
    setResponding(true);
    try {
      await setAssistStatus(requestId, newStatus, token);
      refresh();
      onStatusChange?.();
    } finally {
      setResponding(false);
    }
  }

  return (
    <div className={cn('flex min-h-0 flex-col', className)}>
      <div className="flex items-start gap-3 border-b border-[var(--color-surface-border)] px-4 py-3">
        <span
          aria-hidden="true"
          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
          style={{ backgroundColor: `color-mix(in srgb, ${tint} 14%, transparent)`, color: tint }}
        >
          {SevIcon ? <SevIcon className="size-4" /> : CategoryIcon ? <CategoryIcon className="size-4" /> : null}
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[13.5px] font-semibold text-foreground">
            {request.incident_category ? CATEGORY_LABELS[request.incident_category] ?? request.incident_category : 'Incident'}
            {request.location_address && <span className="font-normal text-muted-foreground"> · {request.location_address}</span>}
          </p>
          <p className="mt-0.5 text-[12px] text-muted-foreground">
            {request.requesting_agency_name} asked {request.requested_agency_name}
          </p>
        </div>
        <StatusPill status={request.status} />
      </div>

      {closed && (
        <p className="border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-2 text-[12px] text-muted-foreground">
          This incident has been resolved — this thread is read-only.
        </p>
      )}

      <div className="flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto px-4 py-3">
        {messages.map(m => <MessageBubble key={m.id} message={m} />)}
        <div ref={scrollEnd} />
      </div>

      {request.can_respond && (
        <div className="flex gap-2 border-t border-[var(--color-surface-border)] px-4 py-3">
          <button
            className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-[var(--color-system-success)] px-3 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={responding}
            onClick={() => void respond('acknowledged')}
            type="button"
          >
            <Check aria-hidden="true" className="size-4" /> We&apos;re responding
          </button>
          <button
            className="flex flex-1 items-center justify-center gap-1.5 rounded-lg border border-[var(--color-surface-border)] px-3 py-2 text-[13px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)] disabled:opacity-50"
            disabled={responding}
            onClick={() => void respond('declined')}
            type="button"
          >
            <X aria-hidden="true" className="size-4" /> Can&apos;t assist
          </button>
        </div>
      )}

      {!closed && !readOnly && (
        <div className="flex items-end gap-2 border-t border-[var(--color-surface-border)] px-4 py-3">
          <textarea
            className="max-h-24 min-h-9 flex-1 resize-none rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2 text-[13px]"
            disabled={sending}
            onChange={e => setDraft(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void send(); } }}
            placeholder="Write a message…"
            rows={1}
            value={draft}
          />
          <button
            aria-label="Send"
            className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-[var(--color-brand)] text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={sending || !draft.trim()}
            onClick={() => void send()}
            type="button"
          >
            <Send aria-hidden="true" className="size-4" />
          </button>
        </div>
      )}
    </div>
  );
}

function StatusPill({ status }: { status: AssistStatus }) {
  const style: Record<AssistStatus, { bg: string; fg: string; label: string }> = {
    pending:      { bg: 'var(--color-surface-raised)',    fg: 'var(--color-text-secondary)', label: 'Pending' },
    acknowledged: { bg: 'var(--color-system-success-bg)', fg: 'var(--color-system-success)', label: 'Responding' },
    declined:     { bg: 'var(--color-system-warning-bg)', fg: 'var(--color-system-warning)', label: 'Declined' },
  };
  const s = style[status];
  return (
    <span className="shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold uppercase tracking-wide" style={{ backgroundColor: s.bg, color: s.fg }}>
      {s.label}
    </span>
  );
}

function MessageBubble({ message }: { message: AssistMessage }) {
  return (
    <div className={cn('flex flex-col', message.mine ? 'items-end' : 'items-start')}>
      <div
        className={cn(
          'max-w-[80%] rounded-xl px-3 py-2 text-[13px] leading-snug',
          message.mine ? 'bg-[var(--color-brand)] text-white' : 'bg-[var(--color-surface-raised)] text-foreground',
        )}
      >
        {message.body}
      </div>
      <span className="mt-0.5 px-1 text-[11px] text-muted-foreground">
        {message.sender_name ?? 'Someone'} · {new Date(message.created_at).toLocaleTimeString('en-PH', { hour: 'numeric', minute: '2-digit' })}
      </span>
    </div>
  );
}
