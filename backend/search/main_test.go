package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_EmptyQuery(t *testing.T) {
	ctx := context.Background()
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{},
	}
	resp, err := HandleRequest(ctx, req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got status %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestHandleRequest_MissingDatabaseURL(t *testing.T) {
	os.Unsetenv("DATABASE_URL")
	ctx := context.Background()
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"query": "housing"},
	}
	resp, err := HandleRequest(ctx, req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusInternalServerError {
		t.Errorf("got status %d, want 500", resp.StatusCode)
	}
}

func TestHandleRequest_WhitespaceQuery(t *testing.T) {
	ctx := context.Background()
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"query": "   "},
	}
	resp, err := HandleRequest(ctx, req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("whitespace-only query: got status %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestDetectQueryLanguage(t *testing.T) {
	cases := []struct {
		query string
		want  string
	}{
		{"housing affordability", "en"},
		{"politique budgétaire", "fr"},
		{"sante logement", "fr"},
		{"budget", "en"},
	}
	for _, c := range cases {
		if got := detectQueryLanguage(c.query); got != c.want {
			t.Errorf("detectQueryLanguage(%q) = %q, want %q", c.query, got, c.want)
		}
	}
}

func TestParamsFromRequestAcceptsQAndFilters(t *testing.T) {
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{
			"q":         " housing ",
			"user_id":   " device-123 ",
			"from_date": "2026-01-01",
			"to_date":   "2026-04-29",
		},
	}

	params, err := paramsFromRequest(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if params.Query != "housing" {
		t.Fatalf("query = %q, want housing", params.Query)
	}
	if params.UserID != "device-123" {
		t.Fatalf("user_id = %q, want device-123", params.UserID)
	}
	assertDate(t, params.FromDate, "2026-01-01")
	assertDate(t, params.ToDate, "2026-04-29")
}

func TestParamsFromRequestKeepsLegacyQueryParameter(t *testing.T) {
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"query": "budget"},
	}

	params, err := paramsFromRequest(req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if params.Query != "budget" {
		t.Fatalf("query = %q, want budget", params.Query)
	}
}

func TestParamsFromRequestRejectsInvalidDateRange(t *testing.T) {
	req := events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{
			"q":         "housing",
			"from_date": "2026-05-01",
			"to_date":   "2026-04-01",
		},
	}

	if _, err := paramsFromRequest(req); err == nil {
		t.Fatal("expected invalid date range error")
	}
}

func TestRankingConfigFromEnv(t *testing.T) {
	t.Setenv("SEARCH_TEXT_WEIGHT", "0")
	t.Setenv("SEARCH_RECENCY_WEIGHT", "0.3")
	t.Setenv("SEARCH_FOLLOW_WEIGHT", "0.1")
	t.Setenv("SEARCH_RECENCY_HALFLIFE_DAYS", "45")
	t.Setenv("SEARCH_LANGUAGE_HINT_BOOST", "1.2")
	t.Setenv("SEARCH_MY_MP_BOOST", "1.1")
	t.Setenv("SEARCH_BILL_BOOST", "0.9")
	t.Setenv("SEARCH_TOPIC_BOOST", "0.7")

	cfg := rankingConfigFromEnv()
	if cfg.TextWeight != 0 || cfg.RecencyWeight != 0.3 || cfg.FollowWeight != 0.1 {
		t.Fatalf("unexpected component weights: %#v", cfg)
	}
	if cfg.RecencyHalfLife != 45 || cfg.LanguageHintBoost != 1.2 {
		t.Fatalf("unexpected recency/language config: %#v", cfg)
	}
	if cfg.MyMPBoost != 1.1 || cfg.BillBoost != 0.9 || cfg.TopicBoost != 0.7 {
		t.Fatalf("unexpected follow boosts: %#v", cfg)
	}
}

func TestRankingConfigRejectsInvalidEnv(t *testing.T) {
	t.Setenv("SEARCH_TEXT_WEIGHT", "-0.1")
	t.Setenv("SEARCH_RECENCY_HALFLIFE_DAYS", "0")

	cfg := rankingConfigFromEnv()
	if cfg.TextWeight != 0.72 {
		t.Fatalf("text weight = %v, want fallback 0.72", cfg.TextWeight)
	}
	if cfg.RecencyHalfLife != 90 {
		t.Fatalf("half life = %v, want fallback 90", cfg.RecencyHalfLife)
	}
}

func TestRankingSQLDocumentsRequiredComponents(t *testing.T) {
	required := []string{
		"ts_rank",
		"POWER(",
		"my_mp_member_id",
		"related_bill_ids",
		"topic_ids",
		"rank_score DESC",
		"s.sitting_date >= $4::DATE",
		"s.sitting_date <= $5::DATE",
	}
	for _, term := range required {
		if !strings.Contains(rankedSpeechSearchSQL, term) {
			t.Fatalf("ranked SQL missing %q", term)
		}
	}
}

func TestSearchEvaluationFixture(t *testing.T) {
	raw, err := os.ReadFile("ranking_evaluation.json")
	if err != nil {
		t.Fatalf("read ranking evaluation: %v", err)
	}

	var suite struct {
		Queries []struct {
			Query        string   `json:"query"`
			ExpectedTop5 []string `json:"expected_top_5"`
		} `json:"queries"`
	}
	if err := json.Unmarshal(raw, &suite); err != nil {
		t.Fatalf("ranking evaluation is invalid JSON: %v", err)
	}
	if len(suite.Queries) != 20 {
		t.Fatalf("got %d evaluation queries, want 20", len(suite.Queries))
	}
	for _, q := range suite.Queries {
		if strings.TrimSpace(q.Query) == "" {
			t.Fatal("evaluation query must not be blank")
		}
		if len(q.ExpectedTop5) != 5 {
			t.Fatalf("%q has %d expected results, want 5", q.Query, len(q.ExpectedTop5))
		}
		seen := map[string]bool{}
		for _, id := range q.ExpectedTop5 {
			if strings.TrimSpace(id) == "" {
				t.Fatalf("%q has blank expected result id", q.Query)
			}
			if seen[id] {
				t.Fatalf("%q repeats expected result id %q", q.Query, id)
			}
			seen[id] = true
		}
	}
}

func assertDate(t *testing.T, got *time.Time, want string) {
	t.Helper()
	if got == nil {
		t.Fatalf("date is nil, want %s", want)
	}
	if formatted := got.Format("2006-01-02"); formatted != want {
		t.Fatalf("date = %s, want %s", formatted, want)
	}
}
