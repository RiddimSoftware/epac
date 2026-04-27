-- EPAC-121: Toronto City Council vote records
-- The toronto-council Lambda creates this table idempotently on each run;
-- this migration exists so the schema is version-controlled and reviewable.

CREATE TABLE IF NOT EXISTS toronto_council_votes (
    vote_id            TEXT NOT NULL,
    source_id          TEXT NOT NULL,
    agenda_item_number TEXT NOT NULL,
    agenda_item_title  TEXT NOT NULL,
    motion_type        TEXT NOT NULL DEFAULT '',
    vote_description   TEXT NOT NULL DEFAULT '',
    result             TEXT NOT NULL DEFAULT '',
    vote_date          TIMESTAMPTZ,
    councillor_first   TEXT NOT NULL,
    councillor_last    TEXT NOT NULL,
    vote_detail        TEXT NOT NULL,
    category           TEXT NOT NULL DEFAULT 'Other',
    source_url         TEXT NOT NULL,
    PRIMARY KEY (vote_id)
);

CREATE INDEX IF NOT EXISTS idx_tcv_agenda_item ON toronto_council_votes(agenda_item_number);
CREATE INDEX IF NOT EXISTS idx_tcv_vote_date   ON toronto_council_votes(vote_date DESC);
CREATE INDEX IF NOT EXISTS idx_tcv_category    ON toronto_council_votes(category);

-- Source: Open Data Toronto
-- Dataset: Members of Toronto City Council - Voting Record
-- Current term resource: member-voting-record-2022-2026
-- URL: https://open.toronto.ca/dataset/members-of-toronto-city-council-voting-record/
