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
| `GET /search/speeches` | Verifies the search response envelope for a fixed query. | Seed known speeches before requiring non-empty results. |
| `GET /api/v1/members/0/speeches` | Verifies pagination, stats, and speech-list contract with an empty-safe member id. | Seed a known MP and speech before asserting content. |
| `GET /api/v1/on-this-day` | Verifies fixed-date response shape and accepts an empty item list. | Seed historical speeches for a known calendar date. |
| `GET /api/v1/ridings/spadina-harbourfront/boundary` | Verifies boundary JSON and geometry shape. | No DB fixture required; depends on the upstream Represent boundary provider. |
| `GET /api/v1/live` | Verifies cached live-status JSON shape. | Do not assert the exact sitting state; it depends on time and polling data. |
| `POST /api/v1/device/register` | Sends `{}` and verifies the safe invalid request is rejected with a token error before writes. | Add a disposable APNs-token fixture and cleanup policy before testing `200 OK`. |
