'use client';

/**
 * Presentational pieces of the incident detail dialog.
 *
 * Split out of incident-detail-modal.tsx, which owns the data fetching and the
 * dispatch actions. Everything here is a pure function of its props (plus one
 * local reveal toggle), so it can be read and changed without the dialog's
 * state in the way.
 */

import { useState } from 'react';
import { Sparkles, type LucideIcon } from 'lucide-react';
import { withoutVoicePlaceholder } from '@/lib/incidents/report-text';
import type { WizardAnswer } from '@/lib/incidents/wizard-catalog';

export function Section({
  title,
  facet,
  icon: Icon,
  children,
}: {
  title: string;
  /** The W (or H) this section answers, shown as a chip beside the heading. */
  facet: string;
  icon: LucideIcon;
  children: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-2">
      {/* Deliberately NOT .text-section-label (11px/500) — that class is the
          quiet sidebar/table-header style shared across the whole app, and
          turning it up here would have turned it up everywhere. These six
          headings are the report's own table of contents; a dispatcher
          scanning a long one needs them to interrupt the eye, not blend into
          the muted body text around them, so they get their own bigger,
          bolder, higher-contrast treatment plus a bottom rule that the quiet
          style never had. */}
      <h3 className="flex items-center gap-2 border-b border-[var(--color-surface-border)] pb-1.5">
        <Icon className="shrink-0" size={16} style={{ color: 'var(--color-text-secondary)' }} />
        <span className="text-[13.5px] font-bold uppercase tracking-wide text-foreground">
          {title}
        </span>
        {/* The facet label is what makes the 5W1H structure legible as a
            structure rather than as six arbitrary headings. */}
        <span
          className="rounded-full border px-1.5 py-px text-[10px] font-bold uppercase tracking-wide"
          style={{
            borderColor: 'color-mix(in srgb, var(--color-brand) 45%, transparent)',
            color: 'var(--color-brand)',
          }}
        >
          {facet}
        </span>
      </h3>
      {children}
    </section>
  );
}

/** Label left, value right — one fact per line, aligned down the panel. */
export function Row({
  label,
  sub,
  icon: Icon,
  children,
}: {
  label: string;
  /** The prompt as the resident saw it, verbatim. */
  sub?: string;
  icon?: LucideIcon;
  children: React.ReactNode;
}) {
  return (
    <div className="grid grid-cols-[150px_minmax(0,1fr)] gap-3 text-[13px]">
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
      <span className="min-w-0 break-words text-foreground">{children}</span>
    </div>
  );
}

/**
 * Wizard answers, rendered verbatim.
 *
 * The VALUE is never translated or prettified — the backend's triage matches
 * these strings literally, so what is displayed has to be exactly what was
 * stored, or the console and the rubric would be describing different reports.
 * The Tagalog prompt sits under the English label as the record of what the
 * resident was actually asked.
 */
export function Answers({ items }: { items: WizardAnswer[] }) {
  if (items.length === 0) return null;
  return (
    <>
      {items.map(a => (
        <Row key={a.key} label={a.label} sub={a.asked ?? undefined}>
          {a.value}
        </Row>
      ))}
    </>
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
    <div className="flex animate-pulse flex-col gap-5">
      {Array.from({ length: 3 }).map((_, i) => (
        <div className="flex flex-col gap-2" key={i}>
          <div className="h-3 w-28 rounded bg-muted" />
          <div className="h-4 w-full rounded bg-muted" />
          <div className="h-4 w-2/3 rounded bg-muted" />
        </div>
      ))}
    </div>
  );
}
