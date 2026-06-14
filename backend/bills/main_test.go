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
	"time"

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

func TestHandleRequestGetsBillCommitteeStage(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "13543613", Number: "C-2", Title: "Committee Act", Status: "InProgress", CurrentStage: "Consideration in committee", Parliament: &p45},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/bills/C-2/committee-stage",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body BillCommitteeStage
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Committee.Code != "SECU" || body.Committee.Name != "Standing Committee on Public Safety and National Security" {
		t.Fatalf("committee = %+v", body.Committee)
	}
	if body.StudiedSince == nil || *body.StudiedSince != "2026-06-03" {
		t.Fatalf("studied since = %+v", body.StudiedSince)
	}
	if len(body.UpcomingMeetings) != 1 || body.UpcomingMeetings[0].MeetingNumber != 42 {
		t.Fatalf("upcoming meetings = %+v", body.UpcomingMeetings)
	}
	if len(body.PastMeetings) != 1 || body.PastMeetings[0].MeetingNumber != 41 {
		t.Fatalf("past meetings = %+v", body.PastMeetings)
	}
	if body.PastMeetings[0].WitnessCount == nil || *body.PastMeetings[0].WitnessCount != 7 {
		t.Fatalf("past meeting witness count = %+v", body.PastMeetings[0].WitnessCount)
	}
}

func TestHandleRequestReturnsNoContentWhenBillHasNoCommitteeStage(t *testing.T) {
	dir := t.TempDir()
	p45 := 45
	writeBillSQLiteUnitFixture(t, dir, []Bill{
		{ID: "C-1", Number: "C-1", Title: "No Committee", Status: "InProgress", Parliament: &p45},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/bills/C-1/committee-stage",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 204 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
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
		return sqliteadapter.New(db, sqliteadapter.WithNow(func() time.Time {
			return time.Date(2026, 6, 14, 12, 0, 0, 0, time.UTC)
		}))
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
	if _, err := db.Exec(`CREATE TABLE bill_committee_stages (
		bill_id TEXT NOT NULL,
		id TEXT NOT NULL,
		stage_id TEXT NOT NULL DEFAULT '',
		stage_name TEXT NOT NULL DEFAULT '',
		chamber TEXT NOT NULL DEFAULT '',
		state TEXT NOT NULL DEFAULT '',
		committee_id TEXT NOT NULL DEFAULT '',
		committee_acronym TEXT NOT NULL DEFAULT '',
		committee_name TEXT NOT NULL DEFAULT '',
		committee_chamber TEXT NOT NULL DEFAULT '',
		committee_url TEXT NOT NULL DEFAULT '',
		studied_since TEXT,
		study_completed_at TEXT,
		sort_order INTEGER NOT NULL DEFAULT 0
	)`); err != nil {
		t.Fatalf("create bill committee stages table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE bill_committee_meetings (
		bill_id TEXT NOT NULL,
		stage_id TEXT NOT NULL,
		id TEXT NOT NULL,
		meeting_number INTEGER NOT NULL DEFAULT 0,
		meeting_date TEXT,
		evidence_url TEXT,
		witness_count INTEGER,
		sort_order INTEGER NOT NULL DEFAULT 0
	)`); err != nil {
		t.Fatalf("create bill committee meetings table: %v", err)
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
	if _, err := db.Exec(`
		INSERT INTO bill_committee_stages (
			bill_id, id, stage_id, stage_name, chamber, state, committee_id,
			committee_acronym, committee_name, committee_chamber, committee_url,
			studied_since, study_completed_at, sort_order
		) VALUES (
			'13543613', '13543613-committee-60049-secu', '60049', 'Consideration in committee',
			'House of Commons', 'In progress', '30576', 'SECU',
			'Standing Committee on Public Safety and National Security', 'HOC',
			'https://www.ourcommons.ca/Committees/en/SECU', '2026-06-03', NULL, 3
		)`); err != nil {
		t.Fatalf("insert committee stage fixture: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO bill_committee_meetings (
			bill_id, stage_id, id, meeting_number, meeting_date, evidence_url, witness_count, sort_order
		) VALUES
			('13543613', '13543613-committee-60049-secu', 'secu-41', 41, '2026-06-11', 'https://www.ourcommons.ca/DocumentViewer/en/45-1/SECU/meeting-41/evidence', 7, 1),
			('13543613', '13543613-committee-60049-secu', 'secu-42', 42, '2026-06-18', NULL, NULL, 2)`); err != nil {
		t.Fatalf("insert committee meeting fixture: %v", err)
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
