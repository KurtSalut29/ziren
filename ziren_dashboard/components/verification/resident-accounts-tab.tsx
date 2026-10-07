'use client';

/**
 * Resident accounts — where a resident goes once they are verified.
 *
 * The ID review queue ends the moment somebody presses Verify: the resident
 * left the list and, as far as this console was concerned, stopped existing.
 * There was nowhere to look a verified person up, and nothing an admin could
 * do when one of them sent a prank report except flag a false SOS.
 *
 * This is that place. Every resident account, how it stands (good standing,
 * warned, suspended), and three things an admin can do about it:
 *
 *   Warn       One warning on the record, for a named violation. The third
 *              suspends the account for thirty days by itself.
 *   Suspend    Stop the account from sending reports, for some days or until
 *              further notice.
 *   Reinstate  Lift the suspension.
 *
 * Each one is told to the resident on their phone, in words they can act on,
 * and is written to the audit trail, which is also the history shown here.
 *
 * A SUSPENSION IS NOT LIKE VERIFICATION. Verifying changes nothing a resident
 * can do. Suspending stops them reporting an emergency through the app, so the
 * dialog says so plainly before it is confirmed, and the resident is always
 * given the hotline to call instead.
 */

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  AlertTriangle, BadgeCheck, Ban, CalendarClock, Check, CircleCheck, FileText, History,
  IdCard, Mail, MapPin, Phone, RotateCcw, ShieldAlert, ShieldCheck, ShieldQuestion, Siren,
  UserRound, Users, type LucideIcon,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import { signOut } from '@/lib/hooks/useAuth';
import {
  AUTO_SUSPEND_AT, AUTO_SUSPEND_DAYS, residentsApi,
  type ResidentAccount, type ResidentDetail, type ResidentList, type StandingEvent,
  type StandingFilter, type StandingResult,
} from '@/lib/api/residents';
import { ID_TYPE_LABELS } from '@/lib/api/verification';
import { ZirenIdCard } from './ziren-id-card';
import { formatDate, formatDateTime } from '@/lib/format/datetime';
import { displayPrefs } from '@/lib/prefs/definitions';
import { useNotice } from '@/lib/toast';
import { cn } from '@/lib/utils';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import {
  DataHead, DataRow, DataTableFrame, DataTd, DataTh, Initials,
} from '@/components/ui/data-table';
import { Pagination } from '@/components/ui/pagination';
import { SearchInput } from '@/components/ui/search-input';
import { StatStrip, StatCell } from '@/components/ui/stat-strip';
import { ActionButton } from '@/components/incidents/incident-action-button';
import { StatusPill } from '@/components/incidents/incident-table-parts';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';

const PAGE_SIZE = 25;

const WARN = 'var(--color-system-warning)';
const STOP = 'var(--color-severity-critical)';
const GOOD = 'var(--color-system-success)';

const FILTERS: { key: StandingFilter; label: string; icon: LucideIcon; hint: string }[] = [
  { key: 'verified', label: 'Verified', icon: BadgeCheck, hint: 'Residents whose ID has been checked' },
  { key: 'warned', label: 'Warned', icon: AlertTriangle, hint: 'At least one warning on record' },
  { key: 'suspended', label: 'Suspended', icon: Ban, hint: 'Cannot send reports right now' },
  { key: 'unverified', label: 'Not verified', icon: ShieldQuestion, hint: 'No ID checked yet' },
  { key: 'all', label: 'Everyone', icon: Users, hint: 'Every resident account' },
];

const METHOD_LABEL: Record<string, string> = {
  government_id: 'Government ID examined',
  barangay_official: 'Barangay official confirmed',
  pwd_id: 'PWD ID examined',
  phone_otp: 'Phone OTP',
};

const VIOLATION_ICON: Record<string, LucideIcon> = {
  false_report: FileText,
  false_sos: Siren,
  spam: History,
  abusive_language: ShieldAlert,
  fake_identity: IdCard,
  other: AlertTriangle,
};

type ActionMode = 'warn' | 'suspend' | 'reinstate';

export function ResidentAccountsTab({ token }: { token: string }) {
  const display = displayPrefs.use();
  const setNotice = useNotice();

  const [standing, setStanding] = useState<StandingFilter>('verified');
  const [q, setQ] = useState('');
  const [page, setPage] = useState(0);
  const [data, setData] = useState<ResidentList | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [openId, setOpenId] = useState<string | null>(null);
  const [detail, setDetail] = useState<ResidentDetail | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [action, setAction] = useState<ActionMode | null>(null);

  // Typing should not fire a request per keystroke.
  const [needle, setNeedle] = useState('');
  useEffect(() => {
    const id = setTimeout(() => setNeedle(q), 250);
    return () => clearTimeout(id);
  }, [q]);
  useEffect(() => { setPage(0); }, [standing, needle]);

  const load = useCallback(async (silent = false) => {
    if (!silent) { setLoading(true); setError(null); }
    try {
      setData(await residentsApi.list(token, {
        standing, q: needle, limit: PAGE_SIZE, offset: page * PAGE_SIZE,
      }));
      setError(null);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      if (!silent) setError(e instanceof Error ? e.message : 'Could not load the resident accounts.');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [token, standing, needle, page]);

  useEffect(() => { void load(); }, [load]);

  const loadDetail = useCallback(async (id: string) => {
    setDetailError(null);
    try {
      setDetail(await residentsApi.detail(token, id));
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setDetailError(e instanceof Error ? e.message : 'Could not open this resident.');
    }
  }, [token]);

  function open(id: string) {
    setOpenId(id);
    setDetail(null);
    void loadDetail(id);
  }

  function close() {
    setOpenId(null);
    setDetail(null);
    setDetailError(null);
    setAction(null);
  }

  async function applied(mode: ActionMode, result: StandingResult, name: string) {
    setAction(null);
    const text =
      mode === 'warn'
        ? result.suspension.active
          ? `${name} was warned. That was warning ${result.warning_count}, so the account is now suspended for ${AUTO_SUSPEND_DAYS} days. They have been notified.`
          : `${name} was warned (${result.warning_count} of ${AUTO_SUSPEND_AT}). They have been notified on their phone.`
        : mode === 'suspend'
          ? `${name} is suspended from reporting. They have been notified on their phone.`
          : `${name} can send reports again. They have been notified on their phone.`;
    setNotice({ type: 'success', text });
    if (openId) await loadDetail(openId);
    await load(true);
  }

  const counts = data?.counts;
  const total = data?.total ?? 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const rows = data?.items ?? [];

  return (
    <div className="flex flex-col gap-4" data-testid="resident-accounts">
      <StatStrip>
        <StatCell
          bg="var(--color-system-success-bg)"
          color={GOOD}
          icon={<BadgeCheck size={12} strokeWidth={2} />}
          label="Verified residents"
          trend={counts ? `of ${counts.all} accounts` : '—'}
          value={counts?.verified ?? '—'}
        />
        <StatCell
          bg="var(--color-system-warning-bg)"
          color={WARN}
          icon={<AlertTriangle size={12} strokeWidth={2} />}
          label="With a warning"
          trend={counts && counts.warned > 0 ? 'on record' : 'none on record'}
          value={counts?.warned ?? '—'}
        />
        <StatCell
          bg="var(--color-severity-critical-bg)"
          color={STOP}
          icon={<Ban size={12} strokeWidth={2} />}
          label="Suspended"
          trend={counts && counts.suspended > 0 ? 'cannot report right now' : 'nobody suspended'}
          value={counts?.suspended ?? '—'}
        />
        <StatCell
          bg="var(--color-surface-raised)"
          color="var(--color-text-secondary)"
          icon={<ShieldQuestion size={12} strokeWidth={2} />}
          label="Not verified"
          trend="no ID checked yet"
          value={counts?.unverified ?? '—'}
        />
      </StatStrip>

      <div className="overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-2.5 border-b border-[var(--color-surface-border)] px-4 py-3">
          <div aria-label="Which residents to show" className="flex flex-wrap gap-1.5" role="group">
            {FILTERS.map(f => {
              const on = standing === f.key;
              const n = counts?.[f.key];
              return (
                <button
                  aria-pressed={on}
                  className={cn(
                    'inline-flex h-8 items-center gap-1.5 rounded-full border px-3 text-[12.5px] font-semibold transition-colors',
                    on
                      ? 'border-transparent bg-foreground text-background'
                      : 'border-[var(--color-surface-border)] bg-[var(--color-surface-card)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
                  )}
                  data-standing={f.key}
                  key={f.key}
                  onClick={() => setStanding(f.key)}
                  title={f.hint}
                  type="button"
                >
                  <f.icon aria-hidden="true" size={14} />
                  {f.label}
                  {n !== undefined && (
                    <span className={cn('tabular-nums text-[11.5px]', on ? 'opacity-80' : n === 0 ? 'opacity-40' : 'text-muted-foreground')}>
                      {n}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
          <SearchInput
            className="ml-auto min-w-[220px] max-w-[360px] flex-1"
            label="Search resident accounts"
            onValueChange={setQ}
            placeholder="Name, email, phone or barangay…"
            value={q}
          />
        </div>

        {error ? (
          <div className="flex items-start gap-3 p-4">
            <div className="flex-1"><Alert message={error} variant="error" /></div>
            <Button onClick={() => void load()} size="sm" variant="outline">Retry</Button>
          </div>
        ) : loading && !data ? (
          <p className="py-14 text-center text-meta text-muted-foreground">Loading resident accounts…</p>
        ) : rows.length === 0 ? (
          <_Empty filter={standing} searching={needle.trim() !== ''} />
        ) : (
          <DataTableFrame className="rounded-none border-0" minWidth={1020}>
            <DataHead>
              <DataTh>Resident</DataTh>
              <DataTh width="210px">Place</DataTh>
              <DataTh width="190px">Verified</DataTh>
              <DataTh align="right" width="92px">Reports</DataTh>
              <DataTh width="210px">Standing</DataTh>
              <DataTh align="right" width="104px"><span className="sr-only">Open</span></DataTh>
            </DataHead>
            <tbody>
              {rows.map(r => (
                <_Row display={display} key={r.id} onOpen={() => open(r.id)} row={r} />
              ))}
            </tbody>
          </DataTableFrame>
        )}

        {pages > 1 && (
          <div className="border-t border-[var(--color-surface-border)] px-4 py-3">
            <Pagination
              disabled={loading}
              onNext={() => setPage(p => p + 1)}
              onPrevious={() => setPage(p => Math.max(0, p - 1))}
              page={page + 1}
              pageCount={pages}
            />
          </div>
        )}
      </div>

      {data?.truncated && (
        <p className="px-1 text-meta text-muted-foreground">
          Showing the newest {data.counts.all.toLocaleString()} accounts. Search by name to find an older one.
        </p>
      )}

      <DetailDialog
        detail={detail}
        error={detailError}
        onAction={setAction}
        onClose={close}
        open={openId !== null}
      />

      {action && detail && (
        <ActionDialog
          detail={detail}
          mode={action}
          onClose={() => setAction(null)}
          onDone={result => void applied(action, result, detail.full_name || detail.email)}
          token={token}
        />
      )}
    </div>
  );
}

// ── Pieces ────────────────────────────────────────────────────────────────

/** How an account stands, as a pill: a dot or icon and the words. Never colour alone. */
export function StandingPill({ row }: { row: Pick<ResidentAccount, 'standing' | 'warning_count' | 'suspension'> }) {
  const display = displayPrefs.use();
  const { color, Icon, label } =
    row.standing === 'suspended'
      ? {
          color: STOP, Icon: Ban,
          label: row.suspension.indefinite || !row.suspension.until
            ? 'Suspended'
            : `Suspended until ${formatDate(row.suspension.until, display)}`,
        }
      : row.standing === 'warned'
        ? { color: WARN, Icon: AlertTriangle, label: `${row.warning_count} warning${row.warning_count === 1 ? '' : 's'}` }
        : { color: GOOD, Icon: CircleCheck, label: 'Good standing' };
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2 py-[3px] text-[11.5px] leading-tight font-semibold whitespace-nowrap"
      data-standing-pill={row.standing}
      style={{ color, backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)` }}
    >
      <Icon aria-hidden="true" size={12} strokeWidth={2.4} />
      {label}
    </span>
  );
}

function _Row({ row, onOpen, display }: {
  row: ResidentAccount;
  onOpen: () => void;
  display: ReturnType<typeof displayPrefs.use>;
}) {
  const name = row.full_name || row.email;
  return (
    <DataRow onClick={onOpen}>
      <DataTd>
        <div className="flex items-center gap-3">
          <Initials name={name} tone={row.verified ? 'brand' : 'neutral'} />
          <div className="min-w-0">
            <p className="flex items-center gap-1.5 truncate font-semibold text-foreground">
              <span className="truncate">{name}</span>
              {row.verified && (
                <BadgeCheck aria-label="Verified" className="size-3.5 shrink-0" role="img" style={{ color: GOOD }} />
              )}
            </p>
            <p className="truncate text-meta text-muted-foreground">
              {row.full_name ? row.email : 'No name on file'}
              {row.phone_number ? ` · ${row.phone_number}` : ''}
            </p>
          </div>
        </div>
      </DataTd>
      <DataTd>
        <p className="flex items-center gap-1.5 text-[13px] text-[var(--color-text-secondary)]">
          <MapPin aria-hidden="true" className="size-3.5 shrink-0 text-muted-foreground" />
          <span className="truncate">
            {[row.barangay, row.municipality_address].filter(Boolean).join(', ') || 'No address on file'}
          </span>
        </p>
      </DataTd>
      <DataTd>
        {row.verified ? (
          <>
            <p className="text-[13px] text-foreground">{row.verified_at ? formatDate(row.verified_at, display) : 'Verified'}</p>
            <p className="truncate text-meta text-muted-foreground">
              {METHOD_LABEL[row.verification_method ?? ''] ?? 'Method not recorded'}
            </p>
          </>
        ) : (
          <span className="text-[13px] text-muted-foreground">Not verified</span>
        )}
      </DataTd>
      <DataTd align="right">
        <span className={row.report_count === 0 ? 'text-muted-foreground' : 'font-semibold text-foreground'}>
          {row.report_count}
        </span>
      </DataTd>
      <DataTd><StandingPill row={row} /></DataTd>
      <DataTd align="right">
        <Button
          aria-label={`Open ${name}`}
          onClick={e => { e.stopPropagation(); onOpen(); }}
          size="sm"
          variant="outline"
        >
          <UserRound data-icon="inline-start" />
          Open
        </Button>
      </DataTd>
    </DataRow>
  );
}

function _Empty({ filter, searching }: { filter: StandingFilter; searching: boolean }) {
  const words: Record<StandingFilter, [string, string]> = {
    verified: ['No verified residents yet', 'A resident appears here as soon as their ID is verified in ID review.'],
    warned: ['Nobody has a warning', 'Accounts you warn for a violation are listed here.'],
    suspended: ['Nobody is suspended', 'Accounts stopped from reporting are listed here until the suspension ends or is lifted.'],
    unverified: ['Everyone is verified', 'Residents who have not had an ID checked are listed here.'],
    all: ['No resident accounts', 'Residents appear here once they register in the mobile app.'],
  };
  const [title, body] = searching ? ['No resident matches that search', 'Try a name, an email, a phone number or a barangay.'] : words[filter];
  return (
    <div className="flex flex-col items-center gap-2 px-6 py-14 text-center" data-empty>
      <span className="flex size-12 items-center justify-center rounded-full bg-[var(--color-surface-raised)] text-[var(--color-text-tertiary)]">
        <Users size={22} />
      </span>
      <p className="mt-1 text-[15px] font-semibold text-foreground">{title}</p>
      <p className="max-w-[46ch] text-[13px] leading-relaxed text-muted-foreground">{body}</p>
    </div>
  );
}

// ── One resident ──────────────────────────────────────────────────────────

function DetailDialog({ open, detail, error, onClose, onAction }: {
  open: boolean;
  detail: ResidentDetail | null;
  error: string | null;
  onClose: () => void;
  onAction: (mode: ActionMode) => void;
}) {
  const display = displayPrefs.use();
  const name = detail ? (detail.full_name || detail.email) : 'Resident';
  const address = detail
    ? [detail.purok_sitio, detail.street_address, detail.barangay, detail.municipality_address].filter(Boolean).join(', ')
    : '';
  const suspended = detail?.standing === 'suspended';
  const tone = !detail ? 'var(--color-surface-border)' : suspended ? STOP : detail.standing === 'warned' ? WARN : GOOD;

  return (
    <Dialog onOpenChange={o => { if (!o) onClose(); }} open={open}>
      <DialogContent
        className="flex max-h-[90vh] flex-col gap-0 overflow-hidden border-t-4 p-0 sm:max-w-[860px]"
        data-testid="resident-detail"
        style={{ borderTopColor: tone }}
      >
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] py-4 pr-14 pl-5 text-left sm:pl-6">
          <div className="flex items-center gap-3.5">
            <span
              aria-hidden="true"
              className="flex size-12 shrink-0 items-center justify-center rounded-full text-[15px] font-semibold"
              style={{ color: 'var(--color-brand)', backgroundColor: 'var(--color-brand-subtle)' }}
            >
              {name.split(' ').map(p => p[0]).join('').slice(0, 2).toUpperCase()}
            </span>
            <div className="min-w-0 flex-1">
              <DialogTitle className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[18px]">
                <span className="truncate">{name}</span>
                {detail && <StandingPill row={detail} />}
                {detail?.verified && (
                  <span
                    className="inline-flex items-center gap-1 rounded-full px-2 py-[3px] text-[11.5px] font-semibold"
                    style={{ color: GOOD, backgroundColor: `color-mix(in srgb, ${GOOD} 12%, transparent)` }}
                  >
                    <BadgeCheck aria-hidden="true" size={12} /> Verified
                  </span>
                )}
              </DialogTitle>
              <DialogDescription className="mt-0.5 truncate">
                {detail ? `Resident since ${formatDate(detail.created_at, display)}` : 'Loading this resident…'}
              </DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-y-auto bg-[var(--color-surface-raised)]/40 px-5 py-4 sm:px-6">
          {error ? (
            <Alert message={error} variant="error" />
          ) : !detail ? (
            <div className="flex animate-pulse flex-col gap-3">
              {[0, 1, 2].map(i => <div className="h-24 rounded-[14px] bg-muted" key={i} />)}
            </div>
          ) : (
            <div className="flex flex-col gap-3.5">
              {suspended && (
                <div
                  className="flex items-start gap-3 rounded-[14px] border px-4 py-3"
                  data-testid="resident-suspended-note"
                  style={{ borderColor: `color-mix(in srgb, ${STOP} 40%, transparent)`, backgroundColor: `color-mix(in srgb, ${STOP} 8%, var(--color-surface-card))` }}
                >
                  <Ban aria-hidden="true" className="mt-0.5 size-4 shrink-0" style={{ color: STOP }} />
                  <p className="text-[13px] leading-relaxed text-foreground">
                    <strong className="font-semibold">This account cannot send reports</strong>{' '}
                    {detail.suspension.indefinite || !detail.suspension.until
                      ? 'until further notice.'
                      : `until ${formatDateTime(detail.suspension.until, display)}.`}
                    {' '}The app tells them to call a hotline in an emergency.
                  </p>
                </div>
              )}

              {/* A verified resident is shown as their Ziren ID first: the
                  face and the particulars an administrator recognises them by. */}
              {detail.verified && <ZirenIdCard detail={detail} />}

              <div className="grid grid-cols-3 gap-2.5">
                <_Stat icon={FileText} label="Reports filed" value={detail.report_count} />
                <_Stat
                  icon={ShieldAlert}
                  label="Reports rejected"
                  tone={detail.rejected_report_count > 0 ? WARN : undefined}
                  value={detail.rejected_report_count}
                />
                <_Stat
                  icon={AlertTriangle}
                  label={`Warnings (${AUTO_SUSPEND_AT} suspends)`}
                  tone={detail.warning_count > 0 ? WARN : undefined}
                  value={detail.warning_count}
                />
              </div>

              <_Card icon={UserRound} title="Who they are">
                <dl className="grid grid-cols-1 gap-x-6 gap-y-3 sm:grid-cols-2">
                  <_Info icon={Phone} label="Mobile">
                    {detail.phone_number
                      ? <a className="font-mono underline-offset-2 hover:underline" href={`tel:${detail.phone_number}`}>{detail.phone_number}</a>
                      : null}
                  </_Info>
                  <_Info icon={Mail} label="Email">{detail.email}</_Info>
                  {/* Already on the Ziren ID above for a verified resident. */}
                  {!detail.verified && <_Info icon={MapPin} label="Address">{address || null}</_Info>}
                  {!detail.verified && <_Info icon={CalendarClock} label="Date of birth">{detail.date_of_birth}</_Info>}
                  <_Info icon={IdCard} label="ID on file">
                    {detail.valid_id_type
                      ? `${ID_TYPE_LABELS[detail.valid_id_type] ?? detail.valid_id_type}${detail.valid_id_number ? ` · ${detail.valid_id_number}` : ''}`
                      : null}
                  </_Info>
                  <_Info icon={ShieldCheck} label="Verified">
                    {detail.verified
                      ? `${detail.verified_at ? formatDate(detail.verified_at, display) : 'Yes'} · ${METHOD_LABEL[detail.verification_method ?? ''] ?? 'method not recorded'}`
                      : 'Not verified'}
                  </_Info>
                  <_Info icon={Phone} label="Emergency contact">
                    {detail.emergency_contact_name
                      ? `${detail.emergency_contact_name}${detail.emergency_contact_number ? ` · ${detail.emergency_contact_number}` : ''}`
                      : null}
                  </_Info>
                </dl>
              </_Card>

              <_Card
                aside={`${detail.history.length} entr${detail.history.length === 1 ? 'y' : 'ies'}`}
                icon={History}
                title="Warnings and suspensions"
              >
                {detail.history.length === 0 ? (
                  <p className="text-[13px] text-muted-foreground">
                    Nothing on record. {detail.warning_count > 0 && 'The warnings counted above were recorded before this history was kept.'}
                  </p>
                ) : (
                  <ol className="flex flex-col gap-2.5" data-testid="resident-history">
                    {detail.history.map(h => <EventRow event={h} key={h.id} />)}
                  </ol>
                )}
              </_Card>

              <_Card aside={`${detail.report_count} in total`} icon={FileText} title="Recent reports">
                {detail.recent_reports.length === 0 ? (
                  <p className="text-[13px] text-muted-foreground">This resident has not filed a report.</p>
                ) : (
                  <ul className="divide-y divide-[var(--color-surface-border)]">
                    {detail.recent_reports.map(r => (
                      <li className="flex items-start gap-3 py-2 first:pt-0 last:pb-0" key={r.id}>
                        <div className="min-w-0 flex-1">
                          <p className="line-clamp-1 text-[13px] font-medium text-foreground">{r.report_text}</p>
                          <p className="text-meta text-muted-foreground">
                            {r.record_number ?? `INC-${r.id.replace(/-/g, '').slice(-6).toUpperCase()}`}
                            {' · '}{CATEGORY_LABELS[r.incident_category ?? ''] ?? 'Uncategorised'}
                            {' · '}{formatDateTime(r.created_at, display)}
                          </p>
                        </div>
                        {r.review_status === 'rejected'
                          ? (
                            <span
                              className="inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-[3px] text-[11.5px] font-semibold"
                              style={{ color: WARN, backgroundColor: `color-mix(in srgb, ${WARN} 12%, transparent)` }}
                            >
                              Rejected
                            </span>
                          )
                          : <StatusPill status={r.status} />}
                      </li>
                    ))}
                  </ul>
                )}
              </_Card>
            </div>
          )}
        </div>

        <div
          className="grid shrink-0 grid-cols-2 gap-2 border-t border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-4 py-3 sm:flex sm:flex-wrap sm:items-center sm:gap-2.5 sm:px-6"
          data-testid="resident-actions"
        >
          {detail && !error && (
            <>
              <ActionButton
                color={WARN}
                hint="Put a warning on record and notify them"
                icon={AlertTriangle}
                label="Warn"
                onClick={() => onAction('warn')}
              />
              {suspended ? (
                <ActionButton
                  color={GOOD}
                  hint="Let them send reports again"
                  icon={RotateCcw}
                  label="Lift suspension"
                  onClick={() => onAction('reinstate')}
                  solidText="var(--color-on-success)"
                />
              ) : (
                <ActionButton
                  color={STOP}
                  hint="Stop this account from sending reports"
                  icon={Ban}
                  label="Suspend"
                  onClick={() => onAction('suspend')}
                />
              )}
              {!suspended && detail.warning_count > 0 && (
                <ActionButton
                  color="var(--color-text-secondary)"
                  hint="Wipe the warnings on this account"
                  icon={RotateCcw}
                  label="Clear warnings"
                  onClick={() => onAction('reinstate')}
                />
              )}
            </>
          )}
          <Button
            className="h-10 w-full rounded-[11px] px-4 text-[13px] font-semibold max-sm:col-span-2 sm:ml-auto sm:h-[38px] sm:w-auto"
            onClick={onClose}
            variant="outline"
          >
            Close
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function _Card({ icon: Icon, title, aside, children }: {
  icon: LucideIcon; title: string; aside?: string; children: React.ReactNode;
}) {
  return (
    <section className="rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4">
      <header className="mb-3 flex items-center gap-2.5">
        <span className="flex size-7 shrink-0 items-center justify-center rounded-[8px] bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)]">
          <Icon aria-hidden="true" size={15} />
        </span>
        <h3 className="flex-1 text-[13.5px] font-semibold text-foreground">{title}</h3>
        {aside && <span className="text-meta text-muted-foreground">{aside}</span>}
      </header>
      {children}
    </section>
  );
}

function _Stat({ icon: Icon, label, value, tone }: {
  icon: LucideIcon; label: string; value: number; tone?: string;
}) {
  return (
    <div className="rounded-[12px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3.5 py-3">
      <p className="flex items-start gap-1.5 text-[11px] leading-tight font-semibold text-[var(--color-text-tertiary)]">
        <Icon aria-hidden="true" className="mt-px shrink-0" size={12} />
        <span className="min-w-0">{label}</span>
      </p>
      <p
        className="mt-1 font-mono text-[22px] leading-none font-bold tabular-nums"
        style={{ color: value === 0 ? 'var(--color-text-muted)' : tone ?? 'var(--color-text-primary)' }}
      >
        {value}
      </p>
    </div>
  );
}

function _Info({ icon: Icon, label, children }: { icon: LucideIcon; label: string; children: React.ReactNode }) {
  return (
    <div className="flex min-w-0 items-start gap-2.5">
      <Icon aria-hidden="true" className="mt-0.5 size-3.5 shrink-0 text-muted-foreground" />
      <div className="min-w-0">
        <dt className="text-[11px] font-semibold text-[var(--color-text-tertiary)]">{label}</dt>
        <dd className="text-[13px] break-words text-foreground">
          {children || <span className="text-muted-foreground">Not on file</span>}
        </dd>
      </div>
    </div>
  );
}

function EventRow({ event }: { event: StandingEvent }) {
  const display = displayPrefs.use();
  const { color, Icon, title } =
    event.kind === 'suspended'
      ? {
          color: STOP, Icon: Ban,
          title: event.indefinite || !event.suspended_until
            ? 'Suspended until further notice'
            : `Suspended until ${formatDate(event.suspended_until, display)}`,
        }
      : event.kind === 'reinstated'
        ? { color: GOOD, Icon: RotateCcw, title: 'Reinstated' }
        : { color: WARN, Icon: AlertTriangle, title: 'Warned' };
  return (
    <li className="flex items-start gap-3" data-event={event.kind}>
      <span
        aria-hidden="true"
        className="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-full"
        style={{ color, backgroundColor: `color-mix(in srgb, ${color} 13%, transparent)` }}
      >
        <Icon size={14} />
      </span>
      <div className="min-w-0 flex-1">
        <p className="flex flex-wrap items-baseline gap-x-2 text-[13px]">
          <span className="font-semibold text-foreground">{title}</span>
          {event.violation_label && <span className="text-[var(--color-text-secondary)]">{event.violation_label}</span>}
          {event.automatic && <span className="text-meta text-muted-foreground">automatic</span>}
        </p>
        {event.note && <p className="mt-0.5 text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">“{event.note}”</p>}
        <p className="mt-0.5 text-meta text-muted-foreground">
          {formatDateTime(event.at, display)}{event.by ? ` · by ${event.by}` : ''}
        </p>
      </div>
    </li>
  );
}

// ── Warn / Suspend / Reinstate ────────────────────────────────────────────

const DURATIONS: { days: number | null; label: string }[] = [
  { days: 3, label: '3 days' },
  { days: 7, label: '7 days' },
  { days: 14, label: '14 days' },
  { days: 30, label: '30 days' },
  { days: null, label: 'Until further notice' },
];

function ActionDialog({ mode, detail, token, onClose, onDone }: {
  mode: ActionMode;
  detail: ResidentDetail;
  token: string;
  onClose: () => void;
  onDone: (result: StandingResult) => void;
}) {
  const name = detail.full_name || detail.email;
  const [violation, setViolation] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const [days, setDays] = useState<number | null>(7);
  const [incidentId, setIncidentId] = useState<string>('');
  const [clear, setClear] = useState(detail.standing !== 'suspended');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const nextWarning = detail.warning_count + 1;
  const willSuspend = mode === 'warn' && nextWarning >= AUTO_SUSPEND_AT && !detail.suspension.active;
  const needsReason = mode !== 'reinstate';
  const ready = !needsReason || (violation !== null && note.trim().length >= 5);

  const copy = useMemo(() => ({
    warn: {
      title: `Warn ${name}`,
      body: 'A warning goes on their record and they are notified on their phone, with what you write below.',
      cta: willSuspend ? 'Warn and suspend' : 'Send warning',
      color: WARN, Icon: AlertTriangle,
    },
    suspend: {
      title: `Suspend ${name}`,
      body: 'They will not be able to send any report, including SOS, until this ends. The app tells them to call a hotline in an emergency.',
      cta: 'Suspend account',
      color: STOP, Icon: Ban,
    },
    reinstate: {
      title: detail.standing === 'suspended' ? `Lift the suspension on ${name}` : `Clear the warnings on ${name}`,
      body: detail.standing === 'suspended'
        ? 'They can send reports again straight away, and are told so on their phone.'
        : 'The warnings on this account are wiped, and they are told so on their phone.',
      cta: detail.standing === 'suspended' ? 'Lift suspension' : 'Clear warnings',
      color: GOOD, Icon: RotateCcw,
    },
  }[mode]), [mode, name, willSuspend, detail.standing]);

  async function submit() {
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      const result =
        mode === 'warn'
          ? await residentsApi.warn(token, detail.id, { violation: violation!, note: note.trim(), incident_id: incidentId || null })
          : mode === 'suspend'
            ? await residentsApi.suspend(token, detail.id, { violation: violation!, note: note.trim(), days })
            : await residentsApi.reinstate(token, detail.id, { note: note.trim() || undefined, clear_warnings: clear });
      onDone(result);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'That could not be saved.');
      setBusy(false);
    }
  }

  return (
    <Dialog onOpenChange={o => { if (!o && !busy) onClose(); }} open>
      <DialogContent className="flex max-h-[90vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[560px]" data-testid={`resident-${mode}-dialog`}>
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] py-4 pr-14 pl-5 text-left sm:pl-6">
          <div className="flex items-start gap-3">
            <span
              aria-hidden="true"
              className="flex size-10 shrink-0 items-center justify-center rounded-[11px]"
              style={{ color: copy.color, backgroundColor: `color-mix(in srgb, ${copy.color} 13%, transparent)` }}
            >
              <copy.Icon size={19} />
            </span>
            <div className="min-w-0">
              <DialogTitle>{copy.title}</DialogTitle>
              <DialogDescription className="mt-1">{copy.body}</DialogDescription>
            </div>
          </div>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
          <div className="flex flex-col gap-4">
            {needsReason && (
              <fieldset className="m-0 border-0 p-0">
                <legend className="mb-2 text-[12px] font-semibold text-[var(--color-text-secondary)]">
                  What did they do? <span style={{ color: 'var(--color-system-error)' }}>*</span>
                </legend>
                <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2" role="radiogroup">
                  {detail.violations.map(v => {
                    const on = violation === v.key;
                    const Icon = VIOLATION_ICON[v.key] ?? AlertTriangle;
                    return (
                      <button
                        aria-checked={on}
                        className={cn(
                          'flex items-center gap-2.5 rounded-[10px] border px-3 py-2 text-left text-[12.5px] font-medium transition-colors',
                          on
                            ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)] text-foreground'
                            : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
                        )}
                        data-violation={v.key}
                        key={v.key}
                        onClick={() => setViolation(v.key)}
                        role="radio"
                        type="button"
                      >
                        <Icon aria-hidden="true" className="size-4 shrink-0" style={{ color: on ? 'var(--color-brand)' : undefined }} />
                        <span className="min-w-0 flex-1">{v.label}</span>
                        {on && <Check aria-hidden="true" className="size-4 shrink-0" style={{ color: 'var(--color-brand)' }} />}
                      </button>
                    );
                  })}
                </div>
              </fieldset>
            )}

            {mode === 'suspend' && (
              <fieldset className="m-0 border-0 p-0">
                <legend className="mb-2 text-[12px] font-semibold text-[var(--color-text-secondary)]">For how long?</legend>
                <div className="flex flex-wrap gap-1.5" role="radiogroup">
                  {DURATIONS.map(d => {
                    const on = days === d.days;
                    return (
                      <button
                        aria-checked={on}
                        className={cn(
                          'h-8 rounded-full border px-3 text-[12.5px] font-semibold transition-colors',
                          on
                            ? 'border-transparent bg-foreground text-background'
                            : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)]',
                        )}
                        data-days={d.days ?? 'indefinite'}
                        key={d.label}
                        onClick={() => setDays(d.days)}
                        role="radio"
                        type="button"
                      >
                        {d.label}
                      </button>
                    );
                  })}
                </div>
              </fieldset>
            )}

            {mode === 'warn' && detail.recent_reports.length > 0 && (
              <label className="flex flex-col gap-1.5">
                <span className="text-[12px] font-semibold text-[var(--color-text-secondary)]">Which report is this about? <span className="font-normal text-muted-foreground">(optional)</span></span>
                <select onChange={e => setIncidentId(e.target.value)} value={incidentId}>
                  <option value="">Not about one report</option>
                  {detail.recent_reports.map(r => (
                    <option key={r.id} value={r.id}>
                      {(r.record_number ?? r.id.slice(0, 8))} — {r.report_text.slice(0, 60)}
                    </option>
                  ))}
                </select>
              </label>
            )}

            <label className="flex flex-col gap-1.5">
              <span className="text-[12px] font-semibold text-[var(--color-text-secondary)]">
                {needsReason ? 'What happened' : 'A note for the resident'}
                {needsReason
                  ? <span style={{ color: 'var(--color-system-error)' }}> *</span>
                  : <span className="font-normal text-muted-foreground"> (optional)</span>}
              </span>
              <textarea
                aria-label={needsReason ? 'What happened' : 'A note for the resident'}
                maxLength={500}
                onChange={e => setNote(e.target.value)}
                placeholder={needsReason
                  ? 'e.g. Reported a house fire on 30 Sept that the crew found did not exist.'
                  : 'e.g. Appeal accepted after speaking with the barangay captain.'}
                rows={3}
                value={note}
              />
              <span className="text-meta text-muted-foreground">The resident reads this on their phone, word for word.</span>
            </label>

            {mode === 'reinstate' && detail.warning_count > 0 && detail.standing === 'suspended' && (
              <label className="flex items-start gap-2.5 rounded-[10px] border border-[var(--color-surface-border)] px-3 py-2.5">
                <input
                  checked={clear}
                  className="mt-0.5 size-4 shrink-0 accent-[var(--color-brand)]"
                  onChange={e => setClear(e.target.checked)}
                  type="checkbox"
                />
                <span className="text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
                  <strong className="font-semibold text-foreground">Also clear their {detail.warning_count} warning{detail.warning_count === 1 ? '' : 's'}.</strong>{' '}
                  Left on, the very next warning suspends them again.
                </span>
              </label>
            )}

            {mode === 'warn' && (
              <p
                className="rounded-[10px] px-3.5 py-2.5 text-[12.5px] leading-relaxed"
                data-testid="warn-count-note"
                style={willSuspend
                  ? { color: 'var(--color-text-primary)', backgroundColor: `color-mix(in srgb, ${STOP} 9%, transparent)` }
                  : { color: 'var(--color-text-secondary)', backgroundColor: 'var(--color-surface-raised)' }}
              >
                {willSuspend
                  ? <>This will be <strong>warning {nextWarning}</strong>. The account is suspended from reporting for {AUTO_SUSPEND_DAYS} days by itself.</>
                  : <>This will be <strong>warning {nextWarning} of {AUTO_SUSPEND_AT}</strong>. The third warning suspends the account for {AUTO_SUSPEND_DAYS} days by itself.</>}
              </p>
            )}

            {error && <Alert message={error} variant="error" />}
          </div>
        </div>

        <div className="flex shrink-0 flex-wrap items-center justify-end gap-2 border-t border-[var(--color-surface-border)] px-5 py-3 sm:px-6">
          <Button disabled={busy} onClick={onClose} variant="outline">Back</Button>
          <Button
            disabled={!ready || busy}
            onClick={() => void submit()}
            style={{ backgroundColor: copy.color, color: mode === 'reinstate' ? 'var(--color-on-success)' : 'var(--color-text-inverse)' }}
          >
            <copy.Icon data-icon="inline-start" />
            {busy ? 'Saving…' : copy.cta}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
