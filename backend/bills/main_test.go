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
	p45 := 45
	p44 := 44
	writeBillFixture(t, dir, BillsResponse{Bills: []Bill{
		{ID: "JSON", Number: "JSON", Title: "JSON fallback", Status: "InProgress", Parliament: &p45},
	}})
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "C-2269", Number: "C-2269", Title: "SQLite Artifact Act", Status: "InProgress", CurrentStage: "House First Reading", Parliament: &p45},
		{ID: "S-999", Number: "S-999", Title: "Filtered Out", Status: "RoyalAssent", Parliament: &p44},
	})
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
	if len(body.Bills) != 1 || body.Bills[0].ID != "C-2269" {
		t.Fatalf("bills = %+v", body.Bills)
	}
	if len(body.Bills[0].Stages) != 1 || body.Bills[0].Stages[0].ID != "C-2269-h1" {
		t.Fatalf("stages = %+v", body.Bills[0].Stages)
	}
}

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

func writeBillSQLiteUnitFixture(t *testing.T, dir string, bills []Bill) {
	t.Helper()
	path := filepath.Join(dir, "bills", "v1", "index.sqlite")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir sqlite fixture: %v", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite fixture: %v", err)
	}
	defer db.Close()
	if _, err := db.Exec(`CREATE TABLE bills (
		id TEXT PRIMARY KEY,
		number TEXT NOT NULL,
		title TEXT NOT NULL,
		sponsor_name TEXT NOT NULL DEFAULT '',
		status TEXT NOT NULL DEFAULT '',
		current_stage TEXT NOT NULL DEFAULT '',
		introduced_on TEXT,
		source_url TEXT NOT NULL DEFAULT '',
		bill_type TEXT NOT NULL DEFAULT '',
		parliament INTEGER,
		session INTEGER,
		legis_info_url TEXT NOT NULL DEFAULT ''
	)`); err != nil {
		t.Fatalf("create bills table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE bill_stages (
		bill_id TEXT NOT NULL,
		id TEXT NOT NULL,
		name TEXT NOT NULL,
		completed_date TEXT,
		is_completed INTEGER NOT NULL,
		sort_order INTEGER NOT NULL
	)`); err != nil {
		t.Fatalf("create stages table: %v", err)
	}
	for _, bill := range bills {
		var parliament any
		if bill.Parliament != nil {
			parliament = *bill.Parliament
		}
		if _, err := db.Exec(`
			INSERT INTO bills (id, number, title, sponsor_name, status, current_stage, parliament)
			VALUES (?, ?, ?, ?, ?, ?, ?)`,
			bill.ID, bill.Number, bill.Title, bill.SponsorName, bill.Status, bill.CurrentStage, parliament,
		); err != nil {
			t.Fatalf("insert bill fixture: %v", err)
		}
	}
	if _, err := db.Exec(`
		INSERT INTO bill_stages (bill_id, id, name, completed_date, is_completed, sort_order)
		VALUES ('C-2269', 'C-2269-h1', 'House First Reading', '2026-06-01', 1, 1)`); err != nil {
		t.Fatalf("insert stage fixture: %v", err)
	}
}
