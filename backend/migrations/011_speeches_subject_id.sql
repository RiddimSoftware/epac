-- Store the source Hansard SubjectOfBusiness id so downstream artifacts can
-- address debate subjects directly instead of deriving unstable ids from text.

ALTER TABLE speeches
  ADD COLUMN IF NOT EXISTS subject_id TEXT;

CREATE INDEX IF NOT EXISTS speeches_subject_id_idx
    ON speeches(subject_id);
