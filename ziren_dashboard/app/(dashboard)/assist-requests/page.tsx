'use client';

/**
 * Assist Requests — every request for help between this station and the
 * others in the province, and the conversation behind each one.
 *
 * Replaces the panel that used to sit at the top of Operational Area's
 * Agencies tab. Stations testing that version could not find it, and once
 * they did, could not tell which requests were asking THEM, which were
 * theirs, and which still needed an answer. So this is its own page with its
 * own sidebar entry (badged while something needs a look), an inbox that
 * leads with "needs your answer", and the full conversation beside it.
 *
 * The list comes from the layout's shared inbox (see useAssistInbox), which
 * polls every ten seconds for the alert anyway; this page does not poll a
 * second copy.
 */

import { Suspense, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  ArrowDownLeft, ArrowUpRight, ChevronLeft, Handshake, Inbox, MessageSquare, Search,
} from 'lucide-react';
import { useAuth } from '@/lib/hooks/useAuth';
import { counterpart, type AssistRequestSummary } from '@/lib/api/assist-requests';
import { useAssistInboxContext } from '@/components/assist/assist-context';
import { AssistConversation } from '@/components/assist/assist-conversation';
import { ASSIST_STATUS, ASSIST_TINT, ASSIST_TINT_BG, ago } from '@/components/assist/assist-vocabulary';
import { AG_COLOR, AGENCY_ICON, SEV_COLOR, SEV_ICON } from '@/components/incidents/incident-vocabulary';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { cn } from '@/lib/utils';

import { DemoTarget } from '@/components/help/demo-target';
type Box = 'attention' | 'incoming' | 'outgoing' | 'all';

export default function AssistRequestsPage() {
  return (
    <Suspense fallback={null}>
      <AssistRequestsView />
    </Suspense>
  );
}

function AssistRequestsView() {
  const { token, isProvincialAdmin } = useAuth();
  const inbox = useAssistInboxContext();
  const router = useRouter();
  const params = useSearchParams();
  const selectedId = params.get('id');
  const [box, setBox] = useState<Box>(isProvincialAdmin ? 'all' : 'attention');
  const [query, setQuery] = useState('');
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), 30_000);
    return () => window.clearInterval(t);
  }, []);

  const items = inbox?.items ?? [];
  const needsLook = (r: AssistRequestSummary) =>
    (r.direction === 'incoming' && r.status === 'pending') || Boolean(inbox?.isUnread(r));

  const counts = useMemo(() => ({
    attention: items.filter(needsLook).length,
    incoming: items.filter(r => r.direction === 'incoming').length,
    outgoing: items.filter(r => r.direction === 'outgoing').length,
    all: items.length,
  // needsLook reads inbox.isUnread, which changes with the inbox itself.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [items, inbox]);

  // Land on "All" when nothing needs a look, rather than an empty first tab.
  useEffect(() => {
    if (inbox?.loaded && box === 'attention' && counts.attention === 0 && counts.all > 0) setBox('all');
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [inbox?.loaded]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items
      // The open request stays in the list even once reading it drops it out of
      // "Needs attention" — a row vanishing under the cursor reads as an error.
      .filter(r => r.id === selectedId || box === 'all' || (box === 'attention' ? needsLook(r) : r.direction === box))
      .filter(r => !q || [
        r.requesting_agency_name, r.requested_agency_name, r.location_address, r.record_number,
        r.incident_category ? CATEGORY_LABELS[r.incident_category] : null, r.last_message_preview,
      ].some(v => v?.toLowerCase().includes(q)))
      .sort((a, b) =>
        Number(needsLook(b)) - Number(needsLook(a))
        || (b.last_message_at ?? b.created_at).localeCompare(a.last_message_at ?? a.created_at));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items, box, query, inbox, selectedId]);

  const selected = items.find(r => r.id === selectedId) ?? null;

  function select(id: string | null) {
    router.replace(id ? `/assist-requests?id=${id}` : '/assist-requests', { scroll: false });
  }

  const tabs: { key: Box; label: string; icon: typeof Inbox; hide?: boolean }[] = [
    { key: 'attention', label: 'Needs attention', icon: Inbox, hide: isProvincialAdmin },
    { key: 'incoming', label: 'Asked of us', icon: ArrowDownLeft, hide: isProvincialAdmin },
    { key: 'outgoing', label: 'We asked', icon: ArrowUpRight, hide: isProvincialAdmin },
    { key: 'all', label: 'All', icon: Handshake },
  ];

  return (
    <div className="flex h-full min-h-0 flex-col gap-4 px-4 py-4 md:px-7 md:py-5">
      {/* The three-step explainer only while nothing is open: with a request
          on screen, its answer buttons need that height more. */}
      {!selectedId && <DemoTarget id="assist:how"><HowItWorks isProvincialAdmin={isProvincialAdmin} /></DemoTarget>}

      <div className="grid min-h-[560px] flex-1 grid-cols-1 overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] lg:grid-cols-[380px_1fr]">
        {/* ── Inbox ─────────────────────────────────────────────────── */}
        <aside data-demo="assist:inbox" className={cn('flex min-h-0 flex-col border-[var(--color-surface-border)] lg:border-r', selected && 'hidden lg:flex')}>
          <div className="flex flex-col gap-3 border-b border-[var(--color-surface-border)] p-3">
            <div data-demo="assist:tabs" className="grid grid-cols-2 gap-1 rounded-xl bg-[var(--color-surface-raised)] p-1">
              {tabs.filter(t => !t.hide).map(t => (
                <button
                  aria-pressed={box === t.key}
                  className={cn(
                    'flex items-center justify-center gap-1.5 rounded-lg px-2 py-1.5 text-[12px] font-semibold transition-colors',
                    box === t.key ? 'bg-[var(--color-surface-card)] text-foreground shadow-sm' : 'text-muted-foreground hover:text-foreground',
                  )}
                  key={t.key}
                  onClick={() => setBox(t.key)}
                  type="button"
                >
                  <t.icon aria-hidden="true" className="size-3.5 shrink-0" />
                  <span className="truncate">{t.label}</span>
                  {counts[t.key] > 0 && (
                    <span
                      className={cn('rounded-full px-1.5 text-[10.5px] font-bold tabular-nums', t.key === 'attention' ? 'text-white' : 'bg-[var(--color-surface-raised)] text-muted-foreground')}
                      style={t.key === 'attention' ? { backgroundColor: 'var(--color-brand)' } : undefined}
                    >
                      {counts[t.key]}
                    </span>
                  )}
                </button>
              ))}
            </div>
            <label data-demo="assist:search" className="relative block">
              <Search aria-hidden="true" className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <input
                className="h-9 w-full rounded-xl border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] pl-9 pr-3 text-[13px] focus:border-[var(--color-brand)] focus:outline-none"
                onChange={e => setQuery(e.target.value)}
                placeholder="Search station, place, record no."
                type="search"
                value={query}
              />
            </label>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto">
            {!inbox?.loaded ? (
              <div className="flex flex-col gap-2 p-3">
                {Array.from({ length: 4 }).map((_, i) => <div className="h-[84px] animate-pulse rounded-xl bg-[var(--color-surface-raised)]" key={i} />)}
              </div>
            ) : inbox.error && !items.length ? (
              <p className="p-5 text-[13px] text-[var(--color-system-error)]">{inbox.error}</p>
            ) : visible.length === 0 ? (
              <EmptyBox box={box} filtered={Boolean(query.trim())} />
            ) : (
              <ul className="flex flex-col gap-1.5 p-2">
                {visible.map(r => (
                  <li key={r.id}>
                    <InboxRow
                      active={r.id === selectedId}
                      needsAnswer={r.direction === 'incoming' && r.status === 'pending'}
                      now={now}
                      onClick={() => select(r.id)}
                      request={r}
                      unread={Boolean(inbox.isUnread(r))}
                    />
                  </li>
                ))}
              </ul>
            )}
          </div>
        </aside>

        {/* ── Conversation ──────────────────────────────────────────── */}
        <section data-demo="assist:conversation" className={cn('flex min-h-0 flex-col', !selected && 'hidden lg:flex')}>
          {selected && token ? (
            <>
              <button
                className="flex items-center gap-1 border-b border-[var(--color-surface-border)] px-4 py-2.5 text-[13px] font-semibold text-muted-foreground hover:text-foreground lg:hidden"
                onClick={() => select(null)}
                type="button"
              >
                <ChevronLeft aria-hidden="true" className="size-4" /> All requests
              </button>
              <AssistConversation
                className="min-h-0 flex-1"
                key={selected.id}
                onChanged={() => inbox?.refresh()}
                onSeen={id => inbox?.markRead(id)}
                readOnly={isProvincialAdmin}
                requestId={selected.id}
                token={token}
              />
            </>
          ) : selectedId && inbox?.loaded ? (
            <Placeholder
              body="It may belong to another station, or the link is out of date."
              title="That request is not in your list"
            />
          ) : (
            <Placeholder
              body={isProvincialAdmin
                ? 'Pick a request on the left to read the conversation between the two stations.'
                : 'Pick a request on the left. To ask another station for help, open the incident and press “Request help”.'}
              title="Select a request"
            />
          )}
        </section>
      </div>
    </div>
  );
}

function InboxRow({
  request: r, active, unread, needsAnswer, now, onClick,
}: {
  request: AssistRequestSummary;
  active: boolean;
  unread: boolean;
  needsAnswer: boolean;
  now: number;
  onClick: () => void;
}) {
  const other = counterpart(r);
  const st = ASSIST_STATUS[r.status];
  const AgIcon = other.type ? AGENCY_ICON[other.type] : undefined;
  const hue = other.type ? AG_COLOR[other.type] : ASSIST_TINT;
  const SevIcon = r.severity ? SEV_ICON[r.severity] : undefined;
  const incoming = r.direction === 'incoming';
  const label = r.direction === 'oversight'
    ? `${r.requesting_agency_name ?? '—'} → ${r.requested_agency_name ?? '—'}`
    : other.name ?? 'Another station';

  return (
    <button
      aria-current={active ? 'true' : undefined}
      className={cn(
        'group relative flex w-full gap-3 rounded-xl border p-3 text-left transition-colors',
        active
          ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]'
          : needsAnswer
            ? 'border-[color-mix(in_srgb,var(--color-system-warning)_45%,transparent)] bg-[var(--color-system-warning-bg)] hover:brightness-[0.98]'
            : 'border-transparent hover:bg-[var(--color-surface-hover)]',
      )}
      onClick={onClick}
      type="button"
    >
      <span
        aria-hidden="true"
        className="relative flex size-9 shrink-0 items-center justify-center rounded-xl"
        style={{ backgroundColor: `color-mix(in srgb, ${hue} 14%, transparent)`, color: hue }}
      >
        {AgIcon && <AgIcon className="size-4" />}
        {r.direction !== 'oversight' && (
          <span className="absolute -bottom-1 -right-1 flex size-4 items-center justify-center rounded-full border-2 border-[var(--color-surface-card)] text-white" style={{ backgroundColor: ASSIST_TINT }}>
            {incoming ? <ArrowDownLeft className="size-2.5" /> : <ArrowUpRight className="size-2.5" />}
          </span>
        )}
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2">
          <span className={cn('truncate text-[13.5px] text-foreground', unread || needsAnswer ? 'font-bold' : 'font-semibold')}>{label}</span>
          <span className="ml-auto shrink-0 text-[11px] text-muted-foreground">{ago(r.last_message_at ?? r.created_at, now)}</span>
        </span>
        <span className="mt-0.5 flex items-center gap-1.5 text-[12px] text-[var(--color-text-secondary)]">
          {SevIcon && r.severity && <SevIcon aria-label={r.severity} className="size-3.5 shrink-0" style={{ color: SEV_COLOR[r.severity] }} />}
          <span className="truncate">
            {r.incident_category ? CATEGORY_LABELS[r.incident_category] ?? r.incident_category : 'Incident'}
            {r.location_address ? ` · ${r.location_address}` : ''}
          </span>
        </span>
        {r.last_message_preview && (
          <span className={cn('mt-1 flex items-center gap-1.5 text-[12px]', unread ? 'font-semibold text-foreground' : 'text-muted-foreground')}>
            <MessageSquare aria-hidden="true" className="size-3 shrink-0" />
            <span className="truncate">{r.last_message_preview}</span>
          </span>
        )}
        <span className="mt-1.5 flex items-center gap-2">
          <span className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10.5px] font-bold" style={{ backgroundColor: st.bg, color: st.fg }}>
            <st.icon aria-hidden="true" className="size-3" />
            {needsAnswer ? 'Needs your answer' : incoming ? st.incoming : r.direction === 'outgoing' ? st.outgoing : st.label}
          </span>
          {unread && (
            <span className="inline-flex items-center gap-1 text-[10.5px] font-bold" style={{ color: 'var(--color-brand)' }}>
              <span className="size-1.5 rounded-full bg-[var(--color-brand)]" /> New message
            </span>
          )}
        </span>
      </span>
    </button>
  );
}

function EmptyBox({ box, filtered }: { box: Box; filtered: boolean }) {
  const text = filtered
    ? 'Nothing matches that search.'
    : box === 'attention'
      ? 'Nothing needs your attention. New requests and replies will show up here — and you will hear an alert.'
      : box === 'incoming'
        ? 'No station has asked you for help yet.'
        : box === 'outgoing'
          ? 'You have not asked another station for help yet. Open an incident and press “Request help”.'
          : 'No assist requests yet.';
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-14 text-center">
      <span className="flex size-12 items-center justify-center rounded-2xl" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>
        <Handshake aria-hidden="true" className="size-6" />
      </span>
      <p className="max-w-[260px] text-[13px] leading-relaxed text-muted-foreground">{text}</p>
    </div>
  );
}

function Placeholder({ title, body }: { title: string; body: string }) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-3 p-10 text-center">
      <span className="flex size-14 items-center justify-center rounded-2xl" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>
        <MessageSquare aria-hidden="true" className="size-7" />
      </span>
      <p className="text-[15px] font-bold text-foreground">{title}</p>
      <p className="max-w-[360px] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

function HowItWorks({ isProvincialAdmin }: { isProvincialAdmin: boolean }) {
  const steps = isProvincialAdmin
    ? [
        ['Stations ask', 'A station handling a report asks any other station in Biliran for help.'],
        ['The asked station answers', 'They accept or decline, and the two stations talk here.'],
        ['You oversee', 'You can read every request involving your agency. Only the stations reply.'],
      ]
    : [
        ['Ask', 'From any incident, press “Request help” and pick one or more stations anywhere in Biliran.'],
        ['They are alerted', 'The station you ask hears an alert and sees what happened and where. The report stays with you.'],
        ['Talk it through', 'They accept or decline, and both stations message each other right here.'],
      ];
  return (
    <ol className="grid grid-cols-1 gap-2 md:grid-cols-3">
      {steps.map(([title, body], i) => (
        <li className="flex items-start gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3" key={title}>
          <span className="flex size-7 shrink-0 items-center justify-center rounded-full text-[12.5px] font-bold" style={{ backgroundColor: ASSIST_TINT_BG, color: ASSIST_TINT }}>{i + 1}</span>
          <span>
            <span className="block text-[13px] font-bold text-foreground">{title}</span>
            <span className="block text-[12px] leading-relaxed text-muted-foreground">{body}</span>
          </span>
        </li>
      ))}
    </ol>
  );
}
