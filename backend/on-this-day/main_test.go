package main

import (
	"context"
	"net/http"
	"os"
	"testing"

	"epac/on-this-day/internal/adapter/postgres"
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

func TestHandleRequest_MissingDatabaseURL(t *testing.T) {
	// Close and nil the cached connection so getDBConn is forced to re-read
	// DATABASE_URL rather than reusing a warm connection from a prior test.
	postgres.ResetDBConnForTest(context.Background())
	orig := os.Getenv("DATABASE_URL")
	os.Unsetenv("DATABASE_URL")
	t.Cleanup(func() {
		if orig != "" {
			os.Setenv("DATABASE_URL", orig)
		}
	})

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
