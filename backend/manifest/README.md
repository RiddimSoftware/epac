# manifest

Go package that generates `manifest.json` for the epac S3 artifact bucket.
The iOS app fetches the manifest on every refresh and downloads only artifacts
whose ETag or SHA-256 hash has changed, avoiding a HEAD request per artifact.

## Manifest schema

`manifest.json` is written to the bucket root with `Cache-Control: public, max-age=60`.

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-17T12:00:00Z",
  "artifacts": [
    {
      "key": "members/v1/all.json",
      "size_bytes": 123456,
      "content_hash_sha256": "e3b0c44298fc1c149afb...",
      "etag": "abc123",
      "last_modified": "2026-05-17T11:30:00Z",
      "schema_version": 1
    }
  ]
}
```

| Field | Type | Notes |
|---|---|---|
| `schema_version` (root) | int | Manifest envelope version. Bump when the envelope shape changes incompatibly. |
| `generated_at` | RFC3339 UTC | Second-precision timestamp of when the manifest was written. |
| `artifacts` | array | Sorted lexicographically by `key`. Same bucket state → byte-identical manifest. |
| `key` | string | S3 object key relative to the bucket root. |
| `size_bytes` | int | Object size in bytes from S3 ListObjectsV2. |
| `content_hash_sha256` | string | Hex SHA-256 of the artifact payload, stored as S3 object metadata `x-amz-meta-content-hash-sha256` by the artifact publisher at write time. ETag for multipart uploads is not a simple MD5, so this field is the authoritative integrity check. |
| `etag` | string | S3 ETag with surrounding quotes stripped. |
| `last_modified` | RFC3339 UTC | Second-precision last-modified timestamp from S3. |
| `schema_version` (per artifact) | int | Version of the artifact's own data schema, extracted from the key path `<dataset>/v<N>/...`. Defaults to 1 for keys without a version segment. |

## Artifact naming convention

All artifacts follow the path pattern:

```
<dataset>/v<N>/<file>.json
```

Examples:
- `members/v1/all.json` — all MPs, schema version 1
- `bills/v2/all.json` — all bills, schema version 2
- `expenditures/v1/by-member.json` — expenditures grouped by member

The version segment `v<N>` is the schema version of the artifact's data payload.
It is also recorded as `schema_version` in the manifest entry so the iOS app
can skip artifacts it does not understand without fetching them.

## Schema version bump rules

**Manifest envelope** (`schema_version` at the root):
- Bump when the manifest JSON shape changes incompatibly (e.g. renaming a field,
  changing a field type, removing a field).
- The iOS app is compiled against a specific envelope version and ignores
  manifests with an unknown root `schema_version`.
- A bump requires coordinated update of the iOS app and the publisher.

**Artifact schema** (`schema_version` per artifact entry, and the `v<N>` in the key):
- Bump when the artifact's own JSON payload changes incompatibly.
- Old app versions continue using the old key (e.g. `members/v1/all.json`)
  while new versions use the new key (`members/v2/all.json`).
- Publishers write both keys during the transition window; old keys are removed
  once the old app version is no longer supported.

## Cache-Control convention

| Object | Cache-Control | Rationale |
|---|---|---|
| `manifest.json` | `public, max-age=60` | Re-checked ~minutely so the app sees new artifacts quickly. |
| Artifact files | `public, max-age=31536000, immutable` | Content-hashed; safe to cache for a year. |

## Architecture

```
GenerateManifest (use case)
    │
    └── ArtifactStore (port/interface)
              │
              └── S3ArtifactStore (adapter — AWS S3 via SDK v2)
```

The `ArtifactStore` interface is the boundary. Unit tests inject a mock;
the CLI entrypoint uses `S3ArtifactStore`. No S3 types leak into the use case.

## Usage

### As a library

```go
import "epac/manifest"

// Uses default AWS credential chain (env vars, instance profile, etc.)
if err := manifest.Generate(ctx, "my-artifacts-bucket"); err != nil {
    log.Fatal(err)
}
```

For testing, inject a custom `ArtifactStore`:

```go
uc := manifest.NewGenerateManifest(myMockStore)
err := uc.Execute(ctx, "my-bucket")
```

### As a CLI binary

```bash
# Build
go build -o generate-manifest ./cmd/generate-manifest

# Run
ARTIFACTS_BUCKET=my-artifacts-bucket ./generate-manifest
# or
./generate-manifest -bucket my-artifacts-bucket
```

The binary is invoked by the GHA publish workflow after all artifact uploads
complete. It requires standard AWS credentials in the environment
(`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN`, or an
IAM role attached to the GitHub Actions runner).

Required IAM permissions:
- `s3:ListBucket` on the artifact bucket
- `s3:GetObject` (HeadObject) on all objects
- `s3:PutObject` on `manifest.json`
