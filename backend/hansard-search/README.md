# hansard-search Lambda

**Slice 1 of 3** — scaffold, S3 manifest reader, and SQLite index downloader.

This Lambda serves `GET /api/v1/hansard/search`. D1 returns HTTP 503 with
`{"error":"search index not yet available"}` for every request. D2 adds the
FTS5 query adapter and use case; D3 wires the real HTTP handler and OpenAPI spec.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `EPAC_ARTIFACT_BUCKET` | Yes | — | S3 bucket holding the search index artifacts |
| `EPAC_HANSARD_SEARCH_PREFIX` | No | `hansard-search/v1` | S3 key prefix for the manifest and SQLite index |

## Manifest contract

The manifest is read from `s3://$EPAC_ARTIFACT_BUCKET/$EPAC_HANSARD_SEARCH_PREFIX/manifest.json`.
Its schema is defined in `internal/domain/manifest.go` and produced by the
hansard-search-index Lambda (EPAC-2062):

```json
{
  "version": "1",
  "built_at": "2026-05-25T00:00:00Z",
  "parliament_number": 45,
  "session_number": 1,
  "sitting_count": 10,
  "intervention_count": 500,
  "message_count": 1200,
  "sqlite_key": "hansard-search/v1/index.sqlite",
  "sqlite_size_bytes": 1048576,
  "sqlite_sha256": "abc123..."
}
```

## Index loading

`OpenSearchIndex` use case (startup path, used in D3):
1. Reads the manifest from S3.
2. Downloads `s3://bucket/sqlite_key` to `/tmp/index.sqlite` via streaming I/O.
3. Verifies SHA-256 matches `manifest.sqlite_sha256`; returns `ErrChecksumMismatch` on failure.
4. Opens the file read-only (`file:/tmp/index.sqlite?mode=ro&_pragma=query_only(1)`),
   reads `meta.version`, and returns `ErrSchemaMismatch` if it is not `v1`.

## Architecture

```
cmd/main.go
  └─▶ observability.WrapAPIGatewayV2
        └─▶ HandleRequest (returns 503 in D1)

internal/
  domain/         — Manifest value object
  usecase/        — OpenSearchIndex (port interfaces ManifestLoader, IndexDownloader)
  adapter/
    s3manifest/   — ManifestLoader backed by S3
    sqlitefile/   — IndexDownloader: S3 download + SHA-256 + schema-version check
```

Dependency rule: `usecase/` has no imports from `aws-sdk-go-v2` or `modernc.org/sqlite`.

## Building

```bash
cd backend && make test package SERVICE=hansard-search
```
