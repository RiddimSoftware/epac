# Backend OpenAPI Contract

**Date:** 2026-04-28
**Status:** Accepted
**Ticket:** EPAC-238

## Decision

Serve the backend API contract from a dedicated Go Lambda in `backend/openapi`.

The EPAC backend is a set of small Go Lambda handlers rather than a single Flask or FastAPI router, so there is no central route registry to generate from. The source of truth for the contract is the checked-in `backend/openapi/openapi.json` file, and the `openapi` Lambda serves:

- `GET /openapi.json`
- `GET /api/v1/openapi.json`
- `GET /docs`
- `GET /api/v1/docs`

The docs UI is intentionally gated by `OPENAPI_DOCS_TOKEN`. If the token is not configured, `/docs` returns `503` instead of exposing Swagger UI publicly. When configured, clients must pass the token through `X-Docs-Token` or the `token` query parameter.

## Maintenance Rule

Adding or changing a backend endpoint requires updating `backend/openapi/openapi.json` in the same PR. Keep response examples tied to authoritative source-derived fields such as Hansard `intervention_id`, Parliament source URLs, and pipeline health rows.

## Deployment Notes

The existing backend Makefile can build and deploy the Lambda:

```bash
cd backend
make build SERVICE=openapi
make package SERVICE=openapi
```

API Gateway should route both `/openapi.json` and `/docs` to the same Lambda. The `/api/v1/*` aliases are supported by the handler for deployments that place docs under the versioned API prefix.
