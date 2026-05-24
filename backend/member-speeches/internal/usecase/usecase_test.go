package usecase

import (
	"context"
	"errors"
	"testing"
)

type memoryHansardRepository struct {
	artifact MemberSpeechesArtifact
	err      error
}

func (r memoryHansardRepository) LoadMemberSpeeches(ctx context.Context, memberID string) (MemberSpeechesArtifact, error) {
	return r.artifact, r.err
}

func TestViewMemberSpeechFeedReturnsEmptyForMissingArtifact(t *testing.T) {
	resp, err := New(memoryHansardRepository{err: ErrNotFound}).Execute(context.Background(), "m-001", 1, DefaultPerPage, "")
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if resp.Total != 0 || len(resp.Speeches) != 0 {
		t.Fatalf("unexpected response: %#v", resp)
	}
}

func TestViewMemberSpeechFeedFiltersAndPaginates(t *testing.T) {
	budget := "Budget"
	health := "Health"
	date1 := "2026-01-01"
	date2 := "2026-01-02"
	seq := 1
	resp, err := New(memoryHansardRepository{
		artifact: MemberSpeechesArtifact{
			Speeches: []SpeechRecord{
				{InterventionID: "old", SittingDate: &date1, SubjectTitle: &budget, InterventionSeq: &seq},
				{InterventionID: "new", SittingDate: &date2, SubjectTitle: &budget, InterventionSeq: &seq},
				{InterventionID: "other", SittingDate: &date2, SubjectTitle: &health, InterventionSeq: &seq},
			},
		},
	}).Execute(context.Background(), "m-001", 1, 1, "budget")
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if resp.Total != 2 || resp.Pages != 2 || len(resp.Speeches) != 1 {
		t.Fatalf("unexpected pagination: %#v", resp)
	}
	if resp.Speeches[0].InterventionID != "new" {
		t.Fatalf("first speech = %q, want new", resp.Speeches[0].InterventionID)
	}
	if resp.Stats.TotalSpeeches != 3 {
		t.Fatalf("stats total = %d, want 3", resp.Stats.TotalSpeeches)
	}
}

func TestViewMemberSpeechFeedPropagatesRepositoryError(t *testing.T) {
	errDB := errors.New("load failed")
	_, err := New(memoryHansardRepository{err: errDB}).Execute(context.Background(), "m-001", 1, DefaultPerPage, "")
	if !errors.Is(err, errDB) {
		t.Fatalf("error = %v, want %v", err, errDB)
	}
}
