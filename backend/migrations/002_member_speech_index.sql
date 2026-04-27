-- Enrich the speeches table with structured fields extracted from Hansard XML.
-- All new columns are nullable so existing rows remain valid after migration.
-- Run once against production; idempotent via IF NOT EXISTS / IF NOT EXISTS guards.

ALTER TABLE speeches
    ADD COLUMN IF NOT EXISTS sitting_date        DATE,
    ADD COLUMN IF NOT EXISTS parliament_num      INT,
    ADD COLUMN IF NOT EXISTS session_num         INT,
    ADD COLUMN IF NOT EXISTS member_id           TEXT,
    ADD COLUMN IF NOT EXISTS subject_id          TEXT,
    ADD COLUMN IF NOT EXISTS subject_title       TEXT,
    ADD COLUMN IF NOT EXISTS intervention_sequence INT,
    ADD COLUMN IF NOT EXISTS word_count          INT;

-- Index for the member speech feed (EPAC-299): fast lookup by member + date
CREATE INDEX IF NOT EXISTS speeches_member_idx
    ON speeches(member_id, sitting_date DESC)
    WHERE member_id IS NOT NULL;

-- Index for subject-level queries (topic notifications — EPAC-297)
CREATE INDEX IF NOT EXISTS speeches_subject_idx
    ON speeches(subject_id)
    WHERE subject_id IS NOT NULL;

-- Index for date-based lookups (most recent sittings)
CREATE INDEX IF NOT EXISTS speeches_date_idx
    ON speeches(sitting_date DESC)
    WHERE sitting_date IS NOT NULL;

-- GIN full-text index on content for fast keyword search (EPAC-293 acceptance criteria)
-- Uses a generated tsvector column so writes are no more expensive than a regular index.
CREATE INDEX IF NOT EXISTS speeches_content_fts_idx
    ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));

-- Register the loader pipeline so /health can track it
INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('member-speech-index', 24)
ON CONFLICT (name) DO NOTHING;
