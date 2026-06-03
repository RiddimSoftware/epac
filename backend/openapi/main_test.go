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

	var spec openAPISpec
	if err := json.Unmarshal([]byte(resp.Body), &spec); err != nil {
		t.Fatalf("spec is not valid JSON: %v", err)
	}
	if spec.OpenAPI == "" {
		t.Fatal("spec missing openapi version")
	}

	requiredPaths := []string{
		"/api/v1/sittings",
		"/api/v1/sittings/{date}/speeches",
		"/api/v1/hansard/search",
		"/api/v1/members",
		"/api/v1/members/{id}/votes",
		"/api/v1/members/{id}/lobbying-exposure",
		"/api/v1/ridings/{slug}/boundary",
		"/api/v1/bills",
		"/api/v1/bills/{legisinfo_id}/lobbying-context",
		"/api/v1/calendar/house.ics",
		"/api/v1/config",
		"/api/v1/on-this-day",
		"/api/v1/lobbying/by-topic/{slug}",
		"/api/v1/ministers/{member_id}/lobbying-by-portfolio",
		"/api/v1/cabinet/lobbying-overview",
		"/api/v1/lobbying/organizations",
		"/api/v1/lobbying/organizations/{id}",
		"/health",
	}
	for _, path := range requiredPaths {
		if _, ok := spec.Paths[path]; !ok {
			t.Fatalf("spec missing required path %s", path)
		}
	}
}

func TestRequiredPathsHaveResponseSchemasAndExamples(t *testing.T) {
	spec := readEmbeddedSpec(t)

	requiredGETPaths := []string{
		"/api/v1/sittings",
		"/api/v1/sittings/{date}/speeches",
		"/api/v1/hansard/search",
		"/api/v1/members",
		"/api/v1/members/{id}/votes",
		"/api/v1/members/{id}/lobbying-exposure",
		"/api/v1/ridings/{slug}/boundary",
		"/api/v1/bills",
		"/api/v1/bills/{legisinfo_id}/lobbying-context",
		"/api/v1/calendar/house.ics",
		"/api/v1/config",
		"/api/v1/on-this-day",
		"/api/v1/lobbying/by-topic/{slug}",
		"/api/v1/ministers/{member_id}/lobbying-by-portfolio",
		"/api/v1/cabinet/lobbying-overview",
		"/api/v1/lobbying/organizations",
		"/api/v1/lobbying/organizations/{id}",
		"/health",
	}

	for _, path := range requiredGETPaths {
		operation, ok := spec.Paths[path]["get"]
		if !ok {
			t.Fatalf("%s missing GET operation", path)
		}
		assertDocumentedOperation(t, path, operation)
	}

	docsOperation, ok := spec.Paths["/docs"]["get"]
	if !ok {
		t.Fatal("/docs missing GET operation")
	}
	assertDocumentedOperation(t, "/docs", docsOperation)
}

func TestRetiredLambdaPathsAreAbsent(t *testing.T) {
	spec := readEmbeddedSpec(t)

	retiredPaths := []string{
		"/api/v1/live",
		"/device/register",
		"/api/v1/device/register",
	}
	for _, path := range retiredPaths {
		if _, ok := spec.Paths[path]; ok {
			t.Fatalf("retired path %s is still documented", path)
		}
	}
}

func TestVersionedSpecEndpoint(t *testing.T) {
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{RawPath: "/api/v1/openapi.json"})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusOK)
	}
}

func TestDocsRenderWithQueryToken(t *testing.T) {
	t.Setenv("OPENAPI_DOCS_TOKEN", "secret")
	resp, err := handler(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/docs",
		QueryStringParameters: map[string]string{"token": "secret"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("got status %d, want %d", resp.StatusCode, http.StatusOK)
	}
	if !strings.Contains(resp.Body, "/openapi.json") {
		t.Fatal("docs HTML did not point at /openapi.json")
	}
}

type openAPISpec struct {
	OpenAPI string                             `json:"openapi"`
	Paths   map[string]map[string]apiOperation `json:"paths"`
}

type apiOperation struct {
	Summary   string                     `json:"summary"`
	Responses map[string]operationResult `json:"responses"`
}

type operationResult struct {
	Content map[string]mediaType `json:"content"`
}

type mediaType struct {
	Schema   json.RawMessage            `json:"schema"`
	Examples map[string]json.RawMessage `json:"examples"`
}

func readEmbeddedSpec(t *testing.T) openAPISpec {
	t.Helper()

	specBytes, err := specFS.ReadFile("openapi.json")
	if err != nil {
		t.Fatalf("read embedded spec: %v", err)
	}

	var spec openAPISpec
	if err := json.Unmarshal(specBytes, &spec); err != nil {
		t.Fatalf("spec is not valid JSON: %v", err)
	}
	return spec
}

func assertDocumentedOperation(t *testing.T, path string, operation apiOperation) {
	t.Helper()

	if operation.Summary == "" {
		t.Fatalf("%s missing operation summary", path)
	}

	hasSchema := false
	hasExample := false
	for _, response := range operation.Responses {
		for _, content := range response.Content {
			if len(content.Schema) > 0 {
				hasSchema = true
			}
			if len(content.Examples) > 0 {
				hasExample = true
			}
		}
	}
	if !hasSchema {
		t.Fatalf("%s missing response schema", path)
	}
	if !hasExample {
		t.Fatalf("%s missing example response", path)
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
