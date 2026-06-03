-- Seeded organization aliases for EPAC-2151.
-- These are intentionally curated rows, not names derived from OCL data at runtime.

INSERT INTO organization_aliases (organization_id, alias_name, normalized_name, source)
VALUES
    ('ocl:6143', 'Le Groupe S.M. International', 'le groupe s m international', 'seed:EPAC-2151'),
    ('ocl:6143', 'Groupe SM International', 'groupe sm international', 'seed:EPAC-2151'),
    ('ocl:5876', 'Kashechewan FN', 'kashechewan fn', 'seed:EPAC-2151'),
    ('ocl:5908', 'Fort Albany FN', 'fort albany fn', 'seed:EPAC-2151')
ON CONFLICT DO NOTHING;
