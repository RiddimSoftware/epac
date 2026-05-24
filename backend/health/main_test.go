package main

import (
	"encoding/json"
	"testing"
)

func TestAPIErrorResponse(t *testing.T) {
	resp := apiError(503, "db connect: refused")

	if resp.StatusCode != 503 {
		t.Fatalf("StatusCode = %d, want 503", resp.StatusCode)
	}
	if got := resp.Headers["Content-Type"]; got != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", got)
	}

	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response body: %v", err)
	}
	if got := body["error"]; got != "db connect: refused" {
		t.Fatalf("error body = %q, want db connect: refused", got)
	}
}
