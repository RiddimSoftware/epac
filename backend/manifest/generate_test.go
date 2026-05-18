package manifest_test

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"epac/manifest"
	"github.com/santhosh-tekuri/jsonschema/v6"
)

type mockStore struct {
	objects []manifest.ObjectInfo
	metas   map[string]manifest.ObjectMeta
	written []byte
}

func (m *mockStore) ListObjects(_ context.Context, _ string) ([]manifest.ObjectInfo, error) {
	return m.objects, nil
}

func (m *mockStore) HeadObject(_ context.Context, _, key string) (manifest.ObjectMeta, error) {
	if meta, ok := m.metas[key]; ok {
		return meta, nil
	}
	return manifest.ObjectMeta{}, nil
}

func (m *mockStore) PutManifest(_ context.Context, _ string, data []byte) error {
	m.written = data
	return nil
}

func TestEmptyBucket(t *testing.T) {
	store := &mockStore{metas: map[string]manifest.ObjectMeta{}}
	uc := manifest.NewGenerateManifest(store)

	if err := uc.Execute(context.Background(), "test-bucket"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var got manifest.Manifest
	if err := json.Unmarshal(store.written, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if got.SchemaVersion != 1 {
		t.Errorf("schema_version: got %d, want 1", got.SchemaVersion)
	}
	if len(got.Artifacts) != 0 {
		t.Errorf("artifacts: got %d, want 0", len(got.Artifacts))
	}
	if got.GeneratedAt.IsZero() {
		t.Error("generated_at must not be zero")
	}
}

func TestMultipleArtifacts(t *testing.T) {
	ts := time.Date(2026, 5, 17, 11, 30, 0, 0, time.UTC)
	store := &mockStore{
		objects: []manifest.ObjectInfo{
			{Key: "members/v1/all.json", SizeBytes: 1000, ETag: `"abc123"`, LastModified: ts},
			{Key: "bills/v1/all.json", SizeBytes: 500, ETag: `"def456"`, LastModified: ts},
		},
		metas: map[string]manifest.ObjectMeta{
			"members/v1/all.json": {ContentHashSHA256: "sha256-members"},
			"bills/v1/all.json":   {ContentHashSHA256: "sha256-bills"},
		},
	}
	uc := manifest.NewGenerateManifest(store)

	if err := uc.Execute(context.Background(), "test-bucket"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var got manifest.Manifest
	if err := json.Unmarshal(store.written, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(got.Artifacts) != 2 {
		t.Fatalf("artifact count: got %d, want 2", len(got.Artifacts))
	}

	// sorted: bills before members
	bills := got.Artifacts[0]
	members := got.Artifacts[1]

	if bills.Key != "bills/v1/all.json" {
		t.Errorf("artifacts[0].key: got %q, want %q", bills.Key, "bills/v1/all.json")
	}
	if members.Key != "members/v1/all.json" {
		t.Errorf("artifacts[1].key: got %q, want %q", members.Key, "members/v1/all.json")
	}
	if members.ContentHashSHA256 != "sha256-members" {
		t.Errorf("members sha256: got %q, want sha256-members", members.ContentHashSHA256)
	}
	if bills.ContentHashSHA256 != "sha256-bills" {
		t.Errorf("bills sha256: got %q, want sha256-bills", bills.ContentHashSHA256)
	}
	// ETags should have surrounding quotes stripped
	if members.ETag != "abc123" {
		t.Errorf("members etag: got %q, want abc123", members.ETag)
	}
	if members.SchemaVersion != 1 {
		t.Errorf("members schema_version: got %d, want 1", members.SchemaVersion)
	}
	if members.SizeBytes != 1000 {
		t.Errorf("members size_bytes: got %d, want 1000", members.SizeBytes)
	}
}

func TestDeterministicOrdering(t *testing.T) {
	ts := time.Date(2026, 5, 17, 11, 30, 0, 0, time.UTC)
	store := &mockStore{
		objects: []manifest.ObjectInfo{
			{Key: "z/v1/file.json", SizeBytes: 1, ETag: `"z"`, LastModified: ts},
			{Key: "a/v1/file.json", SizeBytes: 2, ETag: `"a"`, LastModified: ts},
			{Key: "m/v1/file.json", SizeBytes: 3, ETag: `"m"`, LastModified: ts},
		},
		metas: map[string]manifest.ObjectMeta{
			"z/v1/file.json": {ContentHashSHA256: "sha256-z"},
			"a/v1/file.json": {ContentHashSHA256: "sha256-a"},
			"m/v1/file.json": {ContentHashSHA256: "sha256-m"},
		},
	}
	uc := manifest.NewGenerateManifest(store)

	if err := uc.Execute(context.Background(), "test-bucket"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var got manifest.Manifest
	if err := json.Unmarshal(store.written, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(got.Artifacts) != 3 {
		t.Fatalf("artifact count: got %d, want 3", len(got.Artifacts))
	}
	want := []string{"a/v1/file.json", "m/v1/file.json", "z/v1/file.json"}
	for i, a := range got.Artifacts {
		if a.Key != want[i] {
			t.Errorf("artifacts[%d].key: got %q, want %q", i, a.Key, want[i])
		}
	}
}

func TestSchemaVersionExtraction(t *testing.T) {
	ts := time.Date(2026, 5, 17, 11, 30, 0, 0, time.UTC)
	store := &mockStore{
		objects: []manifest.ObjectInfo{
			{Key: "dataset/v3/all.json", SizeBytes: 100, ETag: `"x"`, LastModified: ts},
			{Key: "other/flat.json", SizeBytes: 50, ETag: `"y"`, LastModified: ts},
		},
		metas: map[string]manifest.ObjectMeta{
			"dataset/v3/all.json": {ContentHashSHA256: "sha256-dataset"},
			"other/flat.json":     {ContentHashSHA256: "sha256-other"},
		},
	}
	uc := manifest.NewGenerateManifest(store)

	if err := uc.Execute(context.Background(), "test-bucket"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var got manifest.Manifest
	if err := json.Unmarshal(store.written, &got); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	// sorted: dataset before other
	if got.Artifacts[0].SchemaVersion != 3 {
		t.Errorf("dataset/v3: schema_version got %d, want 3", got.Artifacts[0].SchemaVersion)
	}
	if got.Artifacts[1].SchemaVersion != 1 {
		t.Errorf("other/flat.json: schema_version got %d, want 1 (default)", got.Artifacts[1].SchemaVersion)
	}
}

func TestMissingHashMetadataFails(t *testing.T) {
	ts := time.Date(2026, 5, 17, 11, 30, 0, 0, time.UTC)
	store := &mockStore{
		objects: []manifest.ObjectInfo{
			{Key: "members/v1/all.json", SizeBytes: 1000, ETag: `"abc"`, LastModified: ts},
		},
		// metas omits the key → HeadObject returns empty ContentHashSHA256
		metas: map[string]manifest.ObjectMeta{},
	}
	uc := manifest.NewGenerateManifest(store)

	err := uc.Execute(context.Background(), "test-bucket")
	if err == nil {
		t.Fatal("expected error for missing content_hash_sha256, got nil")
	}
}

func TestManifestContractSampleMatchesWriterAndSchema(t *testing.T) {
	ts := time.Date(2026, 5, 17, 11, 30, 0, 0, time.UTC)
	store := &mockStore{
		objects: []manifest.ObjectInfo{
			{Key: "members/v1/all.json", SizeBytes: 123456, ETag: `"abc123"`, LastModified: ts},
			{Key: "sittings/v1/all.json", SizeBytes: 45678, ETag: `"def456"`, LastModified: ts},
		},
		metas: map[string]manifest.ObjectMeta{
			"members/v1/all.json":  {ContentHashSHA256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
			"sittings/v1/all.json": {ContentHashSHA256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"},
		},
	}
	uc := manifest.NewGenerateManifestWithClock(store, func() time.Time {
		return time.Date(2026, 5, 17, 12, 0, 0, 0, time.UTC)
	})

	if err := uc.Execute(context.Background(), "test-bucket"); err != nil {
		t.Fatalf("generate manifest: %v", err)
	}

	samplePath := filepath.Join("testdata", "manifest.sample.json")
	want, err := os.ReadFile(samplePath)
	if err != nil {
		t.Fatalf("read sample manifest: %v", err)
	}
	if !bytes.Equal(bytes.TrimSpace(store.written), bytes.TrimSpace(want)) {
		t.Fatalf("generated manifest does not match %s\n--- got ---\n%s\n--- want ---\n%s", samplePath, store.written, want)
	}

	var decoded manifest.Manifest
	if err := json.Unmarshal(want, &decoded); err != nil {
		t.Fatalf("sample does not decode as manifest.Manifest: %v", err)
	}

	schemaData, err := os.ReadFile("manifest.schema.json")
	if err != nil {
		t.Fatalf("read manifest schema: %v", err)
	}
	var schemaDoc any
	if err := json.Unmarshal(schemaData, &schemaDoc); err != nil {
		t.Fatalf("decode manifest schema: %v", err)
	}
	compiler := jsonschema.NewCompiler()
	if err := compiler.AddResource("manifest.schema.json", schemaDoc); err != nil {
		t.Fatalf("add schema resource: %v", err)
	}
	schema, err := compiler.Compile("manifest.schema.json")
	if err != nil {
		t.Fatalf("compile manifest schema: %v", err)
	}
	var sample any
	if err := json.Unmarshal(want, &sample); err != nil {
		t.Fatalf("decode sample for schema validation: %v", err)
	}
	if err := schema.Validate(sample); err != nil {
		t.Fatalf("sample does not validate against manifest.schema.json: %v", err)
	}
}
