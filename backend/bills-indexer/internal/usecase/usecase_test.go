package usecase

import (
	"context"
	"testing"
	"time"

	"epac/bills-indexer/internal/domain"
)

func TestIngestBillsBuildsSQLiteAndManifest(t *testing.T) {
	source := fakeSource{batch: domain.Batch{Bills: []domain.Bill{{ID: "13543613", Number: "C-2"}}}}
	writer := &fakeWriter{stats: domain.Stats{
		BuiltAt:     time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC),
		Parliament:  45,
		Session:     1,
		TableCounts: map[string]int{"bills": 1},
	}}
	uploader := fakeUploader{hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 42}
	manifest := &fakeManifestWriter{}

	uc, err := NewIngestBills(source, writer, uploader, manifest, WithDatabasePath("/tmp/test-bills.db"))
	if err != nil {
		t.Fatalf("NewIngestBills: %v", err)
	}
	out, err := uc.Execute(context.Background(), Input{Session: domain.Session{ParliamentNumber: 45, SessionNumber: 1}, Prefix: "bills/v1"})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}

	if writer.path != "/tmp/test-bills.db" {
		t.Fatalf("writer path = %q", writer.path)
	}
	if out.Manifest.SQLiteKey != "bills/v1/index.sqlite" {
		t.Fatalf("sqlite key = %q", out.Manifest.SQLiteKey)
	}
	if manifest.got.TableCounts["bills"] != 1 {
		t.Fatalf("manifest table counts = %#v", manifest.got.TableCounts)
	}
}

type fakeSource struct {
	batch domain.Batch
}

func (f fakeSource) FetchBills(context.Context, domain.Session) (domain.Batch, error) {
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
