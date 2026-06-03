-- Migration 012: Lobbyist organization aggregate and alias normalization.

CREATE TABLE IF NOT EXISTS lobbyist_organizations (
    organization_id                           TEXT PRIMARY KEY,
    ocl_organization_id                       TEXT,
    name                                      TEXT NOT NULL,
    type                                      TEXT NOT NULL CHECK (
        type IN ('corporation', 'non_profit', 'association', 'indigenous_organization')
    ),
    sector                                    TEXT,
    registered_lobbyists                      JSONB NOT NULL DEFAULT '[]'::jsonb,
    active_subject_matters                    TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    communication_volume_current_parliament   INTEGER NOT NULL DEFAULT 0,
    communication_volume_prior_parliament     INTEGER NOT NULL DEFAULT 0,
    top_dpohs                                 JSONB NOT NULL DEFAULT '[]'::jsonb,
    updated_at                                TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS lobbyist_organizations_ocl_id_idx
    ON lobbyist_organizations (ocl_organization_id)
    WHERE ocl_organization_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS lobbyist_organizations_name_idx
    ON lobbyist_organizations (LOWER(name));

CREATE TABLE IF NOT EXISTS organization_aliases (
    id              BIGSERIAL PRIMARY KEY,
    organization_id TEXT NOT NULL,
    alias_name      TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    source          TEXT NOT NULL DEFAULT 'seeded',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS organization_aliases_normalized_name_idx
    ON organization_aliases (normalized_name);

CREATE UNIQUE INDEX IF NOT EXISTS organization_aliases_org_normalized_name_idx
    ON organization_aliases (organization_id, normalized_name);

CREATE TABLE IF NOT EXISTS pending_organization_aliases (
    id                         BIGSERIAL PRIMARY KEY,
    normalized_name            TEXT NOT NULL,
    observed_name              TEXT NOT NULL,
    source_table               TEXT NOT NULL,
    source_id                  TEXT,
    source_id_key              TEXT GENERATED ALWAYS AS (COALESCE(source_id, '')) STORED,
    candidate_organization_ids TEXT[] NOT NULL,
    first_seen_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    occurrences                INTEGER NOT NULL DEFAULT 1
);

CREATE UNIQUE INDEX IF NOT EXISTS pending_organization_aliases_unique_observation_idx
    ON pending_organization_aliases (normalized_name, observed_name, source_table, source_id_key);

CREATE INDEX IF NOT EXISTS pending_organization_aliases_last_seen_idx
    ON pending_organization_aliases (last_seen_at DESC);

INSERT INTO organization_aliases (organization_id, alias_name, normalized_name, source)
VALUES
    ('ocl:6143', 'Le Groupe S.M. International', 'le groupe s m international', 'seed:EPAC-2151'),
    ('ocl:6143', 'Groupe SM International', 'groupe sm international', 'seed:EPAC-2151'),
    ('ocl:5876', 'Kashechewan FN', 'kashechewan fn', 'seed:EPAC-2151'),
    ('ocl:5908', 'Fort Albany FN', 'fort albany fn', 'seed:EPAC-2151')
ON CONFLICT DO NOTHING;
