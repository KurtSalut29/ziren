'use client';

/**
 * The boxes of one person on the Incident Record Form.
 *
 * The reporting person, every suspect and every victim are the same twenty-odd
 * boxes, printed the same way, so they are one component. A suspect adds what
 * only a suspect is asked (rank, group, height, eye colour, and so on) through
 * `SuspectExtras`.
 *
 * Every box is free text with suggestions rather than a fixed dropdown: the
 * paper form is free text, the people who fill it in write "Live-in" and
 * "Elementary level (undergraduate)" as they see fit, and a closed list would
 * turn a true answer into the nearest wrong one.
 */

import { useId } from 'react';
import type { NarrativePerson, NarrativeSuspect } from '@/lib/api/dispatch';
import {
  CIVIL_STATUS_CHOICES, EDUCATION_CHOICES, GENDER_CHOICES, INFLUENCE_CHOICES,
  RELATION_CHOICES, YES_NO_CHOICES,
} from '@/lib/incidents/narrative-form';

/** The caption-above-the-box cell every field here is drawn as. */
export function Field({
  label, hint, className = '', children,
}: {
  label: string;
  hint?: string;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <label className={`flex min-w-0 flex-col gap-1 ${className}`}>
      <span className="text-[10.5px] font-bold uppercase tracking-[0.06em] text-[var(--color-text-tertiary)]">
        {label}
      </span>
      {children}
      {hint && <span className="text-[11px] text-[var(--color-text-muted)]">{hint}</span>}
    </label>
  );
}

/** The age a birth date works out to, shown as the box's placeholder until one is typed. */
function ageFromBirth(dob: string): string {
  const d = new Date(dob);
  if (!dob || Number.isNaN(d.getTime())) return '';
  const now = new Date();
  let years = now.getFullYear() - d.getFullYear();
  const before = now.getMonth() < d.getMonth() || (now.getMonth() === d.getMonth() && now.getDate() < d.getDate());
  if (before) years -= 1;
  return years >= 0 && years < 130 ? String(years) : '';
}

export function PersonFields<T extends NarrativePerson>({
  value, onChange, relationLabel,
}: {
  value: T;
  onChange: (next: T) => void;
  relationLabel: string;
}) {
  const uid = useId();
  const set = (key: keyof NarrativePerson) => (e: React.ChangeEvent<HTMLInputElement>) =>
    onChange({ ...value, [key]: e.target.value });
  const list = (name: string, options: string[]) => (
    <datalist id={`${uid}-${name}`}>
      {options.map(o => <option key={o} value={o} />)}
    </datalist>
  );

  return (
    <div className="grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
      <Field className="sm:col-span-4" label="Family name">
        <input autoComplete="off" onChange={set('family_name')} type="text" value={value.family_name} />
      </Field>
      <Field className="sm:col-span-4" label="First name">
        <input autoComplete="off" onChange={set('first_name')} type="text" value={value.first_name} />
      </Field>
      <Field className="sm:col-span-4" label="Middle name">
        <input autoComplete="off" onChange={set('middle_name')} type="text" value={value.middle_name} />
      </Field>

      <Field className="sm:col-span-3" label="Qualifier" hint="Jr., Sr., III">
        <input onChange={set('qualifier')} type="text" value={value.qualifier} />
      </Field>
      <Field className="sm:col-span-3" label="Nickname">
        <input onChange={set('nickname')} type="text" value={value.nickname} />
      </Field>
      <Field className="sm:col-span-3" label="Citizenship">
        <input onChange={set('citizenship')} placeholder="Filipino" type="text" value={value.citizenship} />
      </Field>
      <Field className="sm:col-span-3" label="Gender">
        <input list={`${uid}-gender`} onChange={set('gender')} type="text" value={value.gender} />
        {list('gender', GENDER_CHOICES)}
      </Field>

      <Field className="sm:col-span-3" label="Civil status">
        <input list={`${uid}-civil`} onChange={set('civil_status')} type="text" value={value.civil_status} />
        {list('civil', CIVIL_STATUS_CHOICES)}
      </Field>
      <Field className="sm:col-span-3" label="Date of birth">
        <input onChange={set('date_of_birth')} type="date" value={value.date_of_birth} />
      </Field>
      <Field className="sm:col-span-2" label="Age">
        <input
          inputMode="numeric"
          onChange={set('age')}
          placeholder={ageFromBirth(value.date_of_birth)}
          type="text"
          value={value.age}
        />
      </Field>
      <Field className="sm:col-span-4" label="Phone number">
        <input inputMode="tel" onChange={set('phone')} type="text" value={value.phone} />
      </Field>

      <Field className="sm:col-span-6" label="Place of birth">
        <input onChange={set('place_of_birth')} type="text" value={value.place_of_birth} />
      </Field>
      <Field className="sm:col-span-6" label="Highest educational attainment">
        <input list={`${uid}-edu`} onChange={set('education')} type="text" value={value.education} />
        {list('edu', EDUCATION_CHOICES)}
      </Field>

      <Field className="sm:col-span-6" label="Occupation">
        <input onChange={set('occupation')} type="text" value={value.occupation} />
      </Field>
      <Field className="sm:col-span-6" label={relationLabel}>
        <input list={`${uid}-rel`} onChange={set('relation')} type="text" value={value.relation} />
        {list('rel', RELATION_CHOICES)}
      </Field>

      <Field className="sm:col-span-12" label="Address (house number / street) village / sitio">
        <input onChange={set('address_street')} type="text" value={value.address_street} />
      </Field>
      <Field className="sm:col-span-4" label="Barangay">
        <input onChange={set('barangay')} type="text" value={value.barangay} />
      </Field>
      <Field className="sm:col-span-4" label="Town / city">
        <input onChange={set('town_city')} type="text" value={value.town_city} />
      </Field>
      <Field className="sm:col-span-4" label="Province">
        <input onChange={set('province')} type="text" value={value.province} />
      </Field>
    </div>
  );
}

/** What only a suspect is asked: rank and unit, record, physical description, and a guardian. */
export function SuspectExtras({
  value, onChange,
}: {
  value: NarrativeSuspect;
  onChange: (next: NarrativeSuspect) => void;
}) {
  const uid = useId();
  const set = (key: keyof NarrativeSuspect) => (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
  ) => onChange({ ...value, [key]: e.target.value });

  return (
    <div className="mt-4 border-t border-dashed border-[var(--color-surface-border)] pt-4">
      <p className="mb-3 text-[11px] font-bold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">
        Police / group record and description
      </p>
      <div className="grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
        <Field className="sm:col-span-4" label="Rank (AFP / PNP personnel)">
          <input onChange={set('rank')} type="text" value={value.rank} />
        </Field>
        <Field className="sm:col-span-4" label="Unit assignment">
          <input onChange={set('unit_assignment')} type="text" value={value.unit_assignment} />
        </Field>
        <Field className="sm:col-span-4" label="Group affiliation">
          <input onChange={set('group_affiliation')} placeholder="None" type="text" value={value.group_affiliation} />
        </Field>
        <Field className="sm:col-span-4" label="Previous criminal record">
          <input list={`${uid}-yn`} onChange={set('previous_record')} type="text" value={value.previous_record} />
          <datalist id={`${uid}-yn`}>
            {YES_NO_CHOICES.map(o => <option key={o} value={o} />)}
          </datalist>
        </Field>
        <Field className="sm:col-span-8" label="Status of previous case">
          <input onChange={set('previous_case_status')} type="text" value={value.previous_case_status} />
        </Field>

        <Field className="sm:col-span-3" label="Height">
          <input onChange={set('height')} placeholder="e.g. 170 cm" type="text" value={value.height} />
        </Field>
        <Field className="sm:col-span-3" label="Weight">
          <input onChange={set('weight')} placeholder="e.g. 65 kg" type="text" value={value.weight} />
        </Field>
        <Field className="sm:col-span-3" label="Color of eyes">
          <input onChange={set('eye_color')} type="text" value={value.eye_color} />
        </Field>
        <Field className="sm:col-span-3" label="Color of hair">
          <input onChange={set('hair_color')} type="text" value={value.hair_color} />
        </Field>
        <Field className="sm:col-span-8" label="Distinguishing marks">
          <input onChange={set('distinguishing_marks')} placeholder="Scars, tattoos, birthmarks…" type="text" value={value.distinguishing_marks} />
        </Field>
        <Field className="sm:col-span-4" label="Under the influence">
          <input list={`${uid}-inf`} onChange={set('under_influence')} type="text" value={value.under_influence} />
          <datalist id={`${uid}-inf`}>
            {INFLUENCE_CHOICES.map(o => <option key={o} value={o} />)}
          </datalist>
        </Field>
      </div>

      <p className="mb-3 mt-5 text-[11px] font-bold uppercase tracking-[0.08em] text-[var(--color-text-tertiary)]">
        For children in conflict with the law
      </p>
      <div className="grid grid-cols-1 gap-x-3 gap-y-3 sm:grid-cols-12">
        <Field className="sm:col-span-6" label="Name of guardian">
          <input onChange={set('guardian_name')} type="text" value={value.guardian_name} />
        </Field>
        <Field className="sm:col-span-6" label="Guardian address">
          <input onChange={set('guardian_address')} type="text" value={value.guardian_address} />
        </Field>
      </div>
    </div>
  );
}
