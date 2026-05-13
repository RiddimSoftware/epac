# EPAC-1832 Aurora Migration Application

Applied at: 2026-05-13T17:55:10Z

Target database: `epac` on the Aurora PostgreSQL 15 cluster referenced by the
`epac/database-url` Secrets Manager secret.

## Bootstrap

The cluster had no existing tables before this work. The checked-in migrations
start with `002_speeches_enriched.sql`, which alters the `speeches` table rather
than creating it. Before applying the migration files, the base `speeches` table
was created using the table definition from `backend/hansard-backfill/main.go`
`ensureSchema` at commit `f76b936bac04b4eac3ec5e5dbacf6864b89f8ade`.

Exact bootstrap SQL applied before the migration files:

```sql
CREATE TABLE IF NOT EXISTS speeches (
    intervention_id  TEXT PRIMARY KEY,
    filename         TEXT,
    speaker_name     TEXT,
    content          TEXT,
    sitting_date     DATE,
    parliament_num   INT,
    session_num      INT,
    member_id        TEXT,
    subject_title    TEXT,
    intervention_seq INT,
    word_count       INT
);
```

No migration files were edited.

## Applied Migrations

Applied in this order with `psql -v ON_ERROR_STOP=1`:

1. `backend/migrations/001_pipeline_health.sql`
2. `backend/migrations/002_speeches_enriched.sql`
3. `backend/migrations/003_device_subscriptions.sql`
4. `backend/migrations/004_vancouver_council.sql`
5. `backend/migrations/005_toronto_council.sql`
6. `backend/migrations/006_bilingual_speech_search.sql`
7. `backend/migrations/006_hansard_backfill_provenance.sql`
8. `backend/migrations/007_live_session.sql`
9. `backend/migrations/008_live_session_sitting_date.sql`
10. `backend/migrations/009_device_subscription_bill_follows.sql`
11. `backend/migrations/010_main_estimates.sql`
12. `backend/migrations/010_pbo_publications.sql`

All migration files completed without SQL errors.

## Verification

Final `\dt` output returned these public tables:

```text
device_subscriptions
estimates
live_session
live_sitting_day
organizations
pbo_publications
pipeline_health
speeches
toronto_council_votes
vancouver_council_votes
```

`pipeline_health` contains the expected seed rows for:

```text
bills-sync
expenditures-sync
hansard-backfill
hansard-daily-fetch
live-status
members-sync
pbo-publications
votes-sync
```
