'use client';

/**
 * The header card of the Operational Area — one card, three tiers, each answering
 * one question in the order a person asks it:
 *
 *   1. WHERE AM I?            the area's name, whose figures these are, what it covers
 *   2. WHAT AM I LOOKING AT?  the filters, each with a label: municipality (Provincial
 *                             Admin), barangay, period — and how fresh the figures are
 *   3. WHERE CAN I GO?        the views, as tabs on the card's foot
 *
 * The rule the tiers keep: plain text is information, anything with a border or a
 * fill is a control. The old card mixed the two — the facts about the area and the
 * filters read as one line of equal-weight crumbs, and "Showing [Whole
 * municipality] · the last 30 days" was a sentence with a dropdown in the middle.
 *
 * The filter tier fills its row: each field grows from a sensible minimum, so on a
 * wide screen the controls share the width instead of huddling left with a gap
 * beside them, and on a narrow one the same rule wraps a field onto its own full
 * row. Every one of the filters opens a dialog rather than a native dropdown —
 * municipality and a custom date range each say what they are doing to the
 * figures before they do it, and a barangay's list is long enough to need the
 * search box only its own dialog has.
 */

import { useEffect, useRef, useState } from 'react';
import {
  CalendarRange, ChevronDown, Download, Globe, Handshake, MapPin, MapPinned, WifiOff, X,
} from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import type { OperationalArea } from '@/lib/api/operational-area';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { FilterField } from '@/components/ui/filter-field';
import { OptionPicker } from '@/components/ui/option-picker';
import { PeriodPicker } from '@/components/ui/period-picker';
import { cn } from '@/lib/utils';
import { AgencyChip } from './kit';
import { AreaTabs, type AreaTabItem } from './area-tabs';
import { BarangayDialog } from './barangay-picker';
import { periodDates, periodLong, phToday, type Range } from './period';

/** A field that opens a dialog, dressed like the dropdowns beside it. */
const FILTER_BUTTON =
  'flex h-9 min-w-0 flex-1 items-center gap-2 rounded-[var(--radius-control)] border border-input bg-[var(--color-surface-card)] px-3 text-left text-[13px] font-medium text-foreground transition-colors hover:bg-[var(--color-surface-hover)] disabled:cursor-not-allowed disabled:opacity-50';
/** A filter that is switched on says so — same "selected" tint the rest of the console uses. */
const FILTER_ON = 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] font-semibold hover:bg-[var(--color-brand-subtle)] dark:bg-[var(--color-brand-subtle)]';

export function AreaHeader({
  data,
  stale,
  isProvincial,
  municipalities,
  municipality,
  onMunicipality,
  days,
  onDays,
  range,
  onRange,
  barangay,
  onBarangay,
  onExport,
  agencyType,
  tabs,
  activeTab,
  onTab,
}: {
  data: OperationalArea | null;
  /** The last background refresh failed — the figures are older than they look. */
  stale: boolean;
  isProvincial: boolean;
  municipalities: string[];
  municipality: string;
  onMunicipality: (m: string) => void;
  /** The rolling period that is (or was last) chosen. */
  days: number;
  onDays: (d: number) => void;
  /** A range of days the reader chose; when set it replaces `days`. */
  range: Range | null;
  onRange: (r: Range) => void;
  barangay: string | null;
  onBarangay: (b: string | null) => void;
  onExport: () => void;
  agencyType: string | null;
  tabs: AreaTabItem[];
  activeTab: string;
  onTab: (key: string) => void;
}) {
  // "Updated 3 min ago" has to keep counting; a label computed once at render
  // would say "just now" until something else happened to re-render the page.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(id);
  }, []);

  const [barangayOpen, setBarangayOpen] = useState(false);
  // Passed to the dialog so it can hand focus back to the field that opened it when it
  // closes. Radix's own "return focus to whatever was focused before" does not reliably
  // land back on a plain button that isn't a <Dialog.Trigger> — confirmed by hand: without
  // this, closing the dialog (Escape, an outside click, or making a choice) dropped focus
  // to <body>, so the next Tab press started back at the top of the page instead of
  // continuing from the filter a keyboard user was just on. PeriodPicker carries the same
  // fix for its own Custom dialog internally.
  const barangayTriggerRef = useRef<HTMLButtonElement>(null);

  const area = data?.area;
  const own = area?.agency ?? null;
  const hue = AG_COLOR[own?.agency_type ?? agencyType ?? ''] ?? 'var(--color-brand)';

  // A Provincial Admin's title follows the picker, so it never lags the control
  // beside it; the province is added once the figures for that municipality are in.
  const place = isProvincial && municipality ? municipality : area?.municipality ?? '';
  const province = area && (!isProvincial || area.municipality === municipality) ? area.province : null;
  const agencyCount = data?.agencies.length ?? 0;

  // While a new period loads the old figures stay up (dimmed). The dates must not
  // claim the new period until the figures for it are actually here. (A chosen range
  // can come back with its end clamped to today, hence "no later than".)
  const custom = range !== null;
  const settled = !!data && (
    custom
      ? data.filters.date_from === range.from && !!data.filters.date_to && data.filters.date_to <= range.to
      : !data.filters.date_from && data.filters.days === days
  );
  const dates = data && settled ? periodDates(data.filters, data.generated_at) ?? 'Everything on record' : null;

  const today = phToday(now);
  const barangays = data?.barangays;
  const barangayOptions = (barangays?.items ?? []).map(b => ({ name: b.name, incidents: b.incidents }));
  const wholeArea = barangays ? barangays.matched_incidents + barangays.unmatched_incidents + barangays.unlocated_incidents : 0;

  return (
    <header
      className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]"
      data-area-header
    >
      {/* ── 1 · Where am I ─────────────────────────────────────────────── */}
      <div className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-start gap-x-3.5 gap-y-3 px-5 py-4 sm:gap-x-4 sm:py-5 md:px-6">
        <span
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-xl sm:row-span-2 sm:size-12 sm:rounded-[14px]"
          // The agency's own hue, as it is worn everywhere else in the console.
          style={{ backgroundColor: `color-mix(in srgb, ${hue} 12%, transparent)`, color: hue }}
        >
          <MapPinned className="size-5 sm:size-6" />
        </span>

        <div className="min-w-0">
          <p className="text-[11.5px] font-semibold uppercase tracking-[0.1em] text-[var(--color-text-tertiary)]">
            {isProvincial ? 'Geographic overview' : 'Operational area'}
          </p>
          <h1 className="mt-1 text-[24px] font-bold leading-[1.15] tracking-tight text-foreground sm:text-[28px]">
            {place ? (
              <>
                {place}
                {province && <span className="font-medium text-[var(--color-text-tertiary)]">, {province}</span>}
              </>
            ) : (
              <Skeleton className="h-8 w-56" />
            )}
          </h1>
        </div>

        <Button
          aria-label="Export CSV"
          className="shrink-0 rounded-[var(--radius-control)] px-3.5 max-sm:w-9 max-sm:px-0 sm:row-span-2"
          disabled={!data}
          onClick={onExport}
          size="lg"
          title="Download this screen’s figures as a spreadsheet (CSV)"
          type="button"
          variant="outline"
        >
          <Download className="size-4" />
          <span className="max-sm:hidden">Export CSV</span>
        </Button>

        <ul aria-label="About this area" className="col-span-3 flex flex-wrap items-center gap-x-4 gap-y-2 text-[13px] text-[var(--color-text-secondary)] sm:col-span-1 sm:col-start-2 sm:gap-x-5">
          {own && (
            <Fact title={`The reports and crew on this screen belong to ${own.name}`}>
              <AgencyChip type={own.agency_type} />
              <span className="font-semibold text-foreground">{own.name}</span>
            </Fact>
          )}
          {isProvincial && agencyType && (
            <Fact title={`Report and crew figures cover ${agencyType} only. Other agencies’ figures are not shown.`}>
              <AgencyChip type={agencyType} />
              <span className="font-semibold text-foreground">reports &amp; crew</span>
            </Fact>
          )}
          {area ? (
            <>
              {area.region && <Fact icon={Globe} nowrap>{area.region}</Fact>}
              <Fact icon={MapPin} nowrap>{area.barangay_count} barangays</Fact>
              <Fact icon={Handshake} nowrap>{agencyCount} agenc{agencyCount === 1 ? 'y' : 'ies'} present</Fact>
            </>
          ) : (
            <li><Skeleton className="h-4 w-64" /></li>
          )}
        </ul>
      </div>

      {/* ── 2 · What am I looking at ───────────────────────────────────── */}
      <div
        aria-label="What this screen shows"
        className="flex flex-wrap items-end gap-x-5 gap-y-3.5 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/45 px-5 py-3.5 md:px-6"
        role="group"
      >
        {isProvincial && (
          <FilterField className="max-sm:w-full sm:flex-[1_1_180px]" label="Municipality">
            <OptionPicker
              className="h-9"
              label="Choose a municipality"
              onChange={onMunicipality}
              options={municipalities.map(m => ({ value: m, label: m }))}
              placeholder="Choose one"
              value={municipality}
            />
          </FilterField>
        )}

        <FilterField className="max-sm:w-full sm:flex-[1.2_1_230px]" label="Barangay">
          <div className="flex items-center gap-1.5">
            <button
              aria-expanded={barangayOpen}
              aria-haspopup="dialog"
              aria-label={`Barangay: ${barangay ?? 'Whole municipality'}`}
              className={cn(FILTER_BUTTON, barangay && FILTER_ON)}
              disabled={!data}
              onClick={() => setBarangayOpen(true)}
              ref={barangayTriggerRef}
              type="button"
            >
              <MapPin aria-hidden="true" className="size-4 shrink-0 text-[var(--color-text-tertiary)]" />
              <span className="min-w-0 flex-1 truncate">{barangay ?? 'Whole municipality'}</span>
              <ChevronDown aria-hidden="true" className="size-4 shrink-0 text-muted-foreground" />
            </button>
            {barangay && (
              <button
                aria-label="Clear filter"
                className="inline-flex h-9 shrink-0 items-center gap-1 rounded-[var(--radius-control)] px-2.5 text-[12.5px] font-semibold text-[var(--color-text-secondary)] transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
                onClick={() => onBarangay(null)}
                type="button"
              >
                <X aria-hidden="true" className="size-3.5" />
                Clear
              </button>
            )}
          </div>
        </FilterField>

        <FilterField
          aside={data && (
            <span className="flex items-center gap-1 text-[11.5px] font-medium text-[var(--color-text-tertiary)]" data-period-dates>
              <CalendarRange aria-hidden="true" className="size-3" />
              {dates ?? 'Updating…'}
            </span>
          )}
          className="max-sm:w-full sm:flex-[2.4_1_470px]"
          label="Period"
        >
          <PeriodPicker
            days={days}
            onDays={onDays}
            onRange={onRange}
            range={range}
            showComparison
            size="md"
            today={today}
          />
        </FilterField>
      </div>

      {stale && (
        <div
          className="flex items-center gap-2 border-t border-[var(--color-surface-border)] bg-[var(--color-system-warning-bg)] px-5 py-2 text-[12.5px] font-medium text-foreground md:px-6"
          role="status"
        >
          <WifiOff aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-system-warning)]" />
          Couldn’t refresh — showing the last good figures
        </div>
      )}

      {/* ── 3 · Where can I go ─────────────────────────────────────────── */}
      <AreaTabs
        activeKey={activeTab}
        ariaLabel="Operational area views"
        onSelect={onTab}
        tabs={tabs}
      />

      {/* Renders into the page body (a portal), so where it sits here does not matter;
          nothing is drawn while closed. PeriodPicker's own Custom dialog renders the same
          way, from inside the filter tier above. */}
      <BarangayDialog
        municipality={place}
        onChange={onBarangay}
        onOpenChange={setBarangayOpen}
        open={barangayOpen}
        options={barangayOptions}
        periodWords={data ? periodLong(data.filters) : 'this period'}
        total={wholeArea}
        triggerRef={barangayTriggerRef}
        value={barangay}
      />
    </header>
  );
}

/** One fact about the area: plain text, never a control. */
function Fact({
  icon: Icon,
  nowrap = false,
  title,
  children,
}: {
  icon?: LucideIcon;
  nowrap?: boolean;
  title?: string;
  children: React.ReactNode;
}) {
  return (
    <li className={cn('flex items-center gap-2', nowrap && 'whitespace-nowrap')} title={title}>
      {Icon && <Icon aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-text-tertiary)]" />}
      {children}
    </li>
  );
}

