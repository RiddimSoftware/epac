-- Add provenance and linkage columns needed by the bulk Hansard backfill.
-- The backfill remains idempotent through speeches.intervention_id.

ALTER TABLE speeches
  ADD COLUMN IF NOT EXISTS order_title          TEXT,
  ADD COLUMN IF NOT EXISTS subject_qualifier    TEXT,
  ADD COLUMN IF NOT EXISTS source_url           TEXT,
  ADD COLUMN IF NOT EXISTS raw_xml_path         TEXT,
  ADD COLUMN IF NOT EXISTS source_etag          TEXT,
  ADD COLUMN IF NOT EXISTS source_last_modified TEXT,
  ADD COLUMN IF NOT EXISTS language             TEXT DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS related_bill_ids     TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS related_vote_ids     TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS paragraph_ids        TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS search_vector        TSVECTOR;

CREATE INDEX IF NOT EXISTS speeches_source_url_idx
    ON speeches(source_url);

CREATE INDEX IF NOT EXISTS speeches_related_bill_ids_idx
    ON speeches USING gin(related_bill_ids);

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('hansard-backfill', 168)
ON CONFLICT (name) DO NOTHING;
