package artifacts

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/estimates/internal/usecase"
	sharedartifacts "epac/shared/artifacts"
)

func TestEstimatesRepositoryReadsAllArtifactAndFiltersFiscalYear(t *testing.T) {
	dir := t.TempDir()
	writeEstimatesFixture(t, filepath.Join(dir, "estimates", "v1", "all.json"), []usecase.Estimate{
		{FiscalYear: "2024-25", OrganizationID: 1, OrganizationName: "House", VoteNumber: 1},
		{FiscalYear: "2025-26", OrganizationID: 1, OrganizationName: "House", VoteNumber: 2},
	})

	year := "2025-26"
	repo := NewEstimatesRepository(sharedartifacts.NewLocalStore(dir))
	got, err := repo.FetchEstimates(context.Background(), usecase.EstimatesFilter{FiscalYear: &year})
	if err != nil {
		t.Fatalf("FetchEstimates returned error: %v", err)
	}
	if len(got) != 1 || got[0].FiscalYear != "2025-26" {
		t.Fatalf("got %#v, want only 2025-26", got)
	}
}

func TestEstimatesRepositoryReadsByOrgArtifact(t *testing.T) {
	dir := t.TempDir()
	writeEstimatesFixture(t, filepath.Join(dir, "estimates", "v1", "by-org", "44.json"), []usecase.Estimate{
		{FiscalYear: "2025-26", OrganizationID: 44, OrganizationName: "Library", VoteNumber: 1},
	})

	orgID := 44
	repo := NewEstimatesRepository(sharedartifacts.NewLocalStore(dir))
	got, err := repo.FetchEstimates(context.Background(), usecase.EstimatesFilter{OrgID: &orgID})
	if err != nil {
		t.Fatalf("FetchEstimates returned error: %v", err)
	}
	if len(got) != 1 || got[0].OrganizationID != 44 {
		t.Fatalf("got %#v, want org 44", got)
	}
}

func writeEstimatesFixture(t *testing.T, path string, estimates []usecase.Estimate) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir fixture: %v", err)
	}
	data := usecase.EstimatesResponse{Estimates: estimates}
	body, err := json.Marshal(data)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	if err := os.WriteFile(path, body, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
