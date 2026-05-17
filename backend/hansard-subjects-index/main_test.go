package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"

	"epac/hansard-subjects-index/application"
)

func TestWriteArtifactsWritesCompactAllJSONAndMetadata(t *testing.T) {
	index := testIndex(1)
	outputDir := t.TempDir()

	artifacts, err := writeArtifacts(outputDir, index, defaultMaxGzipBytes)
	if err != nil {
		t.Fatalf("write artifacts: %v", err)
	}
	if len(artifacts) != 1 {
		t.Fatalf("artifact count = %d, want 1", len(artifacts))
	}
	if artifacts[0].Path != defaultArtifactPath {
		t.Fatalf("path = %q", artifacts[0].Path)
	}
	if artifacts[0].SHA256 == "" || artifacts[0].GzipBytes == 0 {
		t.Fatalf("metadata missing hash/size: %#v", artifacts[0])
	}

	raw, err := os.ReadFile(filepath.Join(outputDir, "hansard-subjects/v1/all.json"))
	if err != nil {
		t.Fatalf("read artifact: %v", err)
	}
	if !json.Valid(raw) {
		t.Fatalf("artifact is not valid JSON: %s", raw)
	}
	if string(raw[:1]) == "\n" {
		t.Fatal("artifact should be compact JSON, not pretty output")
	}

	metaRaw, err := os.ReadFile(filepath.Join(outputDir, "hansard-subjects/v1/all.json.metadata.json"))
	if err != nil {
		t.Fatalf("read metadata: %v", err)
	}
	var meta artifactMetadata
	if err := json.Unmarshal(metaRaw, &meta); err != nil {
		t.Fatalf("parse metadata: %v", err)
	}
	if meta.SHA256 != artifacts[0].SHA256 {
		t.Fatalf("metadata sha = %q, want %q", meta.SHA256, artifacts[0].SHA256)
	}
}

func TestDefaultWindowArtifactStaysUnderTwoMBGzipped(t *testing.T) {
	index := testIndex(50000)
	meta, _, err := marshalArtifact(defaultArtifactPath, index)
	if err != nil {
		t.Fatalf("marshal artifact: %v", err)
	}
	if meta.GzipBytes >= defaultMaxGzipBytes {
		t.Fatalf("gzip size = %d, want under %d", meta.GzipBytes, defaultMaxGzipBytes)
	}
}

func TestWriteArtifactsPaginatesOversizedOutput(t *testing.T) {
	index := testIndex(20)
	outputDir := t.TempDir()

	artifacts, err := writeArtifacts(outputDir, index, 260)
	if err != nil {
		t.Fatalf("write paginated artifacts: %v", err)
	}
	if len(artifacts) < 2 {
		t.Fatalf("artifact count = %d, want pages plus index", len(artifacts))
	}
	if artifacts[len(artifacts)-1].Path != "hansard-subjects/v1/subjects-index.json" {
		t.Fatalf("last artifact = %q, want index", artifacts[len(artifacts)-1].Path)
	}
	if _, err := os.Stat(filepath.Join(outputDir, "hansard-subjects/v1/all-001.json")); err != nil {
		t.Fatalf("expected first page: %v", err)
	}
}

func testIndex(count int) application.Index {
	subjects := make([]application.IndexSubject, 0, count)
	for i := 0; i < count; i++ {
		subjects = append(subjects, application.IndexSubject{
			SubjectID:    fmt.Sprintf("subject-%05d", i),
			SubjectTitle: fmt.Sprintf("Budget and housing affordability debate %05d", i),
			HansardDate:  "2026-05-17",
		})
	}
	return application.Index{
		SchemaVersion: application.SchemaVersion,
		GeneratedAt:   time.Date(2026, 5, 17, 12, 0, 0, 0, time.UTC).Format(time.RFC3339),
		Window: application.IndexWindow{
			From: "2020-01-01",
			To:   "2026-05-17",
		},
		Subjects: subjects,
	}
}
