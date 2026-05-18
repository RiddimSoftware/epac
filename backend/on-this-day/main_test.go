package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"epac/on-this-day/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_InvalidDate(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"date": "2026/04/29"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestHandleRequest_MissingArtifactConfig(t *testing.T) {
	t.Setenv("ARTIFACTS_DIR", "")
	t.Setenv("EPAC_ARTIFACTS_DIR", "")
	t.Setenv("ARTIFACT_BUCKET", "")
	t.Setenv("EPAC_ARTIFACT_BUCKET", "")

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"date": "2026-04-29"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusInternalServerError {
		t.Fatalf("got status %d, want 500", resp.StatusCode)
	}
}

func TestHandleRequest_ReadsArtifactAndFiltersDate(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, "on-this-day/v1/all.json", `{
		"items": [
			{"id":"speech:new","kind":"speech","year":2026,"date":"2026-04-29","title":"Future","excerpt":"ignored"},
			{"id":"speech:old-1","kind":"speech","year":2024,"date":"2024-04-29","title":"Housing","excerpt":"first"},
			{"id":"speech:wrong-day","kind":"speech","year":2023,"date":"2023-04-28","title":"Budget","excerpt":"ignored"},
			{"id":"speech:old-2","kind":"speech","year":2022,"date":"2022-04-29","title":"Health","excerpt":"second"}
		]
	}`)
	t.Setenv("ARTIFACTS_DIR", dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"date": "2026-04-29", "limit": "1"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d body %s, want 200", resp.StatusCode, resp.Body)
	}
	if !strings.Contains(resp.Body, `"date":"2026-04-29"`) || !strings.Contains(resp.Body, `"id":"speech:old-1"`) {
		t.Fatalf("unexpected body: %s", resp.Body)
	}
	if strings.Contains(resp.Body, "wrong-day") || strings.Contains(resp.Body, "old-2") {
		t.Fatalf("body was not filtered/limited: %s", resp.Body)
	}
}

func TestHandleRequest_DefaultDateExcludesCurrentDayArtifact(t *testing.T) {
	now := time.Now().UTC()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	prior := time.Date(now.Year()-1, now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	if prior.Month() != now.Month() || prior.Day() != now.Day() {
		prior = time.Date(now.Year()-4, now.Month(), now.Day(), 0, 0, 0, 0, time.UTC)
	}

	dir := t.TempDir()
	writeFixture(t, dir, "on-this-day/v1/all.json", fmt.Sprintf(`{
		"items": [
			{"id":"speech:today","kind":"speech","year":%d,"date":%q,"title":"Today","excerpt":"ignored"},
			{"id":"speech:prior","kind":"speech","year":%d,"date":%q,"title":"Prior","excerpt":"included"}
		]
	}`, today.Year(), today.Format("2006-01-02"), prior.Year(), prior.Format("2006-01-02")))
	t.Setenv("ARTIFACTS_DIR", dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"limit": "10"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d body %s, want 200", resp.StatusCode, resp.Body)
	}
	if strings.Contains(resp.Body, "speech:today") {
		t.Fatalf("default date included current-day artifact row: %s", resp.Body)
	}
	if !strings.Contains(resp.Body, "speech:prior") {
		t.Fatalf("default date omitted prior-year matching row: %s", resp.Body)
	}
}

func TestParseLimit(t *testing.T) {
	cases := []struct {
		value string
		want  int
	}{
		{"", 5},
		{"3", 3},
		{"0", 5},
		{"not-number", 5},
		{"200", usecase.MaxLimit},
	}
	for _, tc := range cases {
		if got := parseLimit(tc.value); got != tc.want {
			t.Fatalf("parseLimit(%q) = %d, want %d", tc.value, got, tc.want)
		}
	}
}

func writeFixture(t *testing.T, root, key, body string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(key))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir fixture: %v", err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
