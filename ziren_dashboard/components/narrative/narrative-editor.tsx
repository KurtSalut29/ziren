'use client';

/**
 * NarrativeEditor - the whole Incident Record Form, on a page of its own.
 *
 * The narrative report used to be a dialog with seven boxes. The paper form it is
 * modelled on has a great deal more: the reporting person, every suspect, every
 * victim, the narrative, and a certification block signed by three people. That
 * is a document written over more than one sitting, so it is a page - an outline
 * beside it that says what is done and what is not, a bar that keeps Save in
 * reach, and a draft that saves itself.
 *
 * WHAT IS PRE-FILLED
 *
 * Whatever Ziren already knows: the reporter's name (split into family / first /
 * middle) and phone, the place, the time, the station and its number, the type of
 * incident. All of it is editable and none of it is silently substituted - see
 * narrative-form.ts for why a box is left empty rather than guessed.
 *
 * DRAFT AND FINALIZED
 *
 * A draft saves itself every minute while it has unsaved changes. Finalizing
 * needs the narrative and does not lock anything: agencies correct reports after
 * signing them, so a finalized report keeps "Save changes" and stays finalized.
 *
 * READ-ONLY
 *
 * A Provincial Admin oversees every station of their agency type and files
 * nothing on another station's behalf, so they get the same page with every box
 * disabled and only the PDF to take away.
 */

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Link from 'next/link';
import {
  ArrowLeft, BadgeCheck, CheckCircle2, Circle, ClipboardList, Download, FileText, Loader2,
  Lock, Plus, Save, ScrollText, ShieldCheck, Trash2, TriangleAlert, UserRound, UserSearch,
  Users, type LucideIcon,
} from 'lucide-react';
import { ApiError, apiClient } from '@/lib/api/client';
import {
  downloadNarrativeReportPdf, fetchIncidentDetail, fetchNarrativeReport, saveNarrativeReport,
  type IncidentDetail, type NarrativeDetails, type NarrativeReport,
} from '@/lib/api/dispatch';
import { signOut, useAuth } from '@/lib/hooks/useAuth';
import { toast } from '@/lib/toast';
import { formatDateTime } from '@/lib/format/datetime';
import { displayPrefs } from '@/lib/prefs/definitions';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import {
  COPY_FOR_CHOICES, OFFENSE_SUGGESTIONS, emptyPerson, emptySuspect, fromLocalInput, fullNameOf,
  mergeDetails, narrativeDefaults, progressOf, residentAccount, toLocalInput,
} from '@/lib/incidents/narrative-form';
import { Button } from '@/components/efferd/ui/button';
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from '@/components/efferd/ui/alert-dialog';
import { Field, FieldGroup, PersonFields, SuspectExtras } from './person-fields';

/** How often an unsaved draft saves itself. */
const AUTOSAVE_MS = 60_000;

type Removal = { kind: 'suspect' | 'victim'; index: number } | null;

/** One icon per section, the same in the outline and on the card it points to. */
const SECTION_ICON: Record<string, LucideIcon> = {
  case: ClipboardList,
  a: UserRound,
  b: UserSearch,
  c: Users,
  d: ScrollText,
  cert: BadgeCheck,
};

/** A box Ziren fills in and nobody edits: visibly not a box to type in. */
const LOCKED_INPUT = 'cursor-default bg-[var(--color-surface-raised)] text-[var(--color-text-secondary)] focus:border-[var(--color-surface-border)] focus:shadow-none';

export function NarrativeEditor({ incidentId }: { incidentId: string }) {
  const { token, isProvincialAdmin, hydrated } = useAuth();
  const readOnly = isProvincialAdmin;
  const display = displayPrefs.use();

  const [incident, setIncident] = useState<IncidentDetail | null>(null);
  const [existing, setExisting] = useState<NarrativeReport | null>(null);
  const [detailsSupported, setDetailsSupported] = useState(true);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [narrative, setNarrative] = useState('');
  const [referenceNo, setReferenceNo] = useState('');
  const [occurredAt, setOccurredAt] = useState('');
  const [place, setPlace] = useState('');
  const [preparedBy, setPreparedBy] = useState('');
  const [details, setDetails] = useState<NarrativeDetails>(() => mergeDetails(null));

  const [saving, setSaving] = useState<'draft' | 'finalize' | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [savedAt, setSavedAt] = useState<Date | null>(null);
  const [removal, setRemoval] = useState<Removal>(null);
  const [active, setActive] = useState('case');

  /** What the server holds, as a string - "is there anything unsaved" is a comparison against it. */
  const savedSnapshot = useRef<string>('');
  const narrativeRef = useRef<HTMLTextAreaElement>(null);

  const snapshot = useMemo(
    () => JSON.stringify({ narrative, referenceNo, occurredAt, place, preparedBy, details }),
    [narrative, referenceNo, occurredAt, place, preparedBy, details],
  );
  const dirty = !loading && snapshot !== savedSnapshot.current;

  // ── Load ────────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!token) return;
    let cancelled = false;
    setLoading(true);
    setLoadError(null);

    (async () => {
      try {
        const [inc, state, me] = await Promise.all([
          fetchIncidentDetail(incidentId, token),
          fetchNarrativeReport(incidentId, token),
          apiClient.get<{ full_name?: string }>('/users/me', token).catch(() => null),
        ]);
        if (cancelled) return;

        const defaults = narrativeDefaults(inc, me?.full_name ?? null);
        const report = state.report;
        const hasDetails = !!report?.details && Object.keys(report.details).length > 0;

        const next = {
          narrative: report?.narrative ?? '',
          referenceNo: report?.reference_no ?? '',
          occurredAt: toLocalInput(report?.incident_occurred_at ?? defaults.occurredAt),
          place: report?.place_of_incident ?? defaults.place,
          preparedBy: report?.prepared_by_name ?? defaults.preparedBy,
          // A report saved before migration 040 (or before anything was typed in
          // the detailed boxes) starts from what Ziren knows, not from blank.
          details: hasDetails ? mergeDetails(report!.details) : defaults.details,
        };
        setIncident(inc);
        setExisting(report);
        setDetailsSupported(state.details_supported);
        setNarrative(next.narrative);
        setReferenceNo(next.referenceNo);
        setOccurredAt(next.occurredAt);
        setPlace(next.place);
        setPreparedBy(next.preparedBy);
        setDetails(next.details);
        // What was just loaded IS the baseline. A brand-new form filled from
        // defaults is not "unsaved work" until somebody changes something.
        savedSnapshot.current = JSON.stringify(next);
        setSavedAt(report ? new Date(report.updated_at) : null);
      } catch (e) {
        if (cancelled) return;
        if (e instanceof ApiError && e.status === 401) { signOut(); return; }
        setLoadError(e instanceof Error ? e.message : 'Could not load this report.');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [incidentId, token]);

  // ── Save ────────────────────────────────────────────────────────────────
  const save = useCallback(async (finalize: boolean, opts: { silent?: boolean } = {}) => {
    if (!token || readOnly) return false;
    if (finalize && !narrative.trim()) {
      toast.error('Write the narrative of the incident before finalizing.');
      document.getElementById('sec-d')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      narrativeRef.current?.focus();
      return false;
    }
    setSaving(finalize ? 'finalize' : 'draft');
    // What is being sent, captured now: the person may keep typing while the
    // request is in flight, and what they type after this is still unsaved.
    const sent = JSON.stringify({ narrative, referenceNo, occurredAt, place, preparedBy, details });
    try {
      const saved = await saveNarrativeReport(incidentId, {
        narrative: narrative.trim(),
        reporting_person_name: fullNameOf(details.reporting_person) || null,
        incident_occurred_at: fromLocalInput(occurredAt),
        place_of_incident: place.trim() || null,
        prepared_by_name: preparedBy.trim() || null,
        investigator_name: details.certification.investigator_rank_name.trim() || null,
        reference_no: referenceNo.trim() || null,
        details,
        finalize,
      }, token);
      setExisting(saved);
      setDetailsSupported(saved.details_supported);
      setSavedAt(new Date(saved.updated_at));
      savedSnapshot.current = sent;
      if (!saved.details_saved) {
        toast.warning('Saved, but the detailed sections were not stored', {
          detail: 'Run migration 040 in the Supabase SQL Editor, then save again.',
          duration: 9000,
        });
      } else if (!opts.silent) {
        toast.success(finalize ? 'Narrative report finalized.' : saved.status === 'finalized' ? 'Changes saved.' : 'Draft saved.');
      }
      return true;
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return false; }
      toast.error(e instanceof Error ? e.message : 'Could not save the narrative report.');
      return false;
    } finally {
      setSaving(null);
    }
  }, [token, readOnly, incidentId, narrative, details, occurredAt, place, preparedBy, referenceNo]);

  // A draft saves itself. Never a FINALIZED report (the person editing it should
  // decide when a correction to a signed document is saved), and never while
  // there is nothing worth keeping.
  const autosaveRef = useRef(save);
  autosaveRef.current = save;
  const hasContent = narrative.trim() !== '' || details.suspects.length > 0 || details.victims.length > 0;
  useEffect(() => {
    if (readOnly || loading || existing?.status === 'finalized') return;
    const id = setInterval(() => {
      if (document.visibilityState !== 'visible') return;
      if (snapshot !== savedSnapshot.current && hasContent && !saving) void autosaveRef.current(false, { silent: true });
    }, AUTOSAVE_MS);
    return () => clearInterval(id);
  }, [readOnly, loading, existing?.status, snapshot, hasContent, saving]);

  // Closing the tab with unsaved work asks first.
  useEffect(() => {
    if (!dirty || readOnly) return;
    const onBefore = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ''; };
    window.addEventListener('beforeunload', onBefore);
    return () => window.removeEventListener('beforeunload', onBefore);
  }, [dirty, readOnly]);

  async function handleDownload() {
    if (!token) return;
    setDownloading(true);
    try {
      // The PDF is the SAVED report. A person who has just typed a paragraph and
      // presses Download expects it to be in the file.
      if (dirty && !readOnly && hasContent) {
        const ok = await save(false, { silent: true });
        if (!ok) return;
      }
      await downloadNarrativeReportPdf(incidentId, token);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Could not download the PDF.');
    } finally {
      setDownloading(false);
    }
  }

  // ── Editing the lists ───────────────────────────────────────────────────
  const patch = (next: Partial<NarrativeDetails>) => setDetails(d => ({ ...d, ...next }));
  const setSuspect = (i: number, s: NarrativeDetails['suspects'][number]) =>
    setDetails(d => ({ ...d, suspects: d.suspects.map((x, j) => (j === i ? s : x)) }));
  const setVictim = (i: number, v: NarrativeDetails['victims'][number]) =>
    setDetails(d => ({ ...d, victims: d.victims.map((x, j) => (j === i ? v : x)) }));

  function confirmRemoval() {
    if (!removal) return;
    setDetails(d => removal.kind === 'suspect'
      ? { ...d, suspects: d.suspects.filter((_, j) => j !== removal.index) }
      : { ...d, victims: d.victims.filter((_, j) => j !== removal.index) });
    setRemoval(null);
  }

  // ── Outline ─────────────────────────────────────────────────────────────
  const progress = useMemo(
    () => progressOf(narrative, details, { referenceNo, occurredAt, place }),
    [narrative, details, referenceNo, occurredAt, place],
  );

  useEffect(() => {
    if (loading) return;
    const sections = Array.from(document.querySelectorAll<HTMLElement>('[data-section]'));
    if (sections.length === 0) return;
    const io = new IntersectionObserver(entries => {
      for (const e of entries) if (e.isIntersecting) setActive((e.target as HTMLElement).dataset.section ?? 'case');
    }, { rootMargin: '-18% 0px -70% 0px' });
    sections.forEach(s => io.observe(s));
    return () => io.disconnect();
  }, [loading, incident]);

  const goTo = (key: string) => {
    setActive(key);
    document.getElementById(`sec-${key}`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  // ── Rendering ───────────────────────────────────────────────────────────
  if (!hydrated || loading) return <_Skeleton />;
  if (loadError || !incident) {
    return (
      <_Notice icon={TriangleAlert} title="This report could not be opened" tone="error">
        {loadError ?? 'The incident was not found.'}
        <div className="mt-4"><Link className="font-semibold underline" href="/narrative-reports">Back to Narrative Reports</Link></div>
      </_Notice>
    );
  }
  if (incident.status !== 'resolved' && !existing) {
    return (
      <_Notice icon={FileText} title="This incident is not resolved yet" tone="info">
        A narrative report describes what happened, so it can only be written once the incident is resolved.
        {' '}It is <strong>{incident.status.replace('_', ' ')}</strong> now.
        <div className="mt-4 flex gap-4">
          <Link className="font-semibold underline" href={`/incidents/${incidentId}`}>Open the incident</Link>
          <Link className="font-semibold underline" href="/narrative-reports">Back to Narrative Reports</Link>
        </div>
      </_Notice>
    );
  }
  if (readOnly && !existing) {
    return (
      <_Notice icon={FileText} title="No narrative report yet" tone="info">
        The agency that handled this incident has not written a narrative report for it.
        <div className="mt-4"><Link className="font-semibold underline" href="/narrative-reports">Back to Narrative Reports</Link></div>
      </_Notice>
    );
  }

  const categoryLabel = CATEGORY_LABELS[incident.incident_category ?? ''] ?? 'Incident';
  const finalized = existing?.status === 'finalized';
  const busy = saving !== null;
  const recordNo = incident.record_number ?? incident.id.slice(0, 8);
  const statusText = saving
    ? 'Saving…'
    : dirty ? 'Unsaved changes'
    : savedAt ? `All changes saved · ${savedAt.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`
    : 'Not saved yet';
  const statusDot = saving || dirty
    ? 'var(--color-system-warning)'
    : savedAt ? 'var(--color-system-success)' : 'var(--color-text-muted)';
  const doneCount = progress.filter(p => p.done).length;
  const sectionOf = (key: string) => progress.find(p => p.key === key);

  return (
    <div className="min-h-full">
      {/* ── The bar that stays ── */}
      <div className="sticky top-0 z-20 border-b border-[var(--color-surface-border)] bg-background/95 px-6 py-3 backdrop-blur md:px-7">
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
          <Link
            aria-label="Back to Narrative Reports"
            className="inline-flex size-8 items-center justify-center rounded-[var(--radius-control)] border border-[var(--color-surface-border)] text-muted-foreground transition-colors hover:bg-[var(--color-surface-hover)] hover:text-foreground"
            href="/narrative-reports"
            onClick={e => {
              if (dirty && !readOnly && !window.confirm('You have unsaved changes. Leave without saving?')) e.preventDefault();
            }}
          >
            <ArrowLeft size={15} />
          </Link>
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-[15px] font-semibold text-foreground">Narrative Report</h1>
              <span className="text-[12.5px] font-medium text-[var(--color-text-secondary)]">{categoryLabel}</span>
              <span className="font-mono text-[12.5px] text-muted-foreground">{recordNo}</span>
              {existing ? (
                <span
                  className="rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide"
                  data-report-status={existing.status}
                  style={finalized
                    ? { color: 'var(--color-system-success)', borderColor: 'color-mix(in srgb, var(--color-system-success) 45%, transparent)', backgroundColor: 'color-mix(in srgb, var(--color-system-success) 10%, transparent)' }
                    : { color: 'var(--color-system-warning)', borderColor: 'color-mix(in srgb, var(--color-system-warning) 45%, transparent)', backgroundColor: 'color-mix(in srgb, var(--color-system-warning) 10%, transparent)' }}
                >
                  {existing.status}
                </span>
              ) : (
                <span className="rounded-full border border-[var(--color-surface-border)] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                  New
                </span>
              )}
            </div>
            <p className="mt-0.5 flex items-center gap-1.5 text-[12px] text-muted-foreground" data-save-state>
              {!readOnly && (
                <span aria-hidden="true" className="size-1.5 shrink-0 rounded-full" style={{ backgroundColor: statusDot }} />
              )}
              {readOnly ? 'Oversight view - filed by the assigned agency.' : statusText}
            </p>
          </div>

          <div className="ml-auto flex flex-wrap items-center gap-2">
            {existing && (
              <Button
                disabled={downloading || busy}
                onClick={() => void handleDownload()}
                size="sm"
                variant="outline"
              >
                {downloading ? <Loader2 className="animate-spin" data-icon="inline-start" size={14} /> : <Download data-icon="inline-start" size={14} />}
                Download PDF
              </Button>
            )}
            {!readOnly && (
              <>
                <Button
                  disabled={busy || (!dirty && !!existing)}
                  onClick={() => void save(false)}
                  size="sm"
                  variant="outline"
                >
                  {saving === 'draft' ? <Loader2 className="animate-spin" data-icon="inline-start" size={14} /> : <Save data-icon="inline-start" size={14} />}
                  {finalized ? 'Save changes' : 'Save draft'}
                </Button>
                {!finalized && (
                  <Button
                    disabled={busy}
                    onClick={() => void save(true)}
                    size="sm"
                    style={{ backgroundColor: 'var(--color-system-success)', color: 'var(--color-on-success)' }}
                  >
                    {saving === 'finalize' ? <Loader2 className="animate-spin" data-icon="inline-start" size={14} /> : <ShieldCheck data-icon="inline-start" size={14} />}
                    Finalize report
                  </Button>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      <div className="flex gap-6 px-6 py-5 md:px-7">
        {/* ── Outline ── */}
        <nav aria-label="Sections of this report" className="hidden w-[232px] shrink-0 lg:block">
          <div className="sticky top-[88px] flex flex-col gap-3">
            {/* How far along the whole form is, above the list that says where. */}
            <div
              className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] px-3.5 py-3"
              data-progress={`${doneCount}/${progress.length}`}
            >
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-[10.5px] font-bold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">Progress</span>
                <span className="text-[12px] font-semibold tabular-nums text-foreground">
                  {doneCount} of {progress.length} sections
                </span>
              </div>
              <div
                aria-label={`${doneCount} of ${progress.length} sections complete`}
                aria-valuemax={progress.length}
                aria-valuemin={0}
                aria-valuenow={doneCount}
                className="mt-2 h-1.5 overflow-hidden rounded-full bg-[var(--color-surface-raised)]"
                role="progressbar"
              >
                <div
                  className="h-full rounded-full transition-[width] duration-300"
                  style={{ width: `${(doneCount / progress.length) * 100}%`, backgroundColor: 'var(--color-system-success)' }}
                />
              </div>
            </div>

            <ol className="flex flex-col gap-0.5">
              {progress.map(p => {
                const on = active === p.key;
                return (
                  <li key={p.key}>
                    <button
                      aria-current={on ? 'true' : undefined}
                      className="relative flex w-full items-start gap-2.5 rounded-[var(--radius-control)] px-3 py-2 text-left transition-colors hover:bg-[var(--color-surface-hover)]"
                      data-outline={p.key}
                      onClick={() => goTo(p.key)}
                      style={on ? { backgroundColor: 'var(--color-surface-raised)' } : undefined}
                      type="button"
                    >
                      {on && (
                        <span
                          aria-hidden="true"
                          className="absolute top-2 bottom-2 left-0 w-[3px] rounded-full"
                          style={{ backgroundColor: 'var(--color-brand)' }}
                        />
                      )}
                      {p.done
                        ? <CheckCircle2 className="mt-0.5 shrink-0" size={15} style={{ color: 'var(--color-system-success)' }} />
                        : <Circle className="mt-0.5 shrink-0 text-[var(--color-text-tertiary)]" size={15} />}
                      <span className="min-w-0">
                        <span className={`block text-[13px] ${on ? 'font-semibold text-foreground' : 'font-medium text-[var(--color-text-secondary)]'}`}>
                          {p.label}
                        </span>
                        <span className="block text-[11.5px] text-muted-foreground">{p.hint}</span>
                      </span>
                    </button>
                  </li>
                );
              })}
            </ol>
          </div>
        </nav>

        {/* ── The form ── */}
        <fieldset className="m-0 min-w-0 flex-1 border-0 p-0 [&_input]:h-10 [&_input]:text-[13.5px] [&_textarea]:text-[13.5px]" disabled={readOnly}>
          <div className="flex flex-col gap-5">
            {!detailsSupported && !readOnly && (
              <div
                className="flex items-start gap-3 rounded-[var(--radius-card)] border px-4 py-3"
                data-details-unsupported
                role="status"
                style={{ borderColor: 'var(--color-system-warning)', backgroundColor: 'var(--color-system-warning-bg)' }}
              >
                <TriangleAlert className="mt-0.5 shrink-0" size={16} style={{ color: 'var(--color-system-warning)' }} />
                <div className="text-[12.5px] leading-relaxed text-[var(--color-text-primary)]">
                  <p className="font-semibold">The detailed sections cannot be saved yet.</p>
                  <p className="mt-0.5 text-[var(--color-text-secondary)]">
                    This database is missing one column. Run <span className="font-mono">040_narrative_report_details.sql</span> in
                    the Supabase SQL Editor. Until then the narrative and the basic boxes are saved, and the people and
                    contacts you type here are kept only while this page stays open.
                  </p>
                </div>
              </div>
            )}

            {/* Case details */}
            <_Card
              description="How this incident is filed. Filled in from the report where Ziren knows it; change anything that is wrong."
              id="case"
              progress={sectionOf('case')}
              kicker="Case"
              title="Case details"
            >
              <div className="grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
                <FieldGroup first title="Filing" />
                <Field className="sm:col-span-4" hint="Your own blotter / log number - not the Ziren record number" label="IRF entry number">
                  <input onChange={e => setReferenceNo(e.target.value)} placeholder="e.g. 087803000-202405-6352" type="text" value={referenceNo} />
                </Field>
                <Field className="sm:col-span-4" hint="Set by Ziren" label="Ziren record no.">
                  <_Locked value={recordNo} />
                </Field>
                <Field className="sm:col-span-4" label="Copy for">
                  <input list="copyfor-choices" onChange={e => patch({ copy_for: e.target.value })} type="text" value={details.copy_for} />
                  <datalist id="copyfor-choices">
                    {COPY_FOR_CHOICES.map(o => <option key={o} value={o} />)}
                  </datalist>
                </Field>
                <Field className="sm:col-span-4" label="Type of incident">
                  <input
                    list="offense-choices"
                    onChange={e => patch({ offense: e.target.value })}
                    placeholder={categoryLabel}
                    type="text"
                    value={details.offense}
                  />
                  <datalist id="offense-choices">
                    {(OFFENSE_SUGGESTIONS[incident.incident_category ?? 'other'] ?? []).map(o => <option key={o} value={o} />)}
                  </datalist>
                </Field>
                <Field className="sm:col-span-8" hint="The law or offence, if any - as it would be written on the form" label="Statute / charge / description">
                  <input
                    onChange={e => patch({ offense_detail: e.target.value })}
                    placeholder="e.g. Consummated the Forestry Reform Code of the Philippines (illegal logging)"
                    type="text"
                    value={details.offense_detail}
                  />
                </Field>

                <FieldGroup title="When" />
                <Field className="sm:col-span-6" hint="Set by Ziren when the report arrived" label="Date and time reported">
                  <_Locked value={formatDateTime(incident.created_at, display)} />
                </Field>
                <Field className="sm:col-span-6" hint="Change this if it happened earlier than it was reported" label="Date and time of incident">
                  <input onChange={e => setOccurredAt(e.target.value)} type="datetime-local" value={occurredAt} />
                </Field>

                <FieldGroup title="Where" />
                <Field className="sm:col-span-4" label="Barangay">
                  <input onChange={e => patch({ place_barangay: e.target.value })} type="text" value={details.place_barangay} />
                </Field>
                <Field className="sm:col-span-4" label="Town / city">
                  <input onChange={e => patch({ place_town: e.target.value })} type="text" value={details.place_town} />
                </Field>
                <Field className="sm:col-span-4" label="Province">
                  <input onChange={e => patch({ place_province: e.target.value })} type="text" value={details.place_province} />
                </Field>
                <Field className="sm:col-span-12" label="Place of incident (full address)">
                  <input onChange={e => setPlace(e.target.value)} type="text" value={place} />
                </Field>
              </div>
            </_Card>

            {/* Item A */}
            <_Card
              description="The person who reported the incident."
              id="a"
              progress={sectionOf('a')}
              kicker='Item "A"'
              title="Reporting person"
            >
              <PersonFields
                onChange={p => patch({ reporting_person: p })}
                relationLabel="Relation to suspect"
                value={details.reporting_person}
              />
            </_Card>

            {/* Item B */}
            <_Card
              actions={!readOnly && (
                <Button onClick={() => patch({ suspects: [...details.suspects, emptySuspect()] })} size="sm" variant="outline">
                  <Plus data-icon="inline-start" size={14} /> Add suspect
                </Button>
              )}
              description="Anyone alleged to have caused the incident. Leave empty when there is none - a fire, a flood, an accident with no one at fault."
              id="b"
              progress={sectionOf('b')}
              kicker='Item "B"'
              title="Suspect's data"
            >
              {details.suspects.length === 0 ? (
                <_Empty text="No suspect recorded." />
              ) : (
                <div className="flex flex-col gap-4">
                  {details.suspects.map((s, i) => (
                    <_PersonCard
                      key={i}
                      label={`Suspect ${i + 1}${details.suspects.length > 1 ? ` of ${details.suspects.length}` : ''}`}
                      name={fullNameOf(s)}
                      onRemove={readOnly ? undefined : () => setRemoval({ kind: 'suspect', index: i })}
                    >
                      <PersonFields onChange={next => setSuspect(i, next)} relationLabel="Relation to victim" value={s} />
                      <SuspectExtras onChange={next => setSuspect(i, next)} value={s} />
                    </_PersonCard>
                  ))}
                </div>
              )}
            </_Card>

            {/* Item C */}
            <_Card
              actions={!readOnly && (
                <Button onClick={() => patch({ victims: [...details.victims, emptyPerson()] })} size="sm" variant="outline">
                  <Plus data-icon="inline-start" size={14} /> Add victim
                </Button>
              )}
              description="Anyone who was hurt, lost property or was otherwise affected."
              id="c"
              progress={sectionOf('c')}
              kicker='Item "C"'
              title="Victim's data"
            >
              {details.victims.length === 0 ? (
                <_Empty text="No victim recorded." />
              ) : (
                <div className="flex flex-col gap-4">
                  {details.victims.map((v, i) => (
                    <_PersonCard
                      key={i}
                      label={`Victim ${i + 1}${details.victims.length > 1 ? ` of ${details.victims.length}` : ''}`}
                      name={fullNameOf(v)}
                      onRemove={readOnly ? undefined : () => setRemoval({ kind: 'victim', index: i })}
                    >
                      <PersonFields onChange={next => setVictim(i, next)} relationLabel="Relation to suspect" value={v} />
                    </_PersonCard>
                  ))}
                </div>
              )}
            </_Card>

            {/* Item D */}
            <_Card
              description="The who, what, when, where, why and how - the confirmed account of what happened and what was done about it."
              id="d"
              progress={sectionOf('d')}
              kicker='Item "D"'
              title="Narrative of incident"
            >
              <_Facts incident={incident} />

              <div className="mt-4 flex flex-wrap items-center justify-between gap-2">
                <span className="text-[12px] font-semibold text-[var(--color-text-secondary)]">
                  Narrative <span style={{ color: 'var(--color-system-error)' }}>*</span>
                  <span className="ml-1.5 font-normal text-muted-foreground">needed to finalize</span>
                </span>
                {!readOnly && residentAccount(incident) && (
                  <button
                    className="text-[12px] font-semibold text-[var(--color-brand)] underline-offset-2 hover:underline"
                    onClick={() => {
                      const said = residentAccount(incident);
                      setNarrative(n => (n.trim() ? `${n.trim()}\n\nThe resident's report read: "${said}"` : `The resident reported: "${said}"`));
                      narrativeRef.current?.focus();
                    }}
                    type="button"
                  >
                    Start from what the resident reported
                  </button>
                )}
              </div>
              <textarea
                aria-label="Narrative of incident"
                className="mt-1.5 w-full leading-relaxed"
                onChange={e => setNarrative(e.target.value)}
                placeholder="Who reported it, and when? What did the crew find on arrival? What happened, in order? What was done, and how did it end?"
                ref={narrativeRef}
                rows={14}
                style={{ resize: 'vertical', minHeight: 260 }}
                value={narrative}
              />
              <p className="mt-1.5 text-[11.5px] text-muted-foreground">
                {narrative.trim() ? `${narrative.trim().split(/\s+/).length} words` : 'Nothing written yet'}
                {' · '}Leave a blank line between paragraphs.
              </p>

              <div className="mt-5 grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
                <FieldGroup first title="Supporting details" />
                <Field className="sm:col-span-12" label="Witnesses">
                  <textarea onChange={e => patch({ witnesses: e.target.value })} placeholder="Names and contact details of anyone who saw it" rows={2} style={{ resize: 'vertical' }} value={details.witnesses} />
                </Field>
                <Field className="sm:col-span-6" label="Estimated damage / property involved">
                  <textarea onChange={e => patch({ property_damage: e.target.value })} rows={2} style={{ resize: 'vertical' }} value={details.property_damage} />
                </Field>
                <Field className="sm:col-span-6" label="Actions taken">
                  <textarea onChange={e => patch({ actions_taken: e.target.value })} rows={2} style={{ resize: 'vertical' }} value={details.actions_taken} />
                </Field>
              </div>
            </_Card>

            {/* Certification and contacts */}
            <_Card
              description="Who prepared, sworn and recorded this report, and where the reporting person can follow it up."
              id="cert"
              progress={sectionOf('cert')}
              kicker="Certification"
              title="Certification & station contacts"
            >
              <div className="grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
                <FieldGroup first title="Who signs" />
                <Field className="sm:col-span-6" label="Prepared by">
                  <input onChange={e => setPreparedBy(e.target.value)} placeholder="Your name" type="text" value={preparedBy} />
                </Field>
                <Field className="sm:col-span-6" label="Name of administering officer (duty officer)">
                  <input onChange={e => patch({ certification: { ...details.certification, administering_officer: e.target.value } })} type="text" value={details.certification.administering_officer} />
                </Field>
                <Field className="sm:col-span-6" label="Rank, name and designation of investigator on case">
                  <input onChange={e => patch({ certification: { ...details.certification, investigator_rank_name: e.target.value } })} type="text" value={details.certification.investigator_rank_name} />
                </Field>
                <Field className="sm:col-span-6" label="Rank / name of desk officer (recorded in the blotter by)">
                  <input onChange={e => patch({ certification: { ...details.certification, desk_officer_rank_name: e.target.value } })} type="text" value={details.certification.desk_officer_rank_name} />
                </Field>

                <FieldGroup title="Station contacts" />
                <Field className="sm:col-span-6" label="Name of station">
                  <input onChange={e => patch({ station: { ...details.station, name: e.target.value } })} type="text" value={details.station.name} />
                </Field>
                <Field className="sm:col-span-3" label="Telephone">
                  <input onChange={e => patch({ station: { ...details.station, telephone: e.target.value } })} type="text" value={details.station.telephone} />
                </Field>
                <Field className="sm:col-span-3" label="Mobile phone">
                  <input onChange={e => patch({ station: { ...details.station, mobile: e.target.value } })} type="text" value={details.station.mobile} />
                </Field>
                <Field className="sm:col-span-12" label="Name of chief / head of office">
                  <input onChange={e => patch({ station: { ...details.station, chief: e.target.value } })} type="text" value={details.station.chief} />
                </Field>
              </div>
              <p className="mt-4 text-[11.5px] text-muted-foreground">
                The signatures themselves are not typed here - they are signed on the printed copy.
              </p>
            </_Card>

            {!readOnly && (
              <div className="flex flex-wrap items-center justify-between gap-3 rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-5 py-4">
                <p className="max-w-[60ch] text-[12.5px] text-[var(--color-text-secondary)]">
                  {finalized
                    ? 'This report is finalized. You can still correct it - save your changes and download a fresh PDF.'
                    : 'A draft can be saved with parts still empty. Finalize when the narrative is written and the people are named.'}
                </p>
                <div className="flex gap-2">
                  <Button disabled={busy || (!dirty && !!existing)} onClick={() => void save(false)} size="sm" variant="outline">
                    {finalized ? 'Save changes' : 'Save draft'}
                  </Button>
                  {!finalized && (
                    <Button
                      disabled={busy}
                      onClick={() => void save(true)}
                      size="sm"
                      style={{ backgroundColor: 'var(--color-system-success)', color: 'var(--color-on-success)' }}
                    >
                      Finalize report
                    </Button>
                  )}
                </div>
              </div>
            )}
          </div>
        </fieldset>
      </div>

      <AlertDialog onOpenChange={o => { if (!o) setRemoval(null); }} open={removal !== null}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              Remove this {removal?.kind === 'victim' ? 'victim' : 'suspect'}?
            </AlertDialogTitle>
            <AlertDialogDescription>
              Everything typed for this person is removed from the report. It is not saved anywhere else.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep</AlertDialogCancel>
            <AlertDialogAction onClick={e => { e.preventDefault(); confirmRemoval(); }} variant="destructive">
              Remove
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

// ── Pieces ────────────────────────────────────────────────────────────────

function _Card({
  id, kicker, title, description, actions, progress, children,
}: {
  id: string;
  kicker: string;
  title: string;
  description?: string;
  actions?: React.ReactNode;
  /** This section's line from the outline, repeated on the card it describes. */
  progress?: { hint: string; done: boolean };
  children: React.ReactNode;
}) {
  const Icon = SECTION_ICON[id] ?? FileText;
  return (
    <section
      className="scroll-mt-24 overflow-hidden rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-[var(--shadow-card)]"
      data-section={id}
      id={`sec-${id}`}
    >
      <header className="flex flex-wrap items-start gap-x-3.5 gap-y-3 border-b border-[var(--color-surface-border)] bg-[color-mix(in_srgb,var(--color-surface-raised)_45%,var(--color-surface-card))] px-5 py-4">
        <span
          aria-hidden="true"
          className="flex size-10 shrink-0 items-center justify-center rounded-[11px]"
          style={{ color: 'var(--color-brand)', backgroundColor: 'color-mix(in srgb, var(--color-brand) 12%, transparent)' }}
        >
          <Icon size={19} />
        </span>
        <div className="min-w-0 flex-1 basis-[240px]">
          <p className="text-[10.5px] font-bold uppercase tracking-[0.1em] text-[var(--color-brand)]">{kicker}</p>
          <h2 className="mt-0.5 text-[16px] leading-tight font-semibold text-foreground">{title}</h2>
          {description && <p className="mt-1 max-w-[64ch] text-[12.5px] leading-relaxed text-muted-foreground">{description}</p>}
        </div>
        <div className="flex shrink-0 flex-wrap items-center gap-2">
          {progress && (
            <span
              className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[11.5px] leading-none font-semibold whitespace-nowrap"
              data-section-progress={progress.done ? 'done' : 'todo'}
              style={progress.done
                ? { color: 'var(--color-system-success)', borderColor: 'color-mix(in srgb, var(--color-system-success) 35%, transparent)', backgroundColor: 'color-mix(in srgb, var(--color-system-success) 9%, transparent)' }
                : { color: 'var(--color-text-secondary)', borderColor: 'var(--color-surface-border)', backgroundColor: 'var(--color-surface-card)' }}
            >
              {progress.done ? <CheckCircle2 aria-hidden="true" size={12} /> : <Circle aria-hidden="true" size={12} />}
              {progress.hint}
            </span>
          )}
          {actions}
        </div>
      </header>
      <div className="px-5 py-5">{children}</div>
    </section>
  );
}

/** A box Ziren fills in: shown, not editable, and marked so with a lock. */
function _Locked({ value }: { value: string }) {
  return (
    <span className="relative block">
      <input className={`${LOCKED_INPUT} pr-9`} readOnly tabIndex={-1} type="text" value={value} />
      <Lock aria-hidden="true" className="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-[var(--color-text-muted)]" size={13} />
    </span>
  );
}

function _PersonCard({
  label, name, onRemove, children,
}: {
  label: string;
  name: string;
  onRemove?: () => void;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-[var(--radius-card)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/40 p-4" data-person>
      <div className="mb-4 flex items-center justify-between gap-3 border-b border-[var(--color-surface-border)] pb-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <span className="flex size-7 shrink-0 items-center justify-center rounded-full bg-[var(--color-surface-card)] text-[var(--color-text-secondary)] ring-1 ring-[var(--color-surface-border)]">
            <UserRound size={14} />
          </span>
          <span className="text-[13px] font-semibold text-foreground">{label}</span>
          <span className="truncate text-[12.5px] text-muted-foreground">{name ? `· ${name}` : '· not named yet'}</span>
        </div>
        {onRemove && (
          <button
            aria-label={`Remove ${label}`}
            className="inline-flex items-center gap-1.5 rounded-[var(--radius-control)] px-2 py-1 text-[12px] font-semibold text-[var(--color-severity-critical)] transition-colors hover:bg-[var(--color-severity-critical-bg)]"
            onClick={onRemove}
            type="button"
          >
            <Trash2 size={13} /> Remove
          </button>
        )}
      </div>
      {children}
    </div>
  );
}

function _Empty({ text }: { text: string }) {
  return (
    <p className="rounded-[var(--radius-control)] border border-dashed border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/30 px-4 py-6 text-center text-[12.5px] text-muted-foreground">
      {text}
    </p>
  );
}

/** What Ziren itself recorded about this incident - the facts a narrative should agree with. */
function _Facts({ incident }: { incident: IncidentDetail }) {
  const display = displayPrefs.use();
  const facts: [string, string | null][] = [
    ['Reported', formatDateTime(incident.created_at, display)],
    ['Dispatched', incident.dispatched_at ? formatDateTime(incident.dispatched_at, display) : null],
    ['Resolved', incident.resolved_at ? formatDateTime(incident.resolved_at, display) : null],
    ['Responder', incident.responder?.full_name ?? null],
    ['Station', incident.stations?.name ?? null],
  ];
  return (
    <div className="rounded-[var(--radius-control)] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)]/50 px-4 py-3" data-facts>
      <p className="mb-2 text-[10.5px] font-bold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">
        What Ziren recorded
      </p>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-5">
        {facts.map(([k, v]) => (
          <div className="min-w-0" key={k}>
            <dt className="text-[11px] text-muted-foreground">{k}</dt>
            <dd className="truncate text-[12.5px] font-medium text-foreground" title={v ?? undefined}>{v ?? '-'}</dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

function _Skeleton() {
  return (
    <div className="animate-pulse px-6 py-6 md:px-7">
      <div className="mb-5 h-10 w-1/2 rounded bg-muted" />
      <div className="flex gap-6">
        <div className="hidden h-64 w-[220px] rounded bg-muted lg:block" />
        <div className="flex flex-1 flex-col gap-5">
          {[0, 1, 2].map(i => <div className="h-56 rounded-[var(--radius-card)] bg-muted" key={i} />)}
        </div>
      </div>
    </div>
  );
}

function _Notice({
  icon: Icon, title, tone, children,
}: {
  icon: typeof FileText;
  title: string;
  tone: 'error' | 'info';
  children: React.ReactNode;
}) {
  const color = tone === 'error' ? 'var(--color-severity-critical)' : 'var(--color-system-info)';
  return (
    <div className="mx-auto max-w-[560px] px-6 py-16 text-center">
      <span
        className="mx-auto flex size-12 items-center justify-center rounded-full"
        style={{ backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)`, color }}
      >
        <Icon size={22} />
      </span>
      <h1 className="mt-4 text-[17px] font-semibold text-foreground">{title}</h1>
      <div className="mt-2 text-[13.5px] leading-relaxed text-muted-foreground">{children}</div>
    </div>
  );
}
