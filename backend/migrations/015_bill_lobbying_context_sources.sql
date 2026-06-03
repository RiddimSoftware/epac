-- EPAC-2158: read-side bill subject and reading anchors for bill lobbying context.
-- Ingestion is owned by the LEGISinfo bill-subject pipeline; this schema defines
-- the backend query contract used by /bills/{legisinfo_id}/lobbying-context.

CREATE TABLE IF NOT EXISTS legisinfo_bill_subject_tags (
    legisinfo_id     TEXT NOT NULL,
    subject_tag      TEXT NOT NULL,
    epac_topic_slug  TEXT,
    confidence       DOUBLE PRECISION NOT NULL DEFAULT 1.0
        CHECK (confidence >= 0 AND confidence <= 1),
    source_url       TEXT NOT NULL DEFAULT 'https://www.parl.ca/legisinfo',
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (legisinfo_id, subject_tag)
);

CREATE INDEX IF NOT EXISTS legisinfo_bill_subject_tags_topic_idx
    ON legisinfo_bill_subject_tags (legisinfo_id, epac_topic_slug)
    WHERE epac_topic_slug IS NOT NULL;

CREATE TABLE IF NOT EXISTS legisinfo_bill_readings (
    legisinfo_id  TEXT NOT NULL,
    reading_date  DATE NOT NULL,
    stage_name    TEXT NOT NULL DEFAULT '',
    source_url    TEXT NOT NULL DEFAULT 'https://www.parl.ca/legisinfo',
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (legisinfo_id, reading_date, stage_name)
);

CREATE INDEX IF NOT EXISTS legisinfo_bill_readings_latest_idx
    ON legisinfo_bill_readings (legisinfo_id, reading_date DESC);
