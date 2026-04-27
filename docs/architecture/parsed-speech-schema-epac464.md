# Parsed Speech Schema (EPAC-464)

**Status:** Accepted for v1  
**Last updated:** 2026-04-27  
**Decision owner:** Riddim Software

## Decision

Use the backend `speeches` table as the canonical parsed-speech record for v1. Each row represents one House of Commons Hansard `<Intervention>` and keeps enough source metadata to support member speech feeds, search, topic notifications, citations, and future bill/member linking.

The canonical primary key is the Hansard intervention ID:

```sql
intervention_id TEXT PRIMARY KEY
```

Do not create a second speech identity in the backend. App-side SwiftData speech/message IDs may remain UI/cache implementation details, but backend APIs should expose the source-derived `intervention_id`.

## Current Canonical Fields

The v1 schema is:

| Column | Type | Required | Meaning |
|---|---:|---:|---|
| `intervention_id` | `TEXT` | yes | Source `<Intervention id>` from Hansard XML |
| `filename` | `TEXT` | yes | Hansard XML file that produced the row |
| `speaker_name` | `TEXT` | no | Speaker display name captured from `PersonSpeaking > Affiliation` text |
| `content` | `TEXT` | yes | Verbatim intervention text from Hansard `Content/ParaText` |
| `sitting_date` | `DATE` | no | Sitting date from `ExtractedInformation` |
| `parliament_num` | `INT` | no | Parliament number from `ExtractedInformation` |
| `session_num` | `INT` | no | Session number from `ExtractedInformation` |
| `member_id` | `TEXT` | no | Hansard Affiliation `DbId`; stable join key for member-scoped APIs |
| `subject_title` | `TEXT` | no | Nearest enclosing `SubjectOfBusinessTitle` |
| `intervention_seq` | `INT` | no | Intervention order within the subject |
| `word_count` | `INT` | no | Backend-computed word count of `content` |

Required means required for new rows produced by the parser. Existing rows may remain nullable until backfill completes.

## Source Traceability Rules

- `content` must remain verbatim source text except for whitespace normalization needed to join XML text nodes.
- `speaker_name`, `subject_title`, dates, parliament/session numbers, and member IDs must come from Hansard XML or a documented Parliament source.
- Derived fields such as `word_count` are allowed when deterministic and reproducible.
- No AI-generated summary, topic label, or interpretation belongs in `speeches`.
- Every API response built from `speeches` should include enough fields to reconstruct a citation: `intervention_id`, `filename`, `sitting_date`, and either a source URL or the inputs needed to build one.

## Parser Contract

The backend loader should preserve these XML relationships:

- Document metadata from `ExtractedInformation` applies to every intervention in the file.
- `SubjectOfBusinessTitle` applies to following interventions until the next subject.
- `intervention_seq` resets at each `SubjectOfBusiness`.
- `member_id` comes from the first `Affiliation` under `PersonSpeaking`, not affiliations inside speech content.
- Multiple `ParaText` nodes inside one intervention are joined into one `content` value with whitespace between paragraphs.

Rows with missing `intervention_id` or empty `content` should be skipped. All other metadata should be nullable rather than causing ingestion failure.

## API Contract

Member speech APIs should return source-derived fields directly:

```json
{
  "id": "12345678",
  "sitting_date": "2026-04-27",
  "parliament_num": 45,
  "session_num": 1,
  "subject_title": "Housing",
  "preview": "Verbatim source excerpt...",
  "word_count": 142,
  "filename": "Hansard-2026-04-27.XML"
}
```

`preview` is a truncated excerpt of `content`, not a generated summary.

## Indexes

Keep these indexes for v1:

```sql
CREATE INDEX IF NOT EXISTS speeches_member_date_idx
    ON speeches(member_id, sitting_date DESC);

CREATE INDEX IF NOT EXISTS speeches_fts_idx
    ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));

CREATE INDEX IF NOT EXISTS speeches_subject_idx
    ON speeches(subject_title);
```

EPAC-452 chose Postgres `tsvector` for v1 search. Future search migrations should build on `speeches` rather than duplicate speech content elsewhere.

## Next Migration

The next schema migration should add source-link and bilingual/search support without breaking existing APIs:

```sql
ALTER TABLE speeches
  ADD COLUMN IF NOT EXISTS source_url TEXT,
  ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS search_vector TSVECTOR;
```

`source_url` should point to the official Hansard page or a deterministic Parliament URL when available. `language` should be `en`, `fr`, or `und`. `search_vector` should be populated from source text and metadata by a deterministic backend job.

## Non-Goals

- No topic classifier schema here; controlled topic tagging belongs in EPAC-473.
- No bill-reference linker here; member/bill/vote link tables belong in EPAC-465.
- No AI-generated speech summaries.
- No separate document store for v1 search.
