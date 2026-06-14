# EPAC-2291 Backend Route Verification for Bill Diffs

Date: 2026-06-14
Environment: staging
API ID: `f4x35gduxl`
Domain: `staging-api.epac.riddimsoftware.com`

## 1. OpenAPI and Manifest Route Declaration

Confirming that `GET /api/v1/bills/{id}/diff` is declared in both OpenAPI and deployment manifest:
- **OpenAPI declaration:** Declared in `backend/openapi/openapi.json` under path `"/api/v1/bills/{id}/diff"` with tag `"Bills"` and operation `"getBillVersionDiff"`.
- **Manifest declaration:** Declared in `backend/manifest/deployment-services.json` under the `bills` service for both `staging` and `production` environments:
  ```json
  {
    "method": "GET",
    "path": "/api/v1/bills/{id}/diff"
  }
  ```

## 2. Deployment Contract Verification

Ran the repository's backend manifest/deployment contract checker against staging:
```bash
AWS_PROFILE=riddim-agent python3 scripts/ci/check_backend_manifest_deployment.py --environment staging --api-id f4x35gduxl
```

Output:
```markdown
## Backend manifest deployment check (staging, ready)

| Service | Result |
|---|---|
| members | PASS |
| bills | PASS |
| hansard-search | PASS |
| lobbying | PASS |
| senators | PASS |
```

The route mapping, integrations, Lambda permissions, and runtime environment settings (including `EPAC_ARTIFACT_BUCKET` and suffix prefixes) are all aligned and successfully verified.

## 3. Staging Smoke/Readiness Tests

Ran the staging smoke tests in `full` mode to verify the deployed route behavior:
```bash
AWS_PROFILE=riddim-agent python3 scripts/ci/backend_staging_smoke.py --environment staging --mode full
```

Output:
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
```

## 4. Staging Endpoint Proof

Verified specific scenarios directly via curl to confirm proper application-level responses:

### A. Positive Multi-version Bill Diff (C-11)
- **Request:** `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee`
- **Status:** `HTTP 200`
- **Redacted/Summarized Payload Shape:**
  ```json
  {
    "from": {
      "id": "c-11-13615955-first-reading",
      "label": "First Reading",
      "stage": "First Reading",
      "source_url": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-11/first-reading"
    },
    "to": {
      "id": "c-11-13896514-as-amended-by-committee",
      "label": "As amended by committee",
      "stage": "As amended by committee",
      "source_url": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-11/as-amended-by-committee"
    },
    "clauses": [
      {
        "id": "clause-c-11-diff-c-11-c-11-13615955-first-reading-c-11-13896514-as-amended-by-committee-1",
        "label": "1",
        "change_type": "unchanged",
        "from_text": "Short titleThis Act may be cited as the Military Justice System Modernization Act.",
        "to_text": "Short titleThis Act may be cited as the Military Justice System Modernization Act."
      },
      ...
    ]
  }
  ```

### B. Route is not infrastructure-missing (No API Gateway 404)
Verified that calling the route does not return the infrastructure/gateway 404 `{"message":"Not Found"}`.
- Calling `/api/v1/bills/C-11/diff` with missing `from` and `to` query parameters returns a service-owned `HTTP 400` with the response body:
  ```json
  {
    "error": "missing query parameter 'from' or 'to'"
  }
  ```

### C. Documented unavailable/missing cases
- **One-version Bill (C-10):**
  - **Request:** `GET /api/v1/bills/C-10/diff?from=c-10-13610716-first-reading&to=c-10-13610716-first-reading`
  - **Status:** `HTTP 204`
  - **Body:** Empty (as expected for identical/unavailable diff version checks)
- **Unknown Version:**
  - **Request:** `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-not-a-version`
  - **Status:** `HTTP 404`
  - **Body:** `{"error":"version not found"}`
- **Unknown Bill:**
  - **Request:** `GET /api/v1/bills/ZZ-9999/diff?from=v1&to=v2`
  - **Status:** `HTTP 404`
  - **Body:** `{"error":"bill not found"}`

No infrastructure-level 404 errors or permissions issues were observed. Staging route validation is complete and fully successful.
