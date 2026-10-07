'use client';

/**
 * Who is near this incident - and what each of them is already doing.
 *
 * WHY THIS PANEL EXISTS
 *
 * Responders on duty near a new report are now told at the same moment the agency
 * is, without waiting to be dispatched (see app/services/proximity.py). That
 * moves a decision to the dispatcher's screen that used to be invisible: which of
 * the people who were told is actually the right one to send? The roster this
 * console had said WHO was on duty, not who was close, and a Provincial Admin's
 * router docstring admits it plainly: a dispatcher was picking "with no idea who
 * is actually near the incident or already committed to a call".
 *
 * WHAT IT SHOWS, AND WHY IN THIS ORDER
 *
 * Best fit first: free units nearest first, then busy ones, then anyone whose
 * position is unknown. Each row carries the distance and the crew's own status
 * (Available / Assigned / En route / On scene) and, for a busy responder, WHAT they
 * are already on - because dispatching them costs that call something, and the
 * dispatcher should choose that knowingly. Whether they were told, and how loudly,
 * and whether they have answered "I can respond" are on the row too.
 *
 * WHAT IT NEVER DOES
 *
 * It assigns nothing. Telling a responder is not dispatching them; "Dispatch" here
 * only opens the same dialog the action bar does, with that responder chosen. And
 * the system never takes a busy crew off the call they hold.
 *
 * DISTANCE
 *
 * The figure is the ellipsoidal (WGS-84, Vincenty) distance from the responder's
 * last FRESH position, computed on the server so it is the one number the responder's
 * phone was also told. A position older than ten minutes is shown as unknown rather
 * than trusted. For the first few candidates the road distance is also asked of the
 * routing service the location panel already uses, and shown only when the service
 * really answers: a straight line is not a road, and this console never dresses one
 * up as the other.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import { Radio, Route as RouteIcon, TriangleAlert } from 'lucide-react';
import {
  fetchNearbyResponders,
  type NearbyAnswer, type NearbyPanel, type NearbyReason, type NearbyResponder, type ResponderState,
} from '@/lib/api/dispatch';
import { Button } from '@/components/efferd/ui/button';
import { SearchInput } from '@/components/ui/search-input';
import { cn } from '@/lib/utils';
import { StatusPill, type CurrentStatus } from '@/components/responders/status-pill';
import { fetchResponseRoute, formatDistance, type LatLng } from '@/lib/incidents/response-route';
import { relativeTime } from '@/lib/format/relative-time';

const POLL_MS = 10_000;
/** How many of the best-fit rows also ask for a road route. */
const ROAD_TOP_N = 3;

const STATE_TO_STATUS: Record<ResponderState, CurrentStatus> = {
  free: 'available',
  committed: 'assigned',
  en_route: 'en_route',
  on_scene: 'on_scene',
};

const REASON_COPY: Record<NearbyReason, string> = {
  nearest: 'Free and near',
  escalation: 'More severe than the call they are on',
  no_free_unit: 'Nobody free is near - asked quietly',
  nobody_in_range: 'Nobody in range - told anyway',
  location_unknown: 'Position unknown - told anyway',
  incident_not_located: 'This report has no GPS - every free unit told',
  busy: 'Busy on another call - not alerted',
  beyond_cap: 'Beyond the alert limit',
  out_of_range: 'Out of range',
  not_located: 'No recent position',
};

const SEVERITY_LABEL: Record<string, string> = {
  critical: 'CRITICAL', high: 'HIGH', medium: 'MEDIUM', low: 'LOW',
};

function fixLabel(r: NearbyResponder): string {
  if (r.fix_age_s === null) return 'No position reported';
  if (!r.located) return `Last position ${Math.max(1, Math.round(r.fix_age_s / 60))} min old - too old to trust`;
  if (r.fix_age_s < 60) return 'Position just now';
  return `Position ${Math.round(r.fix_age_s / 60)} min ago`;
}

function callLabel(r: NearbyResponder): string | null {
  const c = r.current_calls[0];
  if (!c) return null;
  const what = (c.category ?? 'incident').replace(/_/g, ' ');
  const sev = c.severity ? SEVERITY_LABEL[c.severity] ?? c.severity : null;
  const more = r.current_calls.length > 1 ? ` (+${r.current_calls.length - 1} more)` : '';
  return `${[what, sev].filter(Boolean).join(' - ')}${more}`;
}

export function NearbyResponders({
  incidentId, token, initial, active, scene, onDispatch,
}: {
  incidentId: string;
  token: string;
  /** What the detail already carried, so the card is never empty on first paint. */
  initial?: NearbyPanel | null;
  /** True while the incident still awaits a responder; polling stops once it does not. */
  active: boolean;
  /** The incident's own [lat, lng], for road routes. */
  scene: LatLng | null;
  /** Agency admins only: open the dispatch dialog with this responder chosen. */
  onDispatch?: (responderId: string) => void;
}) {
  const [panel, setPanel] = useState<NearbyPanel | null>(initial ?? null);
  const [failed, setFailed] = useState(false);
  const [roads, setRoads] = useState<Record<string, { km: number; minutes: number }>>({});
  const asked = useRef<Set<string>>(new Set());

  // Poll while the incident is open and the tab is being looked at.
  useEffect(() => {
    if (!active) return;
    let cancelled = false;
    const load = async () => {
      if (typeof document !== 'undefined' && document.visibilityState === 'hidden') return;
      try {
        const next = await fetchNearbyResponders(incidentId, token);
        if (!cancelled) { setPanel(next); setFailed(false); }
      } catch {
        // Keep what is on screen; say so rather than blanking a dispatcher's panel.
        if (!cancelled) setFailed(true);
      }
    };
    void load();
    const id = setInterval(load, POLL_MS);
    return () => { cancelled = true; clearInterval(id); };
  }, [incidentId, token, active]);

  const rows = useMemo(() => panel?.responders ?? [], [panel]);

  // One controller for the card's whole life. Aborting per poll would cancel a
  // route request that has already been marked as asked, and it would never be
  // retried - so the chip would silently never appear.
  const ctrl = useRef<AbortController | null>(null);
  useEffect(() => {
    const c = new AbortController();
    ctrl.current = c;
    return () => c.abort();
  }, []);

  // Road routes for the best few, once per position - never on every poll.
  useEffect(() => {
    const signal = ctrl.current?.signal;
    if (!scene || !signal) return;
    rows
      .filter(r => r.rank !== null && r.located && r.latitude !== null && r.longitude !== null)
      .slice(0, ROAD_TOP_N)
      .forEach(r => {
        const from: LatLng = [r.latitude as number, r.longitude as number];
        const key = `${r.responder_id}:${from[0].toFixed(4)},${from[1].toFixed(4)}`;
        if (asked.current.has(key)) return;
        asked.current.add(key);
        void fetchResponseRoute(from, scene, signal).then(route => {
          // Aborted (the card unmounted, or React re-ran the effect): forget that it
          // was asked, so the next run asks again instead of never showing the chip.
          if (signal.aborted) { asked.current.delete(key); return; }
          // The service answered with a line, not a road: leave it asked (do not
          // hammer a public routing service) and show nothing extra.
          if (route.source !== 'road') return;
          setRoads(prev => ({ ...prev, [r.responder_id]: { km: route.distanceKm, minutes: route.minutes } }));
        });
      });
  }, [rows, scene]);

  const summary = panel?.summary;
  const header = useMemo(() => {
    if (!summary || !panel) return null;
    const parts = [`${summary.free} free`, `${summary.busy} busy`];
    if (summary.notified > 0) parts.push(`${summary.notified} alerted`);
    return `${parts.join(' · ')} · within ${panel.policy.radius_km} km`;
  }, [summary, panel]);

  if (!panel) {
    return (
      <p className="text-[13px] text-muted-foreground" data-nearby="loading">
        Looking for responders near this incident…
      </p>
    );
  }

  if (rows.length === 0) {
    return (
      <div data-nearby="empty">
        <p className="text-[13px] text-muted-foreground">
          No responder is on duty for this agency
          {summary && summary.off_duty > 0 ? ` (${summary.off_duty} off duty)` : ''}. Nobody has been alerted.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3" data-nearby="panel">
      <div className="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
        <p className="text-[12.5px] font-semibold text-foreground" data-nearby-summary>{header}</p>
        {failed && (
          <span className="text-[11.5px] font-medium" style={{ color: 'var(--color-system-warning)' }}>
            Could not refresh - showing the last reading
          </span>
        )}
      </div>
      {/* Folded: read once, not every time the card is opened. */}
      <details className="group text-[12px] leading-snug text-muted-foreground">
        <summary className="cursor-pointer select-none font-semibold text-[var(--color-text-secondary)] hover:text-foreground">
          How were they alerted?
        </summary>
        <p className="mt-1.5">
          Free responders near the report were alerted the moment it arrived; a responder already on a
          call is only asked quietly, and only when this is more severe or nobody free is near. You still
          decide who goes, and nobody is taken off a call they are on.
        </p>
      </details>

      <NearbyList onDispatch={onDispatch} roads={roads} rows={rows} />
    </div>
  );
}

/** Rows shown before "Show more": the best-fit few are what a dispatcher picks from. */
const FIRST_PAGE = 5;
/** Each "Show more" adds this many. */
const PAGE_STEP = 10;
/** A filter bar and a search box only once there is something to filter. */
const TOOLS_FROM = 6;
const SEARCH_FROM = 9;

type NearbyFilter = 'all' | 'free' | 'busy' | 'alerted' | 'unknown';

const FILTERS: { key: NearbyFilter; label: string; test: (r: NearbyResponder) => boolean }[] = [
  { key: 'all', label: 'All', test: () => true },
  { key: 'free', label: 'Free', test: r => r.state === 'free' },
  { key: 'busy', label: 'Busy', test: r => r.state !== 'free' },
  { key: 'alerted', label: 'Alerted', test: r => r.level !== 'none' },
  { key: 'unknown', label: 'No position', test: r => r.distance_km === null },
];

/**
 * The ranked list, built to stay usable at any size (user request 2026-10-08:
 * "what if 1000 na?"). The best-fit five show first - the order is already
 * best-first, so those are the ones a dispatcher picks from - and the rest is
 * reached by filter, by name or badge, or by "Show more". Past the first page
 * the list scrolls inside its own box, so the dialog never grows with the
 * roster. Filtering and paging are client-side over the one ranked reply the
 * poll already brings; a filter keeps the ranking.
 */
function NearbyList({
  rows, roads, onDispatch,
}: {
  rows: NearbyResponder[];
  roads: Record<string, { km: number; minutes: number }>;
  onDispatch?: (id: string) => void;
}) {
  const [filter, setFilter] = useState<NearbyFilter>('all');
  const [query, setQuery] = useState('');
  const [shown, setShown] = useState(FIRST_PAGE);

  const counts = useMemo(() => {
    const c = {} as Record<NearbyFilter, number>;
    for (const f of FILTERS) c[f.key] = rows.filter(f.test).length;
    return c;
  }, [rows]);

  const matching = useMemo(() => {
    const test = FILTERS.find(f => f.key === filter)!.test;
    const q = query.trim().toLowerCase();
    return rows.filter(r => test(r) && (!q
      || (r.full_name ?? '').toLowerCase().includes(q)
      || (r.badge_id ?? '').toLowerCase().includes(q)));
  }, [rows, filter, query]);

  const visible = matching.slice(0, shown);
  const left = matching.length - visible.length;
  const tools = rows.length >= TOOLS_FROM;

  return (
    <div className="flex flex-col gap-2.5">
      {tools && (
        <div className="flex flex-col gap-2" data-nearby-tools>
          <div className="flex flex-wrap gap-1.5" role="group" aria-label="Show responders">
            {FILTERS.filter(f => f.key === 'all' || counts[f.key] > 0).map(f => {
              const on = filter === f.key;
              return (
                <button
                  aria-pressed={on}
                  className="inline-flex h-7 items-center gap-1.5 rounded-full border px-2.5 text-[12px] font-semibold transition-colors"
                  data-nearby-filter={f.key}
                  key={f.key}
                  onClick={() => { setFilter(f.key); setShown(FIRST_PAGE); }}
                  style={on
                    ? { borderColor: 'var(--color-text-primary)', backgroundColor: 'var(--color-text-primary)', color: 'var(--color-surface-card)' }
                    : { borderColor: 'var(--color-surface-border)', color: 'var(--color-text-secondary)' }}
                  type="button"
                >
                  {f.label}
                  <span className="tabular-nums opacity-75">{counts[f.key]}</span>
                </button>
              );
            })}
          </div>
          {rows.length >= SEARCH_FROM && (
            <SearchInput
              label="Find a responder by name or badge"
              onValueChange={v => { setQuery(v); setShown(FIRST_PAGE); }}
              placeholder="Find by name or badge"
              size="sm"
              value={query}
            />
          )}
        </div>
      )}

      {visible.length === 0 ? (
        <p className="rounded-[var(--radius-md)] border border-dashed border-[var(--color-surface-border)] px-3 py-4 text-center text-[12.5px] text-muted-foreground" data-nearby="no-match">
          No responder matches{query.trim() ? ` "${query.trim()}"` : ' this filter'}.
        </p>
      ) : (
        <ol
          className={cn(
            'flex flex-col gap-2',
            // Past the first page the list scrolls in place; the dialog does not grow.
            shown > FIRST_PAGE && 'scroll-slim max-h-[440px] overflow-y-auto pr-1',
          )}
          data-nearby-list
        >
          {visible.map(r => (
            <NearbyRow
              key={r.responder_id}
              onDispatch={onDispatch}
              road={roads[r.responder_id]}
              row={r}
            />
          ))}
        </ol>
      )}

      {(left > 0 || shown > FIRST_PAGE) && (
        <div className="flex flex-wrap items-center justify-between gap-2 text-[12px] text-muted-foreground">
          <span data-nearby-count>
            Showing <b className="font-semibold text-foreground tabular-nums">{visible.length}</b> of{' '}
            <span className="tabular-nums">{matching.length}</span>
          </span>
          <span className="flex gap-2">
            {shown > FIRST_PAGE && (
              <Button onClick={() => setShown(FIRST_PAGE)} size="sm" variant="ghost">Show fewer</Button>
            )}
            {left > 0 && (
              <Button data-nearby-more onClick={() => setShown(s => s + PAGE_STEP)} size="sm" variant="outline">
                Show {Math.min(PAGE_STEP, left)} more
              </Button>
            )}
          </span>
        </div>
      )}
    </div>
  );
}

function AnswerChip({ answer, at }: { answer: NearbyAnswer; at: string | null }) {
  const yes = answer === 'can_respond';
  return (
    <span
      className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold"
      data-nearby-answer={answer}
      style={{
        backgroundColor: yes ? 'var(--color-system-success-bg)' : 'var(--color-surface-raised)',
        color: yes ? 'var(--color-system-success)' : 'var(--color-text-muted)',
      }}
    >
      {yes ? 'Says they can respond' : 'Says unavailable'}
      {at && <span className="font-normal opacity-80">{relativeTime(at)}</span>}
    </span>
  );
}

function NearbyRow({
  row: r, road, onDispatch,
}: {
  row: NearbyResponder;
  road?: { km: number; minutes: number };
  onDispatch?: (id: string) => void;
}) {
  const busy = r.state !== 'free';
  const current = callLabel(r);
  const told = r.level !== 'none';

  return (
    <li
      className="flex items-center gap-3 rounded-[var(--radius-md)] border px-3 py-2"
      data-nearby-row={r.responder_id}
      data-level={r.level}
      data-state={r.state}
      style={{
        borderColor: told && r.level === 'alarm' ? 'var(--color-brand)' : 'var(--color-surface-border)',
        backgroundColor: told && r.level === 'alarm' ? 'var(--color-brand-subtle)' : 'transparent',
      }}
    >
      {/* Compact (2026-10-08): two lines and the button at the side, so a
          long list reads as a list and not as a wall of cards. */}
      <div className="flex min-w-0 flex-1 flex-col gap-0.5">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          {r.rank !== null && (
            <span
              aria-label={`Rank ${r.rank}`}
              className="grid h-5 min-w-5 place-items-center rounded-full px-1 text-[11px] font-bold"
              style={{ backgroundColor: 'var(--color-brand)', color: 'var(--color-text-inverse)' }}
            >
              {r.rank}
            </span>
          )}
          <span className="text-[13.5px] font-semibold text-foreground">{r.full_name ?? 'Responder'}</span>
          {r.badge_id && <span className="font-mono text-[11.5px] text-muted-foreground">{r.badge_id}</span>}
          <StatusPill
            currentIncident={r.current_calls[0]?.incident_id ? {
              id: r.current_calls[0].incident_id,
              incident_category: r.current_calls[0].category,
              location_address: r.current_calls[0].address,
            } : null}
            status={STATE_TO_STATUS[r.state]}
          />
          {r.level === 'alarm' && (
            <span className="inline-flex items-center gap-1 text-[11.5px] font-semibold" style={{ color: 'var(--color-brand)' }}>
              <Radio size={12} /> Alerted
            </span>
          )}
          {r.level === 'advisory' && (
            <span className="inline-flex items-center gap-1 text-[11.5px] font-semibold text-muted-foreground">
              <Radio size={12} /> Asked quietly
            </span>
          )}
          {r.answer && <AnswerChip answer={r.answer} at={r.answered_at} />}
        </div>

        <div className="flex flex-wrap items-center gap-x-2.5 gap-y-0.5 text-[12px] text-[var(--color-text-secondary)]">
          {r.distance_km !== null ? (
            <span data-nearby-distance>
              <b className="font-semibold text-foreground">{formatDistance(r.distance_km)}</b>
              {r.direction ? ` · head ${r.direction}` : ''}
              {r.eta_min !== null ? ` · about ${r.eta_min} min` : ''}
            </span>
          ) : (
            <span className="inline-flex items-center gap-1" data-nearby-distance style={{ color: 'var(--color-system-warning)' }}>
              <TriangleAlert size={12} /> Distance unknown
            </span>
          )}
          {road && (
            <span
              className="inline-flex items-center gap-1 text-muted-foreground"
              data-nearby-road
              title="Driving route from the routing service; the straight-line figure is a lower bound."
            >
              <RouteIcon size={12} /> by road {formatDistance(road.km)} · {road.minutes} min
            </span>
          )}
          {busy && current ? (
            <span data-nearby-current style={{ color: 'var(--color-status-dispatched)' }}>
              Already on: <b className="font-semibold">{current}</b>
            </span>
          ) : (
            <span className="text-muted-foreground" data-nearby-reason={r.reason}>{REASON_COPY[r.reason]}</span>
          )}
          <span className="text-muted-foreground" title={fixLabel(r)}>· {fixLabel(r)}</span>
        </div>
      </div>
      {onDispatch && (
        <Button
          className="shrink-0"
          data-nearby-dispatch={r.responder_id}
          onClick={() => onDispatch(r.responder_id)}
          size="sm"
          variant="outline"
        >
          Dispatch
        </Button>
      )}
    </li>
  );
}
