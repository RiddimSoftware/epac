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
	"os"
	"sync"
	"testing"

	"epac/_testdb"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
)

type apnsStub struct {
	mu   sync.Mutex
	hits []apnsHit
	errs []error
}

type apnsHit struct {
	Aps struct {
		Alert struct {
			Title string `json:"title"`
			Body  string `json:"body"`
		} `json:"alert"`
	} `json:"aps"`
	DivisionID int `json:"division_id"`
}

func (s *apnsStub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	s.mu.Lock()
	defer s.mu.Unlock()

	var payload apnsHit
	if err := json.Unmarshal(body, &payload); err != nil {
		s.errs = append(s.errs, err)
	} else {
		s.hits = append(s.hits, payload)
	}

	w.WriteHeader(http.StatusOK)
}

func (s *apnsStub) snapshot() ([]apnsHit, []error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]apnsHit, len(s.hits))
	copy(out, s.hits)
	errs := make([]error, len(s.errs))
	copy(errs, s.errs)
	return out, errs
}

func TestAcceptancePushNotificationDispatcherCallsAPNsThroughCompositionRoot(t *testing.T) {
	conn := _testdb.Connect(t)
	token := "test-token-epac-2275"
	_, _ = conn.Exec(context.Background(), `DELETE FROM device_subscriptions WHERE token = $1`, token)
	t.Cleanup(func() {
		_, _ = conn.Exec(context.Background(), `DELETE FROM device_subscriptions WHERE token = $1`, token)
	})

	t.Setenv("DATABASE_URL", os.Getenv("DATABASE_URL"))

	_testdb.SeedDeviceSubscription(t, conn, token, "", nil, nil)

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
		t.Errorf("expected status 202, got %d. body=%v", resp.StatusCode, resp.Body)
	}

	hits, errs := apns.snapshot()
	if len(errs) != 0 {
		t.Fatalf("apns payload decode errors = %v, want none", errs)
	}
	if len(hits) != 1 {
		t.Fatalf("apns hit count = %d, want 1", len(hits))
	}
	alert := hits[0].Aps.Alert
	if alert.Title != "Vote result posted" {
		t.Fatalf("aps.alert.title = %q, want Vote result posted", alert.Title)
	}
	if alert.Body != "Division 42 result: carried." {
		t.Fatalf("aps.alert.body = %q, want Division 42 result: carried.", alert.Body)
	}
	if hits[0].DivisionID != 42 {
		t.Fatalf("division_id = %v, want 42", hits[0].DivisionID)
	}
}
