# Staging Backend Smoke Tests

`Backend Staging Deploy` runs `scripts/ci/backend_staging_smoke.py` after all
staging Lambda updates succeed. The smoke job targets
`https://staging-api.epac.riddimsoftware.com` by default; set the repository
variable `STAGING_API_BASE_URL` to override the externally routable staging API.

The smoke suite is intentionally contract-first. It fails when an endpoint is
unreachable, returns the wrong HTTP status, or returns a body that does not match
the expected JSON shape. It does not require seeded staging data yet.

| Check | Deterministic now | Fixture or seeding follow-up |
| --- | --- | --- |
| `GET /health` | Accepts `ok` or `degraded` `HealthResponse` JSON and fails DB/Lambda error bodies. | Seed/schedule pipeline health rows before requiring `ok`. |
| `GET /api/v1/members/0/speeches` | Verifies pagination, stats, and speech-list contract with an empty-safe member id. | Seed a known MP and speech before asserting content. |
| `GET /api/v1/members/0/votes` | Verifies pagination and vote-list contract with an empty-safe member id. | Seed member vote artifacts before asserting content. |
| `GET /api/v1/on-this-day` | Verifies fixed-date response shape and accepts an empty item list. | Seed historical speeches for a known calendar date. |
| `GET /api/v1/estimates` | Verifies fiscal-year and missing-filter contracts. | Result count depends on the published estimates artifact. |
| `GET /api/v1/ridings/spadina-harbourfront/boundary` | Verifies boundary JSON and geometry shape. | No DB fixture required; depends on the upstream Represent boundary provider. |
| `GET /api/v1/calendar/house.ics` | Verifies the calendar endpoint returns a VCALENDAR response. | No fixture required; depends on the published calendar artifact. |
| `GET /openapi.json` | Verifies the OpenAPI endpoint returns a spec with `paths`. | No fixture required. |
