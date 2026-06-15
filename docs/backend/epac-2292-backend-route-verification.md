# EPAC-2292 Backend Route Verification — Bill diff endpoint

Date: 2026-06-15
Environment: staging
Base URL: `https://staging-api.epac.riddimsoftware.com`
Route under test: `GET /api/v1/bills/{id}/diff`

This is the **project-level** route-verification gate for the bill diff endpoint
(parent project *Bills, Votes & Committees — depth across the legislative cycle*,
originally missed in [EPAC-962](https://linear.app/riddimsoftware/issue/EPAC-962)).
It runs after the implementation siblings ([EPAC-2286](https://linear.app/riddimsoftware/issue/EPAC-2286),
[EPAC-2287](https://linear.app/riddimsoftware/issue/EPAC-2287),
[EPAC-2288](https://linear.app/riddimsoftware/issue/EPAC-2288),
[EPAC-2290](https://linear.app/riddimsoftware/issue/EPAC-2290)) and proves the
shipped repo state and the staging runtime agree across all four sources of
truth: OpenAPI, the deployment manifest, the Lambda handler, and the live
deployment.

It re-verifies (not re-states) the earlier narrower checks recorded in
[`epac-2291-backend-route-verification.md`](epac-2291-backend-route-verification.md)
and [`epac-2289-staging-bill-diff-coverage.md`](epac-2289-staging-bill-diff-coverage.md);
all evidence below was captured fresh on 2026-06-15.

The lesson from the original miss — a contract that existed while the serving
route and API Gateway exposure did not — is the reason no single source is
trusted on its own here.

## Route contract reconstruction (four independent sources)

| Source | Location | Result |
|---|---|---|
| OpenAPI | `backend/openapi/openapi.json` → path `"/api/v1/bills/{id}/diff"`, op `getBillVersionDiff`, `200 → BillVersionDiff` | Declared ✓ |
| Deployment manifest | `backend/manifest/deployment-services.json` → `bills` service, `GET /api/v1/bills/{id}/diff` in **staging and production** route lists | Declared ✓ |
| Lambda handler | `backend/bills/main.go` → `billVersionDiffIDFromRequest` routes to `usecase.NewLoadBillVersionDiff(...)`, returns `domain.BillVersionDiff` (200), `204` when nil, `400` missing `from`/`to`, `404` not found | Serves route ✓ |
| Staging runtime | live API Gateway + `epac-bills-staging` Lambda (below) | Reachable, service-owned responses ✓ |

OpenAPI ↔ manifest agree on method/path semantics (`GET /api/v1/bills/{id}/diff`).
The `BillVersionDiff` schema requires `from`, `to`, and `clauses`; the handler's
`domain.BillVersionDiff` return type matches.

## Local / handler tests

```bash
cd backend && go test ./bills/...
# ok  epac/bills            4.479s
# ok  epac/bills/internal/adapter/sqlite
# ok  epac/bills/internal/usecase
```

The schema-conformance acceptance criterion is exercised by
`TestHandleRequestGetsBillVersionDiff` (`backend/bills/main_test.go`): it invokes
`GET /api/v1/bills/C-2287/diff?from=C-2287-v1&to=C-2287-v2`, asserts HTTP 200,
and decodes the body into `BillVersionDiff`, checking `from.id`, `to.id`, and the
`clauses[]` fields (`id`, `change_type`, `from_text`, `hansard_anchor_url`).
Supporting diff tests (`go test ./bills/ -run Diff -v`, all PASS):

- `TestHandleRequestGetsBillVersionDiff` — 200 + schema
- `TestHandleRequestBillVersionDiffMissingQueryReturns400` — both/from/to missing
- `TestHandleRequestBillVersionDiffUnknownBillReturns404`
- `TestHandleRequestBillVersionDiffUnknownVersionsReturns404`
- `TestHandleRequestBillVersionDiffOneVersionBillReturns404`
- `TestHandleRequestBillVersionDiffVersionsExistButNoDiffReturns204`
- usecase: `TestLoadBillVersionDiff*` (5 cases)

## Repository smoke check (full mode)

```bash
AWS_PROFILE=riddim-agent python3 scripts/ci/backend_staging_smoke.py \
  --environment staging --mode full
```

```
PASS bills:list: HTTP 200
PASS bills:diff-route: HTTP 400
PASS bills:diff-unknown: HTTP 404
PASS bills:diff-full: HTTP 200
PASS bills:diff-one-version: HTTP 204
PASS members:list: HTTP 200
PASS hansard-search: HTTP 200
PASS cabinet-lobbying-overview: HTTP 200
PASS lobbyist-organizations:directory: HTTP 200
Base URL: https://staging-api.epac.riddimsoftware.com
```

## Live staging endpoint proof

Captured directly with `curl` on 2026-06-15 against the recorded
[EPAC-2290](https://linear.app/riddimsoftware/issue/EPAC-2290)/[EPAC-2289](https://linear.app/riddimsoftware/issue/EPAC-2289)
examples.

| # | Request | Expected | Observed |
|---|---|---|---|
| A | `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee` | 200, non-empty `clauses` | **200**, `from`/`to` ids match, `clauses.length == 82` |
| B | `GET /api/v1/bills/C-11/diff` (no `from`/`to`) | service 400, not gateway 404 | **400** `{"error":"missing required query parameters: from, to"}` |
| C | `GET /api/v1/bills/C-10/diff?from=c-10-13610716-first-reading&to=c-10-13610716-first-reading` (one-version) | 204 empty | **204**, 0-byte body |
| D | `GET /api/v1/bills/ZZ-9999/diff?from=v1&to=v2` (unknown bill) | service 404 | **404** `{"error":"bill not found"}` |

Case A response shape (truncated):

```json
{
  "from": { "id": "c-11-13615955-first-reading", "label": "First Reading", "stage": "First Reading", "source_url": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-11/first-reading" },
  "to":   { "id": "c-11-13896514-as-amended-by-committee", "label": "As amended by committee", "stage": "As amended by committee", "source_url": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-11/as-amended-by-committee" },
  "clauses": [ { "id": "...", "label": "1", "change_type": "unchanged", "from_text": "Short title...", "to_text": "Short title..." }, "... 82 total ..." ]
}
```

Case B confirms the route reaches the bills service (which owns the 400) rather
than returning the API Gateway `{"message":"Not Found"}` of an unmapped route.
The 400 body matches the **current** `main` handler message
(`missing required query parameters: from, to`), which differs from the older
phrasing recorded in the EPAC-2291 note — i.e. the live deployment matches the
currently shipped code, not a stale build.

## Verdict

**PASS.** `GET /api/v1/bills/{id}/diff` is exposed and consistent across OpenAPI,
the deployment manifest, the Lambda handler, the repo smoke check, and the live
staging runtime. The documented 200 / 204 / 400 / 404 behaviors all reproduce
against staging.

No gaps were found; no follow-up implementation issues are required. This gate
clears [EPAC-2018](https://linear.app/riddimsoftware/issue/EPAC-2018) on the
backend-route dimension (closing EPAC-2018 itself remains out of scope for this
issue).
