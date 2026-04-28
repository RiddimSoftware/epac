-- Current House sitting state cached for the live status API.
-- The poller owns the singleton row; the API reads it without calling upstream.

CREATE TABLE IF NOT EXISTS live_session (
    id                   BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
    is_sitting           BOOLEAN NOT NULL DEFAULT FALSE,
    business_type        TEXT NOT NULL DEFAULT 'Adjourned',
    current_item_title   TEXT,
    current_bill_number  TEXT,
    current_speaker_name TEXT,
    division_in_progress BOOLEAN NOT NULL DEFAULT FALSE,
    source_url           TEXT NOT NULL DEFAULT 'https://www.ourcommons.ca/en',
    source_snapshot      JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_polled_at       TIMESTAMPTZ,
    last_changed_at      TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS live_sitting_day (
    sitting_date DATE PRIMARY KEY,
    is_sitting   BOOLEAN NOT NULL,
    source_url   TEXT NOT NULL,
    fetched_at   TIMESTAMPTZ NOT NULL
);

INSERT INTO live_session (id, is_sitting, business_type, source_url, source_snapshot)
VALUES (TRUE, FALSE, 'Adjourned', 'https://www.ourcommons.ca/en', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('live-status', 1)
ON CONFLICT (name) DO NOTHING;
