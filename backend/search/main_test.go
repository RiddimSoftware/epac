package main

import (
	"context"
	"net/http"
	"os"
	"testing"

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
