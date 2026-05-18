package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWriteArtifactsWritesIndexAndBoundary(t *testing.T) {
	dir := t.TempDir()
	err := writeArtifacts(dir, []boundaryResponse{{
		Slug:       "spadina-harbourfront",
		Name:       "Spadina-Harbourfront",
		ExternalID: "35100",
	}})
	if err != nil {
		t.Fatalf("writeArtifacts error: %v", err)
	}
	for _, key := range []string{
		"v1/index.json",
		"v1/boundary/spadina-harbourfront.json",
	} {
		if _, err := os.Stat(filepath.Join(dir, filepath.FromSlash(key))); err != nil {
			t.Fatalf("expected %s to be written: %v", key, err)
		}
	}
}
