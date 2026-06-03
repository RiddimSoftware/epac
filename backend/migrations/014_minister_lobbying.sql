-- EPAC-2156: Minister portfolio periods and mandate-topic mappings for
-- cabinet lobbying exposure endpoints.

CREATE TABLE IF NOT EXISTS minister_portfolio_periods (
    id                 BIGSERIAL PRIMARY KEY,
    member_id          TEXT NOT NULL,
    minister_name      TEXT NOT NULL,
    first_name         TEXT,
    last_name          TEXT,
    portfolio_name     TEXT NOT NULL,
    start_date         DATE,
    end_date           DATE,
    tenure_start_date  DATE,
    tenure_end_date    DATE,
    parliament_number  INTEGER,
    source_url         TEXT NOT NULL DEFAULT 'https://www.pm.gc.ca/en/cabinet',
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS minister_portfolio_periods_member_idx
    ON minister_portfolio_periods (member_id, start_date);

CREATE INDEX IF NOT EXISTS minister_portfolio_periods_parliament_portfolio_idx
    ON minister_portfolio_periods (parliament_number, LOWER(portfolio_name));

CREATE TABLE IF NOT EXISTS minister_mandate_topic_mappings (
    id                BIGSERIAL PRIMARY KEY,
    member_id         TEXT NOT NULL,
    portfolio_name    TEXT,
    epac_topic_slug   TEXT NOT NULL,
    confidence        NUMERIC NOT NULL CHECK (confidence > 0 AND confidence <= 1),
    source_url        TEXT NOT NULL DEFAULT 'https://www.pm.gc.ca/en/mandate-letters',
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS minister_mandate_topic_mappings_unique_idx
    ON minister_mandate_topic_mappings (
        member_id,
        COALESCE(portfolio_name, ''),
        epac_topic_slug
    );

CREATE INDEX IF NOT EXISTS minister_mandate_topic_mappings_member_idx
    ON minister_mandate_topic_mappings (member_id, confidence DESC);
