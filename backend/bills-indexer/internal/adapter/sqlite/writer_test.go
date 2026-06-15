package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"epac/bills-indexer/internal/domain"
	"epac/bills-indexer/internal/usecase"

	_ "modernc.org/sqlite"
)

func TestWriterCreatesBillsRelationalSchema(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "bills.db")
	writer := NewWriter(WithClock(fixedClock{}))

	stats, err := writer.Write(context.Background(), dbPath, domain.Batch{Bills: []domain.Bill{{
		ID:           "13543613",
		Number:       "C-2",
		Title:        "Border bill",
		SponsorName:  "Hon. Example",
		Status:       "At report stage",
		CurrentStage: "Report stage",
		Parliament:   45,
		Session:      1,
		Stages: []domain.BillStage{{
			ID: "60029", Name: "First reading", Chamber: "House of Commons", IsCompleted: true, SortOrder: 1,
		}},
		Events: []domain.BillEvent{{ID: "event-1", StageID: "60029", Name: "Introduction"}},
		Versions: []domain.BillVersion{{
			ID: "v1", Stage: "First Reading", HTMLURL: "https://example.test/html", XMLURL: "https://example.test/xml", SortOrder: 1,
			TextHash: ptrString("abc123hash"), TextSourceURL: ptrString("https://example.test/xml"),
		}},
		Diffs: []domain.BillDiff{{
			ID: "diff-1", FromVersionID: "v1", ToVersionID: "v2", SourceURL: "https://example.test/diff",
			Clauses: []domain.BillClauseDiff{{
				ID: "clause-1", Label: "1", ChangeType: "modified", FromText: "Old text", ToText: "New text", HansardAnchorURL: ptrString("https://hansard.test/anchor"),
			}},
		}},
		Amendments:  []domain.Amendment{{ID: "a1", EventID: "event-1", AmendmentCount: 1}},
		PBOCostings: []domain.PBOCosting{{ID: "p1", Title: "PBO costing", URL: "https://pbo.test"}},
		CommitteeStages: []domain.BillCommitteeStage{{
			ID:               "committee-1",
			StageID:          "60049",
			StageName:        "Consideration in committee",
			Chamber:          "House of Commons",
			State:            "In progress",
			CommitteeID:      "30576",
			CommitteeAcronym: "SECU",
			CommitteeName:    "Standing Committee on Public Safety and National Security",
			CommitteeChamber: "HOC",
			CommitteeURL:     "https://www.ourcommons.ca/Committees/en/SECU",
			StudiedSince:     "2026-06-03",
			Meetings: []domain.BillCommitteeMeeting{{
				ID:            "meeting-1",
				MeetingNumber: 42,
				Date:          "2026-06-18",
				EvidenceURL:   "https://www.ourcommons.ca/DocumentViewer/en/45-1/SECU/meeting-42/evidence",
				SortOrder:     1,
			}},
			SortOrder: 3,
		}},
	}}})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if stats.TableCounts["bills"] != 1 || stats.TableCounts["bill_versions"] != 1 || stats.TableCounts["pbo_costings"] != 1 || stats.TableCounts["bill_clause_diffs"] != 1 {
		t.Fatalf("table counts = %#v", stats.TableCounts)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()
	var stageName string
	if err := db.QueryRow("SELECT name FROM bill_stages WHERE bill_id = ?", "13543613").Scan(&stageName); err != nil {
		t.Fatalf("query stage: %v", err)
	}
	if stageName != "First reading" {
		t.Fatalf("stage name = %q", stageName)
	}
	var committeeAcronym string
	if err := db.QueryRow("SELECT committee_acronym FROM bill_committee_stages WHERE bill_id = ?", "13543613").Scan(&committeeAcronym); err != nil {
		t.Fatalf("query committee stage: %v", err)
	}
	if committeeAcronym != "SECU" {
		t.Fatalf("committee acronym = %q", committeeAcronym)
	}
	var meetingNumber int
	if err := db.QueryRow("SELECT meeting_number FROM bill_committee_meetings WHERE bill_id = ?", "13543613").Scan(&meetingNumber); err != nil {
		t.Fatalf("query committee meeting: %v", err)
	}
	if meetingNumber != 42 {
		t.Fatalf("meeting number = %d", meetingNumber)
	}

	var textHash, textSourceURL string
	if err := db.QueryRow("SELECT text_hash, text_source_url FROM bill_versions WHERE bill_id = ? AND id = ?", "13543613", "v1").Scan(&textHash, &textSourceURL); err != nil {
		t.Fatalf("query bill version text info: %v", err)
	}
	if textHash != "abc123hash" || textSourceURL != "https://example.test/xml" {
		t.Fatalf("text_hash = %q, text_source_url = %q", textHash, textSourceURL)
	}

	var changeType, fromText, toText, hansardAnchor string
	if err := db.QueryRow("SELECT change_type, from_text, to_text, hansard_anchor_url FROM bill_clause_diffs WHERE bill_id = ? AND diff_id = ? AND id = ?", "13543613", "diff-1", "clause-1").Scan(&changeType, &fromText, &toText, &hansardAnchor); err != nil {
		t.Fatalf("query bill clause diff: %v", err)
	}
	if changeType != "modified" || fromText != "Old text" || toText != "New text" || hansardAnchor != "https://hansard.test/anchor" {
		t.Fatalf("clause diff fields mismatch: %q, %q, %q, %q", changeType, fromText, toText, hansardAnchor)
	}
}

func TestWriterStoresMultipleBillVersionDiffPairs(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "bills_pairs.db")
	writer := NewWriter(WithClock(fixedClock{}))

	v1 := domain.BillVersion{
		ID:        "v1",
		SortOrder: 1,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "A"},
			{Label: "2", Text: "B"},
		},
		TextHash:      ptrString("h1"),
		TextSourceURL: ptrString("s1"),
	}
	v2 := domain.BillVersion{
		ID:        "v2",
		SortOrder: 2,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "A modified"},
			{Label: "2", Text: "B"},
		},
		TextHash:      ptrString("h2"),
		TextSourceURL: ptrString("s2"),
	}
	v3 := domain.BillVersion{
		ID:        "v3",
		SortOrder: 3,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "A modified"},
			{Label: "3", Text: "C"},
		},
		TextHash:      ptrString("h3"),
		TextSourceURL: ptrString("s3"),
	}

	// Compute all pairs using the use case policy
	diffs := usecase.ComputeBillVersionDiff("C-2", []domain.BillVersion{v1, v2, v3}, "https://example.test/bill")

	bill := domain.Bill{
		ID:       "13543613",
		Number:   "C-2",
		Title:    "Border bill",
		Versions: []domain.BillVersion{v1, v2, v3},
		Diffs:    diffs,
	}

	stats, err := writer.Write(context.Background(), dbPath, domain.Batch{Bills: []domain.Bill{bill}})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if stats.DiffCount != 3 {
		t.Errorf("expected 3 diffs written to stats, got %d", stats.DiffCount)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	// Assert pair count (should be 3 pairs: v1->v2, v1->v3, v2->v3)
	var pairCount int
	if err := db.QueryRow("SELECT COUNT(*) FROM bill_diffs WHERE bill_id = ?", "13543613").Scan(&pairCount); err != nil {
		t.Fatalf("query bill_diffs count: %v", err)
	}
	if pairCount != 3 {
		t.Fatalf("expected 3 diff pairs, got %d", pairCount)
	}

	// Assert stable IDs and presence of adjacent and non-adjacent pairs
	expectedPairs := map[string]struct {
		from string
		to   string
	}{
		"diff-c-2-v1-v2": {from: "v1", to: "v2"},
		"diff-c-2-v1-v3": {from: "v1", to: "v3"},
		"diff-c-2-v2-v3": {from: "v2", to: "v3"},
	}

	rows, err := db.Query("SELECT id, from_version_id, to_version_id FROM bill_diffs WHERE bill_id = ?", "13543613")
	if err != nil {
		t.Fatalf("query bill_diffs: %v", err)
	}
	defer rows.Close()

	for rows.Next() {
		var id, fromVal, toVal string
		if err := rows.Scan(&id, &fromVal, &toVal); err != nil {
			t.Fatalf("scan bill_diff: %v", err)
		}
		expected, found := expectedPairs[id]
		if !found {
			t.Errorf("unexpected diff ID stored: %q", id)
			continue
		}
		if expected.from != fromVal || expected.to != toVal {
			t.Errorf("mismatched versions for diff %q: expected %s->%s, got %s->%s", id, expected.from, expected.to, fromVal, toVal)
		}
	}

	// Assert representative bill_clause_diffs rows
	// For v1->v2 (adjacent): clause 1 modified, clause 2 unchanged
	var v1v2C1Change, v1v2C2Change string
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v1-v2", "1").Scan(&v1v2C1Change)
	if err != nil {
		t.Fatalf("query v1->v2 clause 1 change: %v", err)
	}
	if v1v2C1Change != "modified" {
		t.Errorf("expected v1->v2 clause 1 to be modified, got %q", v1v2C1Change)
	}
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v1-v2", "2").Scan(&v1v2C2Change)
	if err != nil {
		t.Fatalf("query v1->v2 clause 2 change: %v", err)
	}
	if v1v2C2Change != "unchanged" {
		t.Errorf("expected v1->v2 clause 2 to be unchanged, got %q", v1v2C2Change)
	}

	// For v1->v3 (non-adjacent): clause 1 modified, clause 2 removed, clause 3 added
	var v1v3C1Change, v1v3C2Change, v1v3C3Change string
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v1-v3", "1").Scan(&v1v3C1Change)
	if err != nil {
		t.Fatalf("query v1->v3 clause 1 change: %v", err)
	}
	if v1v3C1Change != "modified" {
		t.Errorf("expected v1->v3 clause 1 to be modified, got %q", v1v3C1Change)
	}
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v1-v3", "2").Scan(&v1v3C2Change)
	if err != nil {
		t.Fatalf("query v1->v3 clause 2 change: %v", err)
	}
	if v1v3C2Change != "removed" {
		t.Errorf("expected v1->v3 clause 2 to be removed, got %q", v1v3C2Change)
	}
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v1-v3", "3").Scan(&v1v3C3Change)
	if err != nil {
		t.Fatalf("query v1->v3 clause 3 change: %v", err)
	}
	if v1v3C3Change != "added" {
		t.Errorf("expected v1->v3 clause 3 to be added, got %q", v1v3C3Change)
	}

	// For v2->v3 (adjacent): clause 1 unchanged, clause 2 removed, clause 3 added
	var v2v3C1Change, v2v3C2Change, v2v3C3Change string
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v2-v3", "1").Scan(&v2v3C1Change)
	if err != nil {
		t.Fatalf("query v2->v3 clause 1 change: %v", err)
	}
	if v2v3C1Change != "unchanged" {
		t.Errorf("expected v2->v3 clause 1 to be unchanged, got %q", v2v3C1Change)
	}
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v2-v3", "2").Scan(&v2v3C2Change)
	if err != nil {
		t.Fatalf("query v2->v3 clause 2 change: %v", err)
	}
	if v2v3C2Change != "removed" {
		t.Errorf("expected v2->v3 clause 2 to be removed, got %q", v2v3C2Change)
	}
	err = db.QueryRow("SELECT change_type FROM bill_clause_diffs WHERE diff_id = ? AND label = ?", "diff-c-2-v2-v3", "3").Scan(&v2v3C3Change)
	if err != nil {
		t.Fatalf("query v2->v3 clause 3 change: %v", err)
	}
	if v2v3C3Change != "added" {
		t.Errorf("expected v2->v3 clause 3 to be added, got %q", v2v3C3Change)
	}
}

type fixedClock struct{}

func (fixedClock) Now() time.Time {
	return time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC)
}

func ptrString(s string) *string {
	return &s
}
