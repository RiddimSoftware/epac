package artifacts

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	sharedartifacts "epac/shared/artifacts"
)

func TestHansardRepositoryFiltersArtifactByMonthDayAndPastDate(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "on-this-day", "v1")
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir fixture: %v", err)
	}
	fixture := []byte(`{
  "items": [
    {"id":"past","kind":"speech","year":2021,"date":"2021-05-18","title":"Past","excerpt":"Past"},
    {"id":"same-day","kind":"speech","year":2026,"date":"2026-05-18","title":"Current","excerpt":"Current"},
    {"id":"different-day","kind":"speech","year":2020,"date":"2020-05-19","title":"Other","excerpt":"Other"},
    {"id":"invalid-date","kind":"speech","year":2020,"date":"not-a-date","title":"Invalid","excerpt":"Invalid"}
  ]
}`)
	if err := os.WriteFile(filepath.Join(path, "all.json"), fixture, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	repo := NewHansardRepository(sharedartifacts.NewLocalStore(dir))
	items, err := repo.OnThisDay(context.Background(), time.Date(2026, 5, 18, 0, 0, 0, 0, time.UTC), 10)
	if err != nil {
		t.Fatalf("OnThisDay returned error: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("len(items) = %d, want 1", len(items))
	}
	if items[0].ID != "past" {
		t.Fatalf("items[0].ID = %q, want past", items[0].ID)
	}
}

func TestHansardRepositoryAppliesLimit(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "on-this-day", "v1")
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir fixture: %v", err)
	}
	fixture := []byte(`{
  "items": [
    {"id":"first","kind":"speech","year":2021,"date":"2021-05-18","title":"First","excerpt":"First"},
    {"id":"second","kind":"speech","year":2020,"date":"2020-05-18","title":"Second","excerpt":"Second"}
  ]
}`)
	if err := os.WriteFile(filepath.Join(path, "all.json"), fixture, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	repo := NewHansardRepository(sharedartifacts.NewLocalStore(dir))
	items, err := repo.OnThisDay(context.Background(), time.Date(2026, 5, 18, 12, 0, 0, 0, time.UTC), 1)
	if err != nil {
		t.Fatalf("OnThisDay returned error: %v", err)
	}
	if len(items) != 1 || items[0].ID != "first" {
		t.Fatalf("items = %#v, want only first", items)
	}
}
