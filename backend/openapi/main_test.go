package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestOpenAPISpecEndpoint(t *testing.T) {
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{RawPath: "/openapi.json"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusOK)
	}
	if ct := resp.Headers["Content-Type"]; !strings.Contains(ct, "application/json") {
		t.Fatalf("content type = %q, want JSON", ct)
	}

	var spec struct {
		OpenAPI string                                `json:"openapi"`
		Paths   map[string]map[string]json.RawMessage `json:"paths"`
	}
	if err := json.Unmarshal([]byte(resp.Body), &spec); err != nil {
		t.Fatalf("spec is not valid JSON: %v", err)
	}
	if spec.OpenAPI == "" {
		t.Fatal("spec missing openapi version")
	}

	requiredPaths := []string{
		"/api/v1/sittings",
		"/api/v1/sittings/{date}/speeches",
		"/api/v1/members",
		"/api/v1/members/{id}/votes",
		"/api/v1/bills",
		"/api/v1/live",
		"/api/v1/config",
		"/health",
	}
	for _, path := range requiredPaths {
		if _, ok := spec.Paths[path]; !ok {
			t.Fatalf("spec missing required path %s", path)
		}
	}
}

func TestDocsRequireConfiguredToken(t *testing.T) {
	t.Setenv("OPENAPI_DOCS_TOKEN", "")
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{RawPath: "/docs"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusServiceUnavailable)
	}
}

func TestDocsRequireMatchingToken(t *testing.T) {
	t.Setenv("OPENAPI_DOCS_TOKEN", "secret")
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/docs",
		Headers: map[string]string{"x-docs-token": "wrong"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusUnauthorized)
	}
}

func TestDocsRenderWithToken(t *testing.T) {
	t.Setenv("OPENAPI_DOCS_TOKEN", "secret")
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/docs",
		Headers: map[string]string{"x-docs-token": "secret"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusOK)
	}
	if !strings.Contains(resp.Body, "/api/v1/openapi.json") {
		t.Fatal("docs HTML did not point at /api/v1/openapi.json")
	}
}
