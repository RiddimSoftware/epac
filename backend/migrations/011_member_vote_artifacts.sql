CREATE TABLE IF NOT EXISTS recorded_votes (
    vote_id          INTEGER PRIMARY KEY,
    parliament       INTEGER,
    session          INTEGER,
    number           INTEGER,
    date             DATE,
    description_en   TEXT NOT NULL DEFAULT '',
    bill_number_code TEXT NOT NULL DEFAULT '',
    yea              INTEGER NOT NULL DEFAULT 0,
    nay              INTEGER NOT NULL DEFAULT 0,
    paired           INTEGER NOT NULL DEFAULT 0,
    result_en        TEXT NOT NULL DEFAULT '',
    source_url       TEXT NOT NULL DEFAULT 'https://www.ourcommons.ca/members/en/votes'
);

CREATE TABLE IF NOT EXISTS member_votes (
    vote_id       INTEGER NOT NULL REFERENCES recorded_votes(vote_id) ON DELETE CASCADE,
    member_id     TEXT NOT NULL,
    recorded_vote TEXT NOT NULL,
    PRIMARY KEY (vote_id, member_id)
);

CREATE INDEX IF NOT EXISTS recorded_votes_date_idx
    ON recorded_votes(date DESC);

CREATE INDEX IF NOT EXISTS member_votes_member_id_idx
    ON member_votes(member_id, vote_id DESC);
