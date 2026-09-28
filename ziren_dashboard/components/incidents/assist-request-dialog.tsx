'use client';

/**
 * "Request assist" — compose a new cross-agency assist request from inside
 * the incident detail modal. Not one of dispatch-action-modals.tsx's
 * siblings on purpose: this one fetches its own candidate list and has a
 * compose step, not a single confirm action, so it gets its own file.
 *
 * Uses the triggerRef + onCloseAutoFocus/onOpenAutoFocus pattern
 * option-dialog.tsx established this session (Radix's own "restore
 * previous focus" does not reliably land back on a plain button that
 * isn't a <Dialog.Trigger>) rather than this file's older sibling modals'
 * simpler pattern, since this dialog is also reused from the Agencies tab
 * where that convention is already the norm.
 */

import { useEffect, useState } from 'react';
import { Check, Send, X } from 'lucide-react';
import {
  Dialog, DialogClose, DialogContent, DialogDescription, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  createAssistRequest, fetchAssistCandidates, type AssistCandidate,
} from '@/lib/api/assist-requests';
import { AG_COLOR, AGENCY_ICON } from '@/components/incidents/incident-vocabulary';
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
  onSuccess: () => void;
  onError: (m: string) => void;
}) {
  const [candidates, setCandidates] = useState<AssistCandidate[] | null>(null);
  const [target, setTarget] = useState<string | null>(null);
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);

  useEffect(() => {
    let live = true;
    fetchAssistCandidates(incidentId, token)
      .then(list => {
        if (!live) return;
        setCandidates(list);
        const suggestedType = overlapFlags.map(f => OVERLAP_TO_AGENCY_TYPE[f]).find(Boolean);
        const suggested = suggestedType ? list.find(a => a.agency_type === suggestedType) : undefined;
        setTarget((suggested ?? list[0])?.id ?? null);
      })
      .catch((e: unknown) => onError(e instanceof Error ? e.message : 'Could not load nearby agencies.'));
    return () => { live = false; };
    // overlapFlags/onError are stable for the dialog's lifetime (a fresh
    // instance mounts per open) — only re-fetch if the incident changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [incidentId, token]);

  const usedFlag = overlapFlags.find(f => OVERLAP_TO_AGENCY_TYPE[f] === candidates?.find(a => a.id === target)?.agency_type) ?? null;

  async function send() {
    if (!target || !message.trim()) return;
    setSending(true);
    try {
      await createAssistRequest(incidentId, target, message.trim(), usedFlag, token);
      onSuccess();
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Could not send the request.');
    } finally {
      setSending(false);
    }
  }

  return (
    <Dialog onOpenChange={open => { if (!open && !sending) onClose(); }} open>
      <DialogContent
        className="flex max-h-[calc(100dvh-2rem)] flex-col gap-0 overflow-hidden p-0 sm:max-w-[440px]"
        onCloseAutoFocus={e => { e.preventDefault(); triggerRef.current?.focus(); }}
        onOpenAutoFocus={e => { e.preventDefault(); (e.target as HTMLElement).querySelector('textarea')?.focus(); }}
        showCloseButton={false}
      >
        <div className="flex items-start gap-3 px-5 pb-3 pt-5">
          <div className="min-w-0 flex-1">
            <DialogTitle className="text-[16px] font-bold leading-tight tracking-tight text-foreground">Request assist</DialogTitle>
            <DialogDescription className="mt-1 text-[13px] leading-snug">
              Ask another agency present in this area for help on this incident.
            </DialogDescription>
          </div>
          <DialogClose aria-label="Close" className="-mr-1 -mt-1 flex size-8 shrink-0 items-center justify-center rounded-lg text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground">
            <X aria-hidden="true" className="size-4" />
          </DialogClose>
        </div>

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 pb-5">
          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Agency</p>
            {candidates === null ? (
              <p className="text-[13px] text-muted-foreground">Loading…</p>
            ) : candidates.length === 0 ? (
              <p className="text-[13px] text-muted-foreground">No other active agency is registered in this incident&apos;s municipality.</p>
            ) : (
              <div className="flex flex-col gap-1.5" role="radiogroup">
                {candidates.map(a => {
                  const Icon = AGENCY_ICON[a.agency_type];
                  const active = target === a.id;
                  return (
                    <button
                      aria-checked={active}
                      className={cn(
                        'flex w-full items-center gap-3 rounded-xl border px-3.5 py-2.5 text-left transition-colors',
                        active
                          ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
                          : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] hover:bg-[var(--color-surface-hover)]',
                      )}
                      key={a.id}
                      onClick={() => setTarget(a.id)}
                      role="radio"
                      type="button"
                    >
                      {Icon && (
                        <span
                          aria-hidden="true"
                          className="flex size-8 shrink-0 items-center justify-center rounded-lg"
                          style={{ backgroundColor: `color-mix(in srgb, ${AG_COLOR[a.agency_type]} 14%, transparent)`, color: AG_COLOR[a.agency_type] }}
                        >
                          <Icon className="size-4" />
                        </span>
                      )}
                      <span className="min-w-0 flex-1 text-[14px] font-semibold text-foreground">{a.name}</span>
                      {active && <Check aria-hidden="true" className="size-4 shrink-0 text-[var(--color-brand)]" />}
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          <div>
            <p className="mb-1.5 text-[11px] font-bold uppercase tracking-wide text-muted-foreground">Message</p>
            <textarea
              className="w-full resize-none rounded-lg border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-2 text-[13px]"
              onChange={e => setMessage(e.target.value)}
              placeholder="What do you need from them? e.g. Crowd control at the north entrance."
              rows={3}
              value={message}
            />
          </div>
        </div>

        <div className="flex justify-end gap-2 border-t border-[var(--color-surface-border)] px-5 py-3">
          <button
            className="rounded-lg px-3.5 py-2 text-[13px] font-semibold text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
            onClick={onClose}
            type="button"
          >
            Cancel
          </button>
          <button
            className="flex items-center gap-1.5 rounded-lg bg-[var(--color-brand)] px-4 py-2 text-[13px] font-semibold text-white transition-opacity hover:opacity-90 disabled:opacity-50"
            disabled={sending || !target || !message.trim()}
            onClick={() => void send()}
            type="button"
          >
            <Send aria-hidden="true" className="size-4" /> Send request
          </button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
