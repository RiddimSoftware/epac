-- EPAC-2150: read-side tables for OCL lobbying records by subject matter.
-- Ingestion is handled by a separate issue; these tables define the endpoint contract.

CREATE TABLE IF NOT EXISTS lobbyist_communications (
    comlog_id          TEXT PRIMARY KEY,
    organization_name  TEXT,
    registrant_name    TEXT,
    registrant_type    TEXT,
    communication_date DATE,
    submitted_date     DATE,
    posted_date        DATE,
    source_url         TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lobbyist_registrations (
    reg_id              TEXT PRIMARY KEY,
    registration_number TEXT,
    organization_name   TEXT,
    registrant_name     TEXT,
    registrant_type     TEXT,
    effective_date      DATE,
    end_date            DATE,
    posted_date         DATE,
    source_url          TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS lobbyist_subject_matters (
    id                  BIGSERIAL PRIMARY KEY,
    source_type         TEXT NOT NULL CHECK (source_type IN ('communication', 'registration')),
    source_id           TEXT NOT NULL,
    ocl_code            TEXT NOT NULL,
    subject_text        TEXT,
    custom_subject_text TEXT,
    source_url          TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS lobbyist_subject_matters_topic_idx
    ON lobbyist_subject_matters (ocl_code, source_type, source_id);

CREATE INDEX IF NOT EXISTS lobbyist_subject_matters_source_idx
    ON lobbyist_subject_matters (source_type, source_id);

CREATE INDEX IF NOT EXISTS lobbyist_communications_date_idx
    ON lobbyist_communications (communication_date DESC NULLS LAST, comlog_id);

CREATE INDEX IF NOT EXISTS lobbyist_registrations_date_idx
    ON lobbyist_registrations (effective_date DESC NULLS LAST, posted_date DESC NULLS LAST, reg_id);
