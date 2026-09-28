'use client';

/**
 * Provincial Admin — Accounts
 *
 * Three tabs: access requests awaiting a decision, Agency Admin management,
 * and the directory — both now scoped server-side to the Provincial Admin's
 * own agency_type rather than every agency. Requests lead because they are
 * the only tab with work waiting on a person, which is also what the page's
 * status line reports.
 */

import { Fragment, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Building2, Check, ChevronRight, Inbox, Loader2, MapPin, Plus, Shield, UserCheck, UserCog,
  UserRound, Users, UserX, X,
} from 'lucide-react';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { ApiError, apiClient } from '@/lib/api/client';
import {
  Select, SelectContent, SelectGroup, SelectItem, SelectLabel, SelectTrigger,
  SelectValue,
} from '@/components/efferd/ui/select';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Button } from '@/components/ui/button';
import { Alert } from '@/components/ui/alert';
import { AccessRequestsTab } from '@/components/accounts/access-requests-tab';
import { Input } from '@/components/ui/input';
import { Fig } from '@/components/ui/fig';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { NavTabs } from '@/components/ui/nav-tabs';
import {
  DataGroupRow, DataHead, DataRow, DataTableFrame, DataTd, DataTh, Initials, StatusChip,
} from '@/components/ui/data-table';
import { AgencyChip } from '@/components/operational-area/kit';
import { OptionPicker } from '@/components/ui/option-picker';
import { SearchInput } from '@/components/ui/search-input';
import { AG_COLOR } from '@/components/incidents/incident-vocabulary';
import { TableEmptyState } from '@/components/ui/table';
import { useNotice } from '@/lib/toast';

// ── Types ─────────────────────────────────────────────────────

interface AgencyInfo { name: string; agency_type: string; municipality: string; }

interface AgencyAdminUser {
  id: string; email: string; full_name: string; agency_id: string | null;
  is_verified: boolean; approval_status: string; created_at: string;
  agencies: AgencyInfo | null;
}

interface DirectoryUser {
  id: string; email: string; full_name: string; role: string;
  agency_id: string | null; approval_status: string; availability: string | null;
  is_verified: boolean; created_at: string; agencies: AgencyInfo | null;
  /** A resident's own address. Staff accounts usually have neither. */
  municipality_address: string | null;
  barangay: string | null;
  purok_sitio: string | null;
}

interface BarangayRef { name: string; municipality: string; psgc_code: string | null; }

/** Shown when an account records no place at all. Never hidden — see below. */
const NO_PLACE = 'No address on file';

/**
 * Distinct from NO_PLACE, and the distinction matters.
 *
 * Inside a municipality, every row has an address — it just may not go down to
 * the barangay. Filing those under "No address on file" would say the account
 * is unreachable when what is actually true is that the address is incomplete,
 * and those are different problems with different fixes.
 */
const NO_BARANGAY = 'Barangay not recorded';

/**
 * Where an account is, and how confidently we know it.
 *
 * A resident carries their own address. A responder or agency admin usually
 * does not, and the nearest true thing is the municipality their AGENCY sits
 * in — which is a different claim, so it is labelled as one rather than
 * quietly written into the same column. Merging them would let the directory
 * assert that a BFP responder lives in Naval when all that is known is where
 * they work.
 */
function placeOf(u: DirectoryUser): {
  municipality: string | null;
  barangay: string | null;
  viaAgency: boolean;
} {
  if (u.municipality_address) {
    return { municipality: u.municipality_address, barangay: u.barangay, viaAgency: false };
  }
  const agencyMuni = u.agencies?.municipality ?? null;
  return { municipality: agencyMuni, barangay: null, viaAgency: Boolean(agencyMuni) };
}

interface AgencyOption { id: string; name: string; agency_type: string; municipality: string; }

/** Shared agency picker options — one per agency, tinted by its own hue and
 * subtitled by municipality so two same-type agencies stay tellable apart. */
function agencyOptions(agencies: AgencyOption[]) {
  return agencies.map(a => ({
    value: a.id,
    label: `${a.agency_type} — ${a.name}`,
    hint: a.municipality,
    icon: Building2,
    color: AG_COLOR[a.agency_type] ?? 'var(--color-brand)',
  }));
}

type Tab = 'access_requests' | 'agency_admins' | 'directory';

// The frame around every table on this page — the same card the Operational
// Area's tables sit in.
const TABLE_CARD =
  'overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] ' +
  'bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]';

// ── Page ──────────────────────────────────────────────────────

export default function AccountsPage() {
  const { token, isProvincialAdmin } = useAuth();
  // Requests default first: they are the only tab with work waiting on a
  // person, and they were previously invisible entirely. But that count is
  // only known once AccessRequestsTab itself reports it below, so a quiet
  // day landed every visit on an empty inbox with the real directory of 4
  // accounts one click away and no hint it was there. The redirect below
  // fires once, only away from an empty inbox — it never fights a click
  // back to Access requests once the page has settled.
  const [tab, setTab] = useState<Tab>('access_requests');
  const [pendingCount, setPendingCount] = useState<number | null>(null);
  const autoRedirected = useRef(false);

  useEffect(() => {
    if (autoRedirected.current) return;
    if (pendingCount === 0 && tab === 'access_requests') {
      autoRedirected.current = true;
      setTab('directory');
    } else if (pendingCount !== null) {
      autoRedirected.current = true;
    }
  }, [pendingCount, tab]);

  if (!isProvincialAdmin) {
    return (
      <div className="px-6 py-6 md:px-7">
        <Alert variant="error" message="This page is only accessible to Provincial Admins." />
      </div>
    );
  }

  const tabs = [
    { key: 'access_requests', label: 'Access requests', icon: Inbox, badge: pendingCount ?? undefined, hint: 'Agency admin requests waiting on a decision' },
    { key: 'agency_admins',   label: 'Agency admins',   icon: UserCog, hint: 'Create, reassign and deactivate agency admins' },
    { key: 'directory',       label: 'All accounts',    icon: Shield, hint: 'Every resident, responder and admin, by place' },
  ] as { key: Tab; label: string; icon: typeof Inbox; badge?: number; hint: string }[];

  return (
    <div className="min-h-full">
      {/* The view switcher — the same NavTabs every multi-view screen uses, so
          Accounts navigates like Geographic Overview does. The amber count on
          "Access requests" is the only status this bar needs: it used to be
          repeated in a sentence beside the tabs, saying the same thing twice. */}
      <div className="sticky top-0 z-30 bg-[var(--color-surface-card)]">
        <NavTabs
          activeKey={tab}
          ariaLabel="Account views"
          idPrefix="accounts-tab"
          onSelect={key => setTab(key as Tab)}
          tabs={tabs}
        />
      </div>

      {/* ── Tab content ────────────────────────────────────── */}
      <div className="px-6 py-5 md:px-7">
        {tab === 'access_requests' ? (
          <AccessRequestsTab token={token!} onCountChange={setPendingCount} />
        ) : tab === 'agency_admins' ? (
          <AgencyAdminsTab token={token!} />
        ) : (
          <DirectoryTab token={token!} />
        )}
      </div>
    </div>
  );
}

// ── Agency Admins tab ─────────────────────────────────────────

function AgencyAdminsTab({ token }: { token: string }) {
  const [admins, setAdmins]       = useState<AgencyAdminUser[]>([]);
  const [agencies, setAgencies]   = useState<AgencyOption[]>([]);
  const [loading, setLoading]     = useState(true);
  const [error, setError]         = useState<string | null>(null);
  const setActionMsg = useNotice();
  const [acting, setActing]       = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  // Deactivate is the one high-impact action here — it signs an admin out of
  // every future session until someone reactivates them. Reactivate is
  // restorative and low-stakes, so it stays a single click.
  const [confirmDeactivate, setConfirmDeactivate] = useState<AgencyAdminUser | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const [adminsData, agenciesData] = await Promise.all([
        apiClient.get<AgencyAdminUser[]>('/users/provincial/agency-admins', token),
        apiClient.get<AgencyOption[]>('/users/agencies-list', token),
      ]);
      setAdmins(adminsData);
      setAgencies(agenciesData);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load.');
    } finally { setLoading(false); }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  async function deactivate(id: string) {
    setActing(id); setActionMsg(null);
    try {
      await apiClient.patch(`/users/provincial/agency-admins/${id}`, { is_active: false }, token);
      setActionMsg({ type: 'success', text: 'Account deactivated.' });
      await load();
    } catch (e: unknown) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Action failed.' });
    } finally { setActing(null); }
  }

  async function reactivate(id: string) {
    setActing(id); setActionMsg(null);
    try {
      await apiClient.patch(`/users/provincial/agency-admins/${id}`, { is_active: true }, token);
      setActionMsg({ type: 'success', text: 'Account reactivated.' });
      await load();
    } catch (e: unknown) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Action failed.' });
    } finally { setActing(null); }
  }

  async function reassign(id: string, agencyId: string) {
    setActing(id); setActionMsg(null);
    try {
      await apiClient.patch(`/users/provincial/agency-admins/${id}`, { agency_id: agencyId }, token);
      setActionMsg({ type: 'success', text: 'Agency reassigned.' });
      await load();
    } catch (e: unknown) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Action failed.' });
    } finally { setActing(null); }
  }

  const active   = admins.filter(a => a.is_verified);
  const inactive = admins.filter(a => !a.is_verified);

  return (
    <div className="space-y-5">
      <StatStrip>
        <StatCell
          icon={<UserCog size={12} strokeWidth={2} />}
          label="Agency admins"
          value={admins.length}
          trend={`Across ${agencies.length} agenc${agencies.length === 1 ? 'y' : 'ies'}`}
          color="var(--color-brand)"
          bg="var(--color-brand-subtle)"
        />
        <StatCell
          icon={<UserCheck size={12} strokeWidth={2} />}
          label="Active"
          value={active.length}
          // riseIsBad false: more admins able to log in is the good direction.
          riseIsBad={false}
          trend="can sign in"
          color="var(--color-system-success)"
          bg="var(--color-system-success-bg)"
          whole={admins.length}
          wholeLabel="admins"
        />
        <StatCell
          icon={<UserX size={12} strokeWidth={2} />}
          label="Deactivated"
          value={inactive.length}
          trend="cannot sign in"
          color="var(--color-status-processing)"
          bg="var(--color-status-processing-bg)"
          whole={admins.length}
          wholeLabel="admins"
        />
      </StatStrip>

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-ui text-[var(--color-text-tertiary)]">
          <Fig className="text-[var(--color-text-primary)]">{admins.length}</Fig> agency admin
          {admins.length !== 1 ? 's' : ''} across all agencies
        </p>
        <Button variant="primary" size="sm" onClick={() => setShowCreate(true)}>
          <Plus className="mr-1 h-3.5 w-3.5" /> New agency admin
        </Button>
      </div>

      {error     && <Alert variant="error" message={error} />}

      {showCreate && (
        <CreateAgencyAdminForm
          agencies={agencies} token={token}
          onSuccess={() => { setShowCreate(false); load(); }}
          onCancel={() => setShowCreate(false)}
        />
      )}

      {loading && admins.length === 0 ? (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-6 w-6 animate-spin text-[var(--color-text-muted)]" />
        </div>
      ) : (
        <div className={TABLE_CARD}>
          {admins.length > 0 && (
            <DataTableFrame minWidth={980}>
              <DataHead>
                <DataTh>Admin</DataTh>
                <DataTh width="26%">Agency</DataTh>
                <DataTh width="128px">Status</DataTh>
                <DataTh width="120px">Joined</DataTh>
                <DataTh align="right" width="300px">Actions</DataTh>
              </DataHead>
              {([
                ['Active', 'var(--color-system-success)', active],
                ['Deactivated', 'var(--color-text-muted)', inactive],
              ] as const).map(([title, color, list]) => list.length > 0 && (
                <tbody key={title}>
                  <DataGroupRow colSpan={5}>
                    <span className="flex items-center gap-2">
                      <span aria-hidden="true" className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: color }} />
                      <span className="text-[11px] font-bold uppercase tracking-wide text-[var(--color-text-secondary)]">{title}</span>
                      <Fig className="text-[11.5px] text-[var(--color-text-muted)]">{list.length}</Fig>
                    </span>
                  </DataGroupRow>
                  {list.map(a => (
                    <AdminRow
                      acting={acting === a.id}
                      admin={a}
                      agencies={agencies}
                      key={a.id}
                      onDeactivate={a.is_verified ? () => setConfirmDeactivate(a) : undefined}
                      onReactivate={a.is_verified ? undefined : () => reactivate(a.id)}
                      onReassign={agencyId => reassign(a.id, agencyId)}
                    />
                  ))}
                </tbody>
              ))}
            </DataTableFrame>
          )}
          {admins.length === 0 && (
            <div className="flex flex-col items-center justify-center gap-2 py-16">
              <UserCog className="h-9 w-9 text-[var(--color-text-muted)]" />
              <p className="text-ui font-medium text-[var(--color-text-primary)]">No agency admins yet</p>
              <p className="text-meta text-[var(--color-text-muted)]">
                Create the first one with “New agency admin”.
              </p>
            </div>
          )}
        </div>
      )}

      <AlertDialog
        open={confirmDeactivate !== null}
        onOpenChange={open => { if (!open) setConfirmDeactivate(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Deactivate {confirmDeactivate?.full_name}?</AlertDialogTitle>
            <AlertDialogDescription>
              They will no longer be able to sign in to their agency&apos;s dashboard.
              You can reactivate this account at any time.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={acting !== null}>Keep active</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={acting !== null}
              onClick={() => {
                const target = confirmDeactivate;
                setConfirmDeactivate(null);
                if (target) deactivate(target.id);
              }}
            >
              Deactivate
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

// ── Create Agency Admin form ──────────────────────────────────

function CreateAgencyAdminForm({ agencies, token, onSuccess, onCancel }: {
  agencies: AgencyOption[]; token: string; onSuccess: () => void; onCancel: () => void;
}) {
  const [form, setForm] = useState({ email: '', full_name: '', agency_id: '' });
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.agency_id) { setError('Select an agency.'); return; }
    setSaving(true); setError(null);
    try {
      await apiClient.post('/users/provincial/agency-admins', form, token);
      onSuccess();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Failed to send invite.');
    } finally { setSaving(false); }
  }

  return (
    <div className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-5">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-card-title text-[var(--color-text-primary)]">New agency admin</h2>
        <Button variant="ghost" size="sm" onClick={onCancel} aria-label="Close">
          <X className="h-4 w-4" />
        </Button>
      </div>
      {error && <div className="mb-3"><Alert variant="error" message={error} /></div>}
      <form onSubmit={submit} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <Input placeholder="Full name" value={form.full_name}
          onChange={e => setForm(f => ({ ...f, full_name: e.target.value }))} required />
        <Input type="email" placeholder="Email address" value={form.email}
          onChange={e => setForm(f => ({ ...f, email: e.target.value }))} required />
        <OptionPicker
          className="sm:col-span-2"
          label="Choose an agency"
          onChange={agency_id => setForm(f => ({ ...f, agency_id }))}
          options={agencyOptions(agencies)}
          placeholder="Select agency…"
          value={form.agency_id}
        />
        <div className="mt-1 flex justify-end gap-2 sm:col-span-2">
          <Button variant="ghost" size="sm" type="button" onClick={onCancel}>Cancel</Button>
          <Button variant="primary" size="sm" type="submit" isLoading={saving}>
            <UserCheck className="mr-1 h-3.5 w-3.5" /> Send invite
          </Button>
        </div>
      </form>
    </div>
  );
}

// ── Admin row ─────────────────────────────────────────────────

function AdminRow({ admin, agencies, acting, onDeactivate, onReactivate, onReassign }: {
  admin: AgencyAdminUser; agencies: AgencyOption[]; acting: boolean;
  onDeactivate?: () => void; onReactivate?: () => void; onReassign: (agencyId: string) => void;
}) {
  const [reassigning, setReassigning] = useState(false);
  const [newAgencyId, setNewAgencyId] = useState('');

  return (
    <>
      <DataRow className={acting ? 'pointer-events-none opacity-50' : undefined}>
        <DataTd>
          <div className="flex items-center gap-3">
            <Initials name={admin.full_name} tone="brand" />
            <div className="min-w-0">
              <p className="truncate font-medium text-[var(--color-text-primary)]">{admin.full_name}</p>
              <p className="truncate text-meta text-[var(--color-text-muted)]">{admin.email}</p>
            </div>
          </div>
        </DataTd>
        <DataTd>
          {admin.agencies ? (
            <div className="min-w-0">
              <p className="flex items-center gap-2">
                <AgencyChip type={admin.agencies.agency_type} />
                <span className="truncate font-medium text-[var(--color-text-primary)]">{admin.agencies.name}</span>
              </p>
              <p className="mt-0.5 truncate text-meta text-[var(--color-text-muted)]">{admin.agencies.municipality}</p>
            </div>
          ) : (
            <span className="text-[var(--color-text-muted)]">Not assigned</span>
          )}
        </DataTd>
        <DataTd>
          <StatusChip
            label={admin.is_verified ? 'Active' : 'Deactivated'}
            tone={admin.is_verified ? 'success' : 'neutral'}
          />
        </DataTd>
        <DataTd className="whitespace-nowrap text-[var(--color-text-secondary)]">
          {new Date(admin.created_at).toLocaleDateString()}
        </DataTd>
        <DataTd align="right">
          <div className="flex items-center justify-end gap-2">
            <Button variant="ghost" size="sm" onClick={() => setReassigning(r => !r)}>
              <Building2 className="mr-1 h-3.5 w-3.5" /> Reassign
            </Button>
            {onDeactivate && (
              <Button variant="danger" size="sm" onClick={onDeactivate} isLoading={acting}>
                <X className="mr-1 h-3.5 w-3.5" /> Deactivate
              </Button>
            )}
            {onReactivate && (
              <Button variant="outline" size="sm" onClick={onReactivate} isLoading={acting}>
                <Check className="mr-1 h-3.5 w-3.5" /> Reactivate
              </Button>
            )}
          </div>
        </DataTd>
      </DataRow>
      {reassigning && (
        <tr className="border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50">
          <td className="px-4 py-3" colSpan={5}>
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-meta text-[var(--color-text-muted)]">Move {admin.full_name} to</span>
              <OptionPicker
                className="max-w-[320px] flex-1"
                label="Reassign to"
                onChange={setNewAgencyId}
                options={agencyOptions(agencies)}
                placeholder="Select new agency…"
                value={newAgencyId}
              />
              <Button variant="primary" size="sm" isLoading={acting}
                onClick={() => { if (newAgencyId) { onReassign(newAgencyId); setReassigning(false); } }}>
                <Check className="mr-1 h-3.5 w-3.5" data-icon="inline-start" />
                Confirm
              </Button>
              <Button variant="ghost" size="sm" onClick={() => setReassigning(false)}>Cancel</Button>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

// ── Directory tab ─────────────────────────────────────────────

function DirectoryTab({ token }: { token: string }) {
  const [users, setUsers]           = useState<DirectoryUser[]>([]);
  const [loading, setLoading]       = useState(true);
  const [error, setError]           = useState<string | null>(null);
  const setActionMsg = useNotice();
  // Which role tab is open. Filtered here, on the full list, rather than asking
  // the server for one role: the server-side filter made every other role's
  // count read 0 in the stat strip and on its own tab the moment one was chosen.
  const [roleFilter, setRoleFilter] = useState<string>('');
  const [municipality, setMunicipality] = useState<string>('all');
  const [barangay, setBarangay] = useState<string>('all');
  const [places, setPlaces] = useState<BarangayRef[]>([]);
  const [q, setQ] = useState('');
  const [agencies, setAgencies] = useState<AgencyOption[]>([]);
  const [reassigningId, setReassigningId] = useState<string | null>(null);
  const [acting, setActing] = useState<string | null>(null);
  // Suspend is the one high-impact direction here — it blocks sign-in.
  // Reactivate is restorative and stays a single click, same asymmetry as
  // AgencyAdminsTab's Deactivate/Reactivate above.
  const [confirmSuspend, setConfirmSuspend] = useState<
    { id: string; name: string; kind: 'resident' | 'responder' } | null
  >(null);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const data = await apiClient.get<DirectoryUser[]>('/users/provincial/directory', token);
      setUsers(data);
    } catch (e: unknown) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'Failed to load directory.');
    } finally { setLoading(false); }
  }, [token]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    apiClient.get<AgencyOption[]>('/users/agencies-list', token).then(setAgencies).catch(() => {});
  }, [token]);

  /** Residents: suspend/reactivate toggles is_verified — see the backend
   * endpoint's own docstring for why this never affects incident reporting.
   * Responders: the same two states are the existing approval decision
   * (approved/rejected) a Provincial Admin can already make. */
  async function setResidentActive(id: string, isActive: boolean) {
    setActing(id);
    try {
      await apiClient.patch(`/users/provincial/residents/${id}/status`, { is_active: isActive }, token);
      setActionMsg({ type: 'success', text: `Resident ${isActive ? 'reactivated' : 'suspended'}.` });
      await load();
    } catch (e) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Update failed.' });
    } finally { setActing(null); }
  }

  async function setResponderApproval(id: string, approve: boolean) {
    setActing(id);
    try {
      await apiClient.patch(
        `/users/agency/responders/${id}/approval`,
        { approval_status: approve ? 'approved' : 'rejected' },
        token,
      );
      setActionMsg({ type: 'success', text: `Responder ${approve ? 'reactivated' : 'suspended'}.` });
      await load();
    } catch (e) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Update failed.' });
    } finally { setActing(null); }
  }

  async function reassignResponder(id: string, agencyId: string) {
    setActing(id);
    try {
      await apiClient.patch(`/users/provincial/responders/${id}/reassign`, { agency_id: agencyId }, token);
      setActionMsg({ type: 'success', text: 'Responder reassigned.' });
      setReassigningId(null);
      await load();
    } catch (e) {
      setActionMsg({ type: 'error', text: e instanceof Error ? e.message : 'Reassignment failed.' });
    } finally { setActing(null); }
  }

  /**
   * The place list comes from the barangay reference table, not from the
   * addresses these accounts happen to carry.
   *
   * Deriving it from the loaded users would only ever offer places somebody
   * has already registered from — so a barangay with no accounts would be
   * missing from the dropdown, and "nobody here yet" is precisely what an
   * administrator opens this filter to find out.
   */
  useEffect(() => {
    let cancelled = false;
    apiClient
      .get<BarangayRef[]>('/users/barangays', token)
      .then(rows => { if (!cancelled) setPlaces(rows); })
      // The directory still works without it; only the place filter is lost.
      .catch(() => {});
    return () => { cancelled = true; };
  }, [token]);

  const municipalities = useMemo(
    () => [...new Set(places.map(p => p.municipality))].sort(),
    [places],
  );
  /**
   * What the barangay dropdown offers.
   *
   * Every barangay in the province when no municipality is chosen, grouped by
   * municipality so the duplicated names are told apart by the heading above
   * them. Narrowed to one municipality once one is picked.
   */
  const barangayGroups = useMemo(() => {
    const scope = municipality === 'all'
      ? places
      : places.filter(p => p.municipality === municipality);
    const byMuni = new Map<string, string[]>();
    for (const b of scope) {
      const list = byMuni.get(b.municipality);
      if (list) list.push(b.name);
      else byMuni.set(b.municipality, [b.name]);
    }
    return [...byMuni.entries()];
  }, [places, municipality]);

  /**
   * Barangay is held as "Municipality|Name", never as a bare name.
   *
   * Seven names in Biliran are used by more than one municipality — Looc is a
   * barangay in four of them, Poblacion in four — so a name on its own does
   * not identify a place. Filtering by one would quietly pool residents of
   * four different Loocs into a single group.
   */
  function chooseMunicipality(m: string) {
    setMunicipality(m);
    // Switching municipality clears the barangay: "Naval / Talustusan" then
    // Almeria would otherwise filter Almeria by a barangay not in it, and
    // match nothing for a reason nothing on screen explains.
    setBarangay('all');
  }

  function chooseBarangay(v: string) {
    setBarangay(v);
    // Picking a barangay implies its municipality, so you can go straight to
    // one without knowing which municipality it belongs to. Done here rather
    // than in an effect — an effect keyed on `municipality` would fire right
    // after this and clear the barangay that had just been chosen.
    if (v !== 'all') setMunicipality(v.split('|')[0]);
  }

  const placed = useMemo(
    () => users.map(u => ({ user: u, place: placeOf(u) })),
    [users],
  );

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase();
    return placed.filter(({ user, place }) => {
      if (roleFilter && user.role !== roleFilter) return false;
      if (municipality !== 'all' && place.municipality !== municipality) return false;
      if (barangay !== 'all') {
        // Both halves must match. Comparing the name alone would put every Looc
        // in the province into one bucket.
        const [bMuni, bName] = barangay.split('|');
        if (place.municipality !== bMuni || place.barangay !== bName) return false;
      }
      if (needle && !user.full_name.toLowerCase().includes(needle) && !user.email.toLowerCase().includes(needle)) {
        return false;
      }
      return true;
    });
  }, [placed, roleFilter, municipality, barangay, q]);

  // Counted, never hidden. An account with no address is the one an
  // administrator most needs to know about — it cannot be reached, routed or
  // grouped — and dropping it out of a filtered view without saying so would
  // make the directory quietly under-report its own population.
  const unplaced = placed.filter(({ place }) => !place.municipality).length;

  /**
   * Grouped by the finest place available: barangay once a municipality is
   * chosen, municipality otherwise. Groups are sorted by name, except the
   * "no address" bucket which is pinned last so it never separates two real
   * places in the list.
   */
  const groups = useMemo(() => {
    const byKey = new Map<string, typeof shown>();
    for (const entry of shown) {
      const key =
        municipality !== 'all'
          ? entry.place.barangay
            ?? (entry.place.viaAgency
              ? `${entry.place.municipality} (agency staff)`
              : NO_BARANGAY)
          : entry.place.municipality ?? NO_PLACE;
      const list = byKey.get(key);
      if (list) list.push(entry);
      else byKey.set(key, [entry]);
    }
    // Both "unknown" buckets sink to the bottom, so neither ever separates two
    // real places in an otherwise alphabetical list.
    const sinks = [NO_PLACE, NO_BARANGAY];
    return [...byKey.entries()].sort(([a], [b]) => {
      const ai = sinks.indexOf(a);
      const bi = sinks.indexOf(b);
      if (ai !== -1 || bi !== -1) return (ai === -1 ? -1 : ai) - (bi === -1 ? -1 : bi);
      return a.localeCompare(b);
    });
  }, [shown, municipality]);

  const roleColors: Record<string, string> = {
    responder:    'var(--color-status-dispatched)',
    agency_admin: 'var(--color-brand)',
    resident:     'var(--color-text-muted)',
  };

  const counts = {
    total:        users.length,
    agency_admin: users.filter(u => u.role === 'agency_admin').length,
    responder:    users.filter(u => u.role === 'responder').length,
    resident:     users.filter(u => u.role === 'resident').length,
  };

  return (
    <div className="space-y-5">
      <StatStrip>
        {/* One icon per role, all from the same person family so the four
            cells read as one scale. `Users` previously stood for both "all
            accounts" and "residents", which made two different totals look
            like the same measure. */}
        <StatCell
          icon={<Users size={12} strokeWidth={2} />}
          label="All accounts"
          value={counts.total}
          trend="Registered province-wide"
          color="var(--color-brand)"
          bg="var(--color-brand-subtle)"
        />
        <StatCell
          icon={<UserCog size={12} strokeWidth={2} />}
          label="Agency admins"
          value={counts.agency_admin}
          trend="of the directory"
          whole={counts.total}
          wholeLabel="accounts"
          color="var(--color-status-processing)"
          bg="var(--color-status-processing-bg)"
        />
        <StatCell
          icon={<UserCheck size={12} strokeWidth={2} />}
          label="Responders"
          value={counts.responder}
          trend="of the directory"
          whole={counts.total}
          wholeLabel="accounts"
          color="var(--color-status-dispatched)"
          bg="var(--color-status-dispatched-bg)"
        />
        <StatCell
          icon={<UserRound size={12} strokeWidth={2} />}
          label="Residents"
          value={counts.resident}
          trend="of the directory"
          whole={counts.total}
          wholeLabel="accounts"
          color="var(--color-system-success)"
          bg="var(--color-system-success-bg)"
        />
      </StatStrip>

      <div className={TABLE_CARD}>
        {/* The role switcher is navigation, so it is the same NavTabs as the page's
            own tabs. Each tab carries its count: it says how many before it is clicked. */}
        <NavTabs
          activeKey={roleFilter}
          ariaLabel="Filter accounts by role"
          idPrefix="directory-role"
          onSelect={setRoleFilter}
          tabs={[
            { key: '', label: `All (${counts.total})`, icon: Users },
            { key: 'agency_admin', label: `Agency admins (${counts.agency_admin})`, icon: UserCog },
            { key: 'responder', label: `Responders (${counts.responder})`, icon: UserCheck },
            { key: 'resident', label: `Residents (${counts.resident})`, icon: UserRound },
          ]}
        />

        <div className="flex flex-wrap items-center gap-2 border-b border-[var(--color-surface-border)] px-4 py-3">
          <SearchInput
            className="w-[260px]"
            label="Search by name or email"
            onValueChange={setQ}
            placeholder="Search name or email…"
            size="sm"
            value={q}
          />
          <OptionPicker
            className="w-[170px]"
            label="Choose a municipality"
            onChange={chooseMunicipality}
            options={[
              { value: 'all', label: 'All municipalities', icon: MapPin },
              ...municipalities.map(m => ({ value: m, label: m, icon: MapPin })),
            ]}
            placeholder="Municipality"
            size="sm"
            value={municipality}
          />

          {/* Never disabled.
              It used to be, until a municipality was chosen — which made it a
              control that silently refused to open, with nothing on screen
              saying why. Now it lists every barangay in the province, grouped
              under its municipality, and picking one sets the municipality for
              you. The grouping is not decoration: seven of these names belong
              to more than one municipality, so the heading above an option is
              the only thing that distinguishes four different Loocs. */}
          <Select onValueChange={chooseBarangay} value={barangay}>
            <SelectTrigger className="w-[190px]" size="sm">
              <SelectValue placeholder="Barangay" />
            </SelectTrigger>
            <SelectContent className="max-h-[320px]">
              <SelectItem value="all">
                All barangays{municipality !== 'all' ? ` in ${municipality}` : ''}
              </SelectItem>
              {barangayGroups.map(([muni, names]) => (
                <SelectGroup key={muni}>
                  {/* Skipped when the list is already one municipality — the
                      trigger beside it says so. */}
                  {municipality === 'all' && <SelectLabel>{muni}</SelectLabel>}
                  {names.map(n => (
                    <SelectItem key={`${muni}|${n}`} value={`${muni}|${n}`}>
                      {n}
                    </SelectItem>
                  ))}
                </SelectGroup>
              ))}
            </SelectContent>
          </Select>

          <span className="ml-auto text-meta text-muted-foreground">
            <Fig className="text-[12px] font-semibold text-[var(--color-text-primary)]">{shown.length}</Fig>
            {' '}of <Fig className="text-[12px]">{users.length}</Fig> shown
          </span>
        </div>

        {/* Said out loud, not filtered away. These accounts record no place at
            all, so no municipality filter can ever surface them — and an
            administrator checking coverage needs to know the roll is incomplete
            before they read anything into it. */}
        {(unplaced > 0 || error) && (
          <div className="flex flex-col gap-2 border-b border-[var(--color-surface-border)] px-4 py-3">
            {unplaced > 0 && (
              <p className="text-meta text-[var(--color-text-muted)]">
                <Fig className="text-[12px] font-semibold">{unplaced}</Fig> of{' '}
                <Fig className="text-[12px] font-semibold">{users.length}</Fig> accounts
                record no address and appear under “{NO_PLACE}”. A place filter cannot
                reach them.
              </p>
            )}
            {error && <Alert variant="error" message={error} />}
          </div>
        )}

      {loading && users.length === 0 ? (
        <div className="flex items-center justify-center py-16">
          <Loader2 className="h-6 w-6 animate-spin text-[var(--color-text-muted)]" />
        </div>
      ) : users.length === 0 ? (
        <TableEmptyState
          icon={<Shield className="h-9 w-9" />}
          message="No accounts yet"
        />
      ) : shown.length === 0 ? (
        <TableEmptyState
          icon={<MapPin className="h-9 w-9" />}
          message={municipality === 'all' && barangay === 'all' && !q.trim()
            ? 'No accounts with this role'
            : `No accounts in ${barangay !== 'all' ? barangay.split('|')[1] : municipality !== 'all' ? municipality : 'this search'}`}
          description="Nobody matches these filters. The place exists in the barangay reference list — this is an empty result, not a bad filter."
        />
      ) : (
        <DataTableFrame minWidth={980}>
          <DataHead>
            <DataTh>Account</DataTh>
            <DataTh width="136px">Role</DataTh>
            <DataTh width="128px">Status</DataTh>
            <DataTh width="120px">Joined</DataTh>
            <DataTh align="right" width="240px">Actions</DataTh>
          </DataHead>
          {groups.map(([place, entries]) => (
            <tbody key={place}>
              {/* A full-width row rather than a heading between <tbody> elements —
                  a place name needs to be a real row (spanning every column) to
                  stay inside the table's own structure. */}
              <DataGroupRow colSpan={5}>
                <span className="flex items-center gap-2">
                  <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-[var(--color-text-muted)]" />
                  <h3 className="text-[11px] font-bold uppercase tracking-wide text-[var(--color-text-secondary)]">{place}</h3>
                  <Fig className="text-[11.5px] font-semibold text-[var(--color-text-muted)]">{entries.length}</Fig>
                </span>
              </DataGroupRow>
              {entries.map(({ user: u, place: pl }) => (
                <Fragment key={u.id}>
                  <DataRow>
                    <DataTd>
                      <div className="flex items-center gap-3">
                        <Initials name={u.full_name} tone="neutral" />
                        <div className="min-w-0">
                          <p className="truncate font-medium text-[var(--color-text-primary)]">{u.full_name}</p>
                          <p className="truncate text-meta text-[var(--color-text-muted)]">{u.email}</p>
                          {/* One quiet line for where they are or work. "via agency" is not
                              decoration: without it the row would read as this person's home
                              municipality when all that is known is where they work. */}
                          {(u.agencies || pl.municipality) && (
                            <p className="mt-0.5 flex min-w-0 items-center gap-1 truncate text-meta text-[var(--color-text-muted)]">
                              {u.agencies && <span className="truncate">{u.agencies.agency_type} — {u.agencies.name}</span>}
                              {u.agencies && pl.municipality && <span aria-hidden="true">·</span>}
                              {pl.municipality && (
                                <span className="truncate">
                                  {pl.barangay ? `${pl.barangay}, ` : ''}{pl.municipality}
                                  {pl.viaAgency && <span className="italic opacity-70"> · via agency</span>}
                                </span>
                              )}
                            </p>
                          )}
                        </div>
                      </div>
                    </DataTd>
                    <DataTd>
                      <span
                        className="inline-flex whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-semibold"
                        style={{
                          backgroundColor: `color-mix(in srgb, ${roleColors[u.role] ?? 'var(--color-text-muted)'} 12%, transparent)`,
                          color: roleColors[u.role] ?? 'var(--color-text-muted)',
                        }}
                      >
                        {u.role === 'agency_admin' ? 'Agency admin' : u.role.charAt(0).toUpperCase() + u.role.slice(1)}
                      </span>
                    </DataTd>
                    <DataTd>
                      {u.role === 'responder' ? (
                        <StatusChip
                          label={u.approval_status.charAt(0).toUpperCase() + u.approval_status.slice(1)}
                          tone={u.approval_status === 'approved' ? 'success' : u.approval_status === 'pending' ? 'warning' : 'neutral'}
                        />
                      ) : (
                        <StatusChip label={u.is_verified ? 'Active' : 'Suspended'} tone={u.is_verified ? 'success' : 'neutral'} />
                      )}
                    </DataTd>
                    <DataTd className="whitespace-nowrap text-[var(--color-text-secondary)]">
                      {new Date(u.created_at).toLocaleDateString()}
                    </DataTd>
                    <DataTd align="right">
                      <div className="flex flex-wrap items-center justify-end gap-2">
                        {u.role === 'resident' && (
                          <Button
                            disabled={acting === u.id}
                            isLoading={acting === u.id}
                            onClick={() => u.is_verified
                              ? setConfirmSuspend({ id: u.id, name: u.full_name, kind: 'resident' })
                              : setResidentActive(u.id, true)}
                            size="sm"
                            variant={u.is_verified ? 'outline' : 'success'}
                          >
                            {u.is_verified ? 'Suspend' : 'Reactivate'}
                          </Button>
                        )}
                        {u.role === 'responder' && (
                          <>
                            <Button
                              disabled={acting === u.id}
                              isLoading={acting === u.id}
                              onClick={() => u.approval_status === 'approved'
                                ? setConfirmSuspend({ id: u.id, name: u.full_name, kind: 'responder' })
                                : setResponderApproval(u.id, true)}
                              size="sm"
                              variant={u.approval_status === 'approved' ? 'outline' : 'success'}
                            >
                              {u.approval_status === 'approved' ? 'Suspend' : 'Reactivate'}
                            </Button>
                            <Button
                              disabled={acting === u.id}
                              onClick={() => setReassigningId(v => (v === u.id ? null : u.id))}
                              size="sm"
                              variant="ghost"
                            >
                              Reassign
                            </Button>
                          </>
                        )}
                        {u.role === 'agency_admin' && (
                          <span className="inline-flex items-center gap-0.5 text-meta text-[var(--color-text-muted)]">
                            Manage in Agency admins <ChevronRight aria-hidden="true" className="size-3.5" />
                          </span>
                        )}
                      </div>
                    </DataTd>
                  </DataRow>
                  {reassigningId === u.id && (
                    <tr className="border-b border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50">
                      <td className="px-4 py-3" colSpan={5}>
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-meta text-[var(--color-text-muted)]">Move to:</span>
                          {agencies.map(a => (
                            <Button
                              disabled={acting === u.id || a.id === u.agency_id}
                              key={a.id}
                              onClick={() => reassignResponder(u.id, a.id)}
                              size="sm"
                              variant="outline"
                            >
                              {a.agency_type} — {a.name}
                            </Button>
                          ))}
                          <Button onClick={() => setReassigningId(null)} size="sm" variant="ghost">
                            Cancel
                          </Button>
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          ))}
        </DataTableFrame>
      )}
      </div>

      <AlertDialog
        open={confirmSuspend !== null}
        onOpenChange={open => { if (!open) setConfirmSuspend(null); }}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Suspend {confirmSuspend?.name}?</AlertDialogTitle>
            <AlertDialogDescription>
              {confirmSuspend?.kind === 'responder'
                ? 'They will no longer be able to sign in or be dispatched to incidents. You can reactivate them at any time.'
                : 'They will no longer be able to sign in. You can reactivate this account at any time.'}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={acting !== null}>Keep active</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={acting !== null}
              onClick={() => {
                const target = confirmSuspend;
                setConfirmSuspend(null);
                if (!target) return;
                if (target.kind === 'resident') setResidentActive(target.id, false);
                else setResponderApproval(target.id, false);
              }}
            >
              Suspend
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
