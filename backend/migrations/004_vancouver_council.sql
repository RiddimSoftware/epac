-- EPAC-120: Vancouver City Council vote records
-- The vancouver-council Lambda creates this table idempotently on each run;
-- this migration exists so the schema is version-controlled and reviewable.

CREATE TABLE IF NOT EXISTS vancouver_council_votes (
    vote_id           TEXT NOT NULL,
    vote_number       TEXT NOT NULL,
    motion_title      TEXT NOT NULL,
    vote_date         DATE,
    councillor_first  TEXT NOT NULL,
    councillor_last   TEXT NOT NULL,
    vote_detail       TEXT NOT NULL,  -- "In Favour", "Opposed", "Absent", "Abstain"
    category          TEXT NOT NULL DEFAULT 'Other',
    PRIMARY KEY (vote_id)
);

CREATE INDEX IF NOT EXISTS idx_vcv_vote_number ON vancouver_council_votes(vote_number);
CREATE INDEX IF NOT EXISTS idx_vcv_vote_date   ON vancouver_council_votes(vote_date DESC);
CREATE INDEX IF NOT EXISTS idx_vcv_category    ON vancouver_council_votes(category);

-- Source: City of Vancouver Open Data
-- Dataset: council-voting-records
-- URL: https://opendata.vancouver.ca/explore/dataset/council-voting-records
-- Licence: Open Government Licence – Vancouver
