package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_MissingMemberId(t *testing.T) {
	ctx := context.Background()
	req := events.APIGatewayProxyRequest{
		PathParameters: map[string]string{},
	}
	resp, err := HandleRequest(ctx, req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got status %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestJsonError(t *testing.T) {
	resp := jsonError(http.StatusNotFound, "speech not found")
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("got status %d, want 404", resp.StatusCode)
	}
	if resp.Headers["Content-Type"] != "application/json" {
		t.Errorf("got Content-Type %q, want application/json", resp.Headers["Content-Type"])
	}
	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
	if body["error"] != "speech not found" {
		t.Errorf("got error %q, want 'speech not found'", body["error"])
	}
}

func TestJsonError_BadRequest(t *testing.T) {
	resp := jsonError(http.StatusBadRequest, "missing member id")
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got status %d, want 400", resp.StatusCode)
	}
	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
	if body["error"] != "missing member id" {
		t.Errorf("got error %q, want 'missing member id'", body["error"])
	}
}
