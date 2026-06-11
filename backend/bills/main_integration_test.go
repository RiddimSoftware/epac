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

func TestIntegrationBillsReadsLocalArtifactFixture(t *testing.T) {
	dir := t.TempDir()
	writeBillsSQLiteArtifact(t, dir)
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/bills",
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
	if len(body.Bills) != 2 || body.Bills[0].Number != "C-2269" {
		t.Fatalf("body = %+v", body)
	}
}

func TestIntegrationBillsLambdaQueriesSQLiteArtifactFromCompositionRoot(t *testing.T) {
	dir := t.TempDir()
	writeBillsSQLiteArtifact(t, dir)
	withLocalIndex(t, dir)

	handler := observability.WrapAPIGateway("bills", HandleRequest)
	resp, err := handler(context.Background(), events.APIGatewayProxyRequest{
		Path:                  "/api/v1/bills",
		QueryStringParameters: map[string]string{"status": "in_progress", "parliament": "45"},
		RequestContext: events.APIGatewayProxyRequestContext{
			Identity: events.APIGatewayRequestIdentity{SourceIP: "192.0.2.10"},
		},
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
	if len(body.Bills) != 1 {
		t.Fatalf("bills len = %d, body = %+v", len(body.Bills), body)
	}
	bill := body.Bills[0]
	if bill.ID != "C-2269" || bill.Number != "C-2269" || bill.Title != "SQLite Artifact Act" {
		t.Fatalf("bill shape = %+v", bill)
	}
	if bill.SponsorName != "Example Sponsor" || bill.Status != "InProgress" || bill.CurrentStage != "House First Reading" {
		t.Fatalf("bill metadata = %+v", bill)
	}
	if bill.Parliament == nil || *bill.Parliament != 45 || bill.Session == nil || *bill.Session != 1 {
		t.Fatalf("bill parliament/session = %+v/%+v", bill.Parliament, bill.Session)
	}
	if len(bill.Stages) != 2 {
		t.Fatalf("stages = %+v", bill.Stages)
	}
	if bill.Stages[0].ID != "C-2269-h1" || !bill.Stages[0].IsCompleted || bill.Stages[0].CompletedDate == nil || *bill.Stages[0].CompletedDate != "2026-06-01" {
		t.Fatalf("first stage = %+v", bill.Stages[0])
	}
}

func writeBillsSQLiteArtifact(t *testing.T, dir string) {
	t.Helper()

	path := filepath.Join(dir, "bills", "v1", "index.sqlite")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir sqlite fixture: %v", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite fixture: %v", err)
	}

	statements := []string{
		`CREATE TABLE bills (
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
		)`,
		`CREATE TABLE bill_stages (
			bill_id TEXT NOT NULL,
			id TEXT NOT NULL,
			name TEXT NOT NULL,
			completed_date TEXT,
			is_completed INTEGER NOT NULL,
			sort_order INTEGER NOT NULL
		)`,
		`INSERT INTO bills (
			id, number, title, sponsor_name, status, current_stage, introduced_on,
			source_url, bill_type, parliament, session, legis_info_url
		) VALUES (
			'C-2269', 'C-2269', 'SQLite Artifact Act', 'Example Sponsor', 'InProgress',
			'House First Reading', '2026-06-01', 'https://www.parl.ca/example/c-2269',
			'HouseGovernment', 45, 1, 'https://www.parl.ca/legisinfo/en/bill/45-1/c-2269'
		)`,
		`INSERT INTO bills (
			id, number, title, sponsor_name, status, current_stage, parliament, session
		) VALUES (
			'S-999', 'S-999', 'Filtered Out Act', 'Another Sponsor', 'RoyalAssent',
			'Royal Assent', 44, 1
		)`,
		`INSERT INTO bill_stages (bill_id, id, name, completed_date, is_completed, sort_order) VALUES
			('C-2269', 'C-2269-h1', 'House First Reading', '2026-06-01', 1, 1),
			('C-2269', 'C-2269-h2', 'House Second Reading', NULL, 0, 2)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			t.Fatalf("exec sqlite fixture statement: %v", err)
		}
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite fixture: %v", err)
	}
	writeManifest(t, path, "bills/v1/index.sqlite")
}
