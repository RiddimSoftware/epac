package usecase

import (
	"context"
	"testing"
	"time"

	"epac/members-indexer/internal/domain"
)

func TestIngestMembersBuildsSQLiteAndManifest(t *testing.T) {
	source := fakeSource{batch: domain.Batch{Members: []domain.Member{{ID: "89156", Name: "Jane Example"}}}}
	writer := &fakeWriter{stats: domain.Stats{
		BuiltAt:     time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC),
		TableCounts: map[string]int{"members": 1},
	}}
	uploader := fakeUploader{hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 42}
	manifest := &fakeManifestWriter{}

	uc, err := NewIngestMembers(source, writer, uploader, manifest, WithDatabasePath("/tmp/test-members.db"))
	if err != nil {
		t.Fatalf("NewIngestMembers: %v", err)
	}
	out, err := uc.Execute(context.Background(), Input{Prefix: "members/v1"})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if writer.path != "/tmp/test-members.db" {
		t.Fatalf("writer path = %q", writer.path)
	}
	if out.Manifest.SQLiteKey != "members/v1/index.sqlite" {
		t.Fatalf("sqlite key = %q", out.Manifest.SQLiteKey)
	}
	if manifest.got.TableCounts["members"] != 1 {
		t.Fatalf("manifest table counts = %#v", manifest.got.TableCounts)
	}
}

type fakeSource struct {
	batch domain.Batch
}

func (f fakeSource) FetchMembers(context.Context) (domain.Batch, error) {
	return f.batch, nil
}

type fakeWriter struct {
	path  string
	stats domain.Stats
}

func (f *fakeWriter) Write(_ context.Context, path string, _ domain.Batch) (domain.Stats, error) {
	f.path = path
	return f.stats, nil
}

type fakeUploader struct {
	hash string
	size int64
}

func (f fakeUploader) Upload(context.Context, string, string) (string, int64, error) {
	return f.hash, f.size, nil
}

type fakeManifestWriter struct {
	got domain.Manifest
}

func (f *fakeManifestWriter) Write(_ context.Context, manifest domain.Manifest) error {
	f.got = manifest
	return nil
}
