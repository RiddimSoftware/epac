# manifest

Go package that generates `manifest.json` for the epac S3 artifact bucket.

The manifest is the **port boundary** between the publishing pipeline (writer) and the iOS app (reader). Both sides depend on the schema documented here — a `schema_version` bump is a coordinated change.

## manifest.json schema

```json
{
  "schema_version": 1,
  "generated_at": "2026-05-17T12:00:00Z",
  "artifacts": [
    {
      "key": "members/v1/all.json",
      "size_bytes": 123456,
      "content_hash_sha256": "e3b0c44298fc1c149afb...",
      "etag": "d41d8cd98f00b204e9800998ecf8427e",
      "last_modified": "2026-05-17T11:30:00Z",
      "schema_version": 1
    }
  ]
}
```

### Fields

| Field | Type | Description |
|---|---|---|
| `schema_version` (root) | int | Manifest format version. Bump only when the manifest shape changes incompatibly. |
| `generated_at` | RFC3339 UTC | When the manifest was written, truncated to second precision. |
| `artifacts[].key` | string | S3 object key relative to the bucket root. |
| `artifacts[].size_bytes` | int | Object size in bytes. |
| `artifacts[].content_hash_sha256` | string | SHA-256 of the artifact content, written as S3 user metadata (`x-amz-meta-content-hash-sha256`) by the publisher at upload time. Empty string if the publisher did not set this field. |
| `artifacts[].etag` | string | S3 ETag with surrounding quotes stripped. For multipart uploads the ETag is not an MD5; use `content_hash_sha256` for integrity checks. |
| `artifacts[].last_modified` | RFC3339 UTC | S3 `LastModified` timestamp, truncated to second precision. |
| `artifacts[].schema_version` | int | Schema version of the artifact's data payload, extracted from the key path. |

The `artifacts` array is **sorted by key** so that manifest diffs are reviewable — the same bucket state always produces a byte-identical manifest.

## Artifact naming convention

```
<dataset>/v<N>/<file>.json
```

Examples:

```
members/v1/all.json
bills/v2/all.json
expenditures/v1/2024.json
```

- `<dataset>` — lowercase identifier for the data domain (`members`, `bills`, `expenditures`, …).
- `v<N>` — schema version of the artifact's JSON payload. The manifest extractor reads this component to populate `artifacts[].schema_version`.
- `<file>.json` — descriptive filename. `all.json` is conventional for a complete dataset snapshot.

Keys that do not match this pattern (no `/v<N>/` component) default to `schema_version: 1`.

## Cache-Control conventions

| Object | Cache-Control | Rationale |
|---|---|---|
| `manifest.json` | `public, max-age=60` | iOS re-checks ~minutely; short TTL keeps staleness bounded. |
| Content artifacts | `public, max-age=31536000, immutable` | Keys are version-scoped; content never changes for a given key. |

## Schema version bump rules

The **root** `schema_version` field controls manifest format compatibility:

1. **Additive change** (new optional field in `artifacts[]`): no bump needed; older readers ignore unknown fields.
2. **Field rename or type change**: bump root `schema_version` to 2 and update the iOS parser in the same release train.
3. **Field removal**: bump root `schema_version` and remove iOS code that reads the old field.

The **per-artifact** `schema_version` controls the artifact payload format. It is bumped by the owning publisher (e.g., the members pipeline) when the artifact JSON shape changes incompatibly. Older app versions ignore artifacts whose `schema_version` is higher than the version they were compiled against.

## Running locally

```bash
# Point at a staging bucket
ARTIFACTS_BUCKET=epac-artifacts-staging go run ./cmd/generate-manifest

# Explicit flag
go run ./cmd/generate-manifest -bucket epac-artifacts-staging
```

Requires AWS credentials with `s3:ListBucket`, `s3:GetObject` (for HeadObject), and `s3:PutObject` on the target bucket.

## Clean Architecture

| Layer | Symbol |
|---|---|
| Use case | `GenerateManifest` |
| Entities | `Manifest`, `ManifestEntry` |
| Port | `ArtifactStore` interface |
| Adapter | `S3ArtifactStore` (in `s3.go`) |

Unit tests inject a `mockStore` and never touch S3. The `Generate` convenience function wires `S3ArtifactStore` for production use.
