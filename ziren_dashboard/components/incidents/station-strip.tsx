'use client';

/**
 * StationStrip — the province at a glance. Provincial Admin only.
 *
 * Agency Admin has exactly one station, so there is nothing here to break
 * down — this is the one thing this page can show that a single-station
 * queue structurally cannot: which of MY stations needs attention right now.
 * The old "Agency" filter used to gesture at this and couldn't really answer
 * it, because every row a Provincial Admin sees already shares their own
 * agency_type (see active-view.tsx's own note on why that filter became the
 * Station filter instead).
 *
 * Counts are computed over the WHOLE incident set, not whatever the table is
 * currently filtered to — same rule the severity bands already followed: a
 * count that shrank to match its own filter would be answering a question
 * nobody asked. Clicking a card sets the Station filter; it does not open
 * anything, same as the severity-band buttons beside it.
 *
 * Sorted worst first (critical count, then total load, then name) — this is
 * meant to be read top-to-bottom-then-stop by someone who has ten seconds,
 * not browsed alphabetically.
 */

import { AlertTriangle, Building2 } from 'lucide-react';
import type { QueueIncident } from '@/lib/api/dispatch';
import { AWAITING_STATUSES, SEV_COLOR, longestWait, sevOf } from './incident-vocabulary';

const SEV_RANK: Record<string, number> = { critical: 4, high: 3, medium: 2, low: 1 };

interface StationStat {
  name: string;
  active: number;
  critical: number;
  worstSeverity: string | null;
  longestWaitLabel: string | null;
}

function computeStationStats(incidents: QueueIncident[]): StationStat[] {
  const byStation = new Map<string, QueueIncident[]>();
  for (const inc of incidents) {
    const name = inc.stations?.name;
    if (!name) continue;
    const rows = byStation.get(name);
    if (rows) rows.push(inc); else byStation.set(name, [inc]);
  }

  const stats: StationStat[] = [...byStation.entries()].map(([name, rows]) => {
    const waiting = rows.filter(r => AWAITING_STATUSES.includes(r.status));
    let worst: string | null = null;
    let worstRank = 0;
    let critical = 0;
    for (const r of rows) {
      const sev = sevOf(r);
      if (sev === 'critical') critical++;
      const rank = sev ? (SEV_RANK[sev] ?? 0) : 0;
      if (rank > worstRank) { worstRank = rank; worst = sev; }
    }
    return {
      name,
      active: rows.length,
      critical,
      worstSeverity: worst,
      longestWaitLabel: longestWait(waiting),
    };
  });

  return stats.sort((a, b) => {
    if (a.critical !== b.critical) return b.critical - a.critical;
    if (a.active !== b.active) return b.active - a.active;
    return a.name.localeCompare(b.name);
  });
}

export function StationStrip({
  incidents,
  active,
  onSelect,
}: {
  incidents: QueueIncident[];
  /** 'all' or a station name — mirrors active-view's `station` filter state. */
  active: string;
  onSelect: (station: string) => void;
}) {
  const stats = computeStationStats(incidents);
  const totalCritical = stats.reduce((n, s) => n + s.critical, 0);

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center gap-2 px-0.5">
        <Building2 aria-hidden="true" className="text-muted-foreground" size={13} />
        <span className="text-section-label" style={{ color: 'var(--color-text-tertiary)' }}>
          Your stations
        </span>
        <span className="text-meta text-muted-foreground">
          {stats.length === 0
            ? 'No stations reporting yet'
            : `${stats.length} station${stats.length === 1 ? '' : 's'} reporting`}
        </span>
      </div>

      <div className="scroll-slim flex gap-2 overflow-x-auto pb-1">
        <_StationCard
          active={active === 'all'}
          color="var(--color-brand)"
          count={incidents.length}
          critical={totalCritical}
          label="All stations"
          onClick={() => onSelect('all')}
          sub={`Province-wide · ${stats.length} station${stats.length === 1 ? '' : 's'}`}
        />
        {stats.map(s => (
          <_StationCard
            active={active === s.name}
            color={s.worstSeverity ? (SEV_COLOR[s.worstSeverity] ?? 'var(--color-text-muted)') : 'var(--color-text-muted)'}
            count={s.active}
            critical={s.critical}
            key={s.name}
            label={s.name}
            onClick={() => onSelect(s.name)}
            sub={
              s.longestWaitLabel
                ? `Longest wait ${s.longestWaitLabel}`
                : s.active > 0 ? 'Nothing waiting' : 'All clear'
            }
          />
        ))}
      </div>
    </div>
  );
}

function _StationCard({
  label,
  count,
  critical,
  sub,
  color,
  active,
  onClick,
}: {
  label: string;
  count: number;
  /**
   * Rendered as a labelled chip (icon + colour + number), never colour
   * alone — the same rule the severity tables elsewhere in this app follow
   * (see globals.css). Zero renders no chip at all rather than a "0
   * critical" chip nobody needs to read.
   */
  critical: number;
  sub: string;
  color: string;
  active: boolean;
  onClick: () => void;
}) {
  return (
    <button
      aria-pressed={active}
      className="relative flex w-[184px] shrink-0 flex-col gap-2 overflow-hidden rounded-[var(--radius-card)] border px-3.5 py-3 text-left transition-colors"
      onClick={onClick}
      style={{
        borderColor: active ? color : 'var(--color-surface-border)',
        backgroundColor: active
          ? `color-mix(in srgb, ${color} 8%, transparent)`
          : 'var(--color-surface-card)',
        boxShadow: 'var(--shadow-card)',
      }}
      type="button"
    >
      {/* A thin identity accent, same device the table's own severity-group
          rows and the AgencyCard dot already use — not the thing carrying
          the severity FACT (the chip below does that with a label). */}
      <span
        aria-hidden="true"
        className="absolute inset-x-0 top-0 h-[3px]"
        style={{ backgroundColor: color }}
      />

      <span
        className="truncate text-[12.5px] font-semibold"
        style={{ color: 'var(--color-text-secondary)' }}
        title={label}
      >
        {label}
      </span>

      <div className="flex items-center justify-between gap-2">
        <span
          className="font-mono text-[26px] leading-none font-bold tabular-nums"
          style={{ color: count > 0 ? 'var(--color-text-primary)' : 'var(--color-text-muted)' }}
        >
          {count}
        </span>
        {/* Always true critical-red, independent of the card's own accent
            colour (brand orange for "All stations", the worst severity hue
            for a single station) — red is reserved for critical severity
            specifically, never repurposed as a card's identity colour. */}
        {critical > 0 && (
          <span
            className="inline-flex shrink-0 items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold whitespace-nowrap"
            style={{
              backgroundColor: 'var(--color-severity-critical-bg)',
              color: 'var(--color-severity-critical)',
            }}
          >
            <AlertTriangle aria-hidden="true" size={10} />
            {critical} critical
          </span>
        )}
      </div>

      <span className="truncate text-[11px] text-muted-foreground">{sub}</span>
    </button>
  );
}
