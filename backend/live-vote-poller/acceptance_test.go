//go:build acceptance

// Acceptance test for the live-vote-poller Lambda.
//
// Runs the lambda through its composition root (observability.WrapNoEvent)
// and asserts that a concluded Parliament division is written to the live
// votes artifact and dispatched to the push-notification dispatcher.
//
// This test is genuinely red until EPAC-2261 implements the poller — the
// stub HandleRequest does nothing, so the dispatcher receives no payload
// and the artifact directory stays empty.
//
// Run with: go test -tags=acceptance ./backend/live-vote-poller
package main

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"epac/observability"
)

const parliamentDivisionsFixture = `{
  "divisions": [
    {
      "division_id": 42,
      "parliament": 45,
      "session": 1,
      "sitting": 124,
      "subject": "Motion to adopt the Standing Committee on Finance report",
      "result": "carried",
      "yeas": 178,
      "nays": 149,
      "paired": 0,
      "concluded_at": "2026-06-11T14:32:00Z",
      "status": "concluded"
    }
  ]
}`

type dispatcherStub struct {
	mu   sync.Mutex
	hits []map[string]any
}

func (d *dispatcherStub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	r.Body.Close()

	var payload map[string]any
	_ = json.Unmarshal(body, &payload)

	d.mu.Lock()
	d.hits = append(d.hits, payload)
	d.mu.Unlock()

	w.WriteHeader(http.StatusAccepted)
	_, _ = w.Write([]byte(`{"ok":true}`))
}

func (d *dispatcherStub) snapshot() []map[string]any {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]map[string]any, len(d.hits))
	copy(out, d.hits)
	return out
}

func TestAcceptanceLiveVotePollerEmitsConcludedDivisionThroughCompositionRoot(t *testing.T) {
	parliament := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(parliamentDivisionsFixture))
	}))
	defer parliament.Close()

	dispatcher := &dispatcherStub{}
	dispatcherServer := httptest.NewServer(dispatcher)
	defer dispatcherServer.Close()

	artifactsDir := t.TempDir()

	t.Setenv("EPAC_ARTIFACTS_DIR", artifactsDir)
	t.Setenv("EPAC_PARLIAMENT_DIVISIONS_URL", parliament.URL)
	t.Setenv("EPAC_PUSH_DISPATCHER_URL", dispatcherServer.URL)

	wrapped := observability.WrapNoEvent(pipelineName, HandleRequest)
	if err := wrapped(context.Background()); err != nil {
		t.Fatalf("wrapped HandleRequest error: %v", err)
	}

	hits := dispatcher.snapshot()
	if len(hits) != 1 {
		t.Fatalf("dispatcher hit count = %d, want 1 (live-vote-poller must POST one concluded division to the push dispatcher)", len(hits))
	}

	payload := hits[0]
	if payload["division_id"] != float64(42) {
		t.Fatalf("dispatcher payload division_id = %v (%T), want 42", payload["division_id"], payload["division_id"])
	}
	if payload["parliament"] != float64(45) || payload["session"] != float64(1) {
		t.Fatalf("dispatcher payload parliament/session = %v/%v, want 45/1", payload["parliament"], payload["session"])
	}
	if payload["result"] != "carried" {
		t.Fatalf("dispatcher payload result = %v, want carried", payload["result"])
	}
	if payload["status"] != "concluded" {
		t.Fatalf("dispatcher payload status = %v, want concluded", payload["status"])
	}

	artifactPath := filepath.Join(artifactsDir, "votes", "live", "45-1-42.json")
	contents, err := os.ReadFile(artifactPath)
	if err != nil {
		t.Fatalf("live division artifact missing at %s: %v", artifactPath, err)
	}

	var artifact map[string]any
	if err := json.Unmarshal(contents, &artifact); err != nil {
		t.Fatalf("live division artifact at %s is not valid JSON: %v", artifactPath, err)
	}
	if artifact["division_id"] != float64(42) {
		t.Fatalf("live division artifact division_id = %v, want 42", artifact["division_id"])
	}
	if artifact["result"] != "carried" {
		t.Fatalf("live division artifact result = %v, want carried", artifact["result"])
	}
}
