package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	sqliteadapter "epac/bills/internal/adapter/sqlite"
	"epac/bills/internal/usecase"
	"github.com/aws/aws-lambda-go/events"
	_ "modernc.org/sqlite"
)

func TestHandleRequestReadsSQLiteArtifact(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	p44 := 44
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "C-2269", Number: "C-2269", Title: "SQLite Artifact Act", Status: "InProgress", CurrentStage: "House First Reading", Parliament: &p45},
		{ID: "S-999", Number: "S-999", Title: "Filtered Out", Status: "RoyalAssent", Parliament: &p44},
	})
	withLocalIndex(t, dir)

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

func TestHandleRequestGetsBillDepth(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "C-2260", Number: "C-2260", Title: "Depth Act", Status: "InProgress", CurrentStage: "Committee", Parliament: &p45},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/bills/C-2260",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body BillDepthResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Bill.ID != "C-2260" || body.Bill.Title != "Depth Act" {
		t.Fatalf("bill = %+v", body.Bill)
	}
	if len(body.Bill.Versions) != 1 || body.Bill.Versions[0].Label != "First reading" {
		t.Fatalf("versions = %+v", body.Bill.Versions)
	}
	if len(body.Bill.Amendments) != 1 || body.Bill.Amendments[0].Number != "NDP-1" {
		t.Fatalf("amendments = %+v", body.Bill.Amendments)
	}
}

func TestHandleRequestFiltersBills(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	p44 := 44
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "C-1", Number: "C-1", Title: "First", Status: "InProgress", Parliament: &p45},
		{ID: "S-1", Number: "S-1", Title: "Second", Status: "RoyalAssent", Parliament: &p44},
	})
	withLocalIndex(t, dir)

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
	withLocalIndex(t, t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 404 {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func withLocalIndex(t *testing.T, dir string) {
	t.Helper()
	t.Setenv("EPAC_ARTIFACTS_DIR", dir)
	t.Setenv("BILLS_INDEX_PREFIX", "bills/v1")
	original := billData
	billData = newBillsRuntime(openBillsIndexFromEnv, openSQLiteReadOnly, func(db *sql.DB) usecase.BillRepository {
		return sqliteadapter.New(db)
	})
	t.Cleanup(func() { billData = original })
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
	if _, err := db.Exec(`CREATE TABLE bill_versions (
		bill_id TEXT NOT NULL,
		id TEXT NOT NULL,
		label TEXT NOT NULL,
		title TEXT NOT NULL DEFAULT '',
		stage TEXT NOT NULL DEFAULT '',
		chamber TEXT NOT NULL DEFAULT '',
		published_on TEXT,
		source_url TEXT NOT NULL DEFAULT '',
		sort_order INTEGER NOT NULL
	)`); err != nil {
		t.Fatalf("create bill versions table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE bill_amendments (
		bill_id TEXT NOT NULL,
		id TEXT NOT NULL,
		number TEXT NOT NULL,
		title TEXT NOT NULL DEFAULT '',
		status TEXT NOT NULL DEFAULT '',
		stage TEXT NOT NULL DEFAULT '',
		sponsor_name TEXT NOT NULL DEFAULT '',
		proposed_on TEXT,
		text TEXT NOT NULL DEFAULT '',
		source_url TEXT NOT NULL DEFAULT '',
		sort_order INTEGER NOT NULL
	)`); err != nil {
		t.Fatalf("create bill amendments table: %v", err)
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
	if _, err := db.Exec(`
		INSERT INTO bill_versions (bill_id, id, label, title, stage, chamber, published_on, source_url, sort_order)
		VALUES ('C-2260', 'C-2260-v1', 'First reading', 'Depth Act first reading', 'House First Reading', 'House', '2026-06-01', 'https://www.parl.ca/version', 1)`); err != nil {
		t.Fatalf("insert version fixture: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO bill_amendments (bill_id, id, number, title, status, stage, sponsor_name, proposed_on, text, source_url, sort_order)
		VALUES ('C-2260', 'C-2260-a1', 'NDP-1', 'Add review clause', 'adopted', 'Committee', 'Jane Example', '2026-06-02', 'Clause 2 is amended...', 'https://www.parl.ca/amendment', 1)`); err != nil {
		t.Fatalf("insert amendment fixture: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite fixture: %v", err)
	}
	writeManifest(t, path, "bills/v1/index.sqlite")
}

func writeManifest(t *testing.T, sqlitePath, sqliteKey string) {
	t.Helper()
	data, err := os.ReadFile(sqlitePath)
	if err != nil {
		t.Fatalf("read sqlite fixture: %v", err)
	}
	sum := sha256.Sum256(data)
	manifest := fmt.Sprintf(`{"version":"v1","sqlite_key":%q,"sqlite_size_bytes":%d,"sqlite_sha256":"%x"}`, sqliteKey, len(data), sum[:])
	path := filepath.Join(filepath.Dir(sqlitePath), "manifest.json")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("write manifest fixture: %v", err)
	}
}
