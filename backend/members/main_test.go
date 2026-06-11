package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	_ "modernc.org/sqlite"
)

func TestHandleRequestReadsSQLiteArtifact(t *testing.T) {
	dir := t.TempDir()
	writeMemberFixture(t, dir, MembersResponse{Members: []Member{
		{ID: "json", Name: "JSON fallback", Province: "ON", Party: "Liberal"},
	}})
	writeMemberSQLiteUnitFixture(t, dir, []Member{
		{ID: "2269", Name: "Jane Example", Riding: "Ottawa Centre", Province: "ON", Party: "Liberal", SourceURL: "https://www.ourcommons.ca/members/en"},
		{ID: "2270", Name: "Sam Example", Riding: "Vancouver East", Province: "BC", Party: "NDP", SourceURL: "https://www.ourcommons.ca/members/en"},
	})
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
	if len(body.Members) != 1 || body.Members[0].ID != "2269" {
		t.Fatalf("members = %+v", body.Members)
	}
}

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

func writeMemberSQLiteUnitFixture(t *testing.T, dir string, members []Member) {
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
	if _, err := db.Exec(`CREATE TABLE members (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		riding TEXT NOT NULL DEFAULT '',
		province TEXT NOT NULL DEFAULT '',
		party TEXT NOT NULL DEFAULT '',
		source_url TEXT NOT NULL DEFAULT ''
	)`); err != nil {
		t.Fatalf("create members table: %v", err)
	}
	for _, member := range members {
		if _, err := db.Exec(`
			INSERT INTO members (id, name, riding, province, party, source_url)
			VALUES (?, ?, ?, ?, ?, ?)`,
			member.ID, member.Name, member.Riding, member.Province, member.Party, member.SourceURL,
		); err != nil {
			t.Fatalf("insert member fixture: %v", err)
		}
	}
}
