'use client';

/**
 * The assist-request alert: another station has asked this one for help.
 *
 * Bottom-right, on every page, over everything but the incident alert. The
 * incident alert owns the top right and the centre of the screen; putting
 * this one in the other corner means a station that is asked for help in the
 * middle of its own emergency sees both, and neither covers the other.
 *
 * A request card stays until it is opened or put off ("Later"), and the
 * alarm loops while it is up (see useAssistInbox). "Later" is not "no": the
 * request stays in Assist Requests and in the sidebar badge until answered.
 * Response and message cards are quieter — one chime — and clear themselves.
 */

import { useRouter } from 'next/navigation';
import { AnimatePresence, motion } from 'framer-motion';
import { ArrowRight, Handshake, MapPin, MessageSquare, X } from 'lucide-react';
import { counterpart } from '@/lib/api/assist-requests';
import type { AssistAlert } from '@/lib/hooks/useAssistInbox';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { AG_COLOR, AGENCY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import { ASSIST_STATUS, ASSIST_TINT, ASSIST_TINT_BG, ago } from './assist-vocabulary';

export function AssistAlerts({
  alerts,
  onDismiss,
  onOpen,
}: {
  alerts: AssistAlert[];
  onDismiss: (key: string) => void;
  /** Called with the request id; the caller marks it read. */
  onOpen: (requestId: string) => void;
}) {
  const router = useRouter();
  // Requests first (they need an answer), newest last within each kind, and
  // never more than three cards: past that the stack covers the page it is
  // meant to sit beside. The rest are one click away in Assist Requests.
  const ordered = [...alerts].sort((a, b) =>
    Number(b.kind === 'request') - Number(a.kind === 'request') || a.at - b.at,
  );
  const shown = ordered.slice(0, 3);
  const hidden = ordered.length - shown.length;

  function open(requestId: string) {
    onOpen(requestId);
    router.push(`/assist-requests?id=${requestId}`);
  }

  return (
    <div
      aria-live="assertive"
      className="pointer-events-none fixed bottom-4 right-4 z-[1900] flex w-[380px] max-w-[calc(100vw-2rem)] flex-col gap-3"
    >
      <AnimatePresence initial={false}>
        {shown.map(a => (
          <motion.div
            animate={{ opacity: 1, y: 0, scale: 1 }}
            className="pointer-events-auto"
            exit={{ opacity: 0, x: 40, transition: { duration: 0.18 } }}
            initial={{ opacity: 0, y: 24, scale: 0.97 }}
            key={a.key}
            layout
            transition={{ type: 'spring', stiffness: 380, damping: 30 }}
          >
            {a.kind === 'request'
              ? <RequestCard alert={a} onLater={() => onDismiss(a.key)} onOpen={() => open(a.request.id)} />
              : <SoftCard alert={a} onClose={() => onDismiss(a.key)} onOpen={() => open(a.request.id)} />}
          </motion.div>
        ))}
      </AnimatePresence>
      {hidden > 0 && (
        <button
          className="pointer-events-auto self-end rounded-full border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3 py-1.5 text-[12px] font-semibold text-foreground shadow-[var(--shadow-card)]"
          onClick={() => router.push('/assist-requests')}
          type="button"
        >
          +{hidden} more in Assist Requests
        </button>
      )}
    </div>
  );
}

function RequestCard({ alert, onLater, onOpen }: { alert: AssistAlert; onLater: () => void; onOpen: () => void }) {
  const r = alert.request;
  const from = counterpart(r);
  const AgIcon = from.type ? AGENCY_ICON[from.type] : undefined;
  const SevIcon = r.severity ? SEV_ICON[r.severity] : undefined;
  const sevColor = r.severity ? SEV_COLOR[r.severity] : 'var(--color-text-tertiary)';
  const category = r.incident_category ? CATEGORY_LABELS[r.incident_category] ?? r.incident_category : 'Incident';

  return (
    <div
      aria-label={`${from.name ?? 'Another station'} is asking for your help`}
      className="overflow-hidden rounded-2xl border bg-[var(--color-surface-card)] shadow-[var(--shadow-modal)]"
      role="alertdialog"
      style={{ borderColor: `color-mix(in srgb, ${ASSIST_TINT} 45%, var(--color-surface-border))` }}
    >
      <div className="flex items-center gap-2 px-4 py-2 text-[11px] font-bold uppercase tracking-[0.08em]" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>
        <span className="relative flex size-2">
          <span className="absolute inline-flex size-full animate-ping rounded-full opacity-75" style={{ backgroundColor: ASSIST_TINT }} />
          <span className="relative inline-flex size-2 rounded-full" style={{ backgroundColor: ASSIST_TINT }} />
        </span>
        Help requested
        <span className="ml-auto font-semibold normal-case tracking-normal opacity-80">{ago(r.created_at)}</span>
      </div>

      <div className="px-4 pb-4 pt-3">
        <div className="flex items-start gap-3">
          <span
            aria-hidden="true"
            className="flex size-10 shrink-0 items-center justify-center rounded-xl"
            style={{ backgroundColor: `color-mix(in srgb, ${from.type ? AG_COLOR[from.type] : ASSIST_TINT} 14%, transparent)`, color: from.type ? AG_COLOR[from.type] : ASSIST_TINT }}
          >
            {AgIcon ? <AgIcon className="size-5" /> : <Handshake className="size-5" />}
          </span>
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-bold leading-snug text-foreground">
              {from.name ?? 'Another station'} is asking for your help
            </p>
            <p className="mt-0.5 text-[12.5px] text-muted-foreground">
              {[from.type, from.municipality].filter(Boolean).join(' · ') || 'Cross-agency request'}
            </p>
          </div>
        </div>

        <div className="mt-3 rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-3">
          <p className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[12.5px] font-semibold text-foreground">
            {SevIcon && (
              <span className="inline-flex items-center gap-1" style={{ color: sevColor }}>
                <SevIcon aria-hidden="true" className="size-3.5" />
                {r.severity ? r.severity[0].toUpperCase() + r.severity.slice(1) : ''}
              </span>
            )}
            <span>{category}</span>
          </p>
          {r.location_address && (
            <p className="mt-1 flex items-start gap-1.5 text-[12.5px] text-[var(--color-text-secondary)]">
              <MapPin aria-hidden="true" className="mt-0.5 size-3.5 shrink-0" />
              <span className="line-clamp-2">{r.location_address}</span>
            </p>
          )}
          {r.last_message_preview && (
            <p className="mt-2 line-clamp-3 border-l-2 pl-2.5 text-[13px] leading-snug text-foreground" style={{ borderColor: ASSIST_TINT }}>
              {r.last_message_preview}
            </p>
          )}
        </div>

        <div className="mt-3 grid grid-cols-[auto_1fr] gap-2">
          <button
            className="h-11 rounded-xl border border-[var(--color-surface-border)] px-4 text-[13.5px] font-semibold text-foreground transition-colors hover:bg-[var(--color-surface-hover)]"
            onClick={onLater}
            type="button"
          >
            Later
          </button>
          <button
            className="flex h-11 items-center justify-center gap-2 rounded-xl bg-[var(--color-brand)] px-4 text-[13.5px] font-bold text-white shadow-sm transition-[filter] hover:brightness-110"
            onClick={onOpen}
            type="button"
          >
            Open request <ArrowRight aria-hidden="true" className="size-4" />
          </button>
        </div>
      </div>
    </div>
  );
}

function SoftCard({ alert, onClose, onOpen }: { alert: AssistAlert; onClose: () => void; onOpen: () => void }) {
  const r = alert.request;
  const other = counterpart(r).name ?? 'The other station';
  const st = ASSIST_STATUS[r.status];
  const isMessage = alert.kind === 'message';
  const Icon = isMessage ? MessageSquare : st.icon;
  const color = isMessage ? ASSIST_TINT : st.fg;
  const title = isMessage
    ? `New message from ${other}`
    : r.status === 'acknowledged' ? `${other} is responding` : `${other} can’t assist`;
  const body = isMessage
    ? r.last_message_preview
    : r.status === 'acknowledged'
      ? 'They accepted your request for help.'
      : 'They declined. You can ask another station from the incident.';

  return (
    <div className="flex items-start gap-3 rounded-2xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-3.5 shadow-[var(--shadow-modal)]" role="status">
      <span
        aria-hidden="true"
        className="flex size-9 shrink-0 items-center justify-center rounded-xl"
        style={{ backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)`, color }}
      >
        <Icon className="size-[18px]" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[13.5px] font-bold leading-snug text-foreground">{title}</p>
        {body && <p className="mt-0.5 line-clamp-2 text-[12.5px] text-muted-foreground">{body}</p>}
        <button
          className="mt-2 inline-flex items-center gap-1 text-[12.5px] font-bold text-[var(--color-brand)] hover:underline"
          onClick={onOpen}
          type="button"
        >
          View conversation <ArrowRight aria-hidden="true" className="size-3.5" />
        </button>
      </div>
      <button
        aria-label="Dismiss"
        className="-mr-1 -mt-1 flex size-7 shrink-0 items-center justify-center rounded-lg text-muted-foreground hover:bg-[var(--color-surface-hover)] hover:text-foreground"
        onClick={onClose}
        type="button"
      >
        <X aria-hidden="true" className="size-4" />
      </button>
    </div>
  );
}
