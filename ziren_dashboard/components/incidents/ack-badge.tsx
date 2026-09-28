'use client';

import { AlertOctagon, Check, Timer, Undo2 } from 'lucide-react';
import { useEffect, useState } from 'react';

import {
  DECLINE_REASON_LABEL,
  type AckState,
} from '@/lib/api/dispatch';

/**
 * Has the assigned crew answered?
 *
 * THE HOLE THIS FILLS. `status: 'dispatched'` has only ever meant "a
 * dispatcher pressed a button". Whether a responder ever SAW the assignment
 * was unrepresented anywhere, so a row on this board looked exactly the same
 * whether a truck was rolling or the handset was face-down in a locker — and
 * the difference only became visible when nobody arrived.
 *
 * WHAT IT DOES NOT DO. It does not reassign anything. An overdue incident
 * becomes loud here and a human decides what happens next. A system that
 * silently reassigns a life-safety call can stand two crews down without
 * either of them knowing, and there is nobody left who can see that happened.
 * The rule the whole feature is built on:
 *
 *     The system never silently reassigns a life-safety call.
 *     It makes the silence impossible to miss.
 *
 * THE COUNTDOWN IS TICKED LOCALLY, NOT COMPUTED LOCALLY. The verdict and the
 * deadline both come from the server (responder_ack.py), because the
 * responder's phone is deriving the same answer from the same columns at the
 * same moment. Two implementations means a board showing OVERDUE beside a
 * phone still counting down, and then the dispatcher and the crew are arguing
 * about the clock instead of the fire. All this does is decrement between
 * polls, anchored to the number the server sent.
 */
export function AckBadge({ ack }: { ack?: AckState | null }) {
  const serverRemaining = ack?.seconds_remaining ?? null;
  const [remaining, setRemaining] = useState<number | null>(serverRemaining);

  // Re-anchor whenever the poll brings a fresh number. Without this the local
  // countdown drifts away from the server's and never comes back.
  useEffect(() => {
    setRemaining(serverRemaining);
  }, [serverRemaining]);

  const counting = ack?.state === 'pending' && remaining !== null;

  useEffect(() => {
    if (!counting) return;
    const id = setInterval(() => {
      setRemaining(prev => (prev === null ? null : Math.max(prev - 1, 0)));
    }, 1000);
    return () => clearInterval(id);
  }, [counting]);

  if (!ack || ack.state === 'not_applicable') return null;

  if (ack.state === 'accepted') {
    return (
      <span
        className="flex items-center gap-1.5"
        style={{ color: 'var(--color-system-success, #16a34a)' }}
      >
        <Check className="shrink-0" size={12} />
        Accepted by crew
      </span>
    );
  }

  if (ack.state === 'declined') {
    const reason = ack.declined_reason
      ? DECLINE_REASON_LABEL[ack.declined_reason]
      : 'No reason given';
    return (
      <span
        className="flex items-center gap-1.5 font-semibold"
        style={{ color: 'var(--color-system-warning, #d97706)' }}
      >
        <Undo2 className="shrink-0" size={12} />
        Handed back — {reason}
        {ack.decline_count > 1 && (
          <span className="font-mono tabular-nums opacity-80">
            ×{ack.decline_count}
          </span>
        )}
      </span>
    );
  }

  const overdue = ack.state === 'overdue' || remaining === 0;
  const label = overdue
    ? 'NO ANSWER FROM CREW'
    : `Awaiting answer · ${formatCountdown(remaining ?? 0)}`;

  return (
    <span className="flex min-w-0 items-center gap-1.5">
      <span
        className="flex items-center gap-1.5 font-semibold"
        style={{
          // Red only when the window has actually elapsed. Red is reserved for
          // critical severity across this console, and spending it on a
          // fifteen-second-old assignment that is still perfectly on time
          // would blunt the one place it has to mean something.
          color: overdue
            ? 'var(--color-severity-critical, #dc2626)'
            : 'var(--color-system-warning, #d97706)',
        }}
      >
        {overdue ? (
          <AlertOctagon className="shrink-0" size={12} />
        ) : (
          <Timer className="shrink-0" size={12} />
        )}
        {label}
      </span>

      {/* Three refusals on one incident is not a responder problem, it is a
          coverage problem, and it should be visible as one. */}
      {ack.decline_count > 0 && (
        <span
          className="shrink-0 rounded px-1 text-[10px] font-bold"
          style={{
            backgroundColor: 'var(--color-surface-raised, #f4f4f5)',
            color: 'var(--color-text-muted)',
          }}
          title={`Refused ${ack.decline_count} time(s) before this assignment`}
        >
          {ack.decline_count}× refused
        </span>
      )}
    </span>
  );
}

function formatCountdown(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

/**
 * Whether this row should pull the dispatcher's eye.
 *
 * Exported so the row can raise its border without duplicating the rule — the
 * one thing worse than an invisible unanswered assignment is two components
 * disagreeing about which assignments are unanswered.
 */
export function isAckOverdue(ack?: AckState | null): boolean {
  return ack?.state === 'overdue' || ack?.state === 'declined';
}
