# Bill Version Diff — Staging Coverage Run History (EPAC-2290)

This file records deterministic evidence for the staging `GET /api/v1/bills/{id}/diff`
endpoint: the exact commands run, the bill and version ids used, timestamps, and
summarized outputs. It exists so [EPAC-2018](https://linear.app/riddimsoftware/issue/EPAC-2018/human-handoff-bills-votes-and-committees-depth)
and future agents can reproduce the bill-versions spot-check without re-deriving it.

> **Outcome of the 2026-06-14 run: the diff endpoint is reachable and returns the
> documented "unavailable" response (HTTP 204) for every bill, because the bills
> indexer currently produces diff *headers* but zero clause-level rows. The
> 200 + non-empty `clauses` path cannot be exercised yet. Root cause and the
> follow-up are in [Blocker](#blocker-200--clauses-is-not-yet-reachable) below.**

## Environment

| Field | Value |
| --- | --- |
| Staging API base URL | `https://staging-api.epac.riddimsoftware.com` |
| AWS account | `227530433709` |
| Bills artifact (S3) | `s3://epac-artifacts-227530433709/bills/v1/index.sqlite` (`BILLS_INDEX_PREFIX=bills/v1`) |
| Live API Lambda | `epac-bills-staging` (downloads the S3 index at cold start, caches it in memory) |
| Indexer | `backend/bills-indexer` (run via the `Data Ingestion` workflow, `run_bills_indexer` toggle) |

## Primary smoke target

Per EPAC-2290, the primary current-Parliament example is **C-11**, staging bill id
`13608745`, "An Act to amend the National Defence Act and other Acts", parliament 45,
session 1. It has three published versions:

| Version id | Stage |
| --- | --- |
| `c-11-13615955-first-reading` | First Reading |
| `c-11-13896514-as-amended-by-committee` | As amended by committee |
| `c-11-14114368-as-passed-by-the-house-of-commons` | As passed by the House of Commons |

> The bill depth endpoint resolves by **numeric id** (`/api/v1/bills/13608745`), not by
> number (`/api/v1/bills/C-11` returns 404). The diff endpoint and the smoke fixtures
> therefore use `13608745`. If parliamentary coverage shifts and C-11 is no longer a
> valid multi-version example, rediscover a replacement from `GET /api/v1/bills` and
> update this file plus the `bills:diff-*` fixtures in
> `scripts/ci/backend_staging_smoke.py`.

## Run, 2026-06-14

### Step 1 — Re-run the bills indexer into staging

```bash
gh workflow run data-ingestion.yml --ref main -f environment=staging -f run_bills_indexer=true
```

Run: <https://github.com/RiddimSoftware/epac/actions/runs/27507169123>
(dispatched `2026-06-14T17:52:40Z`, completed `success` `~17:54:42Z`).

The indexer's `artifact_uploaded` log line (stderr, structured JSON):

```json
{"event":"artifact_uploaded","pipeline":"bills-indexer",
 "sqlite_key":"bills/v1/index.sqlite",
 "sqlite_sha256":"1b24feda8e1c967a635469c26648694ed74c5910290e9d5007b1e759ab06366a",
 "sqlite_size_bytes":2523136,
 "table_counts":{"bills":176,"bill_versions":251,"bill_diffs":77,
                 "bill_clause_diffs":0,"bill_committee_stages":106,"pbo_costings":21},
 "timestamp":"2026-06-14T17:54:42Z"}
```

`bill_diffs` = **77** (one header per adjacent version pair) but `bill_clause_diffs` = **0**.

### Step 2 — Inspect the produced artifact

```bash
AWS_PROFILE=riddim-agent aws s3 cp \
  s3://epac-artifacts-227530433709/bills/v1/index.sqlite /tmp/staging-bills.db --region us-east-1

sqlite3 /tmp/staging-bills.db \
  "SELECT 'bill_diffs',COUNT(*) FROM bill_diffs
   UNION ALL SELECT 'bill_clause_diffs',COUNT(*) FROM bill_clause_diffs;"
# bill_diffs|77
# bill_clause_diffs|0
```

Version text is fetched only for the first and final stages, never the intermediate
ones — so no two **adjacent** versions both carry text:

```bash
sqlite3 -header /tmp/staging-bills.db \
  "SELECT stage_slug, COUNT(*) total,
          SUM(CASE WHEN text_hash IS NOT NULL AND text_hash<>'' THEN 1 ELSE 0 END) with_text
   FROM bill_versions GROUP BY stage_slug ORDER BY total DESC;"
```

| stage_slug | total | with_text |
| --- | ---: | ---: |
| first-reading | 167 | 167 |
| as-passed-by-the-house-of-commons | 26 | 0 |
| as-passed-by-the-senate | 24 | 0 |
| as-amended-by-committee | 19 | 0 |
| royal-assent | 15 | 15 |

```bash
# Adjacent (i, i+1 by sort_order) version pairs where BOTH sides have text.
# buildDiffs() only diffs adjacent pairs, so this is the count of pairs that can
# ever produce clauses.
sqlite3 /tmp/staging-bills.db "
WITH v AS (
  SELECT bill_id,
         CASE WHEN text_hash IS NOT NULL AND text_hash<>'' THEN 1 ELSE 0 END ht,
         LEAD(CASE WHEN text_hash IS NOT NULL AND text_hash<>'' THEN 1 ELSE 0 END)
           OVER (PARTITION BY bill_id ORDER BY sort_order) next_ht
  FROM bill_versions)
SELECT COUNT(*) FROM v WHERE ht=1 AND next_ht=1;"
# 0
```

For C-11 specifically, only the first-reading version has text:

```bash
sqlite3 -header /tmp/staging-bills.db \
  "SELECT id, CASE WHEN text_hash IS NOT NULL AND text_hash<>'' THEN 'Y' ELSE 'N' END has_text
   FROM bill_versions WHERE bill_id='13608745' ORDER BY sort_order;"
# c-11-13615955-first-reading|Y
# c-11-13896514-as-amended-by-committee|N
# c-11-14114368-as-passed-by-the-house-of-commons|N
```

### Step 3 — Live endpoint verification (after a Lambda cold start)

The live Lambda caches the index in memory, so it was cold-started to pick up the
freshly-ingested DB before verifying:

```bash
AWS_PROFILE=riddim-agent aws lambda update-function-configuration \
  --function-name epac-bills-staging --region us-east-1 \
  --description "EPAC-2290: cold-start to load freshly ingested bills.db (2026-06-14)"
# wait for LastUpdateStatus=Successful
```

```bash
base=https://staging-api.epac.riddimsoftware.com

# Multi-version bill, real version ids -> 204 (no clauses available)
curl -s -o /dev/null -w '%{http_code}\n' \
  "$base/api/v1/bills/13608745/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee"   # 204
curl -s -o /dev/null -w '%{http_code}\n' \
  "$base/api/v1/bills/13608745/diff?from=c-11-13896514-as-amended-by-committee&to=c-11-14114368-as-passed-by-the-house-of-commons"   # 204

# One-version bill C-201 (13538627) -> 204 (documented unavailable behavior)
curl -s -o /dev/null -w '%{http_code}\n' \
  "$base/api/v1/bills/13538627/diff?from=c-201-13542332-first-reading&to=c-201-13542332-first-reading"   # 204

# Zero-version bill C-1 (13539341), unknown version ids -> 204
curl -s -o /dev/null -w '%{http_code}\n' \
  "$base/api/v1/bills/13539341/diff?from=x&to=y"   # 204
```

### Step 4 — Existing staging smoke checks still pass

```bash
python3 scripts/ci/backend_staging_smoke.py --environment staging \
  --base-url https://staging-api.epac.riddimsoftware.com
# exit 0, 0 FAIL
```

| Check | Result |
| --- | --- |
| `bills:list` | PASS (HTTP 200) |
| `bills:diff-route` | PASS (HTTP 400 for missing from/to) |
| `members:list` | PASS (HTTP 200) |
| `hansard-search` | PASS (HTTP 200) |
| `cabinet-lobbying-overview` | PASS (HTTP 200) |
| `lobbyist-organizations:directory` | PASS (HTTP 200) |

## Acceptance-criteria status

| Criterion | Status | Evidence |
| --- | --- | --- |
| Staging includes diff data for a multi-version current-Parliament bill | **Blocked** | Indexer produced 77 `bill_diffs` but 0 `bill_clause_diffs` (Step 1–2) |
| Use C-11 (`13608745`) as the primary smoke target, or document a replacement | Met | C-11 still has three versions; designated in fixtures and here |
| Multi-version bill `…/diff` returns 200 + non-empty `clauses` | **Blocked** | Returns 204 for every pair (Step 3) — no clause data exists to serve |
| One-version / unsupported bill returns documented empty/unavailable (204) | Met | C-201 and C-1 return 204 (Step 3) |
| Record exact commands, ids, version ids, timestamps, outputs | Met | This file |
| Existing staging smoke checks continue to pass | Met | Contract smoke exit 0, 0 FAIL (Step 4) |

## Blocker: 200 + clauses is not yet reachable

The route, the OpenAPI contract, and the 204 "unavailable" path all work. What is
missing is clause-level data, and that is produced upstream by the bills indexer
(`backend/bills-indexer`), which EPAC-2290 explicitly depends on and does **not** own
("Implementing the indexer diff algorithm" is out of scope).

Two facts pin the cause to the indexer, not to source-data availability:

1. The clause parser is fine. Running `parseBillXML` against the real C-11
   first-reading XML yields **78 sections** with correct labels. The problem is that
   **intermediate-stage version text is never ingested**: `fetchDocumentLinks` does not
   discover an XML link from the `as-amended-by-committee` / `as-passed-*`
   DocumentViewer pages, so those versions get no text (the stage table above: 0/19,
   0/26, 0/24).
2. The source XML exists. parl.ca serves the intermediate documents directly —
   `https://www.parl.ca/Content/Bills/451/Government/C-11/C-11_2/C-11_E.xml` and
   `…/C-11_3/C-11_E.xml` both return HTTP 200 — so this is a discovery gap in the
   indexer, not a publication gap upstream.

Because `buildDiffs` compares only strictly-adjacent versions and a text-less
intermediate stage always sits between the two text-bearing stages, the number of
adjacent pairs that both carry text is 0 across the whole dataset, so every diff has
zero clauses and the endpoint returns 204.

**To unblock**, the indexer needs to either (a) discover and ingest version text for
the intermediate reading stages, or (b) diff the nearest text-bearing versions instead
of strictly-adjacent ones. Both live in `backend/bills-indexer`. Tracked in the
follow-up bug linked from the EPAC-2290 Linear issue. Once it lands, re-run Steps 1–4;
the `bills:diff-full` smoke check (`--mode full`) is the gate that flips to green.
