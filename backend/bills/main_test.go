package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequestFiltersBills(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	p44 := 44
	writeBillFixture(t, dir, BillsResponse{Bills: []Bill{
		{ID: "C-1", Number: "C-1", Title: "First", Status: "InProgress", Parliament: &p45},
		{ID: "S-1", Number: "S-1", Title: "Second", Status: "RoyalAssent", Parliament: &p44},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"status": "in_progress", "parliament": "45"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body BillsResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Bills) != 1 || body.Bills[0].ID != "C-1" {
		t.Fatalf("bills = %+v", body.Bills)
	}
}

func TestHandleRequestMissingArtifactReturns404(t *testing.T) {
	withLocalStore(t, t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 404 {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func withLocalStore(t *testing.T, dir string) {
	t.Helper()
	original := newArtifactStore
	newArtifactStore = func(context.Context) (artifacts.Store, error) {
		return artifacts.NewLocalStore(dir), nil
	}
	t.Cleanup(func() { newArtifactStore = original })
}

func writeBillFixture(t *testing.T, dir string, body BillsResponse) {
	t.Helper()
	path := filepath.Join(dir, "bills", "v1")
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	if err := os.WriteFile(filepath.Join(path, "all.json"), data, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
