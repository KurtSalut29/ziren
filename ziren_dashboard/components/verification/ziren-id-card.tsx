'use client';

/**
 * The Ziren ID — a verified resident shown as an identity card.
 *
 * User request 2026-10-08: opening a verified resident should show Ziren's own
 * ID card — their photograph, their particulars, the number Ziren knows them
 * by — "yung talagang ID talaga". The photograph is the selfie the
 * administrator approved: user_service.decide_verification keeps it on
 * approval (the ID scan itself is still deleted), and the server hands it out
 * as a short-lived signed link, to administrators only.
 *
 * WHAT IS ON IT, AND WHAT IS NOT
 *
 * Name (as on the ID the resident showed), date of birth, address, the date
 * and manner of verification, and the Ziren ID number. NOT sex or gender: the
 * card identifies by the face and the number, the same rule as the Ziren code
 * a responder asks for at the scene (GAD - nobody is identified by how they
 * present), and nothing on it should out or misgender the holder.
 *
 * A printed artefact, so it keeps its own fixed palette in both themes (a card
 * does not turn dark at night) and survives printing: html.print-id-card in
 * globals.css hides everything but [data-id-card] while the print runs.
 */

import { useRef, useState } from 'react';
import { BadgeCheck, Ban, Printer, UserRound } from 'lucide-react';
import { Button } from '@/components/efferd/ui/button';
import { ID_TYPE_LABELS } from '@/lib/api/verification';
import type { ResidentDetail } from '@/lib/api/residents';

const INK = '#16181D';
const MUTED = '#6B7280';
const PAPER = '#FFFDF8';
const RULE = '#E7E1D6';
const SEAL = '#15803D';
const STOP = '#B91C1C';

const METHOD: Record<string, string> = {
  government_id: 'Government ID examined',
  barangay_official: 'Barangay official confirmed',
  pwd_id: 'PWD ID examined',
  phone_otp: 'Phone OTP',
};

/** "ZR-2026-4F3A9C1D": the year Ziren verified them and the account's own id. */
export function zirenIdNumber(d: Pick<ResidentDetail, 'id' | 'verified_at' | 'created_at'>): string {
  const year = new Date(d.verified_at ?? d.created_at).getFullYear();
  const tail = d.id.replace(/-/g, '').slice(0, 8).toUpperCase();
  return `ZR-${Number.isFinite(year) ? year : '----'}-${tail}`;
}

/** A calendar date as printed on an ID: "31 JUL 2005". No time zone shift. */
function cardDate(value: string | null | undefined): string | null {
  if (!value) return null;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(value);
  const d = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d
    .toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })
    .toUpperCase();
}

/** The name in its parts when the account has them; else split the full name. */
function nameParts(d: ResidentDetail): { last: string; given: string; middle: string } {
  if (d.last_name || d.first_name) {
    const last = [d.last_name, d.name_suffix].filter(Boolean).join(' ');
    return { last: last || '—', given: d.first_name || '—', middle: d.middle_name || '—' };
  }
  const words = (d.full_name || '').trim().split(/\s+/).filter(Boolean);
  if (words.length < 2) return { last: words[0] ?? '—', given: '—', middle: '—' };
  return { last: words[words.length - 1], given: words.slice(0, -1).join(' '), middle: '—' };
}

function Field({ label, children, wide }: { label: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={wide ? 'col-span-full min-w-0' : 'min-w-0'}>
      <p className="text-[8.5px] font-bold uppercase tracking-[0.14em]" style={{ color: MUTED }}>{label}</p>
      <p className="truncate text-[13px] font-bold uppercase leading-tight" style={{ color: INK }}>
        {children || '—'}
      </p>
    </div>
  );
}

export function ZirenIdCard({ detail }: { detail: ResidentDetail }) {
  const [photoFailed, setPhotoFailed] = useState(false);
  const name = nameParts(detail);
  const number = zirenIdNumber(detail);
  const suspended = detail.standing === 'suspended';
  const address = [detail.purok_sitio, detail.street_address, detail.barangay, detail.municipality_address, 'Biliran']
    .filter(Boolean).join(', ');
  const initials = `${name.given[0] ?? ''}${name.last[0] ?? ''}`.replace(/—/g, '').toUpperCase();
  const photo = detail.photo_url && !photoFailed ? detail.photo_url : null;

  const cardRef = useRef<HTMLDivElement>(null);

  /** Print the card alone. A copy goes straight under <body>: the dialog it
   *  sits in is transformed, which would carry the card off the page. */
  function print() {
    if (!cardRef.current) return;
    const root = document.documentElement;
    const holder = document.createElement('div');
    holder.setAttribute('data-id-card-print', '');
    holder.appendChild(cardRef.current.cloneNode(true));
    document.body.appendChild(holder);
    root.classList.add('print-id-card');
    let finished = false;
    const done = () => {
      if (finished) return;
      finished = true;
      root.classList.remove('print-id-card');
      holder.remove();
      window.removeEventListener('afterprint', done);
    };
    window.addEventListener('afterprint', done);
    window.print();
    // Some browsers return from print() before afterprint; never leave the copy behind.
    setTimeout(done, 1500);
  }

  return (
    <div className="flex flex-col items-center gap-2.5">
      <div
        aria-label={`Ziren ID of ${detail.full_name}`}
        className="relative w-full max-w-[540px] overflow-hidden rounded-[16px] border shadow-[0_8px_24px_rgba(0,0,0,0.12)]"
        data-id-card
        data-testid="ziren-id-card"
        ref={cardRef}
        role="img"
        style={{
          aspectRatio: '1.586',
          borderColor: RULE,
          backgroundColor: PAPER,
          // A faint guilloche, the way printed IDs carry one: hard to copy, easy to ignore.
          backgroundImage: [
            'repeating-radial-gradient(circle at 78% 120%, rgba(22,24,29,0.035) 0 1px, transparent 1px 9px)',
            'repeating-radial-gradient(circle at 10% -20%, rgba(21,128,61,0.035) 0 1px, transparent 1px 11px)',
          ].join(','),
          printColorAdjust: 'exact',
          WebkitPrintColorAdjust: 'exact',
        }}
      >
        <div className="flex h-full flex-col">
          {/* Band */}
          <div className="flex items-center gap-2.5 px-4 py-2.5" style={{ backgroundColor: INK }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img alt="" className="size-8 shrink-0" src="/ziren-mark-on-dark.png" />
            <div className="min-w-0 flex-1 leading-tight">
              <p className="text-[14px] font-extrabold tracking-[0.22em] text-white">ZIREN</p>
              <p className="truncate text-[9px] font-semibold uppercase tracking-[0.16em] text-white/70">
                Emergency Response · Biliran
              </p>
            </div>
            <p className="shrink-0 text-right text-[10px] font-extrabold uppercase leading-tight tracking-[0.18em] text-white">
              Resident<br />ID card
            </p>
          </div>

          {/* Body */}
          <div className="grid min-h-0 flex-1 grid-cols-[30%_1fr] gap-3.5 px-4 pt-3">
            <div className="flex min-h-0 flex-col gap-1.5">
              <div
                className="relative flex aspect-[3/4] w-full items-center justify-center overflow-hidden rounded-[8px] border"
                style={{ borderColor: RULE, backgroundColor: '#EFEAE0' }}
              >
                {photo ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    alt={`Photograph of ${detail.full_name}`}
                    className="size-full object-cover"
                    data-testid="ziren-id-photo"
                    onError={() => setPhotoFailed(true)}
                    src={photo}
                  />
                ) : (
                  <span className="flex flex-col items-center gap-1 px-2 text-center" data-testid="ziren-id-no-photo">
                    {initials ? (
                      <span className="text-[26px] font-extrabold" style={{ color: '#9CA3AF' }}>{initials}</span>
                    ) : (
                      <UserRound size={30} style={{ color: '#9CA3AF' }} />
                    )}
                    <span className="text-[8px] font-semibold uppercase leading-tight tracking-wider" style={{ color: MUTED }}>
                      No photo on file
                    </span>
                  </span>
                )}
              </div>
            </div>

            <div className="grid min-w-0 content-start grid-cols-2 gap-x-3 gap-y-2">
              <Field label="Surname" wide>{name.last}</Field>
              <Field label="Given name">{name.given}</Field>
              <Field label="Middle name">{name.middle}</Field>
              <Field label="Date of birth">{cardDate(detail.date_of_birth)}</Field>
              <Field label="Verified on">{cardDate(detail.verified_at)}</Field>
              <div className="col-span-full min-w-0">
                <p className="text-[8.5px] font-bold uppercase tracking-[0.14em]" style={{ color: MUTED }}>Address</p>
                <p className="line-clamp-2 text-[11.5px] font-bold uppercase leading-snug" style={{ color: INK }}>
                  {address}
                </p>
              </div>
              {detail.emergency_contact_name && (
                <div className="col-span-full min-w-0">
                  <p className="text-[8.5px] font-bold uppercase tracking-[0.14em]" style={{ color: MUTED }}>In case of emergency</p>
                  <p className="truncate text-[11.5px] font-bold uppercase leading-snug" style={{ color: INK }}>
                    {detail.emergency_contact_name}
                    {detail.emergency_contact_number && (
                      <span className="font-mono normal-case"> · {detail.emergency_contact_number}</span>
                    )}
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Footer */}
          <div className="mt-auto flex items-end justify-between gap-3 border-t px-4 pt-2 pb-2.5" style={{ borderColor: RULE }}>
            <div className="min-w-0">
              <p className="text-[8.5px] font-bold uppercase tracking-[0.14em]" style={{ color: MUTED }}>Ziren ID no.</p>
              <p className="font-mono text-[15px] font-bold tracking-[0.08em]" data-testid="ziren-id-number" style={{ color: INK }}>
                {number}
              </p>
            </div>
            <div className="min-w-0 text-right">
              <p
                className="inline-flex items-center gap-1 text-[10.5px] font-extrabold uppercase tracking-[0.12em]"
                style={{ color: SEAL }}
              >
                <BadgeCheck aria-hidden size={14} /> Verified resident
              </p>
              <p className="truncate text-[9px] font-semibold uppercase tracking-wider" style={{ color: MUTED }}>
                {[
                  METHOD[detail.verification_method ?? ''],
                  detail.valid_id_type ? ID_TYPE_LABELS[detail.valid_id_type] ?? detail.valid_id_type : null,
                ].filter(Boolean).join(' · ') || 'Checked by an administrator'}
              </p>
            </div>
          </div>
        </div>

        {/* A suspended account's card says so across its face. */}
        {suspended && (
          <div
            className="pointer-events-none absolute inset-x-0 top-[44%] flex -rotate-[8deg] items-center justify-center gap-2 py-1.5 text-[13px] font-extrabold uppercase tracking-[0.2em] text-white"
            data-testid="ziren-id-suspended"
            style={{ backgroundColor: `${STOP}E6` }}
          >
            <Ban aria-hidden size={15} /> Reporting suspended
          </div>
        )}
      </div>

      <div className="flex items-center gap-2 print:hidden">
        <Button onClick={print} size="sm" variant="outline">
          <Printer aria-hidden className="size-3.5" /> Print ID
        </Button>
        <span className="text-[11.5px] text-muted-foreground">Administrators only · not shown to responders</span>
      </div>
    </div>
  );
}
