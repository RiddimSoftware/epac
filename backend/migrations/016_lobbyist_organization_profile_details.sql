-- EPAC-996: profile-detail slices for iOS lobbyist organization profiles.
-- Values are populated by the existing organization aggregate refresh from
-- authoritative OCL registration and communication rows.

ALTER TABLE lobbyist_organizations
    ADD COLUMN IF NOT EXISTS registration_status TEXT NOT NULL DEFAULT 'expired'
        CHECK (registration_status IN ('active', 'expired')),
    ADD COLUMN IF NOT EXISTS registrations JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS recent_communications JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS subject_matters JSONB NOT NULL DEFAULT '[]'::jsonb;
