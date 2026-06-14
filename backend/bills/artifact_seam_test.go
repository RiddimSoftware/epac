package main

// This is the producer-to-consumer seam test for the bills SQLite artifact
// (EPAC-2304). The artifact schema is an implicit contract between two separate
// binaries: the bills-indexer writer (producer) and the bills serving
// repository (consumer). Per-unit fixtures on either side can drift apart
// without anyone noticing, because the serving repository used to mask missing
// columns with NULL fallbacks. This test crosses the *real* seam: it drives the
// real producer binary to write a real bills.db from a fixture batch, then
// opens that file with the real serving repository and asserts the served shape
// is populated from columns the producer actually writes — no NULL fallbacks.
//
// The two adapters live in separate Go modules and are internal to each, so
// (matching the issue's guidance) we do not import one's internals into the
// other. The only thing shared across the seam is the on-disk SQLite file, just
// like in production: the producer runs as a binary and the consumer reads its
// output.
//
// Contract decision recorded here and in
// docs/architecture/bills-artifact-contract-epac2304.md: the bills-indexer's
// bill_versions table records only a publication stage name and a canonical
// viewer URL (html_url) per version. It has no label, title, or chamber column
// and never populates a published date. The served BillVersion therefore
// exposes exactly {id, label, stage, source_url}, where label and stage both
// carry the stage name and source_url is html_url. The previously-served title,
// chamber, and published_on fields were always empty and have been dropped from
// the domain model and OpenAPI.

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	sqliteadapter "epac/bills/internal/adapter/sqlite"

	_ "modernc.org/sqlite"
)

func TestBillsArtifactSeam(t *testing.T) {
	batchJSON := contractFixtureBatchJSON(t)
	dbPath := buildContractArtifact(t, batchJSON)

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open produced artifact: %v", err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1)
	repo := sqliteadapter.New(db, sqliteadapter.WithNow(func() time.Time {
		return time.Date(2026, 6, 14, 12, 0, 0, 0, time.UTC)
	}))
	ctx := context.Background()

	// ListBills must read the bills + bill_stages tables the producer wrote.
	bills, err := repo.ListBills(ctx)
	if err != nil {
		t.Fatalf("ListBills: %v", err)
	}
	if len(bills) != 1 || bills[0].ID != "13543613" || bills[0].Number != "C-2" {
		t.Fatalf("ListBills = %+v", bills)
	}
	if len(bills[0].Stages) != 2 || bills[0].Stages[0].Name != "First reading" {
		t.Fatalf("ListBills stages = %+v", bills[0].Stages)
	}

	// GetBillDepth assembles bill + stages + versions + amendments from the
	// produced artifact.
	bill, err := repo.GetBillDepth(ctx, "13543613")
	if err != nil {
		t.Fatalf("GetBillDepth: %v", err)
	}
	if bill.ID != "13543613" || bill.Title == "" {
		t.Fatalf("GetBillDepth bill = %+v", bill)
	}
	if len(bill.Stages) != 2 {
		t.Fatalf("GetBillDepth stages = %+v", bill.Stages)
	}
	if len(bill.Versions) != 2 {
		t.Fatalf("GetBillDepth versions = %+v", bill.Versions)
	}
	// Promised version columns are populated from real producer columns.
	v1 := bill.Versions[0]
	if v1.ID != "C-2-v1" || v1.Label != "First Reading" || v1.Stage != "First Reading" {
		t.Fatalf("version[0] = %+v", v1)
	}
	if v1.SourceURL == "" {
		t.Fatalf("version[0] source_url empty; expected the producer html_url")
	}
	// Amendments expose the producer-backed fields (id, source_url).
	if len(bill.Amendments) != 1 || bill.Amendments[0].ID != "C-2-a1" || bill.Amendments[0].SourceURL == "" {
		t.Fatalf("GetBillDepth amendments = %+v", bill.Amendments)
	}

	// GetBillVersionDiff is the bill-diff route's read. Both endpoints of the
	// diff and every clause must be populated from the produced artifact.
	diff, err := repo.GetBillVersionDiff(ctx, "13543613", "C-2-v1", "C-2-v2")
	if err != nil {
		t.Fatalf("GetBillVersionDiff: %v", err)
	}
	if diff == nil {
		t.Fatal("GetBillVersionDiff = nil; expected a populated diff")
	}
	if diff.From.ID != "C-2-v1" || diff.From.Label != "First Reading" || diff.From.Stage != "First Reading" || diff.From.SourceURL == "" {
		t.Fatalf("diff.From = %+v", diff.From)
	}
	if diff.To.ID != "C-2-v2" || diff.To.Label != "Third Reading" || diff.To.Stage != "Third Reading" || diff.To.SourceURL == "" {
		t.Fatalf("diff.To = %+v", diff.To)
	}
	if len(diff.Clauses) != 2 {
		t.Fatalf("diff.Clauses = %+v", diff.Clauses)
	}
	if diff.Clauses[0].ID != "C-2-clause-1" || diff.Clauses[0].ChangeType != "added" || diff.Clauses[0].FromText != "" || diff.Clauses[0].ToText == "" {
		t.Fatalf("clause[0] = %+v", diff.Clauses[0])
	}
	if diff.Clauses[1].ID != "C-2-clause-2" || diff.Clauses[1].ChangeType != "modified" ||
		diff.Clauses[1].HansardAnchorURL == nil || *diff.Clauses[1].HansardAnchorURL == "" {
		t.Fatalf("clause[1] = %+v", diff.Clauses[1])
	}
}

// buildContractArtifact builds the bills-indexer binary and runs it in offline
// fixture mode to write a real SQLite artifact from batchJSON, returning the
// path to the produced bills.db. Only the on-disk file crosses the seam.
func buildContractArtifact(t *testing.T, batchJSON []byte) string {
	t.Helper()

	indexerDir, err := filepath.Abs("../bills-indexer")
	if err != nil {
		t.Fatalf("resolve bills-indexer dir: %v", err)
	}
	if _, err := os.Stat(filepath.Join(indexerDir, "main.go")); err != nil {
		t.Fatalf("bills-indexer producer not found at %s: %v", indexerDir, err)
	}

	tmp := t.TempDir()
	fixturePath := filepath.Join(tmp, "batch.json")
	if err := os.WriteFile(fixturePath, batchJSON, 0o644); err != nil {
		t.Fatalf("write fixture batch: %v", err)
	}
	dbPath := filepath.Join(tmp, "bills.db")
	binPath := filepath.Join(tmp, "bills-indexer-bin")

	ctx, cancel := context.WithTimeout(context.Background(), 4*time.Minute)
	defer cancel()

	build := exec.CommandContext(ctx, "go", "build", "-o", binPath, ".")
	build.Dir = indexerDir
	var buildOut bytes.Buffer
	build.Stdout = &buildOut
	build.Stderr = &buildOut
	if err := build.Run(); err != nil {
		t.Fatalf("build bills-indexer producer: %v\n%s", err, buildOut.String())
	}

	run := exec.CommandContext(ctx, binPath)
	run.Env = append(os.Environ(),
		"BILLS_FIXTURE_BATCH="+fixturePath,
		"DB_PATH="+dbPath,
	)
	var runOut bytes.Buffer
	run.Stdout = &runOut
	run.Stderr = &runOut
	if err := run.Run(); err != nil {
		t.Fatalf("run bills-indexer producer offline: %v\n%s", err, runOut.String())
	}
	if _, err := os.Stat(dbPath); err != nil {
		t.Fatalf("producer did not write artifact at %s: %v\n%s", dbPath, err, runOut.String())
	}
	return dbPath
}

// contractFixtureBatchJSON is a representative bills-indexer batch serialized
// with the producer domain's field names. Keeping it here (rather than
// importing the producer's internal domain types) preserves the module
// boundary: the producer decodes it into its own domain.Batch.
func contractFixtureBatchJSON(t *testing.T) []byte {
	t.Helper()

	batch := map[string]any{
		"Bills": []map[string]any{{
			"ID":           "13543613",
			"Number":       "C-2",
			"Title":        "An Act respecting certain measures relating to border security",
			"ShortTitle":   "Strong Borders Act",
			"SponsorName":  "Hon. Example Minister",
			"Status":       "At third reading",
			"CurrentStage": "Third reading",
			"IntroducedOn": "2026-05-01",
			"SourceURL":    "https://www.parl.ca/legisinfo/en/bill/45-1/c-2",
			"BillType":     "House Government Bill",
			"Parliament":   45,
			"Session":      1,
			"LegisInfoURL": "https://www.parl.ca/legisinfo/en/bill/45-1/c-2",
			"Stages": []map[string]any{
				{"ID": "60029", "Name": "First reading", "Chamber": "House of Commons", "State": "Completed", "CompletedDate": "2026-05-01", "SortOrder": 1, "IsCompleted": true},
				{"ID": "60030", "Name": "Third reading", "Chamber": "House of Commons", "State": "In progress", "SortOrder": 2, "IsCompleted": false},
			},
			"Versions": []map[string]any{
				{"ID": "C-2-v1", "PublicationID": "1001", "Stage": "First Reading", "StageSlug": "first-reading", "HTMLURL": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-2/first-reading", "XMLURL": "https://www.parl.ca/Content/Bills/451/Government/C-2/C-2_1/C-2_E.xml", "Source": "LEGISinfo publication", "SortOrder": 1},
				{"ID": "C-2-v2", "PublicationID": "1002", "Stage": "Third Reading", "StageSlug": "third-reading", "HTMLURL": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-2/third-reading", "XMLURL": "https://www.parl.ca/Content/Bills/451/Government/C-2/C-2_3/C-2_E.xml", "Source": "LEGISinfo publication", "SortOrder": 2},
			},
			"Diffs": []map[string]any{{
				"ID":            "C-2-diff-v1-v2",
				"FromVersionID": "C-2-v1",
				"ToVersionID":   "C-2-v2",
				"SourceURL":     "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-2/diff",
				"Clauses": []map[string]any{
					{"ID": "C-2-clause-1", "Label": "1", "ChangeType": "added", "FromText": "", "ToText": "Inserted clause 1 text.", "HansardAnchorURL": nil},
					{"ID": "C-2-clause-2", "Label": "2", "ChangeType": "modified", "FromText": "Old clause 2 text.", "ToText": "New clause 2 text.", "HansardAnchorURL": "https://www.ourcommons.ca/hansard#clause-2"},
				},
			}},
			"Amendments": []map[string]any{
				{"ID": "C-2-a1", "EventID": "event-1", "StageName": "Consideration in committee", "AmendmentNoteID": "note-1", "AmendmentCount": 3, "SourceURL": "https://www.parl.ca/DocumentViewer/en/45-1/bill/C-2/amendments"},
			},
		}},
	}

	data, err := json.Marshal(batch)
	if err != nil {
		t.Fatalf("marshal fixture batch: %v", err)
	}
	return data
}
