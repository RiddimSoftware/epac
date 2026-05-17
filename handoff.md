## Implementation notes

Added `backend/manifest/` as a new Go module (`epac/manifest`) with full Clean Architecture shape:

- **`manifest.go`** — `Manifest`, `ManifestEntry` entities and the `ArtifactStore` port interface
- **`generate.go`** — `GenerateManifest` use case: lists objects, fans out HeadObject calls via semaphore-limited goroutine pool (≤20 concurrent), sorts entries by key, marshals to JSON, puts manifest; plus `Generate` convenience function for the CLI
- **`s3.go`** — `S3ArtifactStore` adapter: paginates ListObjectsV2, excludes `manifest.json` from listing, reads `x-amz-meta-content-hash-sha256` from HeadObject metadata
- **`cmd/generate-manifest/main.go`** — CLI entrypoint; accepts `-bucket` flag or `ARTIFACTS_BUCKET` env var
- **`generate_test.go`** — 4 unit tests with a mock store (no real S3 calls): empty bucket, multiple artifacts, deterministic ordering, schema version extraction from key path
- **`README.md`** — manifest schema table, artifact naming convention, cache-control rules, schema-version-bump rules, Clean Architecture layer diagram
- **`backend/go.work`** — added `./manifest` entry

ETag quotes are stripped in manifest entries. Per-artifact `schema_version` is parsed from `<dataset>/v<N>/...` key paths, defaulting to 1 for non-versioned keys.

## Verification evidence

```
=== RUN   TestEmptyBucket
--- PASS: TestEmptyBucket (0.00s)
=== RUN   TestMultipleArtifacts
--- PASS: TestMultipleArtifacts (0.00s)
=== RUN   TestDeterministicOrdering
--- PASS: TestDeterministicOrdering (0.00s)
=== RUN   TestSchemaVersionExtraction
--- PASS: TestSchemaVersionExtraction (0.00s)
PASS
ok  	epac/manifest	0.323s
```

`go build ./...` → BUILD OK (library + cmd/generate-manifest binary)

S3 adapter functions (s3.go) have 0% unit test coverage by design — they require real AWS calls. Use case functions (generate.go) have 73–100% coverage.

PR: https://github.com/RiddimSoftware/epac/pull/466 — open, labeled `autonomous`, auto-merge enabled.

## Tradeoffs

- Used `sync.WaitGroup` + channel semaphore for concurrent HeadObject calls instead of `golang.org/x/sync/errgroup` to avoid adding a dependency; functionally equivalent.
- `Generate` convenience function lives in `generate.go` (not `s3.go`) so unit tests can import `epac/manifest` and inject mocks without pulling in the S3 SDK.
- Manifest is pretty-printed with `json.MarshalIndent` so diffs are human-readable in S3 version history.

## Blockers / follow-ups

No blockers. Waiting for reviewer to approve and auto-merge to complete.

Follow-up: the GHA publish workflow (sibling issue) must invoke `cmd/generate-manifest` after uploading artifacts. It needs `s3:ListBucket`, `s3:GetObject` (HeadObject), and `s3:PutObject` on `manifest.json` — the IAM role from EPAC-1907 should already include these.
