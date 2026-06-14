# EPAC-2289 Staging Bill Diff Coverage Evidence

Date: 2026-06-14
Environment: staging
Artifact bucket: `epac-artifacts-227530433709`
Bills artifact prefix: `bills/v1`

## Backfill Run

Repo-supported command, run from `backend/bills-indexer` with the
`riddim-agent` AWS profile:

```bash
DB_PATH=/tmp/epac-2289-bills.db \
EPAC_ARTIFACT_BUCKET=epac-artifacts-227530433709 \
BILLS_INDEX_PREFIX=bills/v1 \
PARLIAMENT_NUMBER=45 \
SESSION_NUMBER=1 \
AWS_PROFILE=riddim-agent \
go run .
```

Run-history log:

- `2026-06-14T19:16:06Z` - `ingest_started`, session `45-1`, prefix `bills/v1`.
- `2026-06-14T19:16:06Z` - `fetch_started`, `count: 176`.
- `2026-06-14T19:16:56Z` - `fetch_completed`, `count: 176`.
- `2026-06-14T19:16:57Z` - `write_completed`.
- `2026-06-14T19:16:59Z` - `artifact_uploaded`.

Generated manifest:

- S3 key: `bills/v1/manifest.json`.
- S3 version: `HxwYnderulmX.w4ml6JaTh2WJJDgqYuo`.
- S3 `LastModified`: `2026-06-14T19:17:00+00:00`.
- Manifest `built_at`: `2026-06-14T19:16:56Z`.
- SQLite key: `bills/v1/index.sqlite`.
- SQLite size: `12386304` bytes.
- SQLite SHA-256: `4aec557268ddbc60cc2098e823f9c7c096ac0307a9fd64c034c2f1ca3afc7503`.

Table-count proof:

| Table | Before | After |
| --- | ---: | ---: |
| `bills` | 176 | 176 |
| `bill_versions` | 251 | 251 |
| `bill_diffs` | 77 | 77 |
| `bill_clause_diffs` | 0 | 4397 |
| `bill_committee_stages` | 106 | 106 |
| `bill_committee_meetings` | 267 | 267 |
| `bill_related_links` | 506 | 506 |
| `pbo_costings` | 21 | 21 |
| `bill_amendments` | 0 | 0 |

The backfill log contained no warning, error, failed, missing, unsupported, or
parse messages. No new bill-diff source-format gap was observed. The
`bill_amendments` table remained at its prior count and was not changed by this
diff-coverage backfill.

## Runtime Refresh

The first post-backfill public request still returned the old unavailable diff,
which showed that `epac-bills-staging` had the prior SQLite artifact open in a
warm Lambda runtime. To force a clean reopen without leaving staging
configuration changes behind, the Lambda environment was temporarily updated
with `EPAC_CONFIG_REFRESH_NONCE=EPAC-2289-20260614T1919Z`, then restored to:

```json
{
  "EPAC_ARTIFACT_BUCKET": "epac-artifacts-227530433709",
  "BILLS_INDEX_PREFIX": "bills/v1"
}
```

Restored Lambda revision: `3a6a1490-2e93-4647-b6be-be9f53db5602`
Restored `LastModified`: `2026-06-14T19:18:45.000+0000`

## Staging Endpoint Proof

Base URL: `https://staging-api.epac.riddimsoftware.com`

Positive current-Parliament multi-version bill:

- Bill: C-11, LEGISinfo bill ID `13608745`.
- Request: `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee`.
- Result: `HTTP 200`, `clauses.length == 82`.
- Version ids: `c-11-13615955-first-reading` to `c-11-13896514-as-amended-by-committee`.

Second adjacent C-11 pair:

- Request: `GET /api/v1/bills/C-11/diff?from=c-11-13896514-as-amended-by-committee&to=c-11-14114368-as-passed-by-the-house-of-commons`.
- Result: `HTTP 200`, `clauses.length == 82`.

Unavailable one-version bill:

- Bill: C-10, LEGISinfo bill ID `13605049`.
- Request: `GET /api/v1/bills/C-10/diff?from=c-10-13610716-first-reading&to=c-10-13610716-first-reading`.
- Result: `HTTP 204`, empty body.

Documented error cases:

- `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-not-a-version` returned `HTTP 404` with `{"error":"version not found"}`.
- `GET /api/v1/bills/ZZ-9999/diff?from=v1&to=v2` returned `HTTP 404` with `{"error":"bill not found"}`.
