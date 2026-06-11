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
		}},
		Amendments:  []domain.Amendment{{ID: "a1", EventID: "event-1", AmendmentCount: 1}},
		PBOCostings: []domain.PBOCosting{{ID: "p1", Title: "PBO costing", URL: "https://pbo.test"}},
	}}})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if stats.TableCounts["bills"] != 1 || stats.TableCounts["bill_versions"] != 1 || stats.TableCounts["pbo_costings"] != 1 {
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
}

type fixedClock struct{}

func (fixedClock) Now() time.Time {
	return time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC)
}
