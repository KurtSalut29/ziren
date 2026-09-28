-- Migration 019: retire the hazmat and missing_person incident categories
--
-- Phase 4 integrates the trained triage model (app/ml, dataset release 2.1.3).
-- The model classifies six categories: FIRE, CRIME, ACCIDENT,
-- VEHICULAR_ACCIDENT, MEDICAL, NATURAL_HAZARD. It has no class for hazmat or
-- missing_person, so a report filed under either could never receive a
-- model-derived severity — it would sit in the queue with severity NULL
-- forever. Rather than leave two categories the pipeline cannot serve, they
-- are retired from the wizard.
--
-- Nothing is lost:
--   * Both remain valid OverlapFlag values, so a hazmat leak or a missing
--     person can still be flagged as a secondary concern on any report.
--   * Existing rows are rewritten to 'other' with the original category
--     preserved in wizard_answers.retired_category, so historical reports stay
--     readable and the change is reversible.
--
-- Additive and idempotent. Safe to re-run.

-- ---------------------------------------------------------------------------
-- 1. Preserve the original category on affected rows, then rewrite to 'other'.
--
-- Done BEFORE the constraint is replaced: the new CHECK would reject these
-- rows, and Postgres validates an added constraint against existing data.
-- ---------------------------------------------------------------------------
UPDATE incidents
SET
  wizard_answers = COALESCE(wizard_answers, '{}'::jsonb)
                   || jsonb_build_object('retired_category', incident_category),
  incident_category = 'other'
WHERE incident_category IN ('hazmat', 'missing_person');


-- ---------------------------------------------------------------------------
-- 2. Replace the category CHECK constraint with the six surviving values.
--
-- DROP ... IF EXISTS is deliberate, not defensive habit. Migration 006 has a
-- syntax error — its first DO block closes with `END` where PL/pgSQL requires
-- `END IF;` — so on any database where 006 was applied as a single script the
-- block aborted and incidents_category_check was never created. This migration
-- must succeed whether or not that constraint is actually present.
-- ---------------------------------------------------------------------------
ALTER TABLE incidents
  DROP CONSTRAINT IF EXISTS incidents_category_check;

ALTER TABLE incidents
  ADD CONSTRAINT incidents_category_check
    CHECK (
      incident_category IS NULL OR incident_category IN (
        'fire',
        'medical_trauma',
        'vehicular',
        'flood_landslide_calamity',
        'domestic_dispute_crime',
        'other'
      )
    );


-- ---------------------------------------------------------------------------
-- 3. Documentation
-- ---------------------------------------------------------------------------
COMMENT ON COLUMN incidents.incident_category IS
  'Structured incident type from Step 1 of the 5W1H wizard. Six values, each '
  'mapping onto a triage-model class (see triage_service.BACKEND_TO_MODEL); '
  'NULL for SOS and legacy rows. hazmat and missing_person were retired in '
  'migration 019 — they survive as overlap_agencies flags.';

COMMENT ON COLUMN incidents.severity IS
  'Advisory severity from the Ziren triage model, written inline at submission '
  'by triage_service. NULL means the model was unavailable or could not read '
  'the report — the dispatcher triages it by hand. The rule that produced this '
  'value is in signals.severity_rule.';

COMMENT ON COLUMN incidents.signals IS
  'Full triage-model output: predicted category and confidence, the runner-up, '
  'the extracted signals, which signals came from the wizard, the severity rule '
  'id and its plain-language reason, and the engine version that produced them. '
  'This is the audit trail for "why did this incident get this severity".';

COMMENT ON COLUMN incidents.nlp_review_needed IS
  'TRUE when a human must look at the triage result before it is acted on: '
  'either the model was unavailable, or its reading disagrees with the '
  'category the resident selected (verification_status = MISMATCH_FLAGGED). '
  'The resident is at the scene and the model is not, so a mismatch is raised '
  'for the dispatcher rather than resolved silently.';
