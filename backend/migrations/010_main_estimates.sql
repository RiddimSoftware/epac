-- Migration 010: Main Estimates ingestion
-- Adds organizations and estimates tables.

CREATE TABLE IF NOT EXISTS organizations (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    legal_title TEXT,
    abbr        TEXT,
    dept_id     TEXT,
    status      TEXT
);

CREATE TABLE IF NOT EXISTS estimates (
    fiscal_year     TEXT NOT NULL,
    organization_id INTEGER REFERENCES organizations(id),
    vote_number     INTEGER,
    vote_description TEXT, -- Maps to vote_type in GC InfoBase
    authorities     NUMERIC,
    source          TEXT,
    PRIMARY KEY (fiscal_year, organization_id, vote_number, vote_description)
);

-- Index for the API: GET /estimates?fiscal_year=
CREATE INDEX IF NOT EXISTS estimates_fiscal_year_idx ON estimates(fiscal_year);

-- Index for the API: GET /estimates/{org_id}
CREATE INDEX IF NOT EXISTS estimates_org_id_idx ON estimates(organization_id);
