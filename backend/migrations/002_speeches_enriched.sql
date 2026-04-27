-- Add enriched columns to speeches for member attribution, subject context, and full-text search.
-- Columns are nullable so existing rows survive without a backfill.
-- Running this migration twice is safe: IF NOT EXISTS guards every statement.

ALTER TABLE speeches
  ADD COLUMN IF NOT EXISTS sitting_date     DATE,
  ADD COLUMN IF NOT EXISTS parliament_num   INT,
  ADD COLUMN IF NOT EXISTS session_num      INT,
  ADD COLUMN IF NOT EXISTS member_id        TEXT,
  ADD COLUMN IF NOT EXISTS subject_title    TEXT,
  ADD COLUMN IF NOT EXISTS intervention_seq INT,
  ADD COLUMN IF NOT EXISTS word_count       INT;

-- Full-text search via PostgreSQL GIN index.
-- COALESCE guards against rows where content is NULL.
CREATE INDEX IF NOT EXISTS speeches_fts_idx
    ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));

-- Fast "all speeches by this member, newest first" query.
CREATE INDEX IF NOT EXISTS speeches_member_date_idx
    ON speeches(member_id, sitting_date DESC);

-- Topic / subject filter.
CREATE INDEX IF NOT EXISTS speeches_subject_idx
    ON speeches(subject_title);
