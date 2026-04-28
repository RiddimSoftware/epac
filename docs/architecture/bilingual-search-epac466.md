# Bilingual Search Indexing (EPAC-466)

**Status:** Implemented for v1
**Last updated:** 2026-04-28

## Decision

Hansard speech search uses the canonical `speeches` table with one language label per intervention:

- `en`: index `content` with PostgreSQL `english`
- `fr`: index `content` with PostgreSQL `french`
- `mixed`: index the same row in both English and French generated vectors
- `und`: index both vectors until the source language can be backfilled

The generated vectors are stored separately:

```sql
search_vector_en TSVECTOR
search_vector_fr TSVECTOR
```

Each vector has its own partial GIN index. This keeps mixed-language rows searchable in both dictionaries without duplicating the canonical speech row.

## Query Behavior

The search API derives a language hint from the raw query. Accented French characters and common French markers prefer the French rank path; otherwise English is preferred. Results still match both `search_vector_en` and `search_vector_fr`, so cross-language searches can return English, French, and mixed rows. The hint only gives a small ranking boost to the matching dictionary.

Snippets use the dictionary that matched the row. If both vectors match, the query language hint chooses the headline dictionary.

## Verification SQL

Run this after applying migrations and loading speeches:

```sql
SELECT intervention_id, language
FROM speeches
WHERE search_vector_fr @@ plainto_tsquery('french', 'budgétaire')
ORDER BY sitting_date DESC NULLS LAST
LIMIT 10;

SELECT intervention_id, language
FROM speeches
WHERE search_vector_en @@ plainto_tsquery('english', 'budget')
ORDER BY sitting_date DESC NULLS LAST
LIMIT 10;

SELECT intervention_id, language
FROM speeches
WHERE language = 'mixed'
  AND search_vector_en IS NOT NULL
  AND search_vector_fr IS NOT NULL
LIMIT 10;
```

Expected behavior: French queries hit French and mixed rows through `search_vector_fr`; English queries hit English and mixed rows through `search_vector_en`.
