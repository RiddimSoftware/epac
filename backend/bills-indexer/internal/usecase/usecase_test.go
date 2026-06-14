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

// TestExecuteComputesVersionDiffsDuringIngest proves the use case composes the
// clause-diff policy over the fetched batch: the source supplies a two-version
// bill with parsed sections but no diffs, and the batch handed to the writer
// must carry the computed diff. This guards the composition step in Execute,
// not just the standalone ComputeBillVersionDiff policy.
func TestExecuteComputesVersionDiffsDuringIngest(t *testing.T) {
	bill := domain.Bill{
		ID:        "13543613",
		Number:    "C-2",
		SourceURL: "https://example.test/bill",
		Versions: []domain.BillVersion{
			{ID: "v1", SortOrder: 1, Sections: []domain.VersionSection{{Label: "1", Text: "Hello"}}},
			{ID: "v2", SortOrder: 2, Sections: []domain.VersionSection{{Label: "1", Text: "Hello World"}}},
		},
	}
	source := fakeSource{batch: domain.Batch{Bills: []domain.Bill{bill}}}
	writer := &fakeWriter{stats: domain.Stats{TableCounts: map[string]int{"bills": 1}}}
	uploader := fakeUploader{hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", size: 42}
	manifest := &fakeManifestWriter{}

	uc, err := NewIngestBills(source, writer, uploader, manifest, WithDatabasePath("/tmp/test-bills.db"))
	if err != nil {
		t.Fatalf("NewIngestBills: %v", err)
	}
	if _, err := uc.Execute(context.Background(), Input{Session: domain.Session{ParliamentNumber: 45, SessionNumber: 1}, Prefix: "bills/v1"}); err != nil {
		t.Fatalf("Execute: %v", err)
	}

	if len(writer.batch.Bills) != 1 {
		t.Fatalf("writer batch bills = %d", len(writer.batch.Bills))
	}
	diffs := writer.batch.Bills[0].Diffs
	if len(diffs) != 1 {
		t.Fatalf("expected 1 computed diff in ingested batch, got %d", len(diffs))
	}
	if diffs[0].FromVersionID != "v1" || diffs[0].ToVersionID != "v2" || diffs[0].SourceURL != "https://example.test/bill" {
		t.Errorf("unexpected diff record: %+v", diffs[0])
	}
	if len(diffs[0].Clauses) != 1 || diffs[0].Clauses[0].ChangeType != "modified" {
		t.Errorf("expected one modified clause, got: %+v", diffs[0].Clauses)
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
	batch domain.Batch
	stats domain.Stats
}

func (f *fakeWriter) Write(_ context.Context, path string, batch domain.Batch) (domain.Stats, error) {
	f.path = path
	f.batch = batch
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
