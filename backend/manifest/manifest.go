package manifest

import (
	"context"
	"time"
)

// ManifestEntry describes a single artifact registered in manifest.json.
type ManifestEntry struct {
	Key               string    `json:"key"`
	SizeBytes         int64     `json:"size_bytes"`
	ContentHashSHA256 string    `json:"content_hash_sha256"`
	ETag              string    `json:"etag"`
	LastModified      time.Time `json:"last_modified"`
	SchemaVersion     int       `json:"schema_version"`
}

// Manifest is the root manifest.json document written to the bucket root.
type Manifest struct {
	SchemaVersion int             `json:"schema_version"`
	GeneratedAt   time.Time       `json:"generated_at"`
	Artifacts     []ManifestEntry `json:"artifacts"`
}

// ObjectInfo holds list-level metadata returned by ListObjects.
type ObjectInfo struct {
	Key          string
	SizeBytes    int64
	ETag         string
	LastModified time.Time
}

// ObjectMeta holds per-object metadata that requires a HeadObject call.
type ObjectMeta struct {
	// ContentHashSHA256 is stored as S3 object metadata under
	// x-amz-meta-content-hash-sha256 by the artifact publisher.
	ContentHashSHA256 string
}

// ArtifactStore is the port between GenerateManifest and storage.
type ArtifactStore interface {
	// ListObjects returns all artifact keys and their list-level metadata.
	// Implementations must exclude manifest.json itself.
	ListObjects(ctx context.Context, bucket string) ([]ObjectInfo, error)
	// HeadObject returns extended metadata for a single object key.
	HeadObject(ctx context.Context, bucket, key string) (ObjectMeta, error)
	// PutManifest writes manifest.json to the bucket root with the
	// appropriate Cache-Control header.
	PutManifest(ctx context.Context, bucket string, data []byte) error
}
