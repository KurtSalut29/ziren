/**
 * What a report SAYS, as opposed to what the mobile app wrapped around it.
 *
 * When a resident records a voice note and types nothing, the mobile app has
 * to file SOMETHING as `report_text` — the backend rejects anything under ten
 * characters, and the transcript does not exist until after submission. So it
 * files a placeholder: "<Category> — reported by voice recording" (English) or
 * "<Category> — iniulat sa pamamagitan ng boses" (Filipino). The transcription
 * service then APPENDS what it heard, giving
 *
 *     Fire — reported by voice recording — Sir tabang need na mo inyong help…
 *
 * and the spelling correction (`signals.normalisation.text`) is computed over
 * that whole composite, so it carries the same prefix.
 *
 * The prefix is the app's scaffolding, not the resident's words, and it repeats
 * what the Type column already says. On a record it is noise in front of the
 * one thing a reader came for. This strips it for DISPLAY. The stored
 * `report_text` is never touched: it is the record, and the placeholder is part
 * of how it was filed.
 *
 * WHAT IS DELIBERATELY NOT STRIPPED
 *
 *   - A report the resident typed ("Fire — may sunog sa bahay"). The label
 *     before the dash is the app's format for typed notes too, but there the
 *     words after it are the resident's own and the placeholder phrase is
 *     absent, so nothing here matches it.
 *   - "<Category> — no additional details provided". That is the app saying the
 *     resident gave nothing at all, which is true and is not a voice report.
 *
 * Pure functions, no imports beyond types, so they can be checked in isolation.
 */

import type { TriageSignals } from '@/lib/api/dispatch';

/**
 * <label> — <placeholder> [— <what was heard>]
 *
 * The label is anything up to sixty characters without an em dash: category
 * labels are short ("Fire", "Medical / trauma") and never contain one, so
 * excluding the dash is what stops this matching a typed report that merely
 * mentions the phrase further along.
 */
const VOICE_PLACEHOLDER =
  /^\s*[^—]{1,60}?\s+—\s+(?:reported by voice recording|iniulat sa pamamagitan ng boses)(?:\s+—\s+([\s\S]*?))?\s*$/;

/** The words after the placeholder, or null if `text` is not a placeholder. */
function afterPlaceholder(text: string | null | undefined): string | null {
  if (!text) return null;
  const m = VOICE_PLACEHOLDER.exec(text);
  if (!m) return null;
  return (m[1] ?? '').trim();
}

export interface RecordReportText {
  /** What to show. Empty only when `kind` is 'voice-untranscribed'. */
  text: string;
  /**
   * - `typed`               the resident's own words; shown exactly as stored.
   * - `voice`               a voice report; `text` is what was said.
   * - `voice-untranscribed` a voice report with no transcript — there is a
   *                         recording and nothing to read yet, or ever.
   */
  kind: 'typed' | 'voice' | 'voice-untranscribed';
}

/**
 * The text to show for a report on a record.
 *
 * For a voice report: the CORRECTED text when the spelling pass changed
 * something, otherwise the transcript as heard — either way without the app's
 * prefix. Anything else comes back exactly as stored.
 */
export function recordReportText(
  reportText: string,
  signals?: Pick<TriageSignals, 'normalisation'> | null,
): RecordReportText {
  const heard = afterPlaceholder(reportText);
  if (heard === null) return { text: reportText, kind: 'typed' };

  const corrected = afterPlaceholder(signals?.normalisation?.text);
  const spoken = corrected || heard;
  return spoken
    ? { text: spoken, kind: 'voice' }
    : { text: '', kind: 'voice-untranscribed' };
}

/**
 * The same text with only the app's prefix removed, for places that show the
 * resident's words and the corrected words side by side and so must not
 * substitute one for the other. Returns the input unchanged when it is not a
 * voice placeholder.
 */
export function withoutVoicePlaceholder(text: string): string {
  const heard = afterPlaceholder(text);
  return heard === null ? text : heard;
}
