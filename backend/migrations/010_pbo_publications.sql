-- PBO publication index ingestion (EPAC-661).
-- Stores one row per Parliamentary Budget Officer publication.
-- Idempotency: ON CONFLICT on source_url; change detection via content_hash.

CREATE TABLE IF NOT EXISTS pbo_publications (
    id                    TEXT PRIMARY KEY,        -- slug derived from source_url path
    title                 TEXT NOT NULL,
    publication_date      DATE,
    methodology_category  TEXT,                    -- legislative-cost | fiscal-update | election-platform | program-evaluation | other
    source_url            TEXT NOT NULL UNIQUE,
    pdf_url               TEXT,
    summary_text          TEXT,                    -- verbatim from page; never paraphrased
    content_hash          TEXT NOT NULL,           -- SHA-256 of title || publication_date for change detection
    ingested_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pbo_pub_date ON pbo_publications(publication_date DESC);
CREATE INDEX IF NOT EXISTS idx_pbo_category ON pbo_publications(methodology_category);

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('pbo-publications', 24)
ON CONFLICT (name) DO NOTHING;
