-- EPAC-2154: precomputed lobbying cohort averages.
-- party = NULL stores the national average for the parliament.

CREATE TABLE IF NOT EXISTS lobbying_cohort_averages (
    parliament         INT NOT NULL,
    party              TEXT,
    avg_communications NUMERIC,
    computed_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS lobbying_cohort_averages_unique_idx
    ON lobbying_cohort_averages (parliament, COALESCE(party, '__national__'));

CREATE INDEX IF NOT EXISTS lobbying_cohort_averages_parliament_idx
    ON lobbying_cohort_averages (parliament);

INSERT INTO pipeline_health (name, expected_interval_hours) VALUES
    ('lobbying-cohort-averages', 2208)
ON CONFLICT (name) DO NOTHING;
