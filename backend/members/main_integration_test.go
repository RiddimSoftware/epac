//go:build integration

package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	_ "modernc.org/sqlite"
)

func TestIntegrationMembersReadsLocalArtifactFixture(t *testing.T) {
	dir := t.TempDir()
	writeMemberFixture(t, dir, MembersResponse{Members: []Member{
		{ID: "278707", Name: "Example MP", Province: "ON", Party: "Liberal"},
	}})
	withLocalStore(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/members",
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
	if len(body.Members) != 1 || body.Members[0].Name != "Example MP" {
		t.Fatalf("body = %+v", body)
	}
}

func TestIntegrationMembersLambdaQueriesSQLiteArtifactFromCompositionRoot(t *testing.T) {
	dir := t.TempDir()
	writeMembersSQLiteArtifact(t, dir)
	t.Setenv("EPAC_ARTIFACTS_DIR", dir)

	handler := observability.WrapAPIGateway("members", HandleRequest)
	resp, err := handler(context.Background(), events.APIGatewayProxyRequest{
		Path:                  "/api/v1/members",
		QueryStringParameters: map[string]string{"province": "Ontario", "party": "liberal"},
		RequestContext: events.APIGatewayProxyRequestContext{
			Identity: events.APIGatewayRequestIdentity{SourceIP: "192.0.2.11"},
		},
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
	if len(body.Members) != 1 {
		t.Fatalf("members len = %d, body = %+v", len(body.Members), body)
	}
	member := body.Members[0]
	if member.ID != "2269" || member.Name != "Jane Example" || member.Riding != "Ottawa Centre" {
		t.Fatalf("member shape = %+v", member)
	}
	if member.Province != "ON" || member.Party != "Liberal" || member.SourceURL != "https://www.ourcommons.ca/members/en" {
		t.Fatalf("member metadata = %+v", member)
	}
}

func writeMembersSQLiteArtifact(t *testing.T, dir string) {
	t.Helper()

	path := filepath.Join(dir, "members", "v1", "index.sqlite")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir sqlite fixture: %v", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite fixture: %v", err)
	}
	defer db.Close()

	statements := []string{
		`CREATE TABLE members (
			id TEXT PRIMARY KEY,
			name TEXT NOT NULL,
			riding TEXT NOT NULL DEFAULT '',
			province TEXT NOT NULL DEFAULT '',
			party TEXT NOT NULL DEFAULT '',
			source_url TEXT NOT NULL DEFAULT ''
		)`,
		`INSERT INTO members (id, name, riding, province, party, source_url) VALUES
			('2269', 'Jane Example', 'Ottawa Centre', 'ON', 'Liberal', 'https://www.ourcommons.ca/members/en'),
			('2270', 'Sam Example', 'Vancouver East', 'BC', 'NDP', 'https://www.ourcommons.ca/members/en')`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			t.Fatalf("exec sqlite fixture statement: %v", err)
		}
	}
}
