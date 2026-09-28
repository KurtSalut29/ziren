/**
 * The Narrative Report form, as data.
 *
 * The form is the agency's Incident Record Form - Items A to D and the
 * certification block - and everything here is about getting a person from a
 * resolved incident to a filled-in one with as little retyping as possible:
 * empty shapes to build from, defaults taken from what Ziren already knows about
 * the incident, and the small amount of parsing that turns "Kurt Michael S.
 * Salut" or "Brgy. Casiawan, Cabucgayan, Biliran" into the boxes they belong in.
 *
 * Everything parsed is a starting point, never a claim. A name split wrongly or
 * a barangay left blank is corrected in the box; a wrong value that looked
 * authoritative and was quietly printed on an official form is the failure this
 * file is written to avoid, so it leaves a box empty rather than guess.
 */

import type {
  IncidentDetail, NarrativeDetails, NarrativePerson, NarrativeSuspect,
} from '@/lib/api/dispatch';
import { CATEGORY_LABELS } from '@/lib/charts/queue-series';
import { recordReportText } from '@/lib/incidents/report-text';

export function emptyPerson(): NarrativePerson {
  return {
    family_name: '', first_name: '', middle_name: '', qualifier: '', nickname: '',
    citizenship: '', gender: '', civil_status: '', date_of_birth: '', age: '',
    place_of_birth: '', phone: '',
    address_street: '', barangay: '', town_city: '', province: '',
    education: '', occupation: '', relation: '',
  };
}

export function emptySuspect(): NarrativeSuspect {
  return {
    ...emptyPerson(),
    rank: '', unit_assignment: '', group_affiliation: '',
    previous_record: '', previous_case_status: '',
    height: '', weight: '', eye_color: '', hair_color: '',
    distinguishing_marks: '', under_influence: '',
    guardian_name: '', guardian_address: '',
  };
}

export function emptyDetails(): NarrativeDetails {
  return {
    form_version: 1,
    copy_for: 'Complainant',
    offense: '', offense_detail: '',
    place_barangay: '', place_town: '', place_province: '',
    witnesses: '', property_damage: '', actions_taken: '',
    reporting_person: emptyPerson(),
    suspects: [],
    victims: [],
    certification: { administering_officer: '', investigator_rank_name: '', desk_officer_rank_name: '' },
    station: { name: '', telephone: '', mobile: '', chief: '' },
  };
}

/**
 * A saved report's details laid over the empty shape, so a report saved before a
 * box existed (or before migration 040, when there are none) still opens with
 * every field defined.
 */
export function mergeDetails(saved: Partial<NarrativeDetails> | null | undefined): NarrativeDetails {
  const base = emptyDetails();
  if (!saved) return base;
  return {
    ...base,
    ...saved,
    reporting_person: { ...base.reporting_person, ...(saved.reporting_person ?? {}) },
    suspects: (saved.suspects ?? []).map(s => ({ ...emptySuspect(), ...s })),
    victims: (saved.victims ?? []).map(v => ({ ...emptyPerson(), ...v })),
    certification: { ...base.certification, ...(saved.certification ?? {}) },
    station: { ...base.station, ...(saved.station ?? {}) },
  };
}

// ── Parsing what Ziren already has ────────────────────────────────────────

/** Words that belong to a surname rather than standing alone: "Dela Cruz", "De Guzman". */
const SURNAME_PARTICLES = new Set([
  'de', 'del', 'dela', 'delos', 'delas', 'di', 'da', 'la', 'las', 'los', 'san', 'santa', 'van', 'von', 'ver',
]);

export function splitFullName(full: string | null | undefined): {
  first_name: string; middle_name: string; family_name: string;
} {
  const tokens = (full ?? '').trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return { first_name: '', middle_name: '', family_name: '' };
  if (tokens.length === 1) return { first_name: tokens[0], middle_name: '', family_name: '' };

  // The surname is the last word, plus any particle words directly before it.
  let familyStart = tokens.length - 1;
  while (familyStart > 1 && SURNAME_PARTICLES.has(tokens[familyStart - 1].toLowerCase())) familyStart -= 1;
  const family = tokens.slice(familyStart).join(' ');
  const rest = tokens.slice(0, familyStart);

  // With three or more words left over, the last of them is the middle name
  // (a Filipino full name is first names, then the mother's maiden name, then the
  // surname); with two it is a first and a family name only.
  if (rest.length >= 2) {
    return { first_name: rest.slice(0, -1).join(' '), middle_name: rest[rest.length - 1], family_name: family };
  }
  return { first_name: rest[0] ?? '', middle_name: '', family_name: family };
}

const BILIRAN_TOWNS = ['Almeria', 'Biliran', 'Cabucgayan', 'Caibiran', 'Culaba', 'Kawayan', 'Maripipi', 'Naval'];

/**
 * The barangay, town and province out of an address written the way the app writes
 * them: "Brgy. Casiawan, Cabucgayan, Biliran". A barangay is taken ONLY when the
 * address says so ("Brgy X" / "Barangay X") - "Biliran Province State University"
 * is a place, not a barangay, and guessing would print the wrong one on the form.
 */
export function parseAddress(address: string | null | undefined): {
  barangay: string; town: string; province: string;
} {
  const parts = (address ?? '').split(',').map(p => p.trim()).filter(Boolean);
  let province = '';
  let town = '';
  let barangay = '';

  if (parts.length > 0 && /^biliran$/i.test(parts[parts.length - 1])) {
    province = 'Biliran';
    parts.pop();
  }
  if (parts.length > 0) {
    const last = parts[parts.length - 1];
    const match = BILIRAN_TOWNS.find(t => t.toLowerCase() === last.replace(/^(municipality|town) of\s+/i, '').toLowerCase());
    if (match) {
      town = match;
      parts.pop();
    }
  }
  for (const p of parts) {
    const m = p.match(/^(?:brgy\.?|barangay|bgy\.?)\s+(.+)$/i);
    if (m) { barangay = m[1].trim(); break; }
  }
  return { barangay, town, province };
}

/** What the form starts from: everything Ziren already knows about this incident. */
export function narrativeDefaults(
  incident: IncidentDetail,
  adminName: string | null,
): { details: NarrativeDetails; occurredAt: string; place: string; preparedBy: string } {
  const details = emptyDetails();
  const where = parseAddress(incident.location_address);

  details.offense = CATEGORY_LABELS[incident.incident_category ?? ''] ?? '';
  details.place_barangay = where.barangay;
  details.place_town = where.town || incident.stations?.agencies?.municipality || '';
  details.place_province = where.province || (incident.stations ? 'Biliran' : '');

  const name = splitFullName(incident.users?.full_name);
  details.reporting_person = {
    ...emptyPerson(),
    ...name,
    phone: incident.users?.phone_number ?? '',
    citizenship: 'Filipino',
    barangay: '', town_city: '', province: '',
  };
  details.station = {
    name: incident.stations?.name ?? '',
    telephone: incident.stations?.agencies?.contact_number ?? '',
    mobile: '',
    chief: '',
  };

  return {
    details,
    occurredAt: incident.created_at,
    place: incident.location_address ?? '',
    preparedBy: adminName ?? '',
  };
}

/** The resident's own account, without the app's voice-report scaffolding - for "start from what they said". */
export function residentAccount(incident: IncidentDetail): string {
  return recordReportText(incident.report_text ?? '', incident.signals).text.trim();
}

// ── Choices offered in the boxes ──────────────────────────────────────────

export const COPY_FOR_CHOICES = ['Complainant', 'Police station', 'Fire station', 'MDRRMO', 'Prosecutor', 'Court', 'File copy'];
export const GENDER_CHOICES = ['Female', 'Male'];
export const CIVIL_STATUS_CHOICES = ['Single', 'Married', 'Live-in', 'Widowed', 'Separated'];
export const EDUCATION_CHOICES = [
  'No formal schooling', 'Elementary level (undergraduate)', 'Elementary graduate',
  'High school level (undergraduate)', 'High school graduate', 'Senior high school',
  'College level (undergraduate)', 'College graduate', 'Vocational', 'Post-graduate',
];
export const RELATION_CHOICES = [
  'Stranger/No Relationship', 'Spouse', 'Live-in partner', 'Parent', 'Child', 'Sibling', 'Relative',
  'Neighbor', 'Friend', 'Co-worker', 'Employer/Employee', 'Ex-partner',
];
export const INFLUENCE_CHOICES = ['None', 'Alcohol', 'Drugs', 'Alcohol and drugs', 'Unknown'];
export const YES_NO_CHOICES = ['NO', 'YES', 'UNKNOWN'];

/** What the incident type box offers, by the category the resident's report was filed under. */
export const OFFENSE_SUGGESTIONS: Record<string, string[]> = {
  fire: ['Structure fire', 'Grass / forest fire', 'Vehicular fire', 'Electrical fire', 'Arson'],
  medical_trauma: ['Medical emergency', 'Trauma / injury', 'Drowning', 'Childbirth'],
  vehicular: ['Vehicular accident', 'Vehicular accident with injuries', 'Hit and run'],
  flood_landslide_calamity: ['Flood', 'Landslide', 'Storm damage', 'Fallen tree', 'Earthquake'],
  domestic_dispute_crime: [
    'Domestic dispute', 'Physical injuries', 'Theft', 'Robbery', 'Threats', 'Illegal logging',
    'Trespassing', 'Malicious mischief',
  ],
  other: [],
};

// ── Progress ──────────────────────────────────────────────────────────────

export interface SectionProgress {
  key: string;
  label: string;
  /** "3 of 5 filled", "2 added" - one short phrase for the outline. */
  hint: string;
  done: boolean;
}

const filled = (o: object) => Object.values(o).filter(v => typeof v === 'string' && v.trim() !== '').length;

/**
 * What is done and what is not, for the outline beside the form. "Done" is
 * deliberately modest - the narrative written, the people that exist named - so a
 * tick means "this section has what it needs", not "every box on a form built for
 * every kind of incident is filled".
 */
export function progressOf(
  narrative: string,
  d: NarrativeDetails,
  ctx: { referenceNo: string; occurredAt: string; place: string },
): SectionProgress[] {
  const named = (p: NarrativePerson) => p.first_name.trim() !== '' || p.family_name.trim() !== '';
  const words = narrative.trim() ? narrative.trim().split(/\s+/).length : 0;
  const caseFilled = [ctx.referenceNo, d.offense, ctx.occurredAt, ctx.place].filter(v => v.trim() !== '').length;
  const certFilled = filled(d.certification) + filled(d.station);
  return [
    { key: 'case', label: 'Case details', hint: `${caseFilled} of 4 key boxes`, done: caseFilled >= 3 },
    { key: 'a', label: 'A · Reporting person', hint: `${filled(d.reporting_person)} boxes filled`, done: named(d.reporting_person) },
    {
      key: 'b', label: 'B · Suspects',
      hint: d.suspects.length ? `${d.suspects.length} added` : 'None recorded',
      done: d.suspects.length === 0 || d.suspects.every(named),
    },
    {
      key: 'c', label: 'C · Victims',
      hint: d.victims.length ? `${d.victims.length} added` : 'None recorded',
      done: d.victims.length === 0 || d.victims.every(named),
    },
    { key: 'd', label: 'D · Narrative', hint: words ? `${words} words` : 'Not written yet', done: words >= 20 },
    { key: 'cert', label: 'Certification & contacts', hint: `${certFilled} boxes filled`, done: certFilled >= 2 },
  ];
}

// ── datetime-local <-> ISO ────────────────────────────────────────────────

/** `2026-09-23T14:30` - what a datetime-local input reads and writes, from an
 *  ISO timestamp in the viewer's own local time. */
export function toLocalInput(iso: string | null | undefined): string {
  if (!iso) return '';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** The reverse of toLocalInput - empty means "no override", not midnight. */
export function fromLocalInput(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/** A person's name the way the form's certification line prints it. */
export function fullNameOf(p: { first_name: string; middle_name: string; family_name: string }): string {
  return [p.first_name, p.middle_name, p.family_name].map(s => s.trim()).filter(Boolean).join(' ');
}
