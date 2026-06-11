//go:build acceptance

// Acceptance test for the push-notification-dispatcher Lambda.
//
// Runs the lambda through its composition root (observability.WrapAPIGateway)
// and asserts that the dispatcher handles internal payloads and calls the APNs client boundary.
//
// This test is genuinely red until the lambda is implemented.
//
// Run with: go test -tags=acceptance ./backend/push-notification-dispatcher
package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"

	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
)

type apnsStub struct {
	mu   sync.Mutex
	hits []map[string]any
}

func (s *apnsStub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	var payload map[string]any
	_ = json.Unmarshal(body, &payload)

	s.mu.Lock()
	s.hits = append(s.hits, payload)
	s.mu.Unlock()

	w.WriteHeader(http.StatusOK)
}

func (s *apnsStub) snapshot() []map[string]any {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]map[string]any, len(s.hits))
	copy(out, s.hits)
	return out
}

func TestAcceptancePushNotificationDispatcherCallsAPNsThroughCompositionRoot(t *testing.T) {
	apns := &apnsStub{}
	server := httptest.NewServer(apns)
	defer server.Close()

	t.Setenv("EPAC_APNS_URL", server.URL)

	payload := `{
		"division_id": 42,
		"parliament": 45,
		"session": 1,
		"result": "carried",
		"status": "concluded"
	}`

	req := events.APIGatewayProxyRequest{
		Body: payload,
	}

	wrapped := observability.WrapAPIGateway(pipelineName, HandleRequest)
	resp, err := wrapped(context.Background(), req)
	if err != nil {
		t.Fatalf("wrapped HandleRequest error: %v", err)
	}

	if resp.StatusCode != 202 {
		t.Errorf("expected status 202, got %d", resp.StatusCode)
	}

	hits := apns.snapshot()
	if len(hits) != 1 {
		t.Fatalf("apns hit count = %d, want 1", len(hits))
	}
}
