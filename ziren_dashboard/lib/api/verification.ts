/**
 * Resident identity verification.
 *
 * Deliberately a separate module from the responder approval calls, mirroring
 * the split on the backend. The two decisions look similar and are not:
 * approving a responder grants access to every incident in a municipality,
 * while verifying a resident grants nothing at all — it raises a confidence
 * signal a dispatcher reads. Keeping them apart makes it harder to wire the
 * wrong one to a button.
 */

import { apiClient } from './client';

/**
 * Why a human should — or need not — look at this submission.
 *
 * The queue is oldest-first and otherwise undifferentiated, so a thousand
 * waiting residents are a thousand identical-looking jobs. These are the
 * signals that separate the ones worth opening.
 */
export interface ReviewFlags {
  /**
   * Other accounts using the same ID number, compared with punctuation and
   * case stripped so "1234-5678-9012" and "1234 5678 9012" count as one.
   *
   * This is the fraud case verification exists to catch, and nothing looked
   * for it before — the column was stored and never compared. A reviewer
   * holding two photographs cannot see it at all.
   */
  duplicate_id_count: number;
  /** Incidents this resident has actually filed. */
  report_count: number;
  sos_warning_count: number;
  /** No ID photo or no selfie — the comparison cannot be made at all. */
  missing_evidence: boolean;
  /**
   * The automatic ID/selfie comparison disagreed, or found no face on the card.
   *
   * A PRE-SCREEN, NOT A VERDICT, and the wording on screen has to keep saying
   * so. The model has never been validated on Philippine ID cards
   * re-photographed under a phone flash, and its expected failure is a FALSE
   * mismatch — a fifteen-year-old ID photograph, or one taken before an
   * illness, scores badly and is approved in four seconds by anyone who looks.
   * This moves a row up the queue. It does not decide anything.
   *
   * Absent on an older backend, and on every row registered before migration
   * 023 ran.
   */
  face_mismatch?: boolean;
  /**
   * The photographed card produced almost no readable text, has no face on it,
   * or prints an expiry already in the past.
   */
  id_unreadable?: boolean;
  /** True when any signal above (other than missing evidence) is present. */
  needs_review: boolean;
}

/** One row in the review queue. */
export interface VerificationSummary {
  id: string;
  email: string;
  full_name: string;
  phone_number: string | null;
  created_at: string;
  barangay: string | null;
  municipality_address: string | null;
  verification_level: number;
  valid_id_type: string | null;
  valid_id_number: string | null;
  valid_id_image_path: string | null;
  selfie_image_path: string | null;
  residency_proof_type: string | null;
  is_pwd: boolean;
  /** Absent from an older backend; callers must tolerate undefined. */
  review_flags?: ReviewFlags;

  /**
   * Cosine similarity between the ID portrait and the selfie, and the band it
   * falls in. Both null until the account has been through the flow added in
   * migration 023.
   *
   * `face_match_verdict` is one of: match, uncertain, no_match, no_face_on_id,
   * no_face_in_selfie, unavailable. "unavailable" means the deployment has not
   * installed the model — a supported state, and the one where an admin does
   * exactly what they did before this existed.
   */
  face_match_score?: number | null;
  face_match_verdict?: string | null;
  face_match_model?: string | null;
  face_match_checked_at?: string | null;

  /** On-device checks of the ID photo. Shape is open — see migration 023. */
  id_checks?: Record<string, unknown> | null;

  /** How valid_id_number got there: 'typed' | 'ocr' | 'ocr_edited'. */
  id_number_source?: string | null;
}

/** One submission, with signed URLs valid for ~5 minutes. */
export interface VerificationDetail extends VerificationSummary {
  first_name: string | null;
  middle_name: string | null;
  last_name: string | null;
  name_suffix: string | null;
  name_on_file: string | null;
  date_of_birth: string | null;
  sex: string | null;
  purok_sitio: string | null;
  street_address: string | null;
  pwd_id_number: string | null;
  liveness_method: string | null;
  liveness_asserted_at: string | null;
  verification_method: string | null;
  verified_at: string | null;
  /** Null when the object is missing or the signature could not be minted. */
  id_image_url: string | null;
  selfie_url: string | null;
  /** The latest identity decision and who made it (evaluator finding #7).
   *  Null when no decision has been recorded since migration 044. */
  last_review?: {
    decision: 'approved' | 'rejected';
    reviewed_by: string | null;
    reviewed_by_name: string | null;
    reviewed_at: string | null;
  } | null;
}

/**
 * What convinced the reviewer. Must match the verification_method CHECK in
 * migration 012 — the backend rejects anything else with a 422.
 */
export type VerificationMethod =
  | 'government_id'
  | 'barangay_official'
  | 'pwd_id'
  | 'phone_otp';

export interface VerificationDecisionResult {
  id: string;
  verification_level: number;
  verification_method: string | null;
  verified_at: string | null;
  images_purged: boolean;
  reviewed_by: string;
  reviewed_by_name?: string | null;
  reviewed_at?: string;
  decision?: 'approved' | 'rejected';
}

export interface BulkDecisionResult {
  decided: number;
  /** Rows that did not go through, with the server's reason for each. */
  failed: { id: string; reason: string }[];
}

/** Must match BULK_DECIDE_MAX in user_service.py — the server 422s above it. */
export const BULK_DECIDE_MAX = 200;

export const verificationApi = {
  list: (
    token: string,
    opts?: { municipality?: string; includeDecided?: boolean; priorityOnly?: boolean },
  ) => {
    const params = new URLSearchParams();
    if (opts?.municipality) params.set('municipality', opts.municipality);
    if (opts?.includeDecided) params.set('include_decided', 'true');
    if (opts?.priorityOnly) params.set('priority_only', 'true');
    const query = params.toString();
    return apiClient.get<VerificationSummary[]>(
      `/users/verification/residents${query ? `?${query}` : ''}`,
      token,
    );
  },

  detail: (token: string, userId: string) =>
    apiClient.get<VerificationDetail>(`/users/verification/residents/${userId}`, token),

  decide: (
    token: string,
    userId: string,
    body: { approve: boolean; method?: VerificationMethod; purge_images?: boolean },
  ) =>
    apiClient.patch<VerificationDecisionResult>(
      `/users/verification/residents/${userId}`,
      body,
      token,
    ),
  /**
   * One decision, applied to many.
   *
   * `method` is required when approving. It is what makes a batch honest: the
   * same sentence has to be true of every account in it, and this is where
   * that sentence gets written into the audit trail.
   */
  decideBulk: (
    token: string,
    body: {
      user_ids: string[];
      approve: boolean;
      method?: VerificationMethod;
      purge_images?: boolean;
    },
  ) =>
    apiClient.post<BulkDecisionResult>(
      '/users/verification/residents/bulk',
      body,
      token,
    ),
};

/** Human labels for the ID types in migration 012's CHECK constraint. */
export const ID_TYPE_LABELS: Record<string, string> = {
  barangay_id: 'Barangay ID / Clearance',
  voters_id: "Voter's ID",
  pwd_id: 'PWD ID',
  senior_citizen_id: 'Senior Citizen ID',
  philsys: 'PhilSys / National ID',
  umid: 'UMID',
  drivers_license: "Driver's License",
  passport: 'Passport',
  postal_id: 'Postal ID',
  philhealth: 'PhilHealth ID',
  sss: 'SSS ID',
  tin: 'TIN ID',
};

/**
 * Whether the chosen document establishes residency, not merely identity.
 *
 * An LGU issues its IDs only to its own residents, so a barangay ID settles
 * where someone lives. A passport settles who they are and nothing more. The
 * reviewer needs to see that difference, because it changes whether the
 * address on the account has actually been corroborated.
 */
export const RESIDENCY_PROVING_IDS = new Set([
  'barangay_id',
  'voters_id',
  'pwd_id',
  'senior_citizen_id',
]);
