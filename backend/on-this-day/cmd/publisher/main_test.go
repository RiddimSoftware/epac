package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/on-this-day/internal/usecase"
)

func TestWriteJSONCreatesArtifact(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v1", "all.json")
	want := allResponse{
		Items: []usecase.OnThisDayItem{{
			ID:      "speech-1",
			Kind:    "speech",
			Year:    2021,
			Date:    "2021-05-18",
			Title:   "A speech",
			Excerpt: "Excerpt",
		}},
	}

	if err := writeJSON(path, want); err != nil {
		t.Fatalf("writeJSON returned error: %v", err)
	}

	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read artifact: %v", err)
	}
	var got allResponse
	if err := json.Unmarshal(data, &got); err != nil {
		t.Fatalf("unmarshal artifact: %v", err)
	}
	if len(got.Items) != 1 || got.Items[0].ID != "speech-1" {
		t.Fatalf("got %#v, want speech-1", got.Items)
	}
}
