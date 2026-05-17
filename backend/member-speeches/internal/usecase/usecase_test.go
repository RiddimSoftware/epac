package usecase

import (
	"context"
	"errors"
	"testing"
)

type fakeRepo struct {
	count           int
	countErr        error
	speeches        []SpeechEntry
	speechesErr     error
	stats           MemberStats
	statsErr        error
	lastCountTopic  string
	lastFetchTopic  string
	lastFetchPage   int
	lastFetchPer    int
	lastFetchMember string
}

func (r *fakeRepo) CountMemberSpeeches(ctx context.Context, memberId, topic string) (int, error) {
	r.lastCountTopic = topic
	return r.count, r.countErr
}

func (r *fakeRepo) FetchMemberSpeeches(ctx context.Context, memberId string, page, perPage int, topic string) ([]SpeechEntry, error) {
	r.lastFetchMember = memberId
	r.lastFetchPage = page
	r.lastFetchPer = perPage
	r.lastFetchTopic = topic
	return r.speeches, r.speechesErr
}

func (r *fakeRepo) MemberStats(ctx context.Context, memberId string) (MemberStats, error) {
	return r.stats, r.statsErr
}

func TestExecute_PagesAreCeilingOfTotalOverPerPage(t *testing.T) {
	repo := &fakeRepo{count: 25}
	uc := New(repo)

	resp, err := uc.Execute(context.Background(), "m-1", 1, 10, "")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if resp.Pages != 3 {
		t.Fatalf("Pages = %d, want 3", resp.Pages)
	}
	if resp.Total != 25 {
		t.Fatalf("Total = %d, want 25", resp.Total)
	}
}

func TestExecute_PropagatesInputs(t *testing.T) {
	repo := &fakeRepo{count: 0}
	uc := New(repo)

	_, err := uc.Execute(context.Background(), "m-42", 3, 50, "housing")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if repo.lastFetchMember != "m-42" {
		t.Fatalf("memberId = %q, want m-42", repo.lastFetchMember)
	}
	if repo.lastFetchPage != 3 || repo.lastFetchPer != 50 {
		t.Fatalf("page/perPage = %d/%d, want 3/50", repo.lastFetchPage, repo.lastFetchPer)
	}
	if repo.lastFetchTopic != "housing" || repo.lastCountTopic != "housing" {
		t.Fatalf("topic plumbing: fetch=%q count=%q", repo.lastFetchTopic, repo.lastCountTopic)
	}
}

func TestExecute_ReturnsRepoError(t *testing.T) {
	want := errors.New("boom")
	cases := map[string]*fakeRepo{
		"count":    {countErr: want},
		"speeches": {speechesErr: want},
		"stats":    {statsErr: want},
	}
	for name, repo := range cases {
		t.Run(name, func(t *testing.T) {
			uc := New(repo)
			_, err := uc.Execute(context.Background(), "m-1", 1, 10, "")
			if !errors.Is(err, want) {
				t.Fatalf("err = %v, want %v", err, want)
			}
		})
	}
}
