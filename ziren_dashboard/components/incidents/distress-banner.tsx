'use client';

import { Phone, ShieldAlert, X } from 'lucide-react';
import { useCallback, useEffect, useState } from 'react';

import {
  clearDistress,
  fetchOpenDistress,
  type DistressSignal,
} from '@/lib/api/dispatch';

/** How often to re-check. Short, because of what this is. */
const POLL_MS = 15_000;

/**
 * A responder's own emergency, on the dispatcher's console.
 *
 * WHY THIS EXISTS. Every safety affordance in this product points at
 * residents. The people who walk into the burning building and the armed
 * domestic dispute have had none — on a device that is already a
 * location-aware panic button for everybody else.
 *
 * WHY IT IS A FIXED BAR AND NOT A TOAST. A toast is dismissible, transient,
 * and stacks with everything else the console says. This is the only condition
 * in the whole product where a member of staff is in danger, and it stays on
 * screen until somebody clears it deliberately. It is allowed to be the
 * loudest thing here because nothing else on this console outranks it.
 *
 * WHY ONLY A DISPATCHER CAN CLEAR IT. Not the responder, and never a timeout.
 * A distress signal that ages out on its own is a distress signal nobody
 * answered — and the responder is the one person who may be in no position to
 * close it.
 */
export function DistressBanner({ token }: { token: string | null }) {
  const [signals, setSignals] = useState<DistressSignal[]>([]);
  const [clearing, setClearing] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!token) return;
    try {
      setSignals(await fetchOpenDistress(token));
    } catch {
      // Silent. A failure to load distress signals must not put an error
      // banner where the distress banner goes — the dispatcher would learn
      // nothing and lose the space. The next poll tries again.
    }
  }, [token]);

  useEffect(() => {
    void load();
    const id = setInterval(() => void load(), POLL_MS);
    return () => clearInterval(id);
  }, [load]);

  const onClear = async (id: string) => {
    if (!token) return;
    setClearing(id);
    try {
      await clearDistress(token, id);
      setSignals(prev => prev.filter(s => s.id !== id));
    } catch {
      // Leave it on screen. A clear that failed must not look like one that
      // worked, or a signal nobody actually answered disappears.
    } finally {
      setClearing(null);
    }
  };

  if (signals.length === 0) return null;

  return (
    <div className="flex flex-col gap-2">
      {signals.map(signal => (
        <div
          key={signal.id}
          role="alert"
          className="flex flex-wrap items-center gap-3 rounded-[var(--radius-card)] px-4 py-3"
          style={{
            // One of the very few places outside critical severity that earns
            // this red. A responder in danger is the same order of emergency
            // as the incidents this console exists to triage.
            backgroundColor: 'var(--color-severity-critical, #dc2626)',
            color: '#ffffff',
          }}
        >
          <ShieldAlert className="shrink-0" size={20} />

          <div className="min-w-0 flex-1">
            <p className="text-sm font-extrabold uppercase tracking-wide">
              {signal.kind === 'panic'
                ? 'Responder distress signal'
                : 'Responder has not moved'}
            </p>
            <p className="text-sm">
              {signal.responder_name ?? 'Unknown responder'}
              {signal.responder_badge ? ` (${signal.responder_badge})` : ''}
              {' · '}
              {new Date(signal.raised_at).toLocaleTimeString([], {
                hour: '2-digit',
                minute: '2-digit',
              })}
              {signal.latitude !== null && signal.longitude !== null ? (
                <>
                  {' · '}
                  <span className="font-mono tabular-nums">
                    {signal.latitude.toFixed(5)}, {signal.longitude.toFixed(5)}
                  </span>
                </>
              ) : (
                // Said out loud rather than left blank. The backend accepts a
                // signal with no fix on purpose — refusing one because the GPS
                // had not settled would be the worst possible failure — so a
                // missing location is expected, and the dispatcher needs to
                // know to ask where they are rather than assume the map knows.
                <> · no location — ask on the radio</>
              )}
            </p>
            {signal.note && <p className="text-sm italic">“{signal.note}”</p>}
          </div>

          {signal.responder_phone && (
            <a
              href={`tel:${signal.responder_phone}`}
              className="flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-bold"
              style={{ backgroundColor: 'rgba(255,255,255,0.20)' }}
            >
              <Phone size={14} />
              Call
            </a>
          )}

          {/*
            "Answered", not "Dismiss". The word is the guard: a button labelled
            dismiss invites tidying the bar away, and this one is a claim that
            somebody made contact.
          */}
          <button
            type="button"
            onClick={() => void onClear(signal.id)}
            disabled={clearing === signal.id}
            className="flex shrink-0 items-center gap-1.5 rounded-md px-3 py-1.5 text-sm font-bold disabled:opacity-50"
            style={{ backgroundColor: 'rgba(255,255,255,0.20)' }}
          >
            <X size={14} />
            {clearing === signal.id ? 'Clearing…' : 'Answered'}
          </button>
        </div>
      ))}
    </div>
  );
}
