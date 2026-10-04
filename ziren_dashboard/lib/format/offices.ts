/**
 * What a Provincial Admin's office is called (evaluator finding #35).
 *
 * Provincial accounts were labelled "MDRRMO", the municipal office's name,
 * though they represent the province: the provincial disaster office is the
 * PDRRMO. BFP and PNP keep their agency names with "Provincial".
 * Mirrors ziren_backend/app/core/agency_names.py.
 */
const PROVINCIAL_OFFICE: Record<string, string> = {
  BFP: 'BFP Provincial Office',
  PNP: 'PNP Provincial Office',
  MDRRMO: 'PDRRMO',
};

/** "PDRRMO", "BFP Provincial Office"… */
export function provincialOffice(agencyType: string | null | undefined): string {
  return PROVINCIAL_OFFICE[(agencyType ?? '').toUpperCase()] ?? 'Provincial Office';
}

/** The role chip: "PDRRMO Admin", "BFP Provincial Admin"… */
export function provincialAdminLabel(agencyType: string | null | undefined): string {
  const t = (agencyType ?? '').toUpperCase();
  if (t === 'MDRRMO') return 'PDRRMO Admin';
  return t ? `${t} Provincial Admin` : 'Provincial Admin';
}
