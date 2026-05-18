package usecase

import (
	"context"
	"errors"
	"testing"
)

type memoryEstimatesRepository struct {
	estimates []Estimate
	failVote  int
	recorded  int
}

func (r *memoryEstimatesRepository) FetchEstimates(ctx context.Context, filter EstimatesFilter) ([]Estimate, error) {
	return r.estimates, nil
}

func (r *memoryEstimatesRepository) UpsertOrganization(ctx context.Context, org OrgRecord) error {
	return nil
}

func (r *memoryEstimatesRepository) UpsertEstimate(ctx context.Context, est Estimate) error {
	if est.VoteNumber == r.failVote {
		return errors.New("insert failed")
	}
	return nil
}

func (r *memoryEstimatesRepository) RecordHealth(ctx context.Context, count int, runErr error) {
	r.recorded = count
}

func TestGetEstimatesRejectsEmptyFilter(t *testing.T) {
	_, err := NewGet(&memoryEstimatesRepository{}).Execute(context.Background(), EstimatesFilter{})
	if !errors.Is(err, ErrInvalidFilter) {
		t.Fatalf("error = %v, want ErrInvalidFilter", err)
	}
}

func TestIngestEstimatesCountsSuccessfulRows(t *testing.T) {
	repo := &memoryEstimatesRepository{failVote: 2}
	count, err := NewIngest(repo).Execute(context.Background(), IngestInput{
		Organizations: []OrgRecord{{ID: 1, Name: "House of Commons"}},
		Estimates: []Estimate{
			{FiscalYear: "2024-25", OrganizationID: 1, VoteNumber: 1},
			{FiscalYear: "2024-25", OrganizationID: 1, VoteNumber: 2},
		},
	})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if count != 1 {
		t.Fatalf("count = %d, want 1", count)
	}
	if repo.recorded != 1 {
		t.Fatalf("recorded health count = %d, want 1", repo.recorded)
	}
}
