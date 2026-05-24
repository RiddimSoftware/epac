package membercontent

import (
	"context"
	"encoding/json"
	"testing"
)

func TestListMemberSpeechesFiltersAndPaginates(t *testing.T) {
	ctx := context.Background()
	store := FileStore{Root: t.TempDir()}
	dateOld := "2024-01-01"
	dateNew := "2024-01-02"
	housing := "Housing"
	budget := "Budget"
	seq := 1

	if _, err := WriteMemberSpeechesArtifacts(ctx, store, MemberSpeechesArtifact{
		MemberID: "m-1",
		Speeches: []SpeechRecord{
			{InterventionID: "old", SittingDate: &dateOld, SubjectTitle: &budget, Preview: "old", Filename: "HAN001-E.XML", InterventionSeq: &seq},
			{InterventionID: "new", SittingDate: &dateNew, SubjectTitle: &housing, Preview: "new", Filename: "HAN002-E.XML", InterventionSeq: &seq},
		},
	}); err != nil {
		t.Fatalf("write artifacts: %v", err)
	}

	got, err := ListMemberSpeeches(ctx, store, "m-1", 1, 20, "housing")
	if err != nil {
		t.Fatalf("list speeches: %v", err)
	}
	if got.Total != 1 {
		t.Fatalf("total = %d, want 1", got.Total)
	}
	if len(got.Speeches) != 1 || got.Speeches[0].InterventionID != "new" {
		t.Fatalf("speeches = %+v, want filtered newest speech", got.Speeches)
	}
	if got.Stats.TotalSpeeches != 2 {
		t.Fatalf("stats.total_speeches = %d, want 2", got.Stats.TotalSpeeches)
	}
}

func TestListMemberVotesReadsIndexPages(t *testing.T) {
	ctx := context.Background()
	store := FileStore{Root: t.TempDir()}
	oldDate := "2024-01-01"
	newDate := "2024-01-02"

	writeJSON(t, ctx, store, votePageKey("m-1", "2024-01"), MemberVotesArtifact{
		MemberID: "m-1",
		Votes: []VoteEntry{
			{VoteID: "100", Date: &oldDate, Vote: "Nay"},
		},
	})
	writeJSON(t, ctx, store, votePageKey("m-1", "2024-02"), MemberVotesArtifact{
		MemberID: "m-1",
		Votes: []VoteEntry{
			{VoteID: "101", Date: &newDate, Vote: "Yea"},
		},
	})
	writeJSON(t, ctx, store, voteIndexKey("m-1"), ArtifactIndex{
		MemberID: "m-1",
		Pages: []ArtifactPage{
			{Key: votePageKey("m-1", "2024-01"), Count: 1},
			{Key: votePageKey("m-1", "2024-02"), Count: 1},
		},
	})

	got, err := ListMemberVotes(ctx, store, "m-1", 1, 1)
	if err != nil {
		t.Fatalf("list votes: %v", err)
	}
	if got.Total != 2 || got.Pages != 2 {
		t.Fatalf("total/pages = %d/%d, want 2/2", got.Total, got.Pages)
	}
	if len(got.Votes) != 1 || got.Votes[0].VoteID != "101" {
		t.Fatalf("votes = %+v, want newest vote first", got.Votes)
	}
}

func writeJSON(t *testing.T, ctx context.Context, store Store, key string, value any) {
	t.Helper()
	body, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal %s: %v", key, err)
	}
	if err := store.Put(ctx, key, body); err != nil {
		t.Fatalf("put %s: %v", key, err)
	}
}
