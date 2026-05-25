package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_Returns503(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("want status 503, got %d", resp.StatusCode)
	}
	if resp.Headers["Retry-After"] != "5" {
		t.Errorf("want Retry-After: 5, got %q", resp.Headers["Retry-After"])
	}

	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
	if body["error"] != "search index not yet available" {
		t.Errorf("unexpected error message: %q", body["error"])
	}
}
