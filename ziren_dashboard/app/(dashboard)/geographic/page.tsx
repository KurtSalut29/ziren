'use client';

/**
 * Operational Area (Agency Admin) / Geographic Overview (Provincial Admin).
 *
 * One screen, one payload (GET /geographic/operational-area), six views of it:
 *
 *   Overview            the headline figures, the trend, readiness, what came in
 *   Map                 the area's stations, crew and reports, framed on the area
 *   Barangays           every barangay: who is registered, what was reported
 *   Response            how fast the area is answered, against the targets
 *   Stations & crew     the stations here and the roster that staffs them
 *   Agencies            who else is here, and how to reach them
 *   Compare             (Provincial Admin) every municipality side by side
 *
 * An Agency Admin's area is fixed by the server — their agency's own
 * municipality, their own agency's reports. A Provincial Admin picks any
 * municipality and sees the reports of their own agency type. Neither is
 * decided here; this page only asks and shows.
 *
 * The tab, period, barangay and (for provincial admins) municipality all live in
 * this page's state, and the tab in the address (?tab=), so a view can be linked.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  BarChart3, Building2, Gauge, Handshake, LayoutDashboard, Map as MapIcon, MapPin, RefreshCw,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError } from '@/lib/api/client';
import { fetchMunicipalities, type MunicipalityOption } from '@/lib/api/geographic';
import { useOperationalArea } from '@/lib/hooks/useOperationalArea';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import { IncidentDetailModal } from '@/components/incidents/incident-detail-modal';
import { AreaHeader } from '@/components/operational-area/header';
import { AREA_PANEL_ID, areaTabId, type AreaTabItem } from '@/components/operational-area/area-tabs';
import { OverviewTab } from '@/components/operational-area/overview-tab';
import { MapTab } from '@/components/operational-area/map-tab';
import { BarangaysTab } from '@/components/operational-area/barangays-tab';
import { ResponseTab } from '@/components/operational-area/response-tab';
import { CrewTab } from '@/components/operational-area/crew-tab';
import { AgenciesTab } from '@/components/operational-area/agencies-tab';
import { CompareTab } from '@/components/operational-area/compare-tab';
import { areaCsvName, buildAreaCsv, downloadCsv } from '@/components/operational-area/export';
import { MAX_RANGE_DAYS, addDays, parseYmd, phToday, type Range } from '@/components/operational-area/period';

type TabKey = 'overview' | 'map' | 'barangays' | 'response' | 'stations' | 'agencies' | 'compare';
const DAYS_KEY = 'ziren-area-days';
/** How often the screen quietly refreshes itself while it is in view. The Refresh button is there for sooner. */
const POLL_MS = 60_000;
const VALID_DAYS = [0, 7, 30, 90, 365];
const TAB_KEYS: TabKey[] = ['overview', 'map', 'barangays', 'response', 'stations', 'agencies', 'compare'];

function readSavedDays(): number {
  try {
    const v = Number(localStorage.getItem(DAYS_KEY));
    return VALID_DAYS.includes(v) && localStorage.getItem(DAYS_KEY) !== null ? v : 30;
  } catch {
    return 30;
  }
}

/**
 * A chosen range from the address (?from=2026-03-01&to=2026-03-15), if it is a real one.
 * A link that was edited by hand, or is simply old, must not be able to make the screen
 * ask the server something it will refuse: a range that starts in the future, runs
 * backwards or is longer than the server allows is ignored, and an end date after today
 * is brought back to today.
 */
function readUrlRange(params: URLSearchParams): Range | null {
  const from = params.get('from');
  const to = params.get('to');
  if (!from || !to || !parseYmd(from) || !parseYmd(to)) return null;
  const today = phToday();
  if (from > to || from > today || from < addDays(today, -(MAX_RANGE_DAYS - 1))) return null;
  return { from, to: to > today ? today : to };
}

export default function OperationalAreaPage() {
  const { token, isProvincialAdmin, isAgencyAdmin, agencyType } = useAuth();

  const [tab, setTab] = useState<TabKey>('overview');
  const [days, setDays] = useState(30);
  /** A range the reader chose; while set it replaces `days`. Lives in the address, not in storage — see below. */
  const [range, setRange] = useState<Range | null>(null);
  /** The saved period and the linked tab/range have been read; nothing is asked of the server before that. */
  const [hydrated, setHydrated] = useState(false);
  const [barangay, setBarangay] = useState<string | null>(null);
  const [municipality, setMunicipality] = useState('');
  const [municipalities, setMunicipalities] = useState<MunicipalityOption[]>([]);
  const [openId, setOpenId] = useState<string | null>(null);
  const [listError, setListError] = useState<string | null>(null);

  // The saved period, the linked tab and a linked range are read once on arrival, after
  // mount, so the server-rendered shell and the first client render agree. The first
  // question to the server waits for them: asking for "30 days" and then, a moment
  // later, for the 90 that was saved (or the range in the link) is a wasted request
  // and a flash of figures nobody asked for.
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);
    // Assist requests moved to their own page. Bell entries written before
    // the move still point here (?tab=agencies&assist=<id>) — send them on.
    const assist = params.get('assist');
    if (assist) {
      window.location.replace(`/assist-requests?id=${encodeURIComponent(assist)}`);
      return;
    }
    setDays(readSavedDays());
    const wanted = params.get('tab');
    if (wanted && (TAB_KEYS as string[]).includes(wanted)) setTab(wanted as TabKey);
    setRange(readUrlRange(params));
    setHydrated(true);
  }, []);

  // The address always says which tab is open and, for a chosen range, which days — so a
  // reload keeps them and the link can be sent to someone. A preset period is not in the
  // address: it is a habit ("I always look at 90 days") and is remembered per browser.
  useEffect(() => {
    if (!hydrated) return;
    const p = new URLSearchParams({ tab });
    if (range) { p.set('from', range.from); p.set('to', range.to); }
    try {
      window.history.replaceState(null, '', `${window.location.pathname}?${p.toString()}`);
    } catch { /* an embedded context — the state still works */ }
  }, [hydrated, tab, range]);

  // Provincial Admin: the list of municipalities, defaulting to the one with the
  // most residents — landing on an empty one made the whole screen look broken.
  useEffect(() => {
    if (!token || !isProvincialAdmin) return;
    fetchMunicipalities(token)
      .then(list => {
        setMunicipalities(list);
        if (list.length) {
          setMunicipality(prev => prev || list.reduce((a, b) => (b.resident_count > a.resident_count ? b : a)).name);
        }
      })
      .catch((e: unknown) => {
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setListError(e instanceof Error ? e.message : 'Could not load the municipalities.');
      });
  }, [token, isProvincialAdmin]);

  const query = useMemo(() => {
    if (!hydrated) return null;                            // the saved period / linked range are not known yet
    if (isProvincialAdmin && !municipality) return null;   // nothing to ask about yet
    return { municipality: isProvincialAdmin ? municipality : undefined, barangay, days, range };
  }, [hydrated, isProvincialAdmin, municipality, barangay, days, range]);

  const { data, loading, error, stale, refresh } = useOperationalArea(token, query, { pollMs: POLL_MS });

  const selectTab = useCallback((key: string) => setTab(key as TabKey), []);

  const chooseDays = useCallback((d: number) => {
    setRange(null);                 // a preset replaces a chosen range
    setDays(d);
    try { localStorage.setItem(DAYS_KEY, String(d)); } catch { /* private window — the choice still applies now */ }
  }, []);

  const chooseRange = useCallback((r: Range) => setRange(r), []);

  const chooseMunicipality = useCallback((m: string) => {
    setMunicipality(m);
    setBarangay(null);              // a barangay belongs to one municipality
    // Picking a municipality on the Compare table means "open it". Go through
    // selectTab, not just setTab, so the address follows: a reload must not
    // reopen the comparison the reader just left.
    if (tab === 'compare') selectTab('overview');
  }, [tab, selectTab]);

  if (!token) return null;
  if (!isProvincialAdmin && !isAgencyAdmin) {
    return (
      <div className="px-6 py-5 md:px-7">
        <Alert variant="error" message="The operational area is only available to Agency Admins and Provincial Admins." />
      </div>
    );
  }

  const warnings = data ? data.readiness.filter(c => c.status === 'warn').length : 0;
  const tabs: AreaTabItem[] = [
    {
      key: 'overview', label: 'Overview', icon: LayoutDashboard,
      hint: 'Headline figures, the trend and whether the area is ready',
      attention: warnings,
      title: warnings ? `${warnings} readiness check${warnings === 1 ? '' : 's'} need attention` : undefined,
    },
    { key: 'map', label: 'Map', icon: MapIcon, hint: 'Stations, crew and reports on the map' },
    { key: 'barangays', label: 'Barangays', icon: MapPin, hint: 'Every barangay: who lives there and what was reported' },
    { key: 'response', label: 'Response', icon: Gauge, hint: 'How fast the area is answered, against the targets' },
    { key: 'stations', label: 'Stations & crew', icon: Building2, hint: 'The stations here and the responders who staff them' },
    { key: 'agencies', label: 'Agencies', icon: Handshake, hint: 'Who else covers this area, and how to reach them' },
    ...(isProvincialAdmin ? [{ key: 'compare', label: 'Compare', icon: BarChart3, hint: 'Every municipality side by side' } as AreaTabItem] : []),
  ];

  return (
    <div className="mx-auto flex w-full max-w-[1440px] flex-col gap-4 px-6 py-5 md:px-7">
      <AreaHeader
        activeTab={tab}
        agencyType={agencyType}
        barangay={barangay}
        data={data}
        days={days}
        isProvincial={isProvincialAdmin}
        stale={stale}
        municipalities={municipalities.map(m => m.name)}
        municipality={municipality}
        onBarangay={setBarangay}
        onDays={chooseDays}
        onRange={chooseRange}
        range={range}
        onExport={() => data && downloadCsv(areaCsvName(data), buildAreaCsv(data))}
        onMunicipality={chooseMunicipality}
        onTab={selectTab}
        tabs={tabs}
      />

      {(error || listError) && (
        <div className="flex flex-wrap items-center gap-3">
          <div className="min-w-0 flex-1"><Alert variant="error" message={error ?? listError ?? ''} /></div>
          <Button onClick={refresh} size="sm" type="button" variant="outline">
            <RefreshCw className="size-3.5" /> Try again
          </Button>
        </div>
      )}

      <div aria-labelledby={areaTabId(tab)} id={AREA_PANEL_ID} role="tabpanel">
        {!data ? (
          error ? null : <LoadingShell />
        ) : (
          // The previous figures stay put, dimmed, while a new period loads.
          <div aria-busy={loading} className={loading ? 'opacity-60 transition-opacity' : 'transition-opacity'}>
            {tab === 'overview' && <OverviewTab data={data} onOpenIncident={setOpenId} onTab={selectTab} />}
            {tab === 'map' && <MapTab data={data} onOpenIncident={setOpenId} />}
            {tab === 'barangays' && <BarangaysTab data={data} focused={barangay} onFocus={setBarangay} />}
            {tab === 'response' && <ResponseTab data={data} />}
            {tab === 'stations' && <CrewTab data={data} onTab={selectTab} />}
            {tab === 'agencies' && <AgenciesTab data={data} token={token} />}
            {tab === 'compare' && isProvincialAdmin && data.comparison && (
              <CompareTab filters={data.filters} onSelect={chooseMunicipality} rows={data.comparison} selected={municipality} />
            )}
          </div>
        )}
      </div>

      <IncidentDetailModal incidentId={openId} onClose={() => setOpenId(null)} />
    </div>
  );
}

function LoadingShell() {
  return (
    <div aria-busy="true" aria-label="Loading the operational area" className="flex flex-col gap-4" role="status">
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => <Skeleton className="h-[128px] rounded-[var(--radius-card)]" key={i} />)}
      </div>
      <div className="grid grid-cols-1 gap-4 xl:grid-cols-3">
        <Skeleton className="h-[340px] rounded-[var(--radius-card)] xl:col-span-2" />
        <Skeleton className="h-[340px] rounded-[var(--radius-card)]" />
      </div>
    </div>
  );
}
