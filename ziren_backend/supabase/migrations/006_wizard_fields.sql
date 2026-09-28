-- Migration 006: 5W1H Wizard fields on incidents table
-- Additive only — all columns are nullable, no breaking changes to existing rows.
-- RLS policies from Phase 2 (migration 002) are inherited automatically.
--
-- incident_category  : structured incident type selected by Resident in Step 1
-- wizard_answers     : JSONB bag of per-category quick-choice answers (Step 2)
-- overlap_agencies   : array of secondary concern flags (Step 3, "may kasama pa bang...")
-- landmark_note      : optional free-text landmark supplement to GPS (Step 4)
-- victim_relationship: Resident's relationship to the victim (Step 4)
-- nlp_review_needed  : TRUE when category = 'other' and no structured answers;
--                      Phase 4 NLP pipeline reads this to decide whether to run
--                      the full extraction pass. Set by backend, never by client.

ALTER TABLE incidents
  ADD COLUMN IF NOT EXISTS incident_category    VARCHAR(50),
  ADD COLUMN IF NOT EXISTS wizard_answers       JSONB,
  ADD COLUMN IF NOT EXISTS overlap_agencies     TEXT[],
  ADD COLUMN IF NOT EXISTS landmark_note        TEXT,
  ADD COLUMN IF NOT EXISTS victim_relationship  VARCHAR(30),
  ADD COLUMN IF NOT EXISTS nlp_review_needed    BOOLEAN NOT NULL DEFAULT FALSE;

-- Constrain incident_category to known enum values (NULL allowed for legacy rows
-- and for SOS submissions that bypass the wizard entirely).
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'incidents_category_check'
      AND conrelid = 'incidents'::regclass
  ) THEN
    ALTER TABLE incidents
      ADD CONSTRAINT incidents_category_check
        CHECK (
          incident_category IS NULL OR incident_category IN (
            'fire',
            'medical_trauma',
            'vehicular',
            'flood_landslide_calamity',
            'domestic_dispute_crime',
            'hazmat',
            'missing_person',
            'other'
          )
        );
  END 
END $$;

-- Constrain victim_relationship to known values.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'incidents_victim_relationship_check'
      AND conrelid = 'incidents'::regclass
  ) THEN
    ALTER TABLE incidents
      ADD CONSTRAINT incidents_victim_relationship_check
        CHECK (
          victim_relationship IS NULL OR victim_relationship IN (
            'ako_mismo',
            'kamag_anak',
            'kakilala',
            'estranghero'
          )
        );
  END IF;
END $$;

COMMENT ON COLUMN incidents.incident_category    IS 'Structured incident type from Step 1 of the 5W1H wizard. NULL for SOS and legacy rows.';
COMMENT ON COLUMN incidents.wizard_answers       IS 'Per-category quick-choice answers from Step 2 of the 5W1H wizard. Stored as JSONB.';
COMMENT ON COLUMN incidents.overlap_agencies     IS 'Secondary concern flags from Step 3 (e.g., fire with injuries → [''fire'',''injuries'']). Feeds multi-agency routing suggestion in Phase 6A.';
COMMENT ON COLUMN incidents.landmark_note        IS 'Optional free-text landmark supplement to GPS (e.g., "Malapit sa simbahan"). Captured in Step 4.';
COMMENT ON COLUMN incidents.victim_relationship  IS 'Resident''s relationship to the victim: ako_mismo / kamag_anak / kakilala / estranghero. Captured in Step 4.';
COMMENT ON COLUMN incidents.nlp_review_needed    IS 'TRUE when incident_category = other and no structured answers were provided. Phase 4 NLP pipeline uses this as the trigger for full signal extraction.';
