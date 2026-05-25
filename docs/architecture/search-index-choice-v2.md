# Search Index Choice (v2)

**Status:** Accepted for v1 (supersedes EPAC-452)
**Last updated:** 2026-05-25
**Filename convention:** future supersession lands as `search-index-choice-v3.md`, not with an EPAC-NNN suffix.

## Decision

Use SQLite FTS5 with the `porter` tokenizer, stored as a single `.sqlite` file in S3, queried by a stateless Lambda that pulls the file to `/tmp` on cold start.

The index is built by the `backend/hansard-search-index/` Lambda and queried by the `backend/hansard-search/` Lambda (created in EPAC project issues #4 and #5 respectively).

## Why this changed

Two migrations made the Postgres `tsvector` approach (EPAC-452) obsolete before it was fully implemented:

1. **EPAC-1914 → EPAC-1917**: Hot parliamentary entities (members, sittings, bills, statistics pipelines) were migrated from Aurora to S3 artifacts served via CloudFront. The read-side architecture is now S3-native; a Postgres-backed search index would be the only remaining reason to keep a live database connection in the query path.

2. **Aurora retirement**: With the read-side move to S3 artifacts, the production Aurora Serverless v2 cluster (`epac-db`) is being retired (see `infra/rds/README.md`). Building a search index on a database that is being decommissioned is not viable.

A self-contained SQLite file in S3 fits the existing S3-artifact pattern, eliminates the database dependency from the search query path, and keeps operational complexity flat.

## Trade-offs

### SQLite FTS5 in S3 vs Postgres `tsvector`

**SQLite FTS5 pros:** No persistent database connection required; the entire index is a single file that cold-starts in a Lambda's `/tmp`; fits the existing S3-artifact deployment model; FTS5 `porter` tokenizer gives reasonable English stemming out of the box; zero additional AWS infrastructure.

**SQLite FTS5 cons:** The index is rebuilt in full on each refresh cycle (no incremental updates); cold-start latency is proportional to file size; bilingual French stemming is not built in (see Out of scope); concurrent writes to the index file require coordination at build time.

### SQLite FTS5 in S3 vs OpenSearch / Meilisearch

**Managed search service pros:** Better out-of-the-box relevance tuning, typo tolerance, synonym handling, and faceted search; real-time index updates; purpose-built query DSL.

**Managed search service cons:** Adds another production datastore to operate and monitor; requires a reindexing sync path and drift checks between the canonical S3 artifacts and the search index; increases cost and operational surface before search volume justifies it. OpenSearch in particular adds meaningful per-hour cost for a service that is read-heavy and low-QPS at this stage.

## Out of scope for v1

- **Bilingual French stemming:** FTS5 `porter` covers English. French parliamentary debates require a separate tokenizer configuration or a language-split index. Deferred until English search is live and validated.
- **Scheduled refresh:** Index rebuild triggering, freshness SLAs, and alerting on stale indexes are out of scope for the initial implementation.
- **Cross-session search:** Persistent search history, saved searches, and user-scoped results are product features deferred to a later milestone.

## Implementation pointers

- **Index builder:** `backend/hansard-search-index/` — reads canonical S3 artifacts, builds an FTS5 SQLite database, and uploads it to S3.
- **Query Lambda:** `backend/hansard-search/` — pulls the SQLite file to `/tmp` on cold start, accepts `GET /api/v1/search?q=...` requests, and returns paginated source-linked results.
- **Manifest registration:** both services are registered in `backend/manifest/deployment-services.json` as part of their respective implementation PRs.

## Meilisearch migration trigger

Reconsider a managed search service when at least two of these are true:

- Users need typo tolerance or synonym ranking that FTS5 cannot satisfy.
- Search spans enough datasets that relevance tuning dominates backend work.
- Query latency on representative production data exceeds the app target after FTS5 indexing and pagination are tuned.
- Product needs faceted search UX that is awkward with the flat SQLite model.

If a managed service is introduced later, S3 artifacts remain the canonical source. The managed index should be a derived view rebuilt from those records.
