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

func TestListSittingsFiltersAndPaginates(t *testing.T) {
	dir := t.TempDir()
	writeJSONFixture(t, dir, "sittings/v1/all.json", SittingsResponse{Sittings: []Sitting{
		{Date: "2026-04-29", SourceURL: "https://example.test/29"},
		{Date: "2026-04-28", SourceURL: "https://example.test/28"},
		{Date: "2026-04-27", SourceURL: "https://example.test/27"},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/sittings",
		QueryStringParameters: map[string]string{
			"from_date": "2026-04-28",
			"per_page":  "1",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body SittingsResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Total != 2 || len(body.Sittings) != 1 || body.Sittings[0].Date != "2026-04-29" {
		t.Fatalf("body = %+v", body)
	}
}

func TestSittingSpeechesMissingArtifactReturns404(t *testing.T) {
	withLocalStore(t, t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path:           "/api/v1/sittings/2026-04-29/speeches",
		PathParameters: map[string]string{"date": "2026-04-29"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 404 {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestSittingSpeechesPaginates(t *testing.T) {
	dir := t.TempDir()
	speaker := "Example MP"
	writeJSONFixture(t, dir, "sittings/v1/by-date/2026-04-29.json", SpeechesResponse{
		Date: "2026-04-29",
		Speeches: []Speech{
			{ID: "1", SpeakerName: &speaker},
			{ID: "2", SpeakerName: &speaker},
		},
	})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path:                  "/api/v1/sittings/2026-04-29/speeches",
		PathParameters:        map[string]string{"date": "2026-04-29"},
		QueryStringParameters: map[string]string{"page": "2", "per_page": "1"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	var body SpeechesResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Total != 2 || len(body.Speeches) != 1 || body.Speeches[0].ID != "2" {
		t.Fatalf("body = %+v", body)
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

func writeJSONFixture(t *testing.T, dir, key string, body any) {
	t.Helper()
	full := filepath.Join(dir, filepath.FromSlash(key))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	data, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	if err := os.WriteFile(full, data, 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
