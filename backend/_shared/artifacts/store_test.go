package artifacts

import (
	"context"
	"os"
	"path/filepath"
	"testing"
)

func TestLocalStoreReadsCleanKey(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "members", "v1")
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(path, "all.json"), []byte(`{"members":[]}`), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	store := NewLocalStore(dir)
	data, err := store.Get(context.Background(), "members/v1/all.json")
	if err != nil {
		t.Fatalf("Get returned error: %v", err)
	}
	if string(data) != `{"members":[]}` {
		t.Fatalf("body = %s", data)
	}
}

func TestLocalStoreMissingMapsToNotFound(t *testing.T) {
	store := NewLocalStore(t.TempDir())
	_, err := store.Get(context.Background(), "missing.json")
	if !IsNotFound(err) {
		t.Fatalf("IsNotFound(%v) = false", err)
	}
}
