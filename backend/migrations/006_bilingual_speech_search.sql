-- EPAC-466: bilingual full-text indexing for Hansard speeches.
--
-- Hansard marks floor language in the XML. English and French text need
-- different PostgreSQL dictionaries, and mixed-language interventions need both
-- vectors indexed on the same row.

ALTER TABLE speeches
    ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en',
    ADD COLUMN IF NOT EXISTS search_vector_en TSVECTOR GENERATED ALWAYS AS (
        CASE
            WHEN language IN ('en', 'mixed', 'und')
                THEN to_tsvector('english', COALESCE(content, ''))
            ELSE NULL
        END
    ) STORED,
    ADD COLUMN IF NOT EXISTS search_vector_fr TSVECTOR GENERATED ALWAYS AS (
        CASE
            WHEN language IN ('fr', 'mixed', 'und')
                THEN to_tsvector('french', COALESCE(content, ''))
            ELSE NULL
        END
    ) STORED;

ALTER TABLE speeches
    DROP CONSTRAINT IF EXISTS speeches_language_check,
    ADD CONSTRAINT speeches_language_check
        CHECK (language IN ('en', 'fr', 'mixed', 'und'));

UPDATE speeches
SET language = CASE
    WHEN filename ILIKE '%-F.XML' THEN 'fr'
    WHEN language IS NULL OR language = '' THEN 'en'
    ELSE language
END;

CREATE INDEX IF NOT EXISTS speeches_fts_en_idx
    ON speeches USING gin(search_vector_en)
    WHERE search_vector_en IS NOT NULL;

CREATE INDEX IF NOT EXISTS speeches_fts_fr_idx
    ON speeches USING gin(search_vector_fr)
    WHERE search_vector_fr IS NOT NULL;
