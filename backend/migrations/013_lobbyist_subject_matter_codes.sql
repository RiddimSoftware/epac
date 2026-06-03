-- OCL subject-matter controlled vocabulary (EPAC-2149).
-- One row per Office of the Commissioner of Lobbying subject-matter code as
-- published at lobbycanada.gc.ca. Ingested verbatim from the live source;
-- the EPAC-2150 endpoint joins per-record subject assignments
-- (`lobbyist_subject_matters.ocl_code`) against this canonical code list to
-- translate raw OCL codes into bilingual labels and active-status flags.
--
-- Originally specified to land as `lobbyist_subject_matters` per EPAC-2149's
-- acceptance criteria; renamed to `lobbyist_subject_matter_codes` because
-- EPAC-2150 merged ahead and consumed the original table name for a
-- per-record junction table. The schema below is the controlled-vocabulary
-- table EPAC-2149 calls for.
--
-- Idempotency: ON CONFLICT on ocl_code; ingest re-runs upsert label changes.

CREATE TABLE IF NOT EXISTS lobbyist_subject_matter_codes (
    ocl_code     INTEGER PRIMARY KEY,
    label_en     TEXT NOT NULL,
    label_fr     TEXT NOT NULL,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    ingested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_lobbyist_subject_matter_codes_active
    ON lobbyist_subject_matter_codes(active);

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('lobbyist-subject-matters', 168)
ON CONFLICT (name) DO NOTHING;
