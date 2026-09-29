/**
 * Typed API calls for the dispatch endpoints.
 * All functions require an access token — never call without auth.
 */

import { apiClient, ApiError } from './client';

/**
 * Below this, the model's guess at the incident type is not worth trusting on
 * its own and the dispatcher is told to check.
 *
 * The value matches `predict.FLAG_THRESHOLD` in the model release, and the
 * duplication is deliberate rather than an oversight. That one decides
 * ROUTING — which agency is suggested, and whether SR011's fail-safe fires.
 * This one decides DISPLAY — whether a dispatcher reading the incident type
 * is warned about it. They agree today because both were set from the same
 * measurement (70% catch, 0% false alarms on results_checker.csv); they are
 * separate names because raising the bar for a warning a human reads is a
 * different decision from raising it for a rule that changes severity, and
 * one should be movable without the other.
 */
export const LOW_CONFIDENCE_THRESHOLD = 0.6;

/** Fetch the live incident queue (agency-scoped for Agency Admin, agency-type-scoped for Provincial Admin). */
export async function fetchQueue(token: string): Promise<QueueIncident[]> {
  return apiClient.get<QueueIncident[]>('/dispatch/queue', token);
}

/**
 * Incidents created in the last `days`, **including resolved and cancelled**.
 *
 * Use this for anything counting incidents over time. `fetchQueue` excludes
 * closed work by design, so a series derived from it undercounts every past
 * day — an incident opened Monday and resolved Tuesday is simply gone from
 * it, and the line always appears to climb toward today.
 */
export async function fetchActivity(
  token: string,
  days = 30,
): Promise<ActivityIncident[]> {
  return apiClient.get<ActivityIncident[]>(
    `/dispatch/activity?days=${days}`,
    token,
  );
}

/** The trimmed incident shape `/dispatch/activity` returns — chart fuel. */
export interface ActivityIncident {
  id: string;
  status: IncidentStatus;
  severity: SeverityLevel | null;
  /**
   * One of the wizard's six values, or null on rows filed before the field
   * existed.
   *
   * `other` is NOT a sixth kind of emergency — it means the resident skipped
   * the category step, and migration 019 rewrote the retired hazmat and
   * missing_person rows into it as well. Charts must hold it apart from the
   * five real categories rather than rank it among them.
   */
  incident_category: IncidentCategory | null;
  created_at: string;
  dispatched_at: string | null;
  resolved_at: string | null;
  agency_type: string | null;
  /** The station the report was routed to; null when routing found none. */
  station_id?: string | null;
  station_name?: string | null;
}

/** The wizard's Step 1 categories. Closed set — see IncidentCategory in the
 *  backend's models/incident.py. */
export type IncidentCategory =
  | 'fire'
  | 'medical_trauma'
  | 'vehicular'
  | 'flood_landslide_calamity'
  | 'domestic_dispute_crime'
  | 'other';

/** Fetch full incident detail for the dispatch view. */
export async function fetchIncidentDetail(
  incidentId: string,
  token: string,
): Promise<IncidentDetail> {
  return apiClient.get<IncidentDetail>(`/dispatch/queue/${incidentId}`, token);
}

/**
 * An attachment on an incident, with a link that is safe to put in a <src>.
 *
 * `url` is signed and expires in five minutes, so it is fetched when the
 * dispatcher opens the incident and is never cached or stored. A null url
 * means the object could not be signed — the row still renders, marked
 * unavailable, rather than the whole panel failing.
 */
export interface IncidentMedia {
  path: string;
  url: string | null;
  kind: 'audio' | 'video' | 'image';
}

/**
 * Attachments for one incident — chiefly the resident's voice note.
 *
 * The recording matters more than the other attachments: it is the only part
 * of the report that survives the transcript being wrong. Waray and Bisaya
 * transcription is the weakest link in the pipeline, and a dispatcher who
 * speaks the language can settle in ten seconds what the model guessed at.
 */
export async function fetchIncidentMedia(
  incidentId: string,
  token: string,
): Promise<IncidentMedia[]> {
  return apiClient.get<IncidentMedia[]>(
    `/dispatch/queue/${incidentId}/media`,
    token,
  );
}

/**
 * The resident's own post-resolution rating (Resident spec Section 26), if
 * they gave one. null means "not yet rated" — most incidents never get
 * one, since rating is optional, and that is not an error state.
 */
export interface IncidentFeedback {
  id: string;
  incident_id: string;
  rating: number;
  comment: string | null;
  created_at: string;
}

export async function fetchIncidentFeedback(
  incidentId: string,
  token: string,
): Promise<IncidentFeedback | null> {
  return apiClient.get<IncidentFeedback | null>(
    `/dispatch/queue/${incidentId}/feedback`,
    token,
  );
}

/**
 * Fix what the recogniser misheard in a resident's recording.
 *
 * The resident is asked first, on the screen that opens right after they
 * report. But a bad transcript usually comes from someone who was panicking,
 * and they are the least likely to stand in front of an emergency proofreading
 * it. The dispatcher is playing the audio anyway, speaks the language, and has
 * a minute — so the correction cannot depend on the resident alone.
 *
 * Re-scores the incident only while no severity has been set by hand.
 */
export async function correctTranscript(
  incidentId: string,
  correctedText: string,
  token: string,
): Promise<unknown> {
  return apiClient.post(
    `/dispatch/queue/${incidentId}/transcript`,
    { corrected_text: correctedText },
    token,
  );
}

/** Assign a responder + confirm severity → dispatches incident. */
export async function assignResponder(
  incidentId: string,
  body: AssignRequest,
  token: string,
): Promise<AssignResponse> {
  return apiClient.post<AssignResponse>(
    `/dispatch/queue/${incidentId}/assign`,
    body,
    token,
  );
}

/** Override severity without reassigning. */
export async function overrideSeverity(
  incidentId: string,
  body: OverrideRequest,
  token: string,
): Promise<{ incident_id: string; chosen_severity: string; was_override: boolean }> {
  return apiClient.post(
    `/dispatch/queue/${incidentId}/override`,
    body,
    token,
  );
}

/** Resolve an incident. */
export async function resolveIncident(
  incidentId: string,
  notes: string | null,
  token: string,
): Promise<{ incident_id: string; status: string; resolved_at: string }> {
  return apiClient.post(
    `/dispatch/queue/${incidentId}/resolve`,
    { notes },
    token,
  );
}

/** Cancel an incident (requires reason). */
export async function cancelIncident(
  incidentId: string,
  reason: string,
  token: string,
): Promise<{ incident_id: string; status: string }> {
  return apiClient.post(
    `/dispatch/queue/${incidentId}/cancel`,
    { reason },
    token,
  );
}

/**
 * Verification step (Agency Admin spec Section 3): confirm this report is
 * real. Idempotent — pressing it twice on an already-accepted report returns
 * the existing decision rather than erroring.
 */
export async function acceptReport(
  incidentId: string,
  token: string,
): Promise<{ incident_id: string; review_status: ReviewStatus; already_reviewed: boolean }> {
  return apiClient.post(`/dispatch/queue/${incidentId}/accept`, {}, token);
}

/**
 * Verification step: the report is not real (or not this agency's).
 * Requires a reason. Also cancels the incident.
 */
export async function rejectReport(
  incidentId: string,
  reason: string,
  token: string,
): Promise<{ incident_id: string; review_status: ReviewStatus; status: string }> {
  return apiClient.post(`/dispatch/queue/${incidentId}/reject`, { reason }, token);
}

/**
 * Verification step: ask the reporter for more detail before deciding.
 * Leaves the incident in the live queue.
 */
export async function requestClarification(
  incidentId: string,
  note: string,
  token: string,
): Promise<{ incident_id: string; review_status: ReviewStatus }> {
  return apiClient.post(`/dispatch/queue/${incidentId}/request-clarification`, { note }, token);
}

/** Flag SOS report as false alarm. */
export async function flagFalseSos(
  incidentId: string,
  token: string,
): Promise<{ reporter_id: string; warning_count: number; suspended_until: string | null }> {
  return apiClient.post(
    `/dispatch/queue/${incidentId}/flag-false-sos`,
    {},
    token,
  );
}

/**
 * Operational notes / Agency Communication thread for one incident (Agency
 * Admin spec Sections 5 and 18). Author is denormalized onto each row —
 * `users` carries the current name for display, `author_role` is stamped at
 * write time and never recomputed, so the thread keeps showing who spoke as
 * what they were at the time even if their role later changes.
 */
export interface IncidentNote {
  id: string;
  incident_id: string;
  author_id: string;
  author_role: 'agency_admin' | 'responder' | 'provincial_admin' | 'resident';
  body: string;
  created_at: string;
  users?: { full_name: string } | null;
}

/** List an incident's notes thread. Provincial Admin sees their agency_type's (oversight, read-only). */
export async function fetchIncidentNotes(
  incidentId: string,
  token: string,
): Promise<IncidentNote[]> {
  return apiClient.get<IncidentNote[]>(`/dispatch/queue/${incidentId}/notes`, token);
}

/** Add a note. Agency Admin only — Provincial Admin has oversight, not a seat in the thread. */
export async function addIncidentNote(
  incidentId: string,
  bodyText: string,
  token: string,
): Promise<IncidentNote> {
  return apiClient.post<IncidentNote>(`/dispatch/queue/${incidentId}/notes`, { body: bodyText }, token);
}

/**
 * The post-resolution Narrative Report (Agency Admin, once an incident is
 * resolved) - the full Incident Record Form: Item A the reporting person, B the
 * suspects, C the victims, D the narrative, then the certification and station.
 *
 * The narrative and the byline fields are columns; everything else is `details`
 * (migration 040), whose shape the server enforces. `reporting_person_name`,
 * `incident_occurred_at` and `place_of_incident` are overrides: null means "use
 * the incident's own data".
 */
export interface NarrativePerson {
  family_name: string; first_name: string; middle_name: string; qualifier: string; nickname: string;
  citizenship: string; gender: string; civil_status: string; date_of_birth: string; age: string;
  place_of_birth: string; phone: string;
  address_street: string; barangay: string; town_city: string; province: string;
  education: string; occupation: string; relation: string;
}

export interface NarrativeSuspect extends NarrativePerson {
  rank: string; unit_assignment: string; group_affiliation: string;
  previous_record: string; previous_case_status: string;
  height: string; weight: string; eye_color: string; hair_color: string;
  distinguishing_marks: string; under_influence: string;
  guardian_name: string; guardian_address: string;
}

export interface NarrativeDetails {
  form_version?: number;
  copy_for: string;
  offense: string;
  offense_detail: string;
  place_barangay: string;
  place_town: string;
  place_province: string;
  witnesses: string;
  property_damage: string;
  actions_taken: string;
  reporting_person: NarrativePerson;
  suspects: NarrativeSuspect[];
  victims: NarrativePerson[];
  certification: {
    administering_officer: string;
    investigator_rank_name: string;
    desk_officer_rank_name: string;
  };
  station: { name: string; telephone: string; mobile: string; chief: string };
}

export interface NarrativeReport {
  id: string;
  incident_id: string;
  narrative: string;
  reporting_person_name: string | null;
  incident_occurred_at: string | null;
  place_of_incident: string | null;
  prepared_by_name: string | null;
  investigator_name: string | null;
  reference_no: string | null;
  /** Absent on a report saved before migration 040. */
  details?: Partial<NarrativeDetails> | null;
  status: 'draft' | 'finalized';
  finalized_at: string | null;
  created_at: string;
  updated_at: string;
  created?: { full_name: string } | null;
  updated?: { full_name: string } | null;
  finalized?: { full_name: string } | null;
}

export interface NarrativeReportInput {
  /** May be empty on a draft; finalizing needs it. */
  narrative: string;
  reporting_person_name?: string | null;
  incident_occurred_at?: string | null;
  place_of_incident?: string | null;
  prepared_by_name?: string | null;
  investigator_name?: string | null;
  reference_no?: string | null;
  details?: NarrativeDetails;
  finalize?: boolean;
}

/** What GET returns: the report (null until one is started) and whether this database can hold `details`. */
export interface NarrativeState {
  report: NarrativeReport | null;
  details_supported: boolean;
}

/** What a save returns: the row, and whether the detailed sections were actually stored. */
export type SavedNarrativeReport = NarrativeReport & {
  details_saved: boolean;
  details_supported: boolean;
};

export async function fetchNarrativeReport(
  incidentId: string,
  token: string,
): Promise<NarrativeState> {
  return apiClient.get<NarrativeState>(
    `/dispatch/queue/${incidentId}/narrative-report`, token,
  );
}

/** Create or update the Narrative Report. 409s if the incident isn't resolved yet. */
export async function saveNarrativeReport(
  incidentId: string,
  body: NarrativeReportInput,
  token: string,
): Promise<SavedNarrativeReport> {
  return apiClient.put<SavedNarrativeReport>(
    `/dispatch/queue/${incidentId}/narrative-report`, body, token,
  );
}

/** One line of the Narrative Reports library: the report's facts beside its incident's. */
export interface NarrativeListItem {
  id: string;
  incident_id: string;
  status: 'draft' | 'finalized';
  reference_no: string | null;
  prepared_by_name: string | null;
  investigator_name: string | null;
  reporting_person_name: string | null;
  place_of_incident: string | null;
  /** The specific incident/offense the report was filed under, when it says. */
  offense: string | null;
  finalized_at: string | null;
  created_at: string;
  updated_at: string;
  record_number: string | null;
  incident_category: string;
  severity: string | null;
  incident_created_at: string | null;
  resolved_at: string | null;
  station_name: string | null;
  agency_type: string | null;
  agency_name: string | null;
  municipality: string | null;
}

export interface NarrativeLibrary {
  items: NarrativeListItem[];
  total: number;
  counts: {
    /** Tab counts, within the chosen status. */
    by_category: Record<string, number>;
    /** Status chip counts, within the chosen category. */
    by_status: { draft: number; finalized: number };
    all: number;
  };
}

export interface NarrativeLibraryQuery {
  category?: string;
  status?: 'draft' | 'finalized';
  days?: number;
  date_from?: string;
  date_to?: string;
  limit?: number;
  offset?: number;
}

/** Every narrative report this admin may see, newest first. Filtering happens on the server. */
export async function fetchNarrativeReports(
  token: string,
  q: NarrativeLibraryQuery = {},
): Promise<NarrativeLibrary> {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(q)) {
    if (v !== undefined && v !== null && v !== '') params.set(k, String(v));
  }
  const qs = params.toString();
  return apiClient.get<NarrativeLibrary>(`/dispatch/narrative-reports${qs ? `?${qs}` : ''}`, token);
}

/**
 * Downloads the printable PDF as a fetch + blob — same pattern as
 * lib/api/reports.ts's downloadReport, for the same reason: a plain
 * `<a href>` can't carry the Authorization header the API requires.
 */
export async function downloadNarrativeReportPdf(
  incidentId: string,
  token: string,
): Promise<void> {
  const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8000';
  const response = await fetch(`${API_BASE_URL}/dispatch/queue/${incidentId}/narrative-report/pdf`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) {
    const body = await response.json().catch(() => ({ detail: `HTTP ${response.status}` }));
    throw new ApiError(body.detail ?? `HTTP ${response.status}`, response.status);
  }
  const blob = await response.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `narrative-report-${incidentId.slice(0, 8)}.pdf`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/**
 * Who is near this incident, best fit first - the dispatcher's panel.
 *
 * Every on-duty responder of the incident's agency, measured from their last FRESH
 * position (ellipsoidal distance; a position older than ten minutes counts as
 * unknown), with what each is already committed to, who was told and who has
 * answered. Read-only: it assigns nothing. Polled while the panel is open.
 */
export async function fetchNearbyResponders(
  incidentId: string,
  token: string,
): Promise<NearbyPanel> {
  return apiClient.get<NearbyPanel>(
    `/dispatch/queue/${encodeURIComponent(incidentId)}/nearby-responders`,
    token,
  );
}

/** Fetch available on_duty responders for an agency. */
export async function fetchResponders(
  agencyId: string,
  token: string,
): Promise<Responder[]> {
  return apiClient.get<Responder[]>(
    `/dispatch/responders?agency_id=${encodeURIComponent(agencyId)}`,
    token,
  );
}

// ── Types ────────────────────────────────────────────────────

export type SeverityLevel = 'critical' | 'high' | 'medium' | 'low';
export type IncidentStatus = 'received' | 'processing' | 'dispatched' | 'en_route' | 'arrived' | 'resolved' | 'cancelled';

/**
 * Agency Admin spec Section 3 (Verification) — recorded ALONGSIDE `status`,
 * not inside it. See migration 029's header for why `status`'s existing
 * values keep their meaning: `review_status` is the only field that answers
 * "has an agency_admin looked at this report yet".
 */
export type ReviewStatus = 'pending' | 'accepted' | 'rejected' | 'clarification_requested';

/**
 * The `incidents.signals` JSONB column, written by the Phase 4 triage model.
 * Mirrors `TriageSignals` in ziren_backend/app/models/incident.py.
 *
 * This is the audit trail behind `severity` — `severity_rule` and
 * `severity_reason` answer "why did this incident get this severity", and
 * `verification_status` says whether the model agreed with the category the
 * resident picked.
 *
 * Every field is optional on purpose: incidents filed before Phase 4 have
 * `signals: null`, and a later dataset release may add keys. A dispatcher must
 * never lose an incident because its signals blob is an unexpected shape.
 *
 * Returned by both `/dispatch/queue` and `/dispatch/queue/{id}`. The queue
 * list carries it so the dispatcher can see *why* a report is ranked where it
 * is without opening it.
 */
export interface TriageSignals {
  engine?: string | null;                    // "ziren-model"
  engine_version?: string | null;            // dataset release, e.g. "2.1.3"

  model_predicted?: string | null;           // model taxonomy, e.g. "FIRE"
  model_predicted_category?: string | null;  // app taxonomy, e.g. "fire"
  model_confidence?: number | null;
  runner_up?: { category: string; confidence: number } | null;

  user_selected?: string | null;
  verification_status?:
    | 'AGREE'
    | 'MISMATCH_FLAGGED'
    | 'UNCERTAIN'
    | 'NO_SELECTION'
    | 'NO_TEXT'
    | string
    | null;
  verification_message?: string | null;

  severity_level?: 'CRITICAL' | 'HIGH' | 'MODERATE' | 'LOW' | string | null;
  severity_rule?: string | null;             // e.g. "SR002"
  severity_reason?: string | null;           // e.g. "someone is trapped"

  signals?: Record<string, unknown>;
  signals_unknown?: string[];
  signals_from_wizard?: string[];

  /**
   * Present when the words in `report_text` were recovered from the
   * resident's recording rather than typed by them.
   *
   * A dispatcher reading a report is entitled to know a machine heard it, and
   * which machine — Waray and Bisaya are where transcription is weakest, and
   * the recording next to it is the one that is authoritative.
   */
  transcript?: {
    text: string;
    engine: string;
    engine_version: string;
    language?: string | null;
    confidence?: number | null;
    audio_path: string;
    note?: string;
  } | null;

  routing_agencies?: string[];
  routing_based_on?: 'user_selected' | 'model_predicted' | string | null;

  /**
   * How much the agency suggestion is worth (engine 2.1.5).
   *
   * `model_uncertain` means the resident chose no category AND the model was
   * under the flag threshold — the agency rests on a guess. The agencies are
   * still returned so the report reaches someone, but a human must pick.
   * Severity is unaffected; SR010/SR011 already cover that case.
   */
  agency_basis?: 'user_selected' | 'model_confident' | 'model_uncertain' | string | null;
  needs_manual_agency?: boolean;
  agency_note?: string | null;

  /**
   * The recogniser welded a number onto the word after it, so any count
   * in this report is suspect.
   *
   * Measured case: "tulo ka tawo an nasamdan" (three people injured) came
   * back as "tulukataw anasamdan". The injury survived; the count did not,
   * and nothing said so. Deliberately not un-glued — a wrong count is worse
   * than a missing one, because a dispatcher sends for the number they
   * read.
   */
  count_uncertain?: boolean;
  count_note?: string | null;

  /**
   * The report after Waray/Bisaya spelling correction, and the substitutions
   * that produced it. Present only when something actually changed.
   *
   * Each change reads "<heard> -> <written> (<source>)", where source is
   * `alias` (a correction someone confirmed against a recording), `sound`
   * (the phonetic pass) or a match score (the fuzzy pass, currently off).
   */
  normalisation?: { text: string; changes: string[] } | null;
  disclaimer?: string | null;
}

export interface QueueIncident {
  id: string;
  report_text: string;
  status: IncidentStatus;
  severity: SeverityLevel | null;
  suggested_severity?: SeverityLevel | null;
  /** Triage audit trail — the rule behind `severity`. Null on incidents filed
   *  before Phase 4 and on reports where the model was unavailable (those also
   *  have severity null). */
  signals: TriageSignals | null;
  location_address: string | null;
  incident_category: string | null;
  sos_flagged: boolean;
  nlp_review_needed: boolean;
  overlap_agencies: string[] | null;
  /** Photo/video/audio attachment count. A count, not the files themselves —
   *  the queue is a lighter-trust surface than the detail view, so playable
   *  links stay behind /queue/{id}/media until a dispatcher opens the report. */
  media_count?: number;
  created_at: string;
  dispatched_at: string | null;
  assigned_responder_id: string | null;

  /** Migration 024 / Phase 6D. Whether the assigned crew has answered.
   *  Computed server-side in responder_ack.py so this board and the
   *  responder's own phone can never disagree about the clock — see the
   *  note on AckState. */
  ack?: AckState;
  accepted_at?: string | null;
  declined_at?: string | null;
  declined_reason?: DeclineReason | null;
  decline_count?: number;

  /** Set when this incident is a mutual-aid request raised by a responder
   *  already on another incident. */
  backup_of_incident_id?: string | null;
  backup_reason?: string | null;

  /** Verification step (Agency Admin spec Section 3). Defaults to 'pending'
   *  on every row — see ReviewStatus. Optional here only because the
   *  responder-facing endpoints that also return a QueueIncident-shaped row
   *  don't select it; the dispatcher-facing queue/detail always does. */
  review_status?: ReviewStatus;
  rejection_reason?: string | null;
  clarification_note?: string | null;
  clarification_requested_at?: string | null;

  stations: {
    name: string;
    agencies: {
      agency_type: string;
      municipality: string;
      name: string;
    } | null;
  } | null;
  users: {
    full_name: string;
    is_verified: boolean;
    sos_warning_count: number;
    created_at: string;
  } | null;
}

/**
 * Has the assigned crew answered?
 *
 * `status: 'dispatched'` has only ever meant "a dispatcher pressed a
 * button". Whether anybody SAW the assignment was unrepresented, so an
 * alert sitting on a handset in a locker looked identical on this board to
 * one a truck was already rolling on — and the difference surfaced when
 * nobody arrived.
 *
 * COMPUTED SERVER-SIDE, DELIBERATELY. Everything needed to derive it is on
 * the row, and this board could work it out. It must not: the responder's
 * phone is deriving the same verdict from the same columns at the same
 * moment, and the failure mode of two implementations is a board showing
 * OVERDUE in red next to a phone still counting down. Whichever is wrong,
 * the dispatcher and the crew are now arguing about the clock instead of
 * the fire.
 */
export interface AckState {
  /** `pending` — assigned, inside the answer window.
   *  `overdue`  — assigned, window elapsed, still unanswered.
   *  `accepted` — a crew has confirmed they are coming.
   *  `declined` — refused and handed back; see `declined_reason`.
   *  `not_applicable` — never dispatched, or already closed. NOT the same
   *  as accepted: a resolved incident nobody ever accepted really did
   *  happen that way, and flattening it would erase the evidence. */
  state: 'pending' | 'overdue' | 'accepted' | 'declined' | 'not_applicable';
  /** The window that applied to this severity, so the UI can draw a
   *  proportion without hardcoding the policy table a third time. */
  deadline_seconds: number;
  seconds_waiting: number | null;
  seconds_remaining: number | null;
  declined_reason?: DeclineReason | null;
  /** Never reset by reassignment. Three refusals on one incident is a
   *  coverage problem, not a responder problem, and it stays visible. */
  decline_count: number;
}

/** The six the database CHECK constraint allows. */
export type DeclineReason =
  | 'vehicle_down'
  | 'already_committed'
  | 'out_of_area'
  | 'insufficient_crew'
  | 'road_impassable'
  | 'other';

/** What the crew found. The column that finally makes the severity rubric
 *  checkable against reality — an incident scored `critical` that closes
 *  `false_alarm` is a measurable miss. */
export type IncidentOutcome =
  | 'handled_on_scene'
  | 'transported'
  | 'turned_over'
  | 'false_alarm'
  | 'nobody_found'
  | 'refused_assistance'
  | 'unable_to_access'
  | 'other';

export const DECLINE_REASON_LABEL: Record<DeclineReason, string> = {
  vehicle_down: 'Vehicle down',
  already_committed: 'On another call',
  out_of_area: 'Out of area',
  insufficient_crew: 'Insufficient crew',
  road_impassable: 'Road impassable',
  other: 'Other reason',
};

export const OUTCOME_LABEL: Record<IncidentOutcome, string> = {
  handled_on_scene: 'Handled on scene',
  transported: 'Transported',
  turned_over: 'Turned over',
  false_alarm: 'False alarm',
  nobody_found: 'Nobody found',
  refused_assistance: 'Refused assistance',
  unable_to_access: 'Unable to access',
  other: 'Other',
};

/** A responder's own emergency. */
export interface DistressSignal {
  id: string;
  responder_id: string;
  incident_id: string | null;
  agency_id: string | null;
  /** `panic` is the responder pressing and holding the button themselves.
   *  `no_movement` is inferred by the backend and is weaker evidence — it
   *  is shown as a question, not an alarm, because the ordinary
   *  explanation is a phone in a cupholder. */
  kind: 'panic' | 'no_movement';
  latitude: number | null;
  longitude: number | null;
  note: string | null;
  raised_at: string;
  responder_name: string | null;
  responder_badge: string | null;
  responder_phone: string | null;
}

/** Unresolved responder distress signals, agency-scoped by the backend. */
export async function fetchOpenDistress(
  token: string,
): Promise<DistressSignal[]> {
  return apiClient.get<DistressSignal[]>('/dispatch/distress', token);
}

/**
 * Close a distress signal, once somebody has actually answered it.
 *
 * Only a dispatcher or agency admin can, never the responder and never a
 * timeout: a distress signal that ages out on its own is one nobody
 * answered, and the responder is the person least able to close it.
 */
export async function clearDistress(
  token: string,
  distressId: string,
  note?: string,
): Promise<{ id: string; cleared_at: string }> {
  return apiClient.post(`/dispatch/distress/${distressId}/clear`, { note }, token);
}

/**
 * What a responder is doing, from what is already assigned to them:
 * `free`, `committed` (dispatched, not yet moving), `en_route`, `on_scene`.
 */
export type ResponderState = 'free' | 'committed' | 'en_route' | 'on_scene';

/** `alarm` = told at full volume, `advisory` = told quietly, `none` = not told. */
export type NearbyLevel = 'alarm' | 'advisory' | 'none';

/** Why the level is what it is. */
export type NearbyReason =
  | 'nearest' | 'escalation' | 'no_free_unit' | 'nobody_in_range' | 'location_unknown'
  | 'incident_not_located' | 'busy' | 'beyond_cap' | 'out_of_range' | 'not_located';

export type NearbyAnswer = 'can_respond' | 'unavailable';

/** A call the responder already holds. */
export interface NearbyCall {
  incident_id: string | null;
  status: string | null;
  severity: SeverityLevel | null;
  category: string | null;
  address: string | null;
}

/** One responder measured against one incident. */
export interface NearbyResponder {
  responder_id: string;
  full_name: string | null;
  badge_id: string | null;
  state: ResponderState;
  /** Metres and kilometres from their last fresh position; null when it is unknown. */
  distance_m: number | null;
  distance_km: number | null;
  /** Whole minutes at the assumed road speed, rounded up. */
  eta_min: number | null;
  /** Compass point from the responder TO the incident. */
  direction: string | null;
  fix_age_s: number | null;
  /** A fresh, valid position was used. */
  located: boolean;
  latitude: number | null;
  longitude: number | null;
  level: NearbyLevel;
  reason: NearbyReason;
  /** 1-based among those who will be told; null for those who will not. */
  rank: number | null;
  current_calls: NearbyCall[];
  notified_at: string | null;
  answer: NearbyAnswer | null;
  answered_at: string | null;
}

export interface NearbyPanel {
  incident_id: string;
  summary: {
    on_duty: number; free: number; busy: number; in_range: number;
    notified: number; alarm: number; advisory: number; off_duty: number;
  };
  policy: { radius_km: number; fix_max_age_s: number };
  responders: NearbyResponder[];
}

export interface Responder {
  id: string;
  full_name: string;
  badge_id: string | null;
  availability: 'on_duty' | 'off_duty';
  phone_number: string | null;
  // Added to the detail's roster (all optional: they are absent for the
  // dispatcher's own "yourself" entry and from a backend that predates them).
  state?: ResponderState;
  distance_km?: number | null;
  eta_min?: number | null;
  direction?: string | null;
  located?: boolean;
  level?: NearbyLevel;
  reason?: NearbyReason;
  current_calls?: NearbyCall[];
  notified_at?: string | null;
  answer?: NearbyAnswer | null;
  answered_at?: string | null;
  /** 1-based position among those the proximity engine would tell first —
   *  same figure NearbyResponders ranks by. Null/absent means "not in that
   *  ranking" (off-radius, or the nearby fetch hasn't landed/failed), not
   *  "last place" — sort accordingly. */
  rank?: number | null;
}

export interface DispatchLogEntry {
  id: string;
  incident_id: string;
  dispatcher_id: string;
  agency_id: string;
  suggested_severity: SeverityLevel | null;
  chosen_severity: SeverityLevel;
  was_override: boolean;
  override_reason: string | null;
  action: string;
  notes: string | null;
  created_at: string;
  users?: { full_name: string; role: string } | null;
}

export interface IncidentDetail extends QueueIncident, Partial<AfterAction> {
  /**
   * `ZIR-2026-000123`, migration 035. Arrives with no backend change because
   * the detail select is `*`. Optional so a backend that predates the
   * migration falls back to the short id in the panel header.
   */
  record_number?: string;
  /** When the incident closed. Null while it is open. The after-action fields
   *  (`outcome`, casualties, notes) come from `Partial<AfterAction>` above:
   *  they were always in the response, `*` sends them, and were never typed. */
  resolved_at?: string | null;
  /** The assigned crew member, joined by name for the record panel. Null when
   *  nobody was assigned or the account was later deleted. */
  responder?: { full_name: string | null; badge_id: string | null } | null;
  /** PostGIS point, as GeoJSON: `{ type: 'Point', coordinates: [lon, lat] }`.
   *
   *  Detail only — the queue's select does not ask for it, so declaring it on
   *  QueueIncident would promise a field that arrives undefined.
   *
   *  These figures are exact. `location_address` is a name *derived* from
   *  them, and naming is the part that fails: OpenStreetMap covers Biliran
   *  thinly enough that a barangay can be missing altogether. Show both, and
   *  when they disagree, believe these. */
  location: { type?: string; coordinates?: [number, number] } | null;
  wizard_answers: Record<string, unknown> | null;
  landmark_note: string | null;
  victim_relationship: string | null;
  /** Migration 042. The resident placed the incident on the map because they
   *  are not at it — `location` is the incident, these are where THEY were.
   *  Absent (undefined) until the migration is applied. */
  reported_from_elsewhere?: boolean | null;
  reporter_location?: { type?: string; coordinates?: [number, number] } | null;
  reporter_address?: string | null;
  stations: {
    name: string;
    address: string | null;
    /** GeoJSON Point, same shape as the incident's above, or null for a
     *  station nobody has placed yet. Typed rather than `unknown` because the
     *  detail panel measures the response distance from it — see
     *  `geoPoint` in lib/incidents/response-route. */
    location: { type?: string; coordinates?: number[] } | null;
    agencies: {
      agency_type: string;
      municipality: string;
      name: string;
      contact_number: string | null;
    } | null;
  } | null;
  users: {
    id: string;
    full_name: string;
    phone_number: string | null;
    is_verified: boolean;
    sos_warning_count: number;
    sos_suspended_until: string | null;
    created_at: string;
    emergency_contact_name: string | null;
    emergency_contact_number: string | null;
  } | null;
  dispatch_log: DispatchLogEntry[];
  available_responders: Responder[];
  /** How far the report is from the station it was routed to (ellipsoidal km). */
  station_distance_km?: number | null;
  /** Who is near it right now; null when it could not be computed. */
  nearby?: NearbyPanel | null;
}

export interface AssignRequest {
  responder_id: string;
  chosen_severity: SeverityLevel;
  suggested_severity?: SeverityLevel | null;
  override_reason?: string | null;
  notes?: string | null;
}

export interface AssignResponse {
  incident_id: string;
  responder_id: string;
  chosen_severity: SeverityLevel;
  was_override: boolean;
  status: string;
  dispatched_at: string;
}

export interface OverrideRequest {
  chosen_severity: SeverityLevel;
  suggested_severity?: SeverityLevel | null;
  override_reason: string;
  notes?: string | null;
}

/* ── Incident history ─────────────────────────────────────────────────────── */

/**
 * A history row. The queue's shape plus the two fields a queue can never
 * have — `resolved_at`, and a `status` that may be resolved or cancelled.
 */
export interface AfterAction {
  outcome: IncidentOutcome | null;
  outcome_notes: string | null;
  /** NULL and 0 mean different things and both are kept. NULL is "not
   *  recorded"; 0 is "the crew counted, and nobody was hurt". */
  casualties_injured: number | null;
  casualties_fatal: number | null;
  casualties_transported: number | null;
  /** Photos the RESPONDER took on scene — deliberately separate from
   *  media_urls, which is the reporter's. Mixing them would destroy the
   *  only way to tell what was known before the crew arrived from what
   *  they documented after. */
  scene_media_urls: string[];
}

export interface HistoryIncident extends QueueIncident {
  /**
   * The citable record number, `ZIR-2026-000123` (migration 035). Assigned once
   * by a database trigger at insert and never changed. Optional in the type
   * only so a dashboard running against a backend that predates the migration
   * degrades to the short id instead of crashing on `undefined`.
   */
  record_number?: string;
  /** The assigned crew member's name — the queue shape carries only the id.
   *  Null when nobody is assigned, or the account has since been deleted
   *  (the FK is ON DELETE SET NULL). */
  responder?: { full_name: string | null } | null;
  /** The exact station this incident belongs to — `stations.id`. Selected
   *  only by /dispatch/history, to drive the Station filter/column; the
   *  queue never needed it since `stations.name` already reads fine there. */
  station_id?: string | null;
  /** Phase 6D. What the crew actually found, recorded at close.
   *  Optional because every incident closed before migration 024 has
   *  none — and that absence is itself the finding: until this column
   *  existed, no severity the rubric produced could be checked against
   *  reality. */
  outcome?: IncidentOutcome | null;
  outcome_notes?: string | null;
  casualties_injured?: number | null;
  casualties_fatal?: number | null;
  casualties_transported?: number | null;
  resolved_at: string | null;
  /**
   * Whether this incident already has a Narrative Report, and what state
   * it's in — null means nobody has started one. Only resolved incidents
   * can have one (migration 038), but the field is sent for every row so
   * the table can tell "not applicable" (open incident) from "applicable,
   * not started yet" (resolved, null) without a second lookup.
   */
  narrative_report_status?: 'draft' | 'finalized' | null;
}

/**
 * Counts over the WHOLE filtered window, not the page.
 *
 * The history tiles used to be derived from `items`, which is one page of at
 * most a hundred rows, so on a busy window they described an arbitrary slice
 * under a heading that said "Last 30 days".
 *
 * Five disjoint facts, not the four this replaced ({critical, high,
 * untriaged, closed}), which mixed SEVERITY and STATUS into one strip —
 * `closed` silently double-counted rows `critical`/`high` had already
 * counted. `total` is every incident in the window; `critical` is a severity;
 * `resolved`/`cancelled` are the two ways a status closes; none overlap.
 *
 * `critical` counts the DECIDED severity — the stored column, not the
 * rubric's `suggested_severity`, which is computed per row at read time and
 * cannot be counted in SQL.
 *
 * `avg_response_minutes` is created_at -> dispatched_at (time to dispatch,
 * the same figure `dispatchLatency` shows per row in incident-row.tsx), over
 * incidents in the window that were actually dispatched. Null when none were.
 */
export interface HistoryCounts {
  total: number;
  critical: number;
  resolved: number;
  cancelled: number;
  avg_response_minutes: number | null;
  /** Distinct stations represented in the window. Only shown to Provincial
   *  Admin — an Agency Admin's is always 0 or 1, since they have one
   *  station, so the card would state the obvious. */
  stations_with_incidents: number;
}

export interface HistoryPage {
  items: HistoryIncident[];
  /** Rows matching the filters BEFORE paging — "showing 100 of 2,431". */
  total: number;
  counts: HistoryCounts;
}

export interface HistoryQuery {
  days?: number;
  limit?: number;
  offset?: number;
  status?: string;
  severity?: string;
  /** BFP, PNP or MDRRMO — see AG_COLOR in incident-vocabulary.ts. */
  agency_type?: string;
  /** stations.id — Provincial Admin's Station filter. */
  station_id?: string;
  /** One of IncidentCategory. */
  category?: string;
  /**
   * YYYY-MM-DD, inclusive. Overrides `days` on the server whenever either
   * bound is set — a day, a month's first/last date, or a year's.
   */
  date_from?: string;
  date_to?: string;
  /**
   * A record number or its prefix, e.g. `ZIR-2026-0001`. Letters, digits and
   * hyphens only — the server rejects anything else with a 422. Takes over
   * from `days`, the way a date range does, so an old record is findable.
   */
  record_no?: string;
}

/**
 * One page of incident history.
 *
 * NOT /dispatch/queue. That endpoint excludes resolved and cancelled by
 * design, so a history view built on it can only ever show what is still open
 * — which is what the Incident History page did before this existed.
 *
 * Filters go to the server rather than being applied to a fetched page: a
 * narrow filter applied client-side returns a page that is mostly empty and
 * reads as "no results" when it means "not on this page".
 */
export async function fetchHistory(
  token: string,
  q: HistoryQuery = {},
): Promise<HistoryPage> {
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(q)) {
    if (v !== undefined && v !== null && v !== '') params.set(k, String(v));
  }
  const qs = params.toString();
  return apiClient.get<HistoryPage>(`/dispatch/history${qs ? `?${qs}` : ''}`, token);
}
