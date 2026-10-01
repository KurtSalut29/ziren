'use client';

/**
 * Agencies — Agency Management (spec Section 6), grown out of the retired
 * Coverage Areas page rather than rewritten from scratch.
 *
 * ONE POLYGON PER AGENCY. Not per station. `PATCH /stations/{id}/coverage`
 * takes a station only as an entry point and writes `agencies.coverage_area`
 * (see the endpoint's own docstring), so every station in an agency shares one
 * boundary and always will. That is still true here — the boundary editor
 * below is unchanged from the old Coverage Areas page.
 *
 * What is NEW relative to that page, per the spec's Agency Management module:
 *   - Deactivated stations are listed too (with Reactivate), not just
 *     silently dropped — GET /stations/ used to filter is_active=True
 *     unconditionally, so a deactivated station had no way back except a
 *     direct database edit.
 *   - A station's recent activity (incident count, last 30 days) — a
 *     lightweight summary from the same /dispatch/history data the
 *     dashboard already fetches elsewhere, filtered client-side by agency.
 *
 * Deliberately does NOT show or manage Agency Admin accounts — that used to
 * live here too (who runs each agency, an inline invite form), but it was
 * also the Accounts page's job, and having the same account information
 * editable from two places was confusing rather than convenient. Accounts
 * is now the single place for all Agency Admin account management; this
 * page is purely stations, boundaries, and geolocation.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle, Building2, CheckCircle2, Copy, Crosshair, LandPlot,
  MapPin, Pencil, Plus, RotateCcw, Save, Trash2, X,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import { updateStationLocation } from '@/lib/api/platform';
import { StationLocationPicker, type PickedPoint } from '@/components/map/station-location-picker';
import { Alert } from '@/components/ui/alert';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { Fig } from '@/components/ui/fig';
import { Button } from '@/components/efferd/ui/button';
import { Textarea } from '@/components/efferd/ui/textarea';
import { Label } from '@/components/efferd/ui/label';
import { Input } from '@/components/efferd/ui/input';
import { Skeleton } from '@/components/efferd/ui/skeleton';
import {
  Card, CardContent,
} from '@/components/efferd/ui/card';
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader,
  DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { useNotice } from '@/lib/toast';

import { DemoTarget } from '@/components/help/demo-target';
// ── Types ─────────────────────────────────────────────────────

/**
 * What PostgREST actually returns for a PostGIS geometry column.
 *
 * A GeoJSON object — verified against the live database, where every one of
 * the twelve agency rows comes back as
 * `{type: 'Polygon', crs: {...}, coordinates: [[[lng, lat], …]]}`.
 *
 * The string branch is kept only because a PostgREST configuration change
 * could switch the representation back to WKT, and a boundary editor is the
 * last place that should fail silently.
 */
type CoverageGeometry =
  | { type: string; coordinates: number[][][] }
  | string
  | null;

interface AgencyInfo {
  id: string;
  name: string;
  agency_type: string;
  municipality: string;
  coverage_area: CoverageGeometry;
}

interface Station {
  id: string;
  name: string;
  address: string | null;
  agency_id: string;
  is_active: boolean;
  has_coverage: boolean;
  agencies: AgencyInfo | null;
  /** GeoJSON Point, or null for a station nobody has placed yet. */
  location?: { type: string; coordinates: number[] } | null;
}

interface HistoryIncident {
  // /dispatch/history joins the agency through stations, not a flat
  // assigned_agency_id column (that's a raw DB column the endpoint's own
  // SELECT deliberately omits — see get_incident_history's comment on why
  // suggested_severity-shaped columns aren't selected directly). Matched
  // back to a group by agency NAME below, the same key agencyNameById
  // already uses elsewhere on this page.
  stations: { agencies: { name: string } | null } | null;
}

/** Pull [lat, lng] out of the PostGIS point, in the order humans read it. */
function pointOf(s: Station): { lat: number; lng: number } | null {
  const c = s.location?.coordinates;
  // GeoJSON is [lng, lat]. Reading it the other way round puts every station
  // in Biliran somewhere off the coast of Somalia.
  return c && c.length >= 2 ? { lat: c[1], lng: c[0] } : null;
}

interface AgencyGroup {
  agency: AgencyInfo;
  stations: Station[];
  inactiveStations: Station[];
}

type LngLat = [number, number];

// ── Geometry ──────────────────────────────────────────────────

/**
 * Read the stored boundary into a coordinate ring, whatever shape it arrives
 * in, with the closing point dropped.
 *
 * Dropping it is deliberate: the ring is closed, so the last pair repeats the
 * first, and showing that repeat in an editable list invites someone to
 * "correct" it. The backend re-closes whatever it is sent.
 *
 * Returns null — distinct from an empty array — when the value is present but
 * in a form this function does not understand. The caller MUST treat that as
 * "unknown", never as "empty".
 */
function readRing(geom: CoverageGeometry): LngLat[] | null {
  if (geom === null || geom === undefined) return [];

  if (typeof geom === 'object' && Array.isArray(geom.coordinates)) {
    const ring = geom.coordinates[0];
    if (!Array.isArray(ring) || ring.length === 0) return [];
    const pairs = ring
      .filter(p => Array.isArray(p) && p.length >= 2)
      .map(p => [p[0], p[1]] as LngLat);
    if (pairs.length === 0) return null;
    const [first] = pairs;
    const last = pairs[pairs.length - 1];
    const closed =
      pairs.length > 1 && first[0] === last[0] && first[1] === last[1];
    return closed ? pairs.slice(0, -1) : pairs;
  }

  if (typeof geom === 'string') {
    if (!geom.trim()) return [];
    const match = geom.match(/POLYGON\s*\(\(([^)]+)\)\)/i);
    if (!match) return null;   // e.g. hex EWKB, MULTIPOLYGON, a ring with holes
    const pairs: LngLat[] = [];
    for (const part of match[1].split(',')) {
      const [lng, lat] = part.trim().split(/\s+/).map(Number);
      if (!Number.isFinite(lng) || !Number.isFinite(lat)) return null;
      pairs.push([lng, lat]);
    }
    if (pairs.length === 0) return null;
    const [first] = pairs;
    const last = pairs[pairs.length - 1];
    const closed =
      pairs.length > 1 && first[0] === last[0] && first[1] === last[1];
    return closed ? pairs.slice(0, -1) : pairs;
  }

  return null;
}

const ringToText = (ring: LngLat[]) =>
  ring.map(([lng, lat]) => `${lng}, ${lat}`).join('\n');

interface ParseResult {
  coords: LngLat[] | null;
  /** Why it failed, in the operator's terms. Null when it parsed. */
  problem: string | null;
}

/** Parse the textarea. One [lng, lat] pair per line. */
function parseCoordText(text: string): ParseResult {
  const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
  if (lines.length === 0) {
    return { coords: null, problem: 'No coordinates entered.' };
  }
  const coords: LngLat[] = [];
  for (const [i, line] of lines.entries()) {
    const parts = line.split(/[\s,]+/).filter(Boolean);
    const lng = Number(parts[0]);
    const lat = Number(parts[1]);
    if (parts.length < 2 || !Number.isFinite(lng) || !Number.isFinite(lat)) {
      return {
        coords: null,
        problem: `Line ${i + 1} is not a "longitude, latitude" pair.`,
      };
    }
    if (lng < -180 || lng > 180) {
      return { coords: null, problem: `Line ${i + 1}: longitude ${lng} is outside ±180.` };
    }
    if (lat < -90 || lat > 90) {
      return { coords: null, problem: `Line ${i + 1}: latitude ${lat} is outside ±90 — longitude and latitude may be swapped.` };
    }
    coords.push([lng, lat]);
  }
  if (coords.length < 3) {
    return {
      coords: null,
      problem: `A boundary needs at least 3 points — ${coords.length} entered.`,
    };
  }
  return { coords, problem: null };
}

// ── Page ──────────────────────────────────────────────────────

const AGENCY_COLOR: Record<string, string> = {
  BFP:    'var(--color-agency-bfp)',
  PNP:    'var(--color-agency-pnp)',
  MDRRMO: 'var(--color-agency-mdrrmo)',
};

export default function AgenciesPage() {
  const { token, isProvincialAdmin } = useAuth();
  const [stations, setStations] = useState<Station[]>([]);
  const [history, setHistory] = useState<HistoryIncident[]>([]);
  const [loading, setLoading]   = useState(true);
  const [error, setError]       = useState<string | null>(null);
  const setNotice = useNotice();

  const load = useCallback(async () => {
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      const [stationRows, historyPage] = await Promise.all([
        apiClient.get<Station[]>(
          isProvincialAdmin ? '/stations/?include_inactive=true' : '/stations/', token,
        ),
        // 30-day activity summary. Best-effort: a dispatcher's console does
        // not need to fail to load over a chart figure that couldn't be read.
        apiClient
          .get<{ items: HistoryIncident[]; total: number }>('/dispatch/history?days=30&limit=100', token)
          .catch(() => ({ items: [], total: 0 })),
      ]);
      setStations(stationRows);
      setHistory(historyPage.items);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load stations.');
    } finally {
      setLoading(false);
    }
  }, [token, isProvincialAdmin]);

  useEffect(() => { void load(); }, [load]);

  const groups = useMemo<AgencyGroup[]>(() => {
    const byAgency = new Map<string, AgencyGroup>();
    for (const s of stations) {
      if (!s.agencies) continue;
      const existing = byAgency.get(s.agency_id);
      const target = existing ?? { agency: s.agencies, stations: [], inactiveStations: [] };
      if (s.is_active) target.stations.push(s); else target.inactiveStations.push(s);
      if (!existing) byAgency.set(s.agency_id, target);
    }
    return [...byAgency.values()];
  }, [stations]);

  // Keyed by agency NAME, not id — see the HistoryIncident comment above for
  // why the history endpoint doesn't hand back a raw agency id to key on.
  const activityByAgency = useMemo(() => {
    const counts = new Map<string, number>();
    for (const inc of history) {
      const name = inc.stations?.agencies?.name;
      if (!name) continue;
      counts.set(name, (counts.get(name) ?? 0) + 1);
    }
    return counts;
  }, [history]);

  /**
   * Which agencies are drawing the exact same shape as someone else.
   *
   * Every municipality was seeded with one rectangle shared by its BFP, PNP
   * and MDRRMO — byte-identical geometry on three separate records. Keyed on
   * the rounded ring rather than the raw object: two boundaries differing in
   * the last decimal place are the same boundary for this purpose.
   */
  const sharedShapes = useMemo(() => {
    const byShape = new Map<string, string[]>();
    for (const g of groups) {
      const ring = readRing(g.agency.coverage_area);
      if (!ring || ring.length === 0) continue;
      const key = ring
        .map(([lng, lat]) => `${lng.toFixed(5)},${lat.toFixed(5)}`)
        .join(';');
      const owners = byShape.get(key);
      if (owners) owners.push(g.agency.id);
      else byShape.set(key, [g.agency.id]);
    }
    const out = new Map<string, string[]>();
    for (const owners of byShape.values()) {
      if (owners.length < 2) continue;
      for (const id of owners) {
        out.set(id, owners.filter(o => o !== id));
      }
    }
    return out;
  }, [groups]);

  const agencyNameById = useMemo(
    () => new Map(groups.map(g => [g.agency.id, `${g.agency.agency_type} ${g.agency.municipality}`])),
    [groups],
  );

  const drawn = groups.filter(g => g.agency.coverage_area != null).length;
  const stationsUncovered = groups.reduce(
    (n, g) => n + g.stations.filter(s => !s.has_coverage).length, 0,
  );

  return (
    <div className="flex flex-col gap-4 px-6 py-5 md:px-7">
      {error  && <Alert variant="error" message={error} />}

      <DemoTarget id="agn:stats"><StatStrip>
        <StatCell
          bg="var(--color-brand-subtle)"
          color="var(--color-brand)"
          icon={<Building2 size={12} strokeWidth={2} />}
          label="Agencies"
          trend={`${stations.filter(s => s.is_active).length} active station${stations.length === 1 ? '' : 's'}`}
          value={groups.length}
        />
        <StatCell
          bg="var(--color-system-success-bg)"
          color="var(--color-system-success)"
          icon={<LandPlot size={12} strokeWidth={2} />}
          label="Boundaries drawn"
          riseIsBad={false}
          trend="routing enforced"
          value={drawn}
          whole={groups.length}
          wholeLabel="agencies"
        />
        <StatCell
          bg={stationsUncovered > 0 ? 'var(--color-system-warning-bg)' : 'var(--color-system-success-bg)'}
          color={stationsUncovered > 0 ? 'var(--color-system-warning)' : 'var(--color-system-success)'}
          icon={<AlertTriangle size={12} strokeWidth={2} />}
          label="Stations unbounded"
          trend={stationsUncovered > 0 ? 'accepting reports unchecked' : 'every station bounded'}
          value={stationsUncovered}
          whole={stations.filter(s => s.is_active).length}
          wholeLabel="stations"
        />
      </StatStrip></DemoTarget>

      <div className="flex items-start gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-4 py-3">
        <AlertTriangle className="mt-0.5 size-4 shrink-0 text-[var(--color-system-warning)]" />
        <p className="text-meta leading-relaxed text-[var(--color-text-secondary)]">
          <span className="font-semibold">Coverage checks fail open.</span>{' '}
          An agency with no boundary is treated as covering{' '}
          <span className="font-semibold">everywhere</span> — reports from
          outside its jurisdiction are accepted without a warning rather than
          rejected. Drawing a boundary is what makes the check mean anything.
        </p>
      </div>

      {loading && stations.length === 0 ? (
        <div className="flex flex-col gap-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <Skeleton className="h-40 rounded-[var(--radius-card)]" key={i} />
          ))}
        </div>
      ) : groups.length === 0 ? (
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-14 text-center">
            <MapPin className="size-8 text-muted-foreground" />
            <p className="text-[15px] font-semibold text-foreground">
              No stations on file
            </p>
            <p className="max-w-sm text-meta text-muted-foreground">
              An agency reaches this page through its stations. Add a station first.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div data-demo="agn:list" className="grid grid-cols-1 items-start gap-4 xl:grid-cols-2">
          {groups.map(group => (
            <AgencyCard
              activityCount={activityByAgency.get(group.agency.name) ?? 0}
              canManageStations={isProvincialAdmin}
              group={group}
              key={group.agency.id}
              onError={text => setNotice({ type: 'error', text })}
              onSuccess={text => { setNotice({ type: 'success', text }); void load(); }}
              sharedWith={(sharedShapes.get(group.agency.id) ?? []).map(
                id => agencyNameById.get(id) ?? id,
              )}
              token={token!}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ── One agency, one boundary ──────────────────────────────────

function AgencyCard({
  group,
  token,
  canManageStations,
  sharedWith,
  activityCount,
  onSuccess,
  onError,
}: {
  group: AgencyGroup;
  token: string;
  /** Provincial Admin only — station create/deactivate/activate all require it. */
  canManageStations: boolean;
  /** Other agencies whose boundary is geometrically identical to this one. */
  sharedWith: string[];
  /** Incidents assigned to this agency in the last 30 days. */
  activityCount: number;
  onSuccess: (msg: string) => void;
  onError: (msg: string) => void;
}) {
  const { agency, stations, inactiveStations } = group;
  const accent = AGENCY_COLOR[agency.agency_type] ?? 'var(--color-brand)';

  const shortName = agency.name.startsWith(agency.agency_type + ' ')
    ? agency.name.slice(agency.agency_type.length + 1)
    : agency.name;

  const stored = useMemo(() => readRing(agency.coverage_area), [agency.coverage_area]);
  const hasBoundary = agency.coverage_area != null;
  const unreadable = hasBoundary && stored === null;

  const [editing, setEditing] = useState(false);
  const [saving, setSaving]   = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [text, setText] = useState(() => ringToText(stored ?? []));

  const parsed = parseCoordText(text);
  const dirty = text.trim() !== ringToText(stored ?? []).trim();

  // Any active station will do — the endpoint resolves the agency from it and
  // writes the agency row. A brand-new agency with zero stations can never
  // reach this card (groups are built out of stations), so this is safe as
  // long as at least one station is active; falls back to any station
  // (including inactive) so the boundary stays editable even mid-transition.
  const entryStationId = (stations[0] ?? inactiveStations[0])?.id;

  function openEditor() {
    setText(ringToText(stored ?? []));
    setEditing(true);
  }

  async function save() {
    if (!parsed.coords) {
      onError(parsed.problem ?? 'Enter at least 3 coordinate pairs before saving.');
      return;
    }
    setSaving(true);
    try {
      await apiClient.patch(
        `/stations/${entryStationId}/coverage`,
        { coordinates: parsed.coords },
        token,
      );
      onSuccess(`Boundary saved for ${agency.name} — ${parsed.coords.length} points.`);
      setEditing(false);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Failed to save the boundary.');
    } finally {
      setSaving(false);
    }
  }

  async function clear() {
    setSaving(true);
    try {
      await apiClient.patch(
        `/stations/${entryStationId}/coverage`,
        { coordinates: null },
        token,
      );
      setText('');
      onSuccess(`Boundary cleared for ${agency.name}. Its reports now fail open.`);
      setEditing(false);
      setConfirmClear(false);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Failed to clear the boundary.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Card className="gap-0 py-0">
      {/* ── Who this is ─────────────────────────────────────────────
          One row: the agency's own mark, its name and place, and — on the
          right, where actions always live on this page — its boundary state
          and the button that edits it. */}
      <div className="flex flex-wrap items-start gap-x-3.5 gap-y-3 px-5 py-4">
        <span
          aria-hidden="true"
          className="flex size-11 shrink-0 items-center justify-center rounded-xl"
          style={{ backgroundColor: `color-mix(in srgb, ${accent} 12%, transparent)`, color: accent }}
        >
          <Building2 className="size-5" />
        </span>
        <div className="min-w-0 flex-1 basis-[180px]">
          <h2 className="flex flex-wrap items-center gap-2 text-[16px] font-semibold leading-tight tracking-tight text-foreground">
            <span className="truncate">{shortName}</span>
            <span
              className="rounded-md px-1.5 py-0.5 text-[11px] font-bold tracking-wide"
              style={{ backgroundColor: `color-mix(in srgb, ${accent} 12%, transparent)`, color: accent }}
            >
              {agency.agency_type}
            </span>
          </h2>
          <p className="mt-1.5 flex flex-wrap items-center gap-x-2.5 gap-y-1.5 text-[13px] text-muted-foreground">
            <span className="inline-flex items-center gap-1.5">
              <MapPin aria-hidden="true" className="size-3.5 shrink-0" />
              {agency.municipality}
            </span>
            <BoundaryBadge
              points={stored?.length ?? 0}
              state={unreadable ? 'unreadable' : hasBoundary ? 'drawn' : 'none'}
            />
          </p>
        </div>
        {!editing && (
          <Button
            className="shrink-0"
            disabled={unreadable}
            onClick={openEditor}
            size="sm"
            variant="outline"
          >
            <Pencil data-icon="inline-start" />
            {hasBoundary ? 'Edit boundary' : 'Draw boundary'}
          </Button>
        )}
      </div>

      {/* ── The three numbers worth a glance ────────────────────── */}
      <dl className="grid grid-cols-3 divide-x divide-[var(--color-surface-border)] border-y border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/60">
        <Stat label="Active stations" value={String(stations.length)} />
        <Stat label="Reports · 30 days" value={String(activityCount)} />
        <Stat label="Boundary" value={hasBoundary ? `${stored?.length ?? 0} points` : 'None'} />
      </dl>

      <div className="flex flex-col gap-4 px-5 py-4">
        {sharedWith.length > 0 && (
          <p className="flex flex-wrap items-center gap-1.5 rounded-[var(--radius-md)] bg-[var(--color-surface-raised)] px-3 py-2 text-meta text-[var(--color-text-secondary)]">
            <Copy aria-hidden="true" className="size-3.5 shrink-0" />
            <span>
              The same shape as{' '}
              <span className="font-semibold">{sharedWith.join(' and ')}</span>.
              Editing this one leaves those unchanged — draw a different
              boundary here to separate them.
            </span>
          </p>
        )}

        <StationList
          agency={agency}
          canManage={canManageStations}
          inactiveStations={inactiveStations}
          onError={onError}
          onSuccess={onSuccess}
          stations={stations}
          token={token}
        />

        {unreadable && (
          <Alert
            variant="error"
            message={
              `${agency.name} has a boundary stored in a format this editor cannot read, ` +
              'so it is shown read-only rather than risk overwriting it. The map still ' +
              'renders it correctly. Report this — the geometry is likely a multipolygon ' +
              'or has an interior ring.'
            }
          />
        )}

        {editing ? (
          <div className="flex flex-col gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-4">
            <div className="flex flex-col gap-1">
              <label
                className="text-meta font-semibold text-foreground"
                htmlFor={`ring-${agency.id}`}
              >
                Boundary points
              </label>
              <p className="text-meta leading-relaxed text-muted-foreground">
                One pair per line as{' '}
                <span className="rounded bg-[var(--color-surface-card)] px-1 font-mono text-[11px]">
                  longitude, latitude
                </span>{' '}
                — longitude first, the GeoJSON order. At least 3 points; the
                ring closes itself, so do not repeat the first point.
              </p>
            </div>

            <Textarea
              aria-invalid={text.trim().length > 0 && !parsed.coords}
              className="bg-[var(--color-surface-card)] font-mono text-[12px]"
              id={`ring-${agency.id}`}
              onChange={e => setText(e.target.value)}
              placeholder={'124.38, 11.55\n124.46, 11.55\n124.46, 11.62\n124.38, 11.62'}
              rows={8}
              value={text}
            />

            <p
              className="text-meta"
              style={{
                color: parsed.coords
                  ? 'var(--color-system-success)'
                  : 'var(--color-system-error)',
              }}
            >
              {parsed.coords
                ? `${parsed.coords.length} points parsed — ready to save.`
                : parsed.problem}
            </p>

            <div className="flex flex-wrap items-center gap-2">
              <Button
                disabled={saving || !parsed.coords || !dirty}
                onClick={() => void save()}
                size="sm"
                variant={parsed.coords && dirty ? 'default' : 'outline'}
              >
                <Save data-icon="inline-start" />
                {saving ? 'Saving…' : 'Save boundary'}
              </Button>
              <Button
                disabled={saving}
                onClick={() => setEditing(false)}
                size="sm"
                variant="outline"
              >
                <X data-icon="inline-start" />
                Cancel
              </Button>
              {hasBoundary && (
                <Button
                  className="ml-auto text-[var(--color-severity-critical)]"
                  disabled={saving}
                  onClick={() => setConfirmClear(true)}
                  size="sm"
                  variant="ghost"
                >
                  <Trash2 data-icon="inline-start" />
                  Clear boundary
                </Button>
              )}
            </div>
          </div>
        ) : (
          <BoundarySummary ring={stored} />
        )}
      </div>

      <AlertDialog onOpenChange={setConfirmClear} open={confirmClear}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Clear the boundary for {agency.name}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              All {stations.length} station
              {stations.length === 1 ? '' : 's'} in this agency lose their
              jurisdiction check. Coverage fails open, so every report will be
              accepted as in-area until a new boundary is drawn. The{' '}
              {stored?.length ?? 0} stored points cannot be recovered.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={saving}>Keep it</AlertDialogCancel>
            <AlertDialogAction
              className="border bg-transparent hover:bg-[var(--color-severity-critical-bg)]"
              disabled={saving}
              onClick={e => { e.preventDefault(); void clear(); }}
              style={{
                borderColor: 'var(--color-severity-critical)',
                color: 'var(--color-severity-critical)',
              }}
            >
              {saving ? 'Clearing…' : 'Clear boundary'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </Card>
  );
}

// ── Read-only views ───────────────────────────────────────────

function BoundaryBadge({
  state,
  points,
}: {
  state: 'drawn' | 'none' | 'unreadable';
  points: number;
}) {
  const spec = {
    drawn: {
      icon: CheckCircle2,
      label: `${points} points`,
      color: 'var(--color-system-success)',
    },
    none: {
      icon: AlertTriangle,
      label: 'No boundary',
      color: 'var(--color-system-warning)',
    },
    unreadable: {
      icon: AlertTriangle,
      label: 'Unreadable geometry',
      color: 'var(--color-severity-critical)',
    },
  }[state];
  const Icon = spec.icon;
  return (
    <span
      className="flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={{
        backgroundColor: `color-mix(in srgb, ${spec.color} 12%, transparent)`,
        color: spec.color,
      }}
    >
      <Icon aria-hidden="true" className="size-3.5" />
      {spec.label}
    </span>
  );
}

function BoundarySummary({ ring }: { ring: LngLat[] | null }) {
  if (ring === null) return null;
  if (ring.length === 0) {
    return (
      <p className="text-meta text-muted-foreground">
        No boundary drawn. Every report reaching this agency is accepted
        without a coverage check.
      </p>
    );
  }
  const lngs = ring.map(p => p[0]);
  const lats = ring.map(p => p[1]);
  const box = (v: number) => v.toFixed(4);
  return (
    <p className="text-meta text-muted-foreground">
      Extent · longitude{' '}
      <Fig className="text-[12px] text-foreground">{box(Math.min(...lngs))} → {box(Math.max(...lngs))}</Fig>
      {' '}· latitude{' '}
      <Fig className="text-[12px] text-foreground">{box(Math.min(...lats))} → {box(Math.max(...lats))}</Fig>
    </p>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex flex-col gap-0.5 px-5 py-3">
      <dt className="text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
        {label}
      </dt>
      <dd>
        <Fig className="text-[15px] font-semibold text-foreground">{value}</Fig>
      </dd>
    </div>
  );
}

// ── Stations under a boundary ─────────────────────────────────

/**
 * The stations an agency's boundary governs, plus add/deactivate/reactivate
 * for a Provincial Admin.
 *
 * All three mutations are Provincial-Admin-only at the API, so an Agency
 * Admin sees the list and no controls rather than buttons that would 403.
 */
function StationList({
  stations,
  inactiveStations,
  agency,
  token,
  canManage,
  onSuccess,
  onError,
}: {
  stations: Station[];
  inactiveStations: Station[];
  agency: AgencyInfo;
  token: string;
  canManage: boolean;
  onSuccess: (msg: string) => void;
  onError: (msg: string) => void;
}) {
  const [adding, setAdding] = useState(false);
  const [locating, setLocating] = useState<Station | null>(null);
  const [confirmOff, setConfirmOff] = useState<Station | null>(null);
  const [showInactive, setShowInactive] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);

  async function deactivate() {
    if (!confirmOff) return;
    setBusy(confirmOff.id);
    try {
      await apiClient.patch(`/stations/${confirmOff.id}/deactivate`, {}, token);
      onSuccess(`${confirmOff.name} deactivated.`);
      setConfirmOff(null);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Deactivation failed.');
    } finally {
      setBusy(null);
    }
  }

  async function reactivate(s: Station) {
    setBusy(s.id);
    try {
      await apiClient.patch(`/stations/${s.id}/activate`, {}, token);
      onSuccess(`${s.name} reactivated.`);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Reactivation failed.');
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {/* Stations as one bordered list with its own header, so the heading,
          the "Add station" action and every row's actions line up in the same
          two places — the name on the left, the buttons on the right. */}
      <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)]">
        <div className="flex items-center gap-2 border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3 py-2">
          <h3 className="text-[11.5px] font-semibold tracking-wide text-[var(--color-text-tertiary)] uppercase">
            Stations
          </h3>
          <Fig className="text-[11.5px] text-muted-foreground">{stations.length}</Fig>
          {canManage && !adding && (
            <DemoTarget id="agn:add"><Button className="ml-auto" onClick={() => setAdding(true)} size="xs" variant="outline">
              <Plus data-icon="inline-start" />
              Add station
            </Button></DemoTarget>
          )}
        </div>

        {stations.length === 0 ? (
          <p className="px-3 py-4 text-meta text-muted-foreground">
            No active station. Reports routed to this agency have nowhere to land.
          </p>
        ) : (
          <ul className="divide-y divide-[var(--color-surface-border)]">
            {stations.map(s => (
              <li className="flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2.5" key={s.id}>
                <span
                  aria-hidden="true"
                  className="flex size-8 shrink-0 items-center justify-center rounded-lg"
                  style={{
                    backgroundColor: `color-mix(in srgb, ${pointOf(s) ? 'var(--color-system-success)' : 'var(--color-system-warning)'} 14%, transparent)`,
                    color: pointOf(s) ? 'var(--color-system-success)' : 'var(--color-system-warning)',
                  }}
                >
                  <MapPin className="size-4" />
                </span>
                <div className="min-w-0 flex-1 basis-[160px]">
                  <p className="truncate text-[13px] font-medium text-foreground">{s.name}</p>
                  <p className="truncate text-meta text-muted-foreground">
                    {s.address ?? 'No address on file'}
                    {!pointOf(s) && (
                      <span className="font-medium text-[var(--color-system-warning)]"> · Not on the map</span>
                    )}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-1.5">
                  <Button onClick={() => setLocating(s)} size="xs" variant="outline">
                    <Crosshair data-icon="inline-start" />
                    {pointOf(s) ? 'Move' : 'Set location'}
                  </Button>
                  {canManage && (
                    <Button
                      className="text-[var(--color-severity-critical)]"
                      onClick={() => setConfirmOff(s)}
                      size="xs"
                      variant="ghost"
                    >
                      <Trash2 data-icon="inline-start" />
                      Deactivate
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      {canManage && inactiveStations.length > 0 && (
        <div className="flex flex-col gap-1 rounded-[var(--radius-md)] bg-[var(--color-surface-raised)] p-2">
          <button
            className="flex items-center gap-1.5 text-meta font-semibold text-muted-foreground"
            onClick={() => setShowInactive(v => !v)}
            type="button"
          >
            {showInactive ? 'Hide' : 'Show'} {inactiveStations.length} deactivated station
            {inactiveStations.length === 1 ? '' : 's'}
          </button>
          {showInactive && (
            <ul className="flex flex-col gap-1">
              {inactiveStations.map(s => (
                <li
                  className="flex flex-wrap items-center gap-2 rounded-[var(--radius-md)] px-2 py-1.5 opacity-70"
                  key={s.id}
                >
                  <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
                  <span className="text-[13px] text-foreground">{s.name}</span>
                  {s.address && (
                    <span className="truncate text-meta text-muted-foreground">· {s.address}</span>
                  )}
                  <Button
                    className="ml-auto"
                    disabled={busy === s.id}
                    onClick={() => void reactivate(s)}
                    size="xs"
                    variant="outline"
                  >
                    <RotateCcw data-icon="inline-start" />
                    {busy === s.id ? 'Reactivating…' : 'Reactivate'}
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}

      {adding && (
        <NewStationForm
          agency={agency}
          onCancel={() => setAdding(false)}
          onError={onError}
          onSuccess={msg => { setAdding(false); onSuccess(msg); }}
          token={token}
        />
      )}

      <StationLocationDialog
        onClose={() => setLocating(null)}
        onSaved={msg => { setLocating(null); onSuccess(msg); }}
        onError={onError}
        station={locating}
        token={token}
      />

      <AlertDialog
        onOpenChange={open => { if (!open) setConfirmOff(null); }}
        open={confirmOff !== null}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Deactivate {confirmOff?.name}?</AlertDialogTitle>
            <AlertDialogDescription>
              It leaves the active roster and stops receiving reports. Incidents
              already assigned to it keep their assignment, and the record is
              kept rather than deleted — it can be reactivated from the
              deactivated-stations list on this card.
              {stations.length === 1 && (
                <>
                  {' '}
                  <strong>
                    This is the only active station in {agency.name}, so the
                    agency will have nowhere to route reports at all.
                  </strong>
                </>
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={busy !== null}>Keep it</AlertDialogCancel>
            <AlertDialogAction
              className="border bg-transparent hover:bg-[var(--color-severity-critical-bg)]"
              disabled={busy !== null}
              onClick={e => { e.preventDefault(); void deactivate(); }}
              style={{
                borderColor: 'var(--color-severity-critical)',
                color: 'var(--color-severity-critical)',
              }}
            >
              {busy === confirmOff?.id ? 'Deactivating…' : 'Deactivate'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

// ── New station ───────────────────────────────────────────────

function NewStationForm({
  agency,
  token,
  onSuccess,
  onCancel,
  onError,
}: {
  agency: AgencyInfo;
  token: string;
  onSuccess: (msg: string) => void;
  onCancel: () => void;
  onError: (msg: string) => void;
}) {
  const [form, setForm] = useState({ name: '', address: '', latitude: '', longitude: '' });
  const [saving, setSaving] = useState(false);

  const lat = form.latitude.trim();
  const lng = form.longitude.trim();
  const halfCoord = (lat === '') !== (lng === '');
  const badCoord =
    !halfCoord && lat !== '' && (
      !Number.isFinite(Number(lat)) || Number(lat) < -90 || Number(lat) > 90 ||
      !Number.isFinite(Number(lng)) || Number(lng) < -180 || Number(lng) > 180
    );

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (halfCoord) {
      onError('Enter both latitude and longitude, or leave both blank.');
      return;
    }
    if (badCoord) {
      onError('Latitude must be between -90 and 90, longitude between -180 and 180.');
      return;
    }
    setSaving(true);
    try {
      const payload: Record<string, unknown> = {
        agency_id: agency.id,
        name: form.name,
        address: form.address || null,
      };
      if (lat !== '' && lng !== '') {
        payload.latitude = Number(lat);
        payload.longitude = Number(lng);
      }
      await apiClient.post('/stations/', payload, token);
      onSuccess(`${form.name} added. It inherits the boundary drawn for ${agency.name}.`);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Failed to create the station.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <form
      className="flex flex-col gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] p-4"
      onSubmit={submit}
    >
      <div className="flex items-center justify-between">
        <h4 className="text-[13px] font-semibold text-foreground">
          New station under {agency.name}
        </h4>
        <Button aria-label="Cancel" onClick={onCancel} size="icon-sm" type="button" variant="ghost">
          <X />
        </Button>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <div className="flex flex-col gap-1.5 sm:col-span-2">
          <Label htmlFor={`st-name-${agency.id}`}>Station name</Label>
          <Input
            id={`st-name-${agency.id}`}
            onChange={e => setForm(f => ({ ...f, name: e.target.value }))}
            placeholder="e.g. Caraycaray Sub-Station"
            required
            value={form.name}
          />
        </div>
        <div className="flex flex-col gap-1.5 sm:col-span-2">
          <Label htmlFor={`st-addr-${agency.id}`}>Address (optional)</Label>
          <Input
            id={`st-addr-${agency.id}`}
            onChange={e => setForm(f => ({ ...f, address: e.target.value }))}
            placeholder="e.g. Brgy. Sabang, Naval, Biliran"
            value={form.address}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor={`st-lat-${agency.id}`}>Latitude (optional)</Label>
          <Input
            aria-invalid={halfCoord || badCoord}
            id={`st-lat-${agency.id}`}
            onChange={e => setForm(f => ({ ...f, latitude: e.target.value }))}
            placeholder="11.5836"
            step="any"
            type="number"
            value={form.latitude}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor={`st-lng-${agency.id}`}>Longitude (optional)</Label>
          <Input
            aria-invalid={halfCoord || badCoord}
            id={`st-lng-${agency.id}`}
            onChange={e => setForm(f => ({ ...f, longitude: e.target.value }))}
            placeholder="124.4063"
            step="any"
            type="number"
            value={form.longitude}
          />
        </div>
      </div>

      {halfCoord && (
        <p className="text-meta text-[var(--color-system-error)]">
          Enter both latitude and longitude, or leave both blank — half a
          coordinate would be saved as no coordinate.
        </p>
      )}

      <div className="flex justify-end gap-2">
        <Button onClick={onCancel} size="sm" type="button" variant="outline">
          Cancel
        </Button>
        <Button
          disabled={saving || halfCoord || badCoord || !form.name.trim()}
          size="sm"
          type="submit"
        >
          <Plus data-icon="inline-start" />
          {saving ? 'Creating…' : 'Create station'}
        </Button>
      </div>
    </form>
  );
}

// ── Station location dialog ───────────────────────────────────

function StationLocationDialog({
  station,
  token,
  onSaved,
  onClose,
  onError,
}: {
  station: Station | null;
  token: string;
  onSaved: (msg: string) => void;
  onClose: () => void;
  onError: (msg: string) => void;
}) {
  const [picked, setPicked] = useState<PickedPoint | null>(null);
  const [saving, setSaving] = useState(false);

  const current = station ? pointOf(station) : null;
  const moved =
    picked !== null &&
    (!current ||
      Math.abs(picked.lat - current.lat) > 1e-7 ||
      Math.abs(picked.lng - current.lng) > 1e-7);

  async function save() {
    if (!station || !picked) return;
    setSaving(true);
    try {
      await updateStationLocation(token, station.id, {
        latitude: picked.lat,
        longitude: picked.lng,
      });
      onSaved(`${station.name} moved to ${picked.lat.toFixed(5)}, ${picked.lng.toFixed(5)}.`);
    } catch (e: unknown) {
      onError(e instanceof Error ? e.message : 'Could not save the location.');
    } finally {
      setSaving(false);
    }
  }

  return (
    <Dialog onOpenChange={open => { if (!open) onClose(); }} open={station !== null}>
      <DialogContent className="flex max-h-[90vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[680px]">
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] px-6 py-4 text-left">
          <DialogTitle>Where is {station?.name}?</DialogTitle>
          <DialogDescription>
            This is the point the Incident Map pins and the address a dispatcher
            reads. It is not the coverage boundary — that is drawn per agency
            on the card behind this.
          </DialogDescription>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-y-auto px-6 py-4">
          {station && (
            <StationLocationPicker
              agencyType={station.agencies?.agency_type ?? null}
              initial={current}
              key={station.id}
              onChange={setPicked}
            />
          )}
        </div>

        <DialogFooter className="mb-0 shrink-0 flex-wrap gap-2 border-t border-[var(--color-surface-border)] px-6 py-3">
          <Button disabled={saving} onClick={onClose} size="sm" variant="outline">
            Cancel
          </Button>
          <Button disabled={saving || !moved} size="sm" onClick={() => void save()}>
            <Save data-icon="inline-start" />
            {saving ? 'Saving…' : moved ? 'Save location' : 'Pin has not moved'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
