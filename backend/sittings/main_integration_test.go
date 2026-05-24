//go:build integration

package main

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestIntegrationSittingSpeechesReadsLocalArtifactFixture(t *testing.T) {
	dir := t.TempDir()
	content := "Madam Speaker, example content."
	writeJSONFixture(t, dir, "sittings/v1/by-date/2026-04-29.json", SpeechesResponse{
		Date:     "2026-04-29",
		Speeches: []Speech{{ID: "intervention-1", Content: &content}},
	})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path:           "/api/v1/sittings/2026-04-29/speeches",
		PathParameters: map[string]string{"date": "2026-04-29"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body SpeechesResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Total != 1 || body.Speeches[0].ID != "intervention-1" {
		t.Fatalf("body = %+v", body)
	}
}
