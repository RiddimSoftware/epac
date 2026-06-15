package usecase

import (
	"context"
	"errors"
	"testing"

	"epac/bills/internal/domain"
)

func TestLoadBillVersionDiffReturnsRepositoryDiff(t *testing.T) {
	repo := &fakeBillRepository{
		diff: &domain.BillVersionDiff{
			From: domain.BillVersion{ID: "v1"},
			To:   domain.BillVersion{ID: "v2"},
			Clauses: []domain.BillClauseDiff{{
				ID:         "clause-1",
				ChangeType: "modified",
				FromText:   "Old",
				ToText:     "New",
			}},
		},
	}

	diff, err := NewLoadBillVersionDiff(repo).Execute(context.Background(), LoadBillVersionDiffInput{
		BillID:        " C-2 ",
		FromVersionID: " v1 ",
		ToVersionID:   " v2 ",
	})
	if err != nil {
		t.Fatalf("Execute error: %v", err)
	}
	if diff == nil || diff.From.ID != "v1" || diff.To.ID != "v2" || len(diff.Clauses) != 1 {
		t.Fatalf("diff = %+v", diff)
	}
	if repo.billID != "C-2" || repo.fromVersionID != "v1" || repo.toVersionID != "v2" {
		t.Fatalf("repo input = %q/%q/%q", repo.billID, repo.fromVersionID, repo.toVersionID)
	}
}

func TestLoadBillVersionDiffValidatesRequiredInput(t *testing.T) {
	tests := []struct {
		name  string
		input LoadBillVersionDiffInput
		want  error
	}{
		{
			name:  "missing bill",
			input: LoadBillVersionDiffInput{FromVersionID: "v1", ToVersionID: "v2"},
			want:  ErrBillNotFound,
		},
		{
			name:  "missing from",
			input: LoadBillVersionDiffInput{BillID: "C-2", ToVersionID: "v2"},
			want:  ErrDiffMissingFrom,
		},
		{
			name:  "missing to",
			input: LoadBillVersionDiffInput{BillID: "C-2", FromVersionID: "v1"},
			want:  ErrDiffMissingTo,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeBillRepository{}
			diff, err := NewLoadBillVersionDiff(repo).Execute(context.Background(), tt.input)
			if !errors.Is(err, tt.want) {
				t.Fatalf("error = %v, want %v", err, tt.want)
			}
			if diff != nil {
				t.Fatalf("diff = %+v, want nil", diff)
			}
			if repo.called {
				t.Fatal("repository should not be called for invalid input")
			}
		})
	}
}

func TestLoadBillVersionDiffMapsEmptyClauseDiffToUnavailable(t *testing.T) {
	repo := &fakeBillRepository{
		diff: &domain.BillVersionDiff{
			From:    domain.BillVersion{ID: "v1"},
			To:      domain.BillVersion{ID: "v2"},
			Clauses: []domain.BillClauseDiff{},
		},
	}

	diff, err := NewLoadBillVersionDiff(repo).Execute(context.Background(), LoadBillVersionDiffInput{
		BillID:        "C-2",
		FromVersionID: "v1",
		ToVersionID:   "v2",
	})
	if err != nil {
		t.Fatalf("Execute error: %v", err)
	}
	if diff != nil {
		t.Fatalf("diff = %+v, want nil", diff)
	}
}

func TestLoadBillVersionDiffReturns204ForSameVersion(t *testing.T) {
	repo := &fakeBillRepository{}
	diff, err := NewLoadBillVersionDiff(repo).Execute(context.Background(), LoadBillVersionDiffInput{
		BillID:        "C-2",
		FromVersionID: "v1",
		ToVersionID:   "v1",
	})
	if err != nil {
		t.Fatalf("Execute error: %v", err)
	}
	if diff != nil {
		t.Fatalf("expected nil diff for same version comparison, got %+v", diff)
	}
	if repo.called {
		t.Fatal("repository should not be called for same version comparison")
	}
}

func TestLoadBillVersionDiffReturnsEmptyClausesForIdenticalText(t *testing.T) {
	repo := &fakeBillRepository{
		diff: &domain.BillVersionDiff{
			From: domain.BillVersion{ID: "v1"},
			To:   domain.BillVersion{ID: "v2"},
			Clauses: []domain.BillClauseDiff{
				{
					ID:         "c1",
					ChangeType: "unchanged",
					FromText:   "Same",
					ToText:     "Same",
				},
				{
					ID:         "c2",
					ChangeType: "unchanged",
					FromText:   "Also Same",
					ToText:     "Also Same",
				},
			},
		},
	}

	diff, err := NewLoadBillVersionDiff(repo).Execute(context.Background(), LoadBillVersionDiffInput{
		BillID:        "C-2",
		FromVersionID: "v1",
		ToVersionID:   "v2",
	})
	if err != nil {
		t.Fatalf("Execute error: %v", err)
	}
	if diff == nil {
		t.Fatal("expected non-nil diff for identical versions")
	}
	if len(diff.Clauses) != 0 {
		t.Fatalf("expected empty clauses slice, got %d clauses: %+v", len(diff.Clauses), diff.Clauses)
	}
}

type fakeBillRepository struct {
	diff          *domain.BillVersionDiff
	err           error
	called        bool
	billID        string
	fromVersionID string
	toVersionID   string
}

func (f *fakeBillRepository) ListBills(context.Context) ([]domain.Bill, error) {
	return nil, nil
}

func (f *fakeBillRepository) GetBillDepth(context.Context, string) (domain.Bill, error) {
	return domain.Bill{}, nil
}

func (f *fakeBillRepository) GetBillCommitteeStage(context.Context, string) (*domain.BillCommitteeStage, error) {
	return nil, nil
}

func (f *fakeBillRepository) GetBillVersionDiff(_ context.Context, billID, fromVersionID, toVersionID string) (*domain.BillVersionDiff, error) {
	f.called = true
	f.billID = billID
	f.fromVersionID = fromVersionID
	f.toVersionID = toVersionID
	return f.diff, f.err
}
