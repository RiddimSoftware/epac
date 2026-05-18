package usecase

import (
	"context"
	"testing"
)

type memoryHansardRepository struct {
	context SearchContext
	results []SearchResult
}

func (r *memoryHansardRepository) SearchSpeeches(ctx context.Context, params SearchParams, languageHint string, searchContext SearchContext, cfg RankingConfig) ([]SearchResult, error) {
	r.context = searchContext
	return r.results, nil
}

type memoryMemberRepository struct {
	context SearchContext
}

func (r memoryMemberRepository) LoadSearchContext(ctx context.Context, userID string) (SearchContext, error) {
	return r.context, nil
}

func TestSearchHansardAddsTopicKeywordHints(t *testing.T) {
	hansard := &memoryHansardRepository{
		results: []SearchResult{{ID: "speech-1", Title: "Budget", Snippet: "housing budget"}},
	}
	member := memoryMemberRepository{
		context: SearchContext{TopicIDs: []string{"housing", "defence"}},
	}

	resp, err := New(hansard, member).Execute(context.Background(), SearchParams{Query: "housing"}, RankingConfig{})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if resp.LanguageHint != "en" {
		t.Fatalf("LanguageHint = %q, want en", resp.LanguageHint)
	}
	if len(resp.Results) != 1 {
		t.Fatalf("got %d results, want 1", len(resp.Results))
	}
	if !contains(hansard.context.TopicKeywordHints, "affordable housing") {
		t.Fatalf("missing topic keyword hints: %#v", hansard.context.TopicKeywordHints)
	}
}

func TestSearchHansardReturnsEmptySlice(t *testing.T) {
	resp, err := New(&memoryHansardRepository{}, memoryMemberRepository{}).Execute(context.Background(), SearchParams{Query: "budget"}, RankingConfig{})
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if resp.Results == nil {
		t.Fatal("Results is nil, want empty slice")
	}
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}
