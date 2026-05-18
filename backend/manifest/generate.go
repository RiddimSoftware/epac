package manifest

import (
	"context"
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	currentSchemaVersion = 1
	maxConcurrentHeads   = 20
)

var versionPattern = regexp.MustCompile(`/v(\d+)/`)

// GenerateManifest is the use case that lists artifacts and writes manifest.json.
type GenerateManifest struct {
	store ArtifactStore
	now   func() time.Time
}

// NewGenerateManifest creates a GenerateManifest use case backed by store.
func NewGenerateManifest(store ArtifactStore) *GenerateManifest {
	return &GenerateManifest{store: store, now: time.Now}
}

// NewGenerateManifestWithClock creates a GenerateManifest use case with an
// injected clock for deterministic contract tests.
func NewGenerateManifestWithClock(store ArtifactStore, now func() time.Time) *GenerateManifest {
	return &GenerateManifest{store: store, now: now}
}

// Execute lists all artifacts in bucket, builds a deterministic manifest, and
// writes manifest.json back to the bucket root.
func (g *GenerateManifest) Execute(ctx context.Context, bucket string) error {
	objects, err := g.store.ListObjects(ctx, bucket)
	if err != nil {
		return fmt.Errorf("list objects: %w", err)
	}

	entries, err := g.buildEntries(ctx, bucket, objects)
	if err != nil {
		return fmt.Errorf("build entries: %w", err)
	}

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Key < entries[j].Key
	})

	m := Manifest{
		SchemaVersion: currentSchemaVersion,
		GeneratedAt:   g.now().UTC().Truncate(time.Second),
		Artifacts:     entries,
	}

	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("marshal manifest: %w", err)
	}

	if err := g.store.PutManifest(ctx, bucket, data); err != nil {
		return fmt.Errorf("put manifest: %w", err)
	}
	return nil
}

func (g *GenerateManifest) buildEntries(ctx context.Context, bucket string, objects []ObjectInfo) ([]ManifestEntry, error) {
	if len(objects) == 0 {
		return []ManifestEntry{}, nil
	}

	type result struct {
		entry ManifestEntry
		err   error
	}

	results := make([]result, len(objects))
	sem := make(chan struct{}, maxConcurrentHeads)

	var wg sync.WaitGroup
	for i, obj := range objects {
		wg.Add(1)
		go func(idx int, o ObjectInfo) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			meta, err := g.store.HeadObject(ctx, bucket, o.Key)
			if err != nil {
				results[idx] = result{err: fmt.Errorf("head %q: %w", o.Key, err)}
				return
			}
			if meta.ContentHashSHA256 == "" {
				results[idx] = result{err: fmt.Errorf("artifact %q is missing required x-amz-meta-content-hash-sha256 metadata; publish pipeline must set this field", o.Key)}
				return
			}
			results[idx] = result{
				entry: ManifestEntry{
					Key:               o.Key,
					SizeBytes:         o.SizeBytes,
					ContentHashSHA256: meta.ContentHashSHA256,
					ETag:              strings.Trim(o.ETag, `"`),
					LastModified:      o.LastModified.UTC().Truncate(time.Second),
					SchemaVersion:     artifactSchemaVersion(o.Key),
				},
			}
		}(i, obj)
	}
	wg.Wait()

	entries := make([]ManifestEntry, 0, len(objects))
	for _, r := range results {
		if r.err != nil {
			return nil, r.err
		}
		entries = append(entries, r.entry)
	}
	return entries, nil
}

// artifactSchemaVersion extracts the version from keys like "dataset/v1/file.json".
// Defaults to 1 for keys that don't match the naming convention.
func artifactSchemaVersion(key string) int {
	if m := versionPattern.FindStringSubmatch(key); len(m) > 1 {
		if v, err := strconv.Atoi(m[1]); err == nil {
			return v
		}
	}
	return 1
}

// Generate creates an S3-backed store and runs the GenerateManifest use case.
func Generate(ctx context.Context, bucket string) error {
	store, err := NewS3ArtifactStore(ctx)
	if err != nil {
		return fmt.Errorf("create S3 store: %w", err)
	}
	return NewGenerateManifest(store).Execute(ctx, bucket)
}
