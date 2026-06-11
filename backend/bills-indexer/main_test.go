package main

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"os"
	"testing"
	"time"

	"epac/bills-indexer/internal/domain"
	"epac/bills-indexer/internal/usecase"
)

func TestLifecycleLogging(t *testing.T) {
	oldStderr := os.Stderr
	r, w, _ := os.Pipe()
	os.Stderr = w
	defer func() { os.Stderr = oldStderr }()

	source := &fakeSource{
		batch: domain.Batch{Bills: []domain.Bill{{ID: "13543613", Number: "C-2"}}},
		log:   func(p map[string]any) { logJSON(p) },
	}
	writer := &fakeWriter{stats: domain.Stats{
		BuiltAt:     time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC),
		Parliament:  45,
		Session:     1,
		TableCounts: map[string]int{"bills": 1},
	}}
	uploader := &fakeUploader{
		hash: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
		size: 42,
		log:  func(p map[string]any) { logJSON(p) },
	}
	manifest := &fakeManifestWriter{}

	err := runPipeline(
		context.Background(),
		domain.Session{ParliamentNumber: 45, SessionNumber: 1},
		"bills/v1",
		"my-bucket",
		source,
		writer,
		uploader,
		manifest,
		"/tmp/test-bills.db",
	)
	if err != nil {
		t.Fatalf("runPipeline failed: %v", err)
	}

	w.Close()
	os.Stderr = oldStderr
	out, _ := io.ReadAll(r)

	lines := bytes.Split(bytes.TrimSpace(out), []byte("\n"))
	if len(lines) < 4 {
		t.Fatalf("expected at least 4 log lines, got %d:\n%s", len(lines), string(out))
	}

	assertEvent := func(i int, expectedEvent string) {
		var payload map[string]any
		if err := json.Unmarshal(lines[i], &payload); err != nil {
			t.Fatalf("failed to parse log line %d: %v", i, err)
		}
		if payload["event"] != expectedEvent {
			t.Errorf("line %d: expected event %q, got %q", i, expectedEvent, payload["event"])
		}
	}

	assertEvent(0, "ingest_started")
	assertEvent(1, "fetch_completed")
	assertEvent(2, "upload_started")
	assertEvent(3, "artifact_uploaded")
}

type fakeSource struct {
	batch domain.Batch
	log   func(map[string]any)
}

func (f *fakeSource) FetchBills(_ context.Context, _ domain.Session) (domain.Batch, error) {
	if f.log != nil {
		f.log(map[string]any{"pipeline": "bills-indexer", "event": "fetch_completed", "count": len(f.batch.Bills)})
	}
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
	log  func(map[string]any)
}

func (f *fakeUploader) Upload(_ context.Context, _, _ string) (string, int64, error) {
	if f.log != nil {
		f.log(map[string]any{"pipeline": "bills-indexer", "event": "upload_started"})
	}
	return f.hash, f.size, nil
}

type fakeManifestWriter struct {
	got domain.Manifest
}

func (f *fakeManifestWriter) Write(_ context.Context, manifest domain.Manifest) error {
	f.got = manifest
	return nil
}
