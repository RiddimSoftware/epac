# Backend Manifest And Smoke Tests

`Backend Staging Deploy` runs a manifest topology check, deploys the selected
Lambdas, then runs a manifest readiness check and
`scripts/ci/backend_staging_smoke.py`. The smoke job targets
`https://staging-api.epac.riddimsoftware.com` by default; set the repository
variable `STAGING_API_BASE_URL` to override the externally routable staging API.

`Promote Backend Production` uses the same manifest checker before and after
promotion, then runs the same smoke script against
`https://api.epac.riddimsoftware.com` for services with smoke coverage.

The manifest checker is intentionally narrower than infrastructure-as-code. It
selects services from `backend/manifest/deployment-services.json` where
`deploy.<env>`, `http`, and `sync.<env>.artifact` are all enabled. For that S3
HTTP Lambda shape, it verifies source, Lambda existence, API Gateway
route/integration/payload format, invoke permission, artifact environment, and
required S3 objects. Missing standard S3 HTTP Lambdas are deployment failures,
not skipped warnings.

The smoke suite is contract-first. It fails when an endpoint is unreachable,
returns the wrong HTTP status, or returns a body that does not match the expected
JSON shape. Public artifact-backed list endpoints for bills and members must be
non-empty; fixture-dependent endpoints still accept empty result sets.

| Check | Deterministic now | Fixture or seeding follow-up |
| --- | --- | --- |
| `GET /health` | Accepts `ok` or `degraded` `HealthResponse` JSON and fails DB/Lambda error bodies. | Seed/schedule pipeline health rows before requiring `ok`. |
| `GET /api/v1/bills` | Verifies the bills envelope and requires a non-empty `bills` list from the published artifact. | No fixture required; the canonical bills artifact should not be empty after ingestion. |
| `GET /api/v1/bills/C-8/diff` without query params | Verifies the diff route reaches the bills Lambda by expecting the service-owned missing-parameter `400`. | No diff fixture required. |
| `GET /api/v1/bills/ZZ-9999/diff?from=v1&to=v2` | Verifies unknown bills return the service-owned application `404`, not an API Gateway route-missing `404`. | No diff fixture required. |
| `GET /api/v1/bills/C-11/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee` | Full-mode only. Verifies a current-Parliament multi-version bill returns `200` with a non-empty `clauses` array. | Run the bills indexer/backfill before using `--mode full`. |
| `GET /api/v1/bills/C-10/diff?from=c-10-13610716-first-reading&to=c-10-13610716-first-reading` | Full-mode only. Verifies a real one-version bill returns the documented unavailable `204` empty response. | Run the bills indexer/backfill before using `--mode full`. |
| `GET /api/v1/members` | Verifies the members envelope and requires a non-empty `members` list from the published artifact. | No fixture required; the canonical members artifact should not be empty after ingestion. |
| `GET /api/v1/members/0/speeches` | Verifies pagination, stats, and speech-list contract with an empty-safe member id. | Seed a known MP and speech before asserting content. |
| `GET /api/v1/members/0/votes` | Verifies pagination and vote-list contract with an empty-safe member id. | Seed member vote artifacts before asserting content. |
| `GET /api/v1/on-this-day` | Verifies fixed-date response shape and accepts an empty item list. | Seed historical speeches for a known calendar date. |
| `GET /api/v1/estimates` | Verifies fiscal-year and missing-filter contracts. | Result count depends on the published estimates artifact. |
| `GET /api/v1/ridings/spadina-harbourfront/boundary` | Verifies boundary JSON and geometry shape. | No DB fixture required; depends on the upstream Represent boundary provider. |
| `GET /api/v1/calendar/house.ics` | Verifies the calendar endpoint returns a VCALENDAR response. | No fixture required; depends on the published calendar artifact. |
| `GET /openapi.json` | Verifies the OpenAPI endpoint returns a spec with `paths`. | No fixture required. |
