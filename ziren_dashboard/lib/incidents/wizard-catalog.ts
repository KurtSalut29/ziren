/**
 * The 5W1H wizard, as the dashboard needs to read it back.
 *
 * The mobile app asks a resident a short set of questions per category and
 * posts the result as `wizard_answers`, a flat `{key: answer}` map. The
 * QUESTION TEXT never leaves the phone — the API stores only keys and answers
 * — so a console that wants to show what was actually asked has to hold its
 * own copy of the prompts. This is that copy.
 *
 * Keys and their categories are mirrored from
 *   ziren_mobile/lib/features/incident_report/presentation/wizard_report_screen.dart
 * Adding a question there without adding it here does not break anything: an
 * unrecognised key still renders, under "How", with its raw key as the label.
 * Nothing is ever silently dropped.
 *
 * ── DO NOT TRANSLATE THE ANSWER VALUES ──────────────────────────────────────
 * The answer strings are not display text. The backend's triage matches them
 * literally — triage_service compares against "Oo, kumakalat", and the rubric's
 * _STRUCTURE_MATERIALS set contains "Bahay" and "Gusali / Bodega" — so an
 * answer is a machine token that happens to be readable. Render it verbatim.
 * The PROMPTS below are display text and are given in English, because the
 * console's chrome is English while the resident answered in Tagalog/Bisaya.
 */

/** Which of the six a question answers. */
export type Facet = 'what' | 'who' | 'how';

interface WizardQuestion {
  /** English rendering of the prompt the resident actually saw. */
  label: string;
  /** Tagalog prompt as shown on the phone, for the record. */
  asked: string;
  facet: Facet;
}

export const WIZARD_QUESTIONS: Record<string, WizardQuestion> = {
  // ── fire ────────────────────────────────────────────────────────────────
  material:     { label: 'What is burning',        asked: 'Ano ang nasusunog?',              facet: 'what' },
  spreading:    { label: 'Still spreading',        asked: 'Kumakalat pa ba?',                facet: 'how'  },
  road_blocked: { label: 'Road blocked',           asked: 'Nakaharang sa daan?',             facet: 'how'  },

  // ── medical / trauma ────────────────────────────────────────────────────
  type:         { label: 'Kind of emergency',      asked: 'Uri ng emergency?',               facet: 'what' },
  victim_count: { label: 'Number of victims',      asked: 'Ilang biktima?',                  facet: 'who'  },
  bleeding:     { label: 'Bleeding or severe injury', asked: 'May dugo o matinding sugat?',  facet: 'who'  },
  conscious:    { label: 'Victim conscious',       asked: 'Gising ba ang biktima?',          facet: 'who'  },
  injured:      { label: 'Anyone hurt or trapped', asked: 'May nasugatan o nakulong?',       facet: 'who'  },

  // ── vehicular ───────────────────────────────────────────────────────────
  vehicle_type: { label: 'Vehicle involved',       asked: 'Anong sasakyan?',                 facet: 'what' },

  // ── flood / landslide / calamity ────────────────────────────────────────
  affected:     { label: 'Families affected',      asked: 'Ilang pamilya ang apektado?',     facet: 'who'  },
  evacuation:   { label: 'Evacuation needed',      asked: 'Kailangan ng evacuation?',        facet: 'how'  },

  // ── dispute / crime ─────────────────────────────────────────────────────
  weapon:       { label: 'Weapon present',         asked: 'May armas?',                      facet: 'how'  },
  ongoing:      { label: 'Still happening now',    asked: 'Nangyayari pa ba ngayon?',        facet: 'how'  },

  // ── every category ──────────────────────────────────────────────────────
  catch_all:    { label: 'Anything else',          asked: 'May iba pa bang dapat naming malaman?', facet: 'how' },
};

/** Reporter's relationship to the victim — the WHO the wizard asks directly. */
export const VICTIM_RELATIONSHIP: Record<string, string> = {
  ako_mismo:   'The reporter themselves',
  kamag_anak:  'A relative',
  kakilala:    'Someone they know',
  estranghero: 'A stranger',
};

/** Hazards flagged as also present, beyond the primary category. */
export const OVERLAP_LABELS: Record<string, string> = {
  injuries:       'Injuries',
  fire:           'Fire',
  flooding:       'Flooding',
  missing_person: 'Missing person',
  hazmat:         'Hazardous material',
  none:           'None',
};

/**
 * A stored value that means "nobody answered this", per key.
 *
 * `people_count: 'notsure'` is written by the phone on EVERY voice report
 * (incident_provider.dart, stopVoiceNote), as the default of a question the
 * app no longer shows anywhere: nothing calls setPeopleCount. The console
 * was drawing it as a fact of the report, "people count · notsure", which
 * told a dispatcher nothing and looked like something the resident had said.
 * The backend already treats it as no answer (triage_service's
 * _COUNT_ANSWERS leaves it out on purpose). A real count from an older report
 * ('2people', '4plus') is still shown.
 */
const NO_ANSWER: Record<string, string> = {
  people_count: 'notsure',
};

export interface WizardAnswer {
  key: string;
  label: string;
  asked: string | null;
  value: string;
}

/**
 * Split a wizard_answers payload into the facets it answers.
 *
 * Values are stringified rather than assumed — wizard_answers is JSONB and a
 * future question could store a number or a list. An empty or null answer is
 * dropped, because "the resident skipped this" is better said by the question
 * being absent than by a blank row implying an answer of "".
 */
export function groupWizardAnswers(
  answers: Record<string, unknown> | null | undefined,
): Record<Facet, WizardAnswer[]> {
  const out: Record<Facet, WizardAnswer[]> = { what: [], who: [], how: [] };
  if (!answers) return out;

  for (const [key, raw] of Object.entries(answers)) {
    if (raw === null || raw === undefined || raw === '') continue;
    const value = Array.isArray(raw) ? raw.join(', ') : String(raw);
    if (!value.trim()) continue;
    if (NO_ANSWER[key] === value) continue;

    const q = WIZARD_QUESTIONS[key];
    out[q?.facet ?? 'how'].push({
      key,
      // An unknown key keeps its raw name rather than vanishing. A question
      // added on the phone and not here should look unfinished, not absent.
      label: q?.label ?? key.replace(/_/g, ' '),
      asked: q?.asked ?? null,
      value,
    });
  }
  return out;
}
