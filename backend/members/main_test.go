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

func TestHandleRequestFiltersMembers(t *testing.T) {
	dir := t.TempDir()
	writeMemberFixture(t, dir, MembersResponse{Members: []Member{
		{ID: "1", Name: "Ada Lovelace", Province: "ON", Party: "Liberal"},
		{ID: "2", Name: "Grace Hopper", Province: "BC", Party: "NDP"},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"province": "Ontario", "party": "liberal"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body MembersResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Members) != 1 || body.Members[0].ID != "1" {
		t.Fatalf("members = %+v", body.Members)
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

func writeMemberFixture(t *testing.T, dir string, body MembersResponse) {
	t.Helper()
	path := filepath.Join(dir, "members", "v1")
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
