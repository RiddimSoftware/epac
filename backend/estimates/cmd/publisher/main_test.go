package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/estimates/internal/usecase"
)

func TestWriteArtifactsWritesAllAndPerOrganizationFiles(t *testing.T) {
	dir := t.TempDir()
	estimates := []usecase.Estimate{
		{FiscalYear: "2025-26", OrganizationID: 2, OrganizationName: "Senate", VoteNumber: 1},
		{FiscalYear: "2025-26", OrganizationID: 1, OrganizationName: "House", VoteNumber: 1},
		{FiscalYear: "2024-25", OrganizationID: 1, OrganizationName: "House", VoteNumber: 2},
	}

	if err := writeArtifacts(dir, estimates); err != nil {
		t.Fatalf("writeArtifacts returned error: %v", err)
	}

	all := readResponse(t, filepath.Join(dir, "v1", "all.json"))
	if len(all.Estimates) != 3 {
		t.Fatalf("len(all.Estimates) = %d, want 3", len(all.Estimates))
	}
	house := readResponse(t, filepath.Join(dir, "v1", "by-org", "1.json"))
	if len(house.Estimates) != 2 {
		t.Fatalf("len(house.Estimates) = %d, want 2", len(house.Estimates))
	}
	senate := readResponse(t, filepath.Join(dir, "v1", "by-org", "2.json"))
	if len(senate.Estimates) != 1 || senate.Estimates[0].OrganizationID != 2 {
		t.Fatalf("senate = %#v, want org 2", senate.Estimates)
	}
}

func readResponse(t *testing.T, path string) usecase.EstimatesResponse {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	var resp usecase.EstimatesResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("unmarshal %s: %v", path, err)
	}
	return resp
}
