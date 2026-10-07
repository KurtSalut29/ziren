'use client';

/**
 * Presentational pieces of the incident detail dialog.
 *
 * Split out of incident-detail-modal.tsx, which owns the data fetching and the
 * dispatch actions. Everything here is a pure function of its props (plus one
 * local reveal toggle), so it can be read and changed without the dialog's
 * state in the way.
 *
 * REDESIGNED 2026-09-30. The dialog used to be one long column of
 * label-and-value rows under six headings, every fact at the same weight, and
 * the ones a dispatcher decides on (is someone trapped, is it spreading, how
 * many victims, the landmark, the number to call back) sat below the fold.
 * The pieces here are what replaced it: cards with a clear title, the
 * resident's answers as tiles that can be read at a glance, warning chips for
 * anything that should change how the report is handled, and the timestamps
 * as a row of steps.
 */

import { useState } from 'react';
import { Check, Sparkles, type LucideIcon } from 'lucide-react';
import { withoutVoicePlaceholder } from '@/lib/incidents/report-text';
import type { WizardAnswer } from '@/lib/incidents/wizard-catalog';
import { cn } from '@/lib/utils';

/**
 * One card of the report: an icon, a title, and what belongs under it.
 *
 * The 5W1H structure the dialog has always had is kept: [facet] is the W (or
 * H) this card answers, shown as a quiet tag at the right of its heading.
 */
export function Section({
  title,
  facet,
  icon: Icon,
  tone,
  aside,
  className,
  demo,
  children,
}: {
  title: string;
  /** The W (or H) this section answers, shown as a tag beside the heading. */
  facet?: string;
  icon: LucideIcon;
  /** Tints the icon tile. Defaults to the neutral secondary text colour. */
  tone?: string;
  /** Something for the right of the heading, in place of the facet tag. */
  aside?: React.ReactNode;
  className?: string;
  /** A part a Ziren demo points at (its `data-demo`). */
  demo?: string;
  children: React.ReactNode;
}) {
  const color = tone ?? 'var(--color-text-secondary)';
  return (
    <section
      data-demo={demo}
      className={cn(
        'flex min-w-0 flex-col gap-3 rounded-[14px] border border-[var(--color-surface-border)] bg-[var(--color-surface-card)] p-4',
        className,
      )}
    >
      <h3 className="flex items-center gap-2.5">
        <span
          className="flex size-7 shrink-0 items-center justify-center rounded-lg"
          style={{ color, backgroundColor: `color-mix(in srgb, ${color} 12%, transparent)` }}
        >
          <Icon size={15} />
        </span>
        <span className="min-w-0 flex-1 truncate text-[13.5px] font-bold text-foreground">
          {title}
        </span>
        {aside ?? (facet && (
          <span className="shrink-0 rounded-full bg-[var(--color-surface-raised)] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-muted-foreground">
            {facet}
          </span>
        ))}
      </h3>
      {children}
    </section>
  );
}

/**
 * One fact as a tinted box: an icon, a small label, the value, and an optional
 * action at the right. "Where it is" and "Who reported it" both build from
 * these, so the two cards side by side are made of the same parts and come
 * out the same height (user report 2026-10-08: one card ended in a gap).
 */
export function InfoTile({
  icon: Icon,
  label,
  tone,
  action,
  testId,
  children,
}: {
  icon: LucideIcon;
  label: string;
  /** Tints the box and icon. Defaults to a neutral grey. */
  tone?: string;
  action?: React.ReactNode;
  testId?: string;
  children: React.ReactNode;
}) {
  const color = tone ?? 'var(--color-text-secondary)';
  return (
    <div
      className="flex min-w-0 items-center gap-2.5 rounded-[10px] border px-3 py-2"
      data-testid={testId}
      style={{
        borderColor: `color-mix(in srgb, ${color} ${tone ? 38 : 22}%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${color} ${tone ? 8 : 5}%, transparent)`,
      }}
    >
      <Icon aria-hidden className="shrink-0" size={16} style={{ color }} />
      <span className="min-w-0 flex-1">
        <span className="block text-[10.5px] font-bold uppercase tracking-wider text-muted-foreground">{label}</span>
        <span className="block min-w-0 break-words text-[13.5px] font-semibold leading-snug text-foreground">{children}</span>
      </span>
      {action && <span className="shrink-0">{action}</span>}
    </div>
  );
}

/** Label left, value right — one secondary fact per line. */
export function Row({
  label,
  sub,
  icon: Icon,
  stacked,
  children,
}: {
  label: string;
  /** The prompt as the resident saw it, verbatim. */
  sub?: string;
  icon?: LucideIcon;
  /** Label above the value, for a card too narrow to hold them side by side. */
  stacked?: boolean;
  children: React.ReactNode;
}) {
  if (stacked) {
    return (
      <div className="flex min-w-0 flex-col gap-0.5 text-[13px] leading-snug">
        <span className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
          {Icon && <Icon className="shrink-0" size={12} />}
          {label}
        </span>
        <span className="min-w-0 break-words font-medium text-foreground">{children}</span>
      </div>
    );
  }
  return (
    <div className="grid grid-cols-[124px_minmax(0,1fr)] gap-3 text-[13px] leading-snug">
      <span className="flex flex-col text-muted-foreground">
        <span className="flex items-center gap-1.5">
          {Icon && <Icon className="shrink-0" size={13} />}
          {label}
        </span>
        {sub && (
          <span className="text-[11px] italic leading-tight opacity-70">
            &ldquo;{sub}&rdquo;
          </span>
        )}
      </span>
      <span className="min-w-0 break-words font-medium text-foreground">{children}</span>
    </div>
  );
}

/**
 * One fact as a tile: a small label over a large value.
 *
 * What the long label/value list could not do — a dispatcher reads six of
 * these in one look, without following a line across the panel.
 */
export function Fact({
  label,
  hint,
  tag,
  children,
}: {
  label: string;
  /** The prompt as the resident saw it, verbatim. */
  hint?: string;
  /** Which of the 5W1H this answers. */
  tag?: string;
  children: React.ReactNode;
}) {
  return (
    <div
      className={cn(
        'flex min-w-0 flex-col gap-0.5 rounded-[10px] border border-[var(--color-surface-border)] bg-[var(--color-surface-raised)] px-3 py-2',
        hint && 'cursor-help',
      )}
      // The prompt as the resident saw it. A tooltip, not a third line: shown
      // on every tile it pushed the address and the phone number below the
      // fold, and it is the record of the question, not the answer.
      title={hint ? `Asked: “${hint}”` : undefined}
    >
      <span className="flex items-start justify-between gap-2">
        <span className="text-[11px] font-semibold uppercase leading-tight tracking-wide text-muted-foreground">
          {label}
        </span>
        {tag && (
          <span className="shrink-0 text-[9.5px] font-bold uppercase tracking-wider text-[var(--color-text-muted)]">
            {tag}
          </span>
        )}
      </span>
      <span className="break-words text-[14.5px] font-bold leading-snug text-foreground">
        {children}
      </span>
    </div>
  );
}

/**
 * Wizard answers, as tiles, rendered verbatim.
 *
 * The VALUE is never translated or prettified — the backend's triage matches
 * these strings literally, so what is displayed has to be exactly what was
 * stored, or the console and the rubric would be describing different reports.
 * The Tagalog prompt, the record of what the resident was actually asked, is
 * the tile's tooltip.
 */
export function Answers({ items, tag }: { items: WizardAnswer[]; tag?: string }) {
  if (items.length === 0) return null;
  return (
    <>
      {items.map(a => (
        <Fact hint={a.asked ?? undefined} key={a.key} label={a.label} tag={tag}>
          {a.value}
        </Fact>
      ))}
    </>
  );
}

/**
 * Something about this report that should change how it is handled: filed
 * with the SOS button, a reporter with false alarms on record, an unverified
 * identity. A chip with an icon and words, never colour alone.
 */
export function Flag({
  icon: Icon,
  tone,
  children,
}: {
  icon: LucideIcon;
  tone: string;
  children: React.ReactNode;
}) {
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[12px] font-semibold leading-tight"
      style={{
        color: tone,
        borderColor: `color-mix(in srgb, ${tone} 40%, transparent)`,
        backgroundColor: `color-mix(in srgb, ${tone} 10%, transparent)`,
      }}
    >
      <Icon className="shrink-0" size={13} />
      {children}
    </span>
  );
}

export interface Milestone {
  label: string;
  /** Already formatted. Null means it has not happened. */
  at: string | null;
  /** "after 2m", "50m in total". */
  note?: string | null;
  /** Shown in place of the time while it has not happened. */
  pending?: string;
  /** Colour of a reached step. Defaults to the success green. */
  tone?: string;
}

/**
 * The report's timestamps as a row of steps, reached ones filled.
 *
 * They used to be four label/value rows; as steps the order and the gaps
 * ("dispatched after 2m") read as one line of events.
 */
export function Milestones({ items }: { items: Milestone[] }) {
  return (
    <ol
      className="grid gap-x-2 gap-y-3"
      style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}
    >
      {items.map((m, i) => {
        const done = m.at !== null;
        const tone = m.tone ?? 'var(--color-system-success)';
        return (
          <li className="relative flex min-w-0 flex-col gap-1" key={m.label}>
            <span className="flex items-center gap-2">
              <span
                className="flex size-5 shrink-0 items-center justify-center rounded-full border-2"
                style={done
                  ? { backgroundColor: tone, borderColor: tone, color: '#fff' }
                  : { borderColor: 'var(--color-border-strong)' }}
              >
                {done && <Check size={11} strokeWidth={3.5} />}
              </span>
              {i < items.length - 1 && (
                <span
                  className="h-0.5 flex-1 rounded-full"
                  style={{
                    backgroundColor: done && items[i + 1].at !== null
                      ? tone
                      : 'var(--color-surface-border)',
                  }}
                />
              )}
            </span>
            <span className={cn('text-[12px] font-bold leading-tight', done ? 'text-foreground' : 'text-muted-foreground')}>
              {m.label}
            </span>
            <span className="text-[12px] leading-tight text-[var(--color-text-secondary)]">
              {m.at ?? m.pending ?? 'Not yet'}
            </span>
            {m.note && (
              <span className="font-mono text-[11px] tabular-nums leading-tight text-muted-foreground">
                {m.note}
              </span>
            )}
          </li>
        );
      })}
    </ol>
  );
}

/**
 * The report as the system read it, when that differs from what was heard.
 *
 * A Waray voice note comes back from the recogniser as "Sunog Didiha Amon" —
 * readable to nobody, including the responder who has to act on it. The
 * correction layer already turns that into "sunog didi ha amon" before any
 * signal is extracted, and the API has always sent the result. Nothing
 * displayed it, so the dispatcher saw the mangled line, saw a severity badge
 * beside it, and had nothing on screen connecting the two.
 *
 * That connection is the point. When a count is recovered — "Tulukataw
 * Anasamdan" -> "tulo ka tawo an nasamdan" -> SR003, three injured — the words
 * the count came from were invisible, and "where did the 3 come from?" had no
 * answer a responder could read.
 *
 * Shown, not hidden behind a disclosure: an agency reading this needs to
 * understand the report, not audit it. The resident's own words stay directly
 * above, because a corrected transcript is still a machine's opinion and the
 * recording remains the only ground truth.
 *
 * Purple throughout, per the rule in globals.css: this is machine output and
 * must never be mistaken for what the resident said. The changed words carry
 * it inline so the substitution is visible at a glance rather than only in the
 * list below.
 */
export function Normalisation({
  reportText,
  normalisation,
}: {
  reportText: string;
  normalisation?: { text: string; changes: string[] } | null;
}) {
  if (!normalisation?.text) return null;

  // The correction is computed over the whole stored text, so on a voice report
  // it starts with the app's "Fire — reported by voice recording —" scaffolding.
  // Both sides are stripped the same way before comparing or showing, so the
  // comparison below still means what it did and the prefix is not repeated
  // inside the "read as" box.
  const said = withoutVoicePlaceholder(normalisation.text);
  const original = withoutVoicePlaceholder(reportText);

  // Incidents filed before the alias casing fix carry a record of corrections
  // that were reported and never applied: `changes` lists them, `text` is the
  // uncorrected string. Triage is a snapshot taken at submit and nothing
  // recomputes it, so those rows keep that shape forever.
  //
  // Rendering them would show "read as" text identical to the line above it,
  // under a list claiming substitutions that are not in it. Say nothing
  // instead — there is no correction to show, whatever the record claims.
  if (said.trim() === original.trim()) return null;

  // "didiha -> didi ha (alias)" — the shape triage_service writes. Anything
  // that does not parse is skipped rather than guessed at; a malformed entry
  // should cost a highlight, not the whole panel.
  const edits = (normalisation.changes ?? [])
    .filter((c): c is string => typeof c === 'string')
    .map(c => /^(.+?) -> (.+?) \(([^)]+)\)$/.exec(c))
    .filter((m): m is RegExpExecArray => m !== null)
    .map(m => ({ heard: m[1], written: m[2], source: m[3] }));

  return (
    <div
      className="mt-2 rounded-md border px-3 py-2 text-[13px] leading-relaxed"
      style={{
        borderColor: 'var(--color-ai-suggested)',
        background: 'var(--color-ai-suggested-bg)',
      }}
    >
      <span className="badge-ai mb-1 inline-flex items-center gap-1">
        <Sparkles size={11} aria-hidden />
        Read by the system as
      </span>

      <p className="not-italic">{highlight(said, edits)}</p>

      {edits.length > 0 && (
        <ul className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[11px]">
          {edits.map(e => (
            <li key={`${e.heard}-${e.written}`} className="text-[var(--color-text-muted)]">
              <span className="line-through">{e.heard}</span>
              {' → '}
              <span style={{ color: 'var(--color-ai-suggested)' }}>{e.written}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

/** Mark the corrected words inside the corrected sentence. */
function highlight(text: string, edits: { written: string }[]) {
  const targets = edits.map(e => e.written).filter(Boolean);
  if (targets.length === 0) return text;

  // Longest first, so a multi-word replacement ("didi ha") is matched before
  // any single word inside it.
  const pattern = targets
    .slice()
    .sort((a, b) => b.length - a.length)
    .map(t => t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('|');

  const parts = text.split(new RegExp(`(${pattern})`, 'gi'));
  const isTarget = new Set(targets.map(t => t.toLowerCase()));

  return parts.map((part, i) =>
    isTarget.has(part.toLowerCase()) ? (
      <mark
        key={i}
        className="rounded-sm bg-transparent px-0.5 font-medium"
        style={{
          color: 'var(--color-ai-suggested)',
          boxShadow: 'inset 0 -1px 0 var(--color-ai-suggested)',
        }}
      >
        {part}
      </mark>
    ) : (
      part
    ),
  );
}

/**
 * A phone number that can be masked until the dispatcher asks for it.
 *
 * Off by default (Settings → Privacy → Mask contact numbers). It exists for the
 * screen other people can see — a shared display, a screen share, a projected
 * demo — where a resident's number should not be readable by whoever is
 * looking. It hides DISPLAY only; the number is still in the page's data, so
 * this is a courtesy against shoulder-surfing and not a security boundary.
 * Keeps the first four and last two digits so it is still recognisable.
 */
export function MaskedContact({
  value,
  mask,
  callable = true,
}: {
  value: string;
  mask: boolean;
  /** A tel: link, because the dispatcher's next action is often to ring it. */
  callable?: boolean;
}) {
  const [shown, setShown] = useState(false);

  if (!mask || shown) {
    return callable ? (
      <a className="underline underline-offset-2" href={`tel:${value}`}>
        {value}
      </a>
    ) : (
      <>{value}</>
    );
  }

  const total = value.replace(/\D/g, '').length;
  let seen = 0;
  const masked = value.replace(/\d/g, d => {
    const keep = seen < 4 || seen >= total - 2;
    seen += 1;
    return keep ? d : '•';
  });

  return (
    <span className="inline-flex items-center gap-2">
      <span className="font-mono tabular-nums">{masked}</span>
      <button
        className="text-[12px] font-semibold text-[var(--color-brand)] hover:underline"
        onClick={() => setShown(true)}
        type="button"
      >
        Reveal
      </button>
    </span>
  );
}

export function DetailSkeleton() {
  return (
    <div className="flex animate-pulse flex-col gap-3">
      {Array.from({ length: 3 }).map((_, i) => (
        <div
          className="flex flex-col gap-2.5 rounded-[14px] border border-[var(--color-surface-border)] p-4"
          key={i}
        >
          <div className="h-3 w-28 rounded bg-muted" />
          <div className="h-4 w-full rounded bg-muted" />
          <div className="h-4 w-2/3 rounded bg-muted" />
        </div>
      ))}
    </div>
  );
}
