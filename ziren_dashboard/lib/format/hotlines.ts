/**
 * Station hotlines, as stored in agencies.contact_number (migration 042):
 *
 *   one number                 0905-480-1417
 *   several, labelled or not   Globe: 0955-723-6300; Smart: 0948-024-3466
 *
 * Numbers are separated by ";" (or "|", a newline, or a "/" BETWEEN two
 * numbers — never the one in a label like "MDRRMO/EMS"); an optional
 * "Label:" names the network or line. The mobile app parses the same format
 * (ziren_mobile/lib/features/hotlines/domain/station_hotlines.dart) — keep
 * the two rules identical.
 */

export interface Hotline {
  /** As written for people: "0955-723-6300". */
  display: string;
  /** The network or line, when given: Globe, Smart, Landline. */
  label: string | null;
  /** What a phone dials: digits and a leading +. */
  dial: string;
}

const SPLIT = /[;\n|]|(?<=\d)\s*\/\s*(?=[\d(+])/;

export function parseHotlines(raw: string | null | undefined): Hotline[] {
  if (!raw) return [];
  const out: Hotline[] = [];
  for (const part of raw.split(SPLIT)) {
    let text = part.trim();
    if (!text) continue;
    let label: string | null = null;
    const colon = text.indexOf(':');
    if (colon > 0) {
      const head = text.slice(0, colon).trim();
      if (!/\d/.test(head)) {
        label = head;
        text = text.slice(colon + 1).trim();
      }
    }
    const digits = text.replace(/[^0-9]/g, '');
    if (digits.length < 7) continue;
    const dial = (text.startsWith('+') ? '+' : '') + digits;
    if (!out.some(h => h.dial === dial)) out.push({ display: text, label, dial });
  }
  return out;
}

/**
 * Why a contact_number value would not work as hotlines, or null when it
 * does. Every part must be a number of 7–15 digits.
 */
export function hotlineProblem(raw: string): string | null {
  const v = raw.trim();
  if (v === '') return null;
  if (v.length > 200) return 'Keep it under 200 characters.';
  const parts = v.split(SPLIT).map(p => p.trim()).filter(Boolean);
  for (const p of parts) {
    const colon = p.indexOf(':');
    const number = colon > 0 && !/\d/.test(p.slice(0, colon)) ? p.slice(colon + 1) : p;
    if (!/^\+?\d{7,15}$/.test(number.replace(/[\s\-().]/g, ''))) {
      return 'Use digits, for example 0955-723-6300. Separate several numbers with ";" — e.g. Globe: 0955-723-6300; Smart: 0948-024-3466.';
    }
  }
  return null;
}
