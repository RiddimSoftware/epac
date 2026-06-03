-- EPAC-2153: precomputed MP lobbying exposure read models.
-- OCL refresh jobs write timeline rows and refresh quarterly summaries before
-- the API reads these tables.

CREATE TABLE IF NOT EXISTS mp_lobbying_timeline_entries (
    id                      BIGSERIAL PRIMARY KEY,
    member_id               TEXT NOT NULL,
    parliament              INTEGER NOT NULL,
    communication_id         TEXT NOT NULL,
    communication_date       DATE NOT NULL,
    organization_name        TEXT NOT NULL,
    organization_sector      TEXT,
    subject_matter           TEXT NOT NULL,
    communication_type       TEXT NOT NULL CHECK (communication_type IN ('meeting', 'written')),
    bill_number              TEXT,
    bill_title               TEXT,
    bill_url                 TEXT,
    bill_mapping_confidence  DOUBLE PRECISION,
    source_url               TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (member_id, parliament, communication_id, subject_matter)
);

CREATE INDEX IF NOT EXISTS mp_lobbying_timeline_member_date_idx
    ON mp_lobbying_timeline_entries (member_id, parliament, communication_date DESC, communication_id DESC);

CREATE INDEX IF NOT EXISTS mp_lobbying_timeline_parliament_date_idx
    ON mp_lobbying_timeline_entries (parliament, communication_date DESC);

CREATE TABLE IF NOT EXISTS mp_lobbying_summaries (
    member_id                                TEXT NOT NULL,
    parliament                               INTEGER NOT NULL,
    quarter_start                            DATE NOT NULL,
    "window"                                 TEXT NOT NULL CHECK ("window" IN ('30d', '3m', '12m', 'all')),
    total_communication_count                INTEGER NOT NULL DEFAULT 0,
    unique_organizations_count               INTEGER NOT NULL DEFAULT 0,
    most_frequent_subject_matter             TEXT,
    top_organizations                        JSONB NOT NULL DEFAULT '[]'::jsonb,
    current_parliament_communication_count   INTEGER NOT NULL DEFAULT 0,
    previous_parliament_communication_count  INTEGER NOT NULL DEFAULT 0,
    party_average_communications             NUMERIC(10, 2) NOT NULL DEFAULT 0,
    national_average_communications          NUMERIC(10, 2) NOT NULL DEFAULT 0,
    updated_at                               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (member_id, parliament, quarter_start, "window")
);

CREATE INDEX IF NOT EXISTS mp_lobbying_summaries_lookup_idx
    ON mp_lobbying_summaries (member_id, parliament, "window", quarter_start DESC);

CREATE TABLE IF NOT EXISTS mp_lobbying_subject_breakdowns (
    member_id             TEXT NOT NULL,
    parliament            INTEGER NOT NULL,
    quarter_start         DATE NOT NULL,
    "window"              TEXT NOT NULL CHECK ("window" IN ('30d', '3m', '12m', 'all')),
    subject_matter        TEXT NOT NULL,
    communication_count   INTEGER NOT NULL DEFAULT 0,
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (member_id, parliament, quarter_start, "window", subject_matter)
);

CREATE INDEX IF NOT EXISTS mp_lobbying_subject_breakdowns_lookup_idx
    ON mp_lobbying_subject_breakdowns (member_id, parliament, "window", quarter_start DESC, communication_count DESC);
