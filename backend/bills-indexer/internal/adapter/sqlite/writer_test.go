package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"epac/bills-indexer/internal/domain"

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

type fixedClock struct{}

func (fixedClock) Now() time.Time {
	return time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC)
}

func ptrString(s string) *string {
	return &s
}
