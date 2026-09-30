'use client';

/**
 * Writing an announcement, in three steps: what kind, what it says, who and
 * where. Beside it, the card as a resident's phone will show it.
 *
 * WHY STEPS, AND WHY THE COUNT ON THE BUTTON
 *
 * The old form was a title, a message and two drop-downs, and publishing said
 * only "Publish to Residents?". Nothing asked where the evacuation centre was,
 * and nothing said how many people were about to be woken up. Now each kind
 * asks for the facts it is useless without (the backend refuses it otherwise),
 * the place is picked town by town and barangay by barangay, and the publish
 * button carries the number it will reach - worked out by the same code that
 * sends it, so the number is not an estimate.
 *
 * An ALL CLEAR opens straight at step 2: it reaches exactly the people the
 * warning reached (the backend enforces that), so there is nothing to pick.
 */

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowLeft, ArrowRight, Check, LifeBuoy, Loader2, Lock, MapPin, Megaphone, Minus, Plus, ShieldCheck, Users,
} from 'lucide-react';
import { ApiError } from '@/lib/api/client';
import {
  createAnnouncement, previewAudience,
  type Announcement, type AnnouncementCategory, type AnnouncementDetails, type AnnouncementTarget,
  type BarangayRef, type CreateAnnouncementRequest, type EvacuationCenter, type Reach,
} from '@/lib/api/announcements';
import { signOut } from '@/lib/hooks/useAuth';
import { cn } from '@/lib/utils';
import { Alert } from '@/components/ui/alert';
import { Button } from '@/components/efferd/ui/button';
import {
  Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle,
} from '@/components/efferd/ui/dialog';
import { Switch } from '@/components/efferd/ui/switch';
import {
  factChips, HAZARD_LABEL, KIND_OWNERS, KINDS, kindOf, mayIssue, MUNICIPALITIES, placeLine, RAINFALL_COLOR, RAINFALL_LABEL,
  TARGET_LABEL, type Kind,
} from './kinds';

export interface AgencyOption { id: string; name: string; agency_type: string }

/** category opens a new one already on that kind (the Send an alert shortcuts). */
export type ComposerMode = { kind: 'new'; category?: AnnouncementCategory } | { kind: 'all_clear'; of: Announcement };

type Step = 1 | 2 | 3;

const EXPIRY = [
  { key: 'none', label: 'No end', hours: null },
  { key: '6h', label: '6 hours', hours: 6 },
  { key: '12h', label: '12 hours', hours: 12 },
  { key: '24h', label: '1 day', hours: 24 },
  { key: '72h', label: '3 days', hours: 72 },
  { key: '168h', label: '1 week', hours: 168 },
] as const;
type ExpiryKey = typeof EXPIRY[number]['key'];

const TARGETS: AnnouncementTarget[] = ['all', 'resident', 'responder', 'agency_admin', 'agency'];

const FIELD = 'flex flex-col gap-1.5';

/** A kind colour as a solid fill under white text. The dark theme lightens
 *  every token, and white on a light red or green cannot be read - so the fill
 *  is taken a little towards black, which leaves the light theme near its own colour. */
const solid = (c: string) => `color-mix(in srgb, ${c} 80%, black)`;
const LABEL = 'text-[12px] font-semibold text-[var(--color-text-secondary)]';
const REQ = <span style={{ color: 'var(--color-system-error)' }}> *</span>;

export function ComposerDialog({ token, mode, agencies, barangays, agencyType, onClose, onPublished }: {
  token: string;
  /** The signed-in Provincial Admin's office - decides which kinds they may issue. */
  agencyType: string | null;
  mode: ComposerMode;
  agencies: AgencyOption[];
  barangays: BarangayRef[];
  onClose: () => void;
  onPublished: (row: Announcement & { reach: Reach }) => void;
}) {
  const clearing = mode.kind === 'all_clear' ? mode.of : null;
  const preset = mode.kind === 'new' && mode.category && mayIssue(mode.category, agencyType) ? KINDS[mode.category] : null;
  const [step, setStep] = useState<Step>(clearing || preset ? 2 : 1);
  const [category, setCategory] = useState<AnnouncementCategory | null>(clearing ? 'all_clear' : preset?.key ?? null);
  const [title, setTitle] = useState(clearing ? `All clear: ${clearing.title}`.slice(0, 120) : preset?.template.title ?? '');
  const [body, setBody] = useState(clearing ? KINDS.all_clear.template.body : preset?.template.body ?? '');
  const [expiry, setExpiry] = useState<ExpiryKey>('none');
  const [d, setD] = useState<AnnouncementDetails>({ centers: [{ name: '' }] });
  const [target, setTarget] = useState<AnnouncementTarget>(preset?.defaultTarget ?? 'all');
  const [agencyId, setAgencyId] = useState('');
  const [towns, setTowns] = useState<string[]>([]);
  const [picked, setPicked] = useState<Record<string, string[]>>({}); // town -> barangay ids
  const [asks, setAsks] = useState(preset?.askByDefault ?? false);
  const [reach, setReach] = useState<Reach | null>(null);
  const [reachBusy, setReachBusy] = useState(false);
  const [reachError, setReachError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const kind = category ? KINDS[category] : null;
  const set = (patch: Partial<AnnouncementDetails>) => setD(prev => ({ ...prev, ...patch }));

  // ── Choosing a kind fills in what it usually is ─────────────────────────
  const lastTemplate = useRef<{ title: string; body: string }>(preset?.template ?? { title: '', body: '' });
  function choose(k: Kind) {
    setCategory(k.key);
    // Replace the text only if it is still the previous kind's template (or empty):
    // never throw away words somebody typed.
    if (!title || title === lastTemplate.current.title) setTitle(k.template.title);
    if (!body || body === lastTemplate.current.body) setBody(k.template.body);
    lastTemplate.current = k.template;
    setTarget(k.defaultTarget);
    setAsks(k.askByDefault);
    setStep(2);
  }

  // ── What is still missing ───────────────────────────────────────────────
  const missing = useMemo(() => {
    const out: string[] = [];
    if (!category) return ['a kind'];
    if (category === 'weather' && !d.signal && !d.rainfall) out.push('a wind signal or rainfall warning');
    if (category === 'hazard' && !d.hazard) out.push('which hazard');
    if (category === 'evacuation' && !(d.centers ?? []).some(c => c.name.trim())) out.push('an evacuation centre');
    if (category === 'road_closure' && !d.road?.trim()) out.push('the road');
    if (category === 'missing_person') {
      if (!d.name?.trim()) out.push('the name');
      if (!d.last_seen?.trim()) out.push('where they were last seen');
      if (!d.contact?.trim()) out.push('who to call');
    }
    if (!title.trim()) out.push('a title');
    if (!body.trim()) out.push('a message');
    return out;
  }, [category, d, title, body]);

  const placeMissing = !clearing && target === 'agency' && !agencyId;

  // ── The request, as the backend wants it ────────────────────────────────
  const request = useMemo<CreateAnnouncementRequest | null>(() => {
    if (!category) return null;
    const hours = EXPIRY.find(e => e.key === expiry)?.hours ?? null;
    const clean: AnnouncementDetails = { ...d };
    clean.centers = (d.centers ?? []).filter(c => c.name.trim()).map(c => ({ name: c.name.trim(), ...(c.place?.trim() ? { place: c.place.trim() } : {}) }));
    if (!clean.centers.length) delete clean.centers;
    const ids = towns.flatMap(t => picked[t] ?? []);
    return {
      title: title.trim(),
      body: body.trim(),
      category,
      target_type: clearing ? clearing.target_type : target,
      target_agency_id: target === 'agency' ? agencyId || null : null,
      expires_at: hours ? new Date(Date.now() + hours * 3600_000).toISOString() : null,
      details: clean,
      target_municipalities: clearing ? null : (towns.length ? towns : null),
      target_barangay_ids: clearing ? null : (ids.length ? ids : null),
      asks_response: !clearing && !!kind?.canAsk && asks && (target === 'all' || target === 'resident'),
      ends_announcement_id: clearing?.id ?? null,
    };
  }, [category, d, title, body, expiry, target, agencyId, towns, picked, asks, kind, clearing]);

  // ── Live count of who it reaches (step 3 only) ──────────────────────────
  // Expiry is left out of the key: it changes nothing about who is reached,
  // and its timestamp moves every render.
  const reachKey = request && (step === 3 || clearing) && !placeMissing
    ? JSON.stringify({ ...request, expires_at: null, title: 'x', body: 'x' })
    : null;
  useEffect(() => {
    if (!reachKey || !request) return;
    let alive = true;
    setReachBusy(true);
    const t = setTimeout(() => {
      previewAudience(token, { ...request, expires_at: null })
        .then(r => { if (alive) { setReach(r); setReachError(null); } })
        .catch(e => {
          if (e instanceof ApiError && e.status === 401) { signOut(); return; }
          if (alive) { setReach(null); setReachError(e instanceof Error ? e.message : 'Could not count the audience.'); }
        })
        .finally(() => { if (alive) setReachBusy(false); });
    }, 350);
    return () => { alive = false; clearTimeout(t); };
  }, [reachKey]); // eslint-disable-line react-hooks/exhaustive-deps

  async function publish() {
    if (!request || busy) return;
    setBusy(true);
    setError(null);
    try {
      const row = await createAnnouncement(token, request);
      onPublished(row);
    } catch (e) {
      if (e instanceof ApiError && e.status === 401) { signOut(); return; }
      setError(e instanceof Error ? e.message : 'It could not be published.');
      setBusy(false);
    }
  }

  const byTown = useMemo(() => {
    const m: Record<string, BarangayRef[]> = {};
    for (const b of barangays) (m[b.municipality] ??= []).push(b);
    return m;
  }, [barangays]);

  const toggleTown = (t: string) => {
    setTowns(prev => prev.includes(t) ? prev.filter(x => x !== t) : [...prev, t].sort((a, b) => MUNICIPALITIES.indexOf(a as never) - MUNICIPALITIES.indexOf(b as never)));
    setPicked(prev => { const next = { ...prev }; delete next[t]; return next; });
  };
  const toggleBarangay = (t: string, id: string) => setPicked(prev => {
    const cur = prev[t] ?? [];
    return { ...prev, [t]: cur.includes(id) ? cur.filter(x => x !== id) : [...cur, id] };
  });

  const pickedBarangays = useMemo(
    () => towns.flatMap(t => (picked[t] ?? []).map(id => barangays.find(b => b.id === id)).filter(Boolean) as BarangayRef[]),
    [towns, picked, barangays],
  );

  const headline = clearing
    ? 'Send an all clear'
    : step === 1 ? 'New announcement' : kind ? `New ${kind.label.toLowerCase()}` : 'New announcement';
  const stepNote = clearing
    ? `Ends “${clearing.title}” and tells exactly the people it reached.`
    : ['What kind of announcement is this?', 'What should people know?', 'Who should get it, and where?'][step - 1];

  return (
    <Dialog onOpenChange={o => { if (!o && !busy) onClose(); }} open>
      <DialogContent className="flex max-h-[92vh] flex-col gap-0 overflow-hidden p-0 sm:max-w-[1040px]" data-testid="announcement-composer">
        <DialogHeader className="shrink-0 border-b border-[var(--color-surface-border)] py-4 pr-14 pl-5 text-left sm:pl-6">
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <div className="min-w-0 flex-1">
              <DialogTitle className="text-[17px]">{headline}</DialogTitle>
              <DialogDescription className="mt-0.5">{stepNote}</DialogDescription>
            </div>
            {!clearing && <_Steps step={step} />}
          </div>
        </DialogHeader>

        <div className="scroll-slim min-h-0 flex-1 overflow-y-auto">
          {step === 1 ? (
            <_KindPicker agencyType={agencyType} onChoose={choose} selected={category} />
          ) : (
            <div className="grid gap-0 lg:grid-cols-[minmax(0,1fr)_360px]">
              <div className="flex flex-col gap-5 px-5 py-5 sm:px-6">
                {error && <Alert message={error} variant="error" />}

                {step === 2 && kind && (
                  <>
                    {clearing && (
                      <div className="flex items-start gap-2.5 rounded-[12px] border border-[color-mix(in_srgb,var(--color-system-success)_35%,transparent)] bg-[color-mix(in_srgb,var(--color-system-success)_7%,transparent)] px-3.5 py-3 text-[12.5px] text-[var(--color-text-secondary)]">
                        <ShieldCheck aria-hidden="true" className="mt-0.5 size-4 shrink-0" style={{ color: 'var(--color-system-success)' }} />
                        <p>
                          <strong className="text-foreground">{clearing.title}</strong> will be marked ended, and this goes to the same people in the same place
                          ({placeLine(clearing.target_municipalities, clearing.target_barangays)} · {TARGET_LABEL[clearing.target_type]}).
                          {clearing.asks_response && ' Their answers stay on its answer board.'}
                        </p>
                      </div>
                    )}
                    <_KindFields category={kind.key} d={d} set={set} />
                    <label className={FIELD}>
                      <span className={LABEL}>Title{REQ}</span>
                      <input
                        aria-label="Title"
                        maxLength={120}
                        onChange={e => setTitle(e.target.value)}
                        placeholder={kind.template.title || 'A short headline'}
                        value={title}
                      />
                    </label>
                    <label className={FIELD}>
                      <span className="flex items-center justify-between gap-2">
                        <span className={LABEL}>Message{REQ}</span>
                        {kind.template.body && body !== kind.template.body && (
                          <button className="text-[12px] font-semibold text-[var(--color-brand)]" onClick={() => setBody(kind.template.body)} type="button">
                            Use the suggested text
                          </button>
                        )}
                      </span>
                      <textarea
                        aria-label="Message"
                        maxLength={2000}
                        onChange={e => setBody(e.target.value)}
                        placeholder="Write it the way you would say it over the radio: what is happening, what to do, until when."
                        rows={5}
                        value={body}
                      />
                      <span className="text-meta text-muted-foreground">Residents read this word for word. Filipino or English - whichever your people use.</span>
                    </label>
                    <fieldset className="m-0 border-0 p-0">
                      <legend className={cn(LABEL, 'mb-2')}>Stays up for</legend>
                      <_Chips
                        onPick={k => setExpiry(k as ExpiryKey)}
                        options={EXPIRY.map(e => ({ key: e.key, label: e.label }))}
                        selected={expiry}
                        testid="expiry"
                      />
                      <span className="mt-1.5 block text-meta text-muted-foreground">After this it leaves every feed by itself. An all clear ends it sooner.</span>
                    </fieldset>
                  </>
                )}

                {step === 3 && kind && (
                  <>
                    <fieldset className="m-0 border-0 p-0">
                      <legend className={cn(LABEL, 'mb-2 flex items-center gap-1.5')}><Users className="size-3.5" /> Who gets it</legend>
                      <_Chips
                        onPick={k => setTarget(k as AnnouncementTarget)}
                        options={TARGETS.map(t => ({ key: t, label: TARGET_LABEL[t] }))}
                        selected={target}
                        testid="target"
                      />
                      {target === 'agency' && (
                        <select aria-label="Agency" className="mt-2" onChange={e => setAgencyId(e.target.value)} value={agencyId}>
                          <option value="">Pick an agency…</option>
                          {agencies.map(a => <option key={a.id} value={a.id}>{a.agency_type} — {a.name}</option>)}
                        </select>
                      )}
                    </fieldset>

                    <fieldset className="m-0 border-0 p-0" data-testid="place-picker">
                      <legend className={cn(LABEL, 'mb-2 flex items-center gap-1.5')}><MapPin className="size-3.5" /> Where</legend>
                      <div className="flex flex-wrap gap-1.5">
                        <button
                          aria-pressed={towns.length === 0}
                          className={_chip(towns.length === 0)}
                          data-town="province"
                          onClick={() => { setTowns([]); setPicked({}); }}
                          type="button"
                        >
                          Whole province
                        </button>
                        {MUNICIPALITIES.map(t => (
                          <button aria-pressed={towns.includes(t)} className={_chip(towns.includes(t))} data-town={t} key={t} onClick={() => toggleTown(t)} type="button">
                            {towns.includes(t) && <Check aria-hidden="true" className="size-3.5" />}
                            {t}
                          </button>
                        ))}
                      </div>

                      {towns.map(t => {
                        const list = byTown[t] ?? [];
                        const mine = picked[t] ?? [];
                        const narrowing = picked[t] !== undefined;
                        return (
                          <div className="mt-3 rounded-[12px] border border-[var(--color-surface-border)] px-3.5 py-3" data-town-panel={t} key={t}>
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <p className="text-[13px] font-semibold text-foreground">{t}</p>
                              <div className="flex rounded-full border border-[var(--color-surface-border)] p-0.5 text-[12px] font-semibold">
                                <button
                                  className={cn('rounded-full px-2.5 py-1', !narrowing ? 'bg-foreground text-background' : 'text-[var(--color-text-secondary)]')}
                                  onClick={() => setPicked(prev => { const n = { ...prev }; delete n[t]; return n; })}
                                  type="button"
                                >
                                  Whole town
                                </button>
                                <button
                                  className={cn('rounded-full px-2.5 py-1', narrowing ? 'bg-foreground text-background' : 'text-[var(--color-text-secondary)]')}
                                  data-narrow={t}
                                  onClick={() => setPicked(prev => ({ ...prev, [t]: prev[t] ?? [] }))}
                                  type="button"
                                >
                                  Pick barangays
                                </button>
                              </div>
                            </div>
                            {narrowing && (
                              <>
                                <div className="mt-2.5 flex max-h-[168px] flex-wrap gap-1.5 overflow-y-auto">
                                  {list.length === 0 && <p className="text-[12px] text-muted-foreground">The barangay list could not be loaded.</p>}
                                  {list.map(b => (
                                    <button
                                      aria-pressed={mine.includes(b.id)}
                                      className={_chip(mine.includes(b.id), true)}
                                      data-barangay={b.name}
                                      key={b.id}
                                      onClick={() => toggleBarangay(t, b.id)}
                                      type="button"
                                    >
                                      {mine.includes(b.id) && <Check aria-hidden="true" className="size-3" />}
                                      {b.name}
                                    </button>
                                  ))}
                                </div>
                                <p className="mt-2 text-meta text-muted-foreground">
                                  {mine.length === 0
                                    ? `None picked yet - until you pick, all of ${t} gets it.`
                                    : `${mine.length} of ${list.length} barangays. Residents of ${t} whose barangay is not on record get it too.`}
                                </p>
                              </>
                            )}
                          </div>
                        );
                      })}
                    </fieldset>

                    {kind.canAsk && (
                      <label className="flex items-start gap-3 rounded-[12px] border border-[var(--color-surface-border)] px-3.5 py-3">
                        <Switch
                          aria-label="Ask residents if they are safe"
                          checked={asks && (target === 'all' || target === 'resident')}
                          className="mt-0.5"
                          data-testid="asks-switch"
                          disabled={!(target === 'all' || target === 'resident')}
                          onCheckedChange={setAsks}
                        />
                        <span className="text-[12.5px] leading-relaxed text-[var(--color-text-secondary)]">
                          <strong className="font-semibold text-foreground">Ask residents if they are safe.</strong>{' '}
                          Their phone shows “I am safe” and “I need help”. Anyone who needs help is sent to the stations of their town at once,
                          and you see who has not answered.
                          {!(target === 'all' || target === 'resident') && <em className="block not-italic text-muted-foreground">Only residents answer - send it to residents or everyone.</em>}
                        </span>
                      </label>
                    )}

                    <_ReachBox busy={reachBusy} error={reachError} placeMissing={placeMissing} reach={reach} />
                  </>
                )}
              </div>

              {kind && (
                <aside className="border-t border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-5 py-5 sm:px-6 lg:border-t-0 lg:border-l">
                  <p className="mb-2.5 text-[11.5px] font-semibold tracking-wide text-muted-foreground uppercase">On a resident’s phone</p>
                  <PhonePreview
                    asks={!!request?.asks_response}
                    body={body}
                    category={kind.key}
                    details={d}
                    place={clearing ? placeLine(clearing.target_municipalities, clearing.target_barangays) : placeLine(towns, pickedBarangays)}
                    title={title}
                  />
                </aside>
              )}
            </div>
          )}
        </div>

        {/* ── Footer ─────────────────────────────────────────────── */}
        <div className="flex shrink-0 flex-wrap items-center gap-2 border-t border-[var(--color-surface-border)] px-5 py-3 sm:px-6">
          {step > 1 && !clearing && (
            <Button disabled={busy} onClick={() => setStep(s => (s - 1) as Step)} variant="outline">
              <ArrowLeft data-icon="inline-start" /> Back
            </Button>
          )}
          {step === 2 && missing.length > 0 && (
            <p className="text-[12px] text-muted-foreground" data-testid="composer-missing">Still needed: {missing.join(', ')}.</p>
          )}
          <div className="ml-auto flex items-center gap-2">
            <Button disabled={busy} onClick={onClose} variant="ghost">Cancel</Button>
            {step === 2 && !clearing && (
              <Button disabled={missing.length > 0} onClick={() => setStep(3)}>
                Next: who and where <ArrowRight data-icon="inline-end" />
              </Button>
            )}
            {(step === 3 || (step === 2 && clearing)) && (
              <Button
                data-testid="composer-publish"
                disabled={busy || missing.length > 0 || placeMissing || (!clearing && (reachBusy || !reach || reach.total === 0))}
                onClick={() => void publish()}
                style={{ backgroundColor: kind?.group === 'safety' ? solid(kind.color) : undefined, color: kind?.group === 'safety' ? '#fff' : undefined }}
              >
                {busy ? <Loader2 className="animate-spin" data-icon="inline-start" /> : <Megaphone data-icon="inline-start" />}
                {clearing ? (reach && !reachBusy ? `Send all clear to ${reach.total.toLocaleString()} ${reach.total === 1 ? 'person' : 'people'}` : 'Send all clear') : reach && !reachBusy ? `Publish to ${reach.total.toLocaleString()} ${reach.total === 1 ? 'person' : 'people'}` : 'Publish'}
              </Button>
            )}
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}

// ── Pieces ───────────────────────────────────────────────────────────────────

function _chip(on: boolean, small = false) {
  return cn(
    'inline-flex items-center gap-1 rounded-full border font-semibold transition-colors',
    small ? 'h-7 px-2.5 text-[12px]' : 'h-8 px-3 text-[12.5px]',
    on
      ? 'border-transparent bg-foreground text-background'
      : 'border-[var(--color-surface-border)] text-[var(--color-text-secondary)] hover:bg-[var(--color-surface-hover)] hover:text-foreground',
  );
}

function _Chips({ options, selected, onPick, testid }: {
  options: { key: string; label: string; color?: string }[];
  selected: string | number | null | undefined;
  onPick: (key: string) => void;
  testid?: string;
}) {
  return (
    <div className="flex flex-wrap gap-1.5" data-testid={testid} role="radiogroup">
      {options.map(o => {
        const on = String(selected ?? '') === o.key;
        return (
          <button
            aria-checked={on}
            className={_chip(on)}
            data-option={o.key}
            key={o.key}
            onClick={() => onPick(o.key)}
            role="radio"
            style={on && o.color ? { backgroundColor: solid(o.color), color: '#fff' } : undefined}
            type="button"
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

function _Steps({ step }: { step: Step }) {
  return (
    <ol className="flex items-center gap-1.5 text-[12px] font-semibold" aria-label="Steps">
      {['Kind', 'Message', 'Who and where'].map((label, i) => {
        const n = (i + 1) as Step;
        const done = n < step;
        const on = n === step;
        return (
          <li className="flex items-center gap-1.5" key={label}>
            {i > 0 && <span aria-hidden="true" className="h-px w-4 bg-[var(--color-surface-border)]" />}
            <span
              aria-current={on ? 'step' : undefined}
              className={cn(
                'flex size-5 items-center justify-center rounded-full text-[11px]',
                on ? 'bg-[var(--color-brand)] text-white' : done ? 'bg-foreground text-background' : 'bg-[var(--color-surface-raised)] text-muted-foreground',
              )}
            >
              {done ? <Check className="size-3" /> : n}
            </span>
            <span className={cn('hidden sm:inline', on ? 'text-foreground' : 'text-muted-foreground')}>{label}</span>
          </li>
        );
      })}
    </ol>
  );
}

function _KindPicker({ selected, onChoose, agencyType }: { selected: AnnouncementCategory | null; onChoose: (k: Kind) => void; agencyType: string | null }) {
  const offered = Object.values(KINDS).filter(k => k.offered);
  const groups: [string, string, Kind[]][] = [
    ['Safety alerts', 'Pop up on the phone the moment they arrive.', offered.filter(k => k.group === 'safety')],
    ['Information', 'Arrive quietly in the notifications list.', offered.filter(k => k.group === 'info')],
  ];
  return (
    <div className="flex flex-col gap-6 px-5 py-5 sm:px-6" data-testid="kind-picker">
      {groups.map(([name, note, kinds]) => (
        <section key={name}>
          <h3 className="text-[13px] font-semibold text-foreground">{name}</h3>
          <p className="mb-2.5 text-[12px] text-muted-foreground">{note}</p>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {kinds.map(k => {
              // Shown, not hidden: an office that cannot issue a kind should
              // see that it exists and whose it is, not wonder where it went.
              const allowed = mayIssue(k.key, agencyType);
              return (
              <button
                aria-disabled={!allowed}
                className={cn(
                  'group flex items-start gap-3 rounded-[12px] border px-3.5 py-3 text-left transition-colors',
                  !allowed
                    ? 'cursor-not-allowed border-dashed border-[var(--color-surface-border)] opacity-60'
                    : selected === k.key ? 'border-[var(--color-brand)] bg-[var(--color-brand-subtle)]' : 'border-[var(--color-surface-border)] hover:bg-[var(--color-surface-hover)]',
                )}
                data-allowed={allowed}
                data-kind={k.key}
                disabled={!allowed}
                key={k.key}
                onClick={() => onChoose(k)}
                title={allowed ? undefined : `Issued by the ${KIND_OWNERS[k.key]!.join(' or ')} provincial office`}
                type="button"
              >
                <span
                  aria-hidden="true"
                  className="flex size-9 shrink-0 items-center justify-center rounded-[10px]"
                  style={{ color: k.color, backgroundColor: `color-mix(in srgb, ${k.color} 13%, transparent)` }}
                >
                  <k.Icon size={18} />
                </span>
                <span className="min-w-0">
                  <span className="block text-[13.5px] font-semibold text-foreground">{k.label}</span>
                  <span className="mt-0.5 block text-[12px] leading-snug text-muted-foreground">{k.blurb}</span>
                  {!allowed ? (
                    <span className="mt-1.5 inline-flex items-center gap-1 rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] font-semibold text-[var(--color-text-secondary)]">
                      <Lock aria-hidden="true" className="size-3" /> {KIND_OWNERS[k.key]!.join(' or ')} only
                    </span>
                  ) : k.canAsk && (
                    <span className="mt-1.5 inline-block rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[11px] font-semibold text-[var(--color-text-secondary)]">
                      Can ask “are you safe?”
                    </span>
                  )}
                </span>
              </button>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}

/** The facts each kind is useless without. */
function _KindFields({ category, d, set }: {
  category: AnnouncementCategory;
  d: AnnouncementDetails;
  set: (patch: Partial<AnnouncementDetails>) => void;
}) {
  const text = (key: keyof AnnouncementDetails, label: string, placeholder: string, required = false, max = 160) => (
    <label className={FIELD} key={key}>
      <span className={LABEL}>{label}{required && REQ}</span>
      <input
        aria-label={label}
        maxLength={max}
        onChange={e => set({ [key]: e.target.value } as Partial<AnnouncementDetails>)}
        placeholder={placeholder}
        value={(d[key] as string | undefined) ?? ''}
      />
    </label>
  );

  if (category === 'weather') {
    return (
      <div className="flex flex-col gap-4 rounded-[12px] border border-[var(--color-surface-border)] px-4 py-3.5" data-testid="kind-fields">
        <fieldset className="m-0 border-0 p-0">
          <legend className={cn(LABEL, 'mb-2')}>Tropical cyclone wind signal</legend>
          <_Chips
            onPick={k => set({ signal: k === '' ? undefined : Number(k) })}
            options={[{ key: '', label: 'None' }, ...[1, 2, 3, 4, 5].map(n => ({ key: String(n), label: `Signal No. ${n}` }))]}
            selected={d.signal ?? ''}
            testid="signal"
          />
        </fieldset>
        <fieldset className="m-0 border-0 p-0">
          <legend className={cn(LABEL, 'mb-2')}>Rainfall warning</legend>
          <_Chips
            onPick={k => set({ rainfall: (k || undefined) as AnnouncementDetails['rainfall'] })}
            options={[{ key: '', label: 'None' }, ...(['yellow', 'orange', 'red'] as const).map(r => ({ key: r, label: RAINFALL_LABEL[r], color: RAINFALL_COLOR[r] }))]}
            selected={d.rainfall ?? ''}
            testid="rainfall"
          />
        </fieldset>
        {text('storm_name', 'Storm name', 'e.g. Typhoon Ada (local name)', false, 60)}
      </div>
    );
  }

  if (category === 'hazard') {
    return (
      <div className="flex flex-col gap-4 rounded-[12px] border border-[var(--color-surface-border)] px-4 py-3.5" data-testid="kind-fields">
        <fieldset className="m-0 border-0 p-0">
          <legend className={cn(LABEL, 'mb-2')}>Which hazard{REQ}</legend>
          <_Chips
            onPick={k => set({ hazard: k as AnnouncementDetails['hazard'] })}
            options={Object.entries(HAZARD_LABEL).map(([key, label]) => ({ key, label }))}
            selected={d.hazard}
            testid="hazard"
          />
        </fieldset>
        {text('area', 'Area at risk', 'e.g. Houses along the Catmon river', false, 200)}
      </div>
    );
  }

  if (category === 'evacuation') {
    const centers = d.centers?.length ? d.centers : [{ name: '' }];
    const edit = (i: number, patch: Partial<EvacuationCenter>) =>
      set({ centers: centers.map((c, j) => (j === i ? { ...c, ...patch } : c)) });
    return (
      <div className="flex flex-col gap-4 rounded-[12px] border border-[var(--color-surface-border)] px-4 py-3.5" data-testid="kind-fields">
        <fieldset className="m-0 border-0 p-0">
          <legend className={cn(LABEL, 'mb-2')}>Kind of evacuation</legend>
          <_Chips
            onPick={k => set({ kind: k as AnnouncementDetails['kind'] })}
            options={[{ key: 'preemptive', label: 'Pre-emptive' }, { key: 'forced', label: 'Forced', color: 'var(--color-severity-critical)' }]}
            selected={d.kind}
            testid="evac-kind"
          />
        </fieldset>
        <fieldset className="m-0 border-0 p-0">
          <legend className={cn(LABEL, 'mb-2')}>Where to go{REQ}</legend>
          <div className="flex flex-col gap-2">
            {centers.map((c, i) => (
              <div className="flex items-start gap-2" data-center={i} key={i}>
                <input aria-label={`Evacuation centre ${i + 1}`} className="min-w-0 flex-1" maxLength={120} onChange={e => edit(i, { name: e.target.value })} placeholder="Evacuation centre, e.g. Naval Central School" value={c.name} />
                <input aria-label={`Where centre ${i + 1} is`} className="min-w-0 flex-1" maxLength={160} onChange={e => edit(i, { place: e.target.value })} placeholder="Where it is (optional)" value={c.place ?? ''} />
                {centers.length > 1 && (
                  <Button aria-label="Remove this centre" onClick={() => set({ centers: centers.filter((_, j) => j !== i) })} size="icon-sm" variant="ghost">
                    <Minus />
                  </Button>
                )}
              </div>
            ))}
            {centers.length < 10 && (
              <Button className="w-fit" onClick={() => set({ centers: [...centers, { name: '' }] })} size="sm" variant="outline">
                <Plus data-icon="inline-start" /> Add another centre
              </Button>
            )}
          </div>
        </fieldset>
        {text('bring', 'What to bring', 'e.g. Go-bag, medicines, IDs, drinking water', false, 300)}
      </div>
    );
  }

  const box = (children: React.ReactNode) => (
    <div className="grid gap-3 rounded-[12px] border border-[var(--color-surface-border)] px-4 py-3.5 sm:grid-cols-2" data-testid="kind-fields">{children}</div>
  );

  if (category === 'road_closure') {
    return box(<>
      {text('road', 'Road or bridge closed', 'e.g. Naval–Caibiran road at Km 12', true)}
      {text('alternate', 'Use instead', 'e.g. Via Almeria coastal road', false, 200)}
      {text('reopens', 'Expected to reopen', 'e.g. Tomorrow 6 AM', false, 80)}
    </>);
  }
  if (category === 'missing_person') {
    return box(<>
      {text('name', 'Name', 'Full name', true, 120)}
      <label className={FIELD}>
        <span className={LABEL}>Age</span>
        <input
          aria-label="Age" inputMode="numeric" max={120} min={0}
          onChange={e => set({ age: e.target.value === '' ? undefined : Math.max(0, Math.min(120, Number(e.target.value))) })}
          type="number" value={d.age ?? ''}
        />
      </label>
      {text('last_seen', 'Last seen', 'Where and when, e.g. Naval port, 30 Sept 5 PM', true, 200)}
      {text('contact', 'Who to call', 'e.g. Naval PNP 0921-555-3961', true, 80)}
      <div className="sm:col-span-2">{text('description', 'What they look like', 'Height, clothes, anything that helps', false, 300)}</div>
    </>);
  }
  if (category === 'relief') {
    return box(<>
      {text('where', 'Where', 'e.g. Barangay hall, Caraycaray')}
      {text('when', 'When', 'e.g. 2 Oct, 8 AM to 12 NN', false, 120)}
      <div className="sm:col-span-2">{text('bring', 'What to bring', 'e.g. Valid ID, family ration card', false, 200)}</div>
    </>);
  }
  if (category === 'utility') {
    return box(<>
      {text('provider', 'From', 'e.g. BILECO / Naval Water District', false, 80)}
      {text('when', 'When', 'e.g. 3 Oct, 8 AM to 5 PM', false, 120)}
    </>);
  }
  if (category === 'health' || category === 'drill') {
    return box(text('when', 'When', category === 'drill' ? 'e.g. 9 Oct, 9 AM' : 'e.g. Every Monday this month', false, 120));
  }
  return null;
}

function _ReachBox({ reach, busy, error, placeMissing }: { reach: Reach | null; busy: boolean; error: string | null; placeMissing: boolean }) {
  if (placeMissing) {
    return <p className="rounded-[12px] border border-dashed border-[var(--color-surface-border)] px-3.5 py-3 text-[12.5px] text-muted-foreground">Pick the agency to see who this reaches.</p>;
  }
  if (error) return <Alert message={error} variant="error" />;
  const parts = reach ? ([
    ['resident', 'resident'], ['responder', 'responder'], ['agency_admin', 'agency admin'], ['provincial_admin', 'provincial admin'],
  ] as const).filter(([k]) => reach[k] > 0).map(([k, w]) => `${reach[k].toLocaleString()} ${w}${reach[k] === 1 ? '' : 's'}`) : [];
  const nobody = reach && reach.total === 0;
  return (
    <div
      className={cn(
        'flex items-start gap-3 rounded-[12px] border px-3.5 py-3',
        nobody ? 'border-[color-mix(in_srgb,var(--color-system-warning)_40%,transparent)] bg-[color-mix(in_srgb,var(--color-system-warning)_8%,transparent)]' : 'border-[var(--color-surface-border)]',
      )}
      data-testid="reach-box"
    >
      <Users aria-hidden="true" className="mt-0.5 size-4 shrink-0 text-muted-foreground" />
      <div className="min-w-0 text-[12.5px] text-[var(--color-text-secondary)]">
        {busy || !reach ? (
          <span className="inline-flex items-center gap-1.5"><Loader2 className="size-3.5 animate-spin" /> Counting who this reaches…</span>
        ) : nobody ? (
          <><strong className="text-foreground">Nobody would get this.</strong> No account matches that audience and place yet.</>
        ) : (
          <>
            <strong className="text-[14px] text-foreground" data-testid="reach-total">{reach.total.toLocaleString()} {reach.total === 1 ? 'person' : 'people'}</strong>
            {' '}will get it on their phone or dashboard: {parts.join(', ')}.
          </>
        )}
      </div>
    </div>
  );
}

/** Roughly what the phone draws - enough to catch a missing centre or a title that is too long. */
export function PhonePreview({ category, title, body, details, place, asks }: {
  category: AnnouncementCategory; title: string; body: string; details: AnnouncementDetails; place: string; asks: boolean;
}) {
  const k = kindOf(category);
  const chips = factChips(category, details);
  const centers = (details.centers ?? []).filter(c => c.name.trim());
  return (
    <div className="mx-auto w-full max-w-[320px] overflow-hidden rounded-[22px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] shadow-sm" data-testid="phone-preview">
      <div className="flex items-center gap-2.5 px-4 py-3" style={{ backgroundColor: `color-mix(in srgb, ${k.color} 12%, transparent)` }}>
        <span className="flex size-8 items-center justify-center rounded-full text-white" style={{ backgroundColor: solid(k.color) }}>
          <k.Icon size={16} />
        </span>
        <div className="min-w-0">
          <p className="text-[11px] font-bold tracking-wide uppercase" style={{ color: k.color }}>{k.label}</p>
          <p className="truncate text-[11px] text-[var(--color-text-secondary)]">{place}</p>
        </div>
      </div>
      <div className="flex flex-col gap-2 px-4 py-3">
        <p className="text-[14.5px] leading-snug font-bold text-foreground">{title || 'Your title'}</p>
        {chips.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {chips.map(c => (
              <span className="rounded-full border px-2 py-0.5 text-[10.5px] font-semibold" key={c.label} style={{ color: c.color ?? 'var(--color-text-secondary)', borderColor: c.color ? `color-mix(in srgb, ${c.color} 35%, transparent)` : 'var(--color-surface-border)' }}>
                {c.label}
              </span>
            ))}
          </div>
        )}
        <p className="line-clamp-5 text-[12.5px] leading-relaxed whitespace-pre-line text-[var(--color-text-secondary)]">{body || 'Your message.'}</p>
        {centers.length > 0 && (
          <div className="rounded-[10px] bg-[var(--color-surface-raised)] px-2.5 py-2 text-[11.5px]">
            <p className="font-semibold text-foreground">Pumunta sa:</p>
            {centers.map((c, i) => <p className="text-[var(--color-text-secondary)]" key={i}>• {c.name}{c.place ? ` — ${c.place}` : ''}</p>)}
          </div>
        )}
        {asks && (
          <div className="mt-1 grid gap-1.5">
            <span className="flex h-9 items-center justify-center gap-1 rounded-[10px] text-[12px] font-bold text-white" style={{ backgroundColor: solid('var(--color-system-success)') }}>
              <ShieldCheck className="size-3.5" /> Ligtas ako
            </span>
            <span className="flex h-9 items-center justify-center gap-1 rounded-[10px] text-[12px] font-bold text-white" style={{ backgroundColor: solid('var(--color-severity-critical)') }}>
              <LifeBuoy className="size-3.5" /> Kailangan ko ng tulong
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
