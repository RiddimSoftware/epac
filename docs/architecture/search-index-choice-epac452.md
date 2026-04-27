# Search Index Choice (EPAC-452)

**Status:** Accepted for v1
**Last updated:** 2026-04-27
**Decision:** Use PostgreSQL full-text search (`tsvector`) for the v1 parliamentary search index. Revisit Meilisearch after the canonical Hansard, bill, vote, and member records are flowing through the backend.

## Context

epac needs search across parliamentary records that users can verify against primary sources:

- Hansard speeches and subjects of business
- Members and ridings
- Bills and bill stages
- Recorded votes
- Later: committee evidence, PBO publications, estimates, and other government datasets

The first backend priority is correctness and traceability. Search results must preserve source IDs, dates, chambers, speakers, bills, and canonical URLs. Search should improve discovery, but it cannot become a separate truth store that drifts from the data pipeline.

## Options Considered

### PostgreSQL `tsvector`

Postgres full-text search keeps the search index beside the canonical records. It supports weighted fields, phrase queries, generated columns or materialized views, GIN indexes, and language-specific dictionaries. It also fits the AWS backend shape already planned for epac: ingestion jobs write normalized records, API handlers query the same database, and deployment does not require operating another search service.

Trade-offs:

- Typo tolerance and synonym handling are weaker than a dedicated search engine.
- Ranking tuning is more manual.
- Bilingual stemming needs deliberate dictionary/configuration work.

### Meilisearch

Meilisearch gives better out-of-the-box relevance, typo tolerance, facets, synonyms, and operationally simple search APIs. It is a strong candidate once epac has enough search volume and enough content diversity to justify a dedicated search service.

Trade-offs:

- Adds another production datastore and sync path.
- Requires a reindexing workflow, drift monitoring, and failure handling between Postgres and Meilisearch.
- Increases operational surface before the canonical record model has settled.

## Decision

Use Postgres `tsvector` for v1.

Build a unified `search_documents` table or materialized view with:

- `document_type`: `speech`, `subject`, `member`, `bill`, `vote`
- `source_id`: stable source identifier from Parliament or epac ingestion
- `title`: display title
- `snippet`: short source-derived excerpt
- `source_url`: primary-source URL when available
- `occurred_on`: sitting date, vote date, bill event date, or record date
- `member_id`, `bill_id`, `vote_id`: nullable join fields for filters and deep links
- `language`: `en`, `fr`, or `und`
- `search_vector`: weighted `tsvector`

Suggested weighting:

- `A`: member names, bill numbers, vote numbers, exact titles
- `B`: subject headings, bill titles, riding names
- `C`: speech snippets and descriptions
- `D`: low-signal metadata

API shape:

```text
GET /search?q=housing&types=speech,bill&member_id=123&page=1
```

The API should return source-linked result objects, not generated summaries.

## Implementation Guardrails

- Search documents are derived from normalized source records. Do not ingest raw search-only records that cannot be traced back to a canonical Hansard, bill, vote, or member row.
- Store enough source metadata with each result to render an honest result card without a second lookup: title, snippet, date, source label, and primary-source URL when available.
- Keep writes idempotent by using `(document_type, source_id, language)` as the logical key.
- Prefer generated `tsvector` columns when each document type has its own table; prefer a materialized view when the unified index is assembled from several canonical tables.
- Add GIN indexes for `search_vector` and btree indexes for common filters (`document_type`, `occurred_on`, `member_id`, `bill_id`, `vote_id`).
- Rebuild or refresh the index from canonical records in CI or a backend job; never hand-edit search rows.

## Follow-On Tickets

- EPAC-466: bilingual indexing design on Postgres dictionaries and language-specific vectors.
- EPAC-467: ranking and relevance tuning with weighted fields, recency boosts, and type-specific boosts.
- A backend schema ticket should create the first `search_documents` table or materialized view.
- An API ticket should expose paginated search results with source labels, dates, and deep-link targets.

## Meilisearch Migration Trigger

Reconsider Meilisearch when at least two of these are true:

- Users need typo tolerance or synonym ranking that Postgres cannot satisfy cleanly.
- Search spans enough datasets that relevance tuning dominates backend work.
- Query latency on representative production data exceeds the app target after Postgres indexing and pagination are tuned.
- Product needs faceted search UX that is awkward or slow with the relational model.

If Meilisearch is introduced later, Postgres remains the canonical source. Meilisearch should be a derived index rebuilt from normalized records, with a documented rebuild command and drift checks.

## Consequences

- EPAC-466 should design bilingual indexing on top of Postgres dictionaries first.
- EPAC-467 should tune ranking with weighted `tsvector`, recency boosts, and type-specific boosts before introducing a second search service.
- Backend ingestion tickets should emit normalized source records before search documents, so search never becomes the first place a dataset is modeled.
- The app should display source labels and dates in search results from day one.

## Non-Goals

- No AI-generated result text.
- No editorial ranking of political importance.
- No Meilisearch deployment in v1.
- No separate search index that lacks a path back to primary-source records.
