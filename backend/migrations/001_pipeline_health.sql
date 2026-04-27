-- Pipeline health tracking table.
-- Each pipeline job upserts a row on every run (success or failure).
-- The /health Lambda queries this table to determine overall health.

CREATE TABLE IF NOT EXISTS pipeline_health (
    name                    TEXT PRIMARY KEY,
    last_run_at             TIMESTAMPTZ,
    last_success_at         TIMESTAMPTZ,
    last_error              TEXT,
    record_count            INTEGER,
    expected_interval_hours INTEGER NOT NULL DEFAULT 24
);

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('hansard-daily-fetch',  24),
    ('members-sync',         168),
    ('votes-sync',           24),
    ('bills-sync',           24),
    ('expenditures-sync',    168)
ON CONFLICT (name) DO NOTHING;
