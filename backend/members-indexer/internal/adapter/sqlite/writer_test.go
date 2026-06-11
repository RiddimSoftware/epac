package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
	"time"

	"epac/members-indexer/internal/domain"

	_ "modernc.org/sqlite"
)

func TestWriterCreatesMembersRelationalSchema(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "members.db")
	writer := NewWriter(WithClock(fixedClock{}))

	stats, err := writer.Write(context.Background(), dbPath, domain.Batch{Members: []domain.Member{{
		ID:        "89156",
		Name:      "Jane Example",
		Riding:    "Ottawa Centre",
		Province:  "Ontario",
		Party:     "Liberal",
		SourceURL: "https://www.ourcommons.ca/Members/en/search/XML",
		Biography: domain.Biography{
			MemberID:          "89156",
			Summary:           "Jane Example - Member of Parliament",
			PreferredLanguage: "English / French",
			SourceURL:         "https://www.ourcommons.ca/Members/en/89156",
		},
		Attendance: []domain.AttendanceRecord{{
			ID: "vote-151", VoteNumber: "151", Subject: "Report stage", Ballot: "Yea", Result: "Agreed To",
		}},
		PMBSponsorships: []domain.PMBSponsorship{{
			ID: "sponsored-c-234", BillNumber: "C-234", Title: "Living Donor Recognition Medal Act", Relationship: "sponsored",
		}},
	}}})
	if err != nil {
		t.Fatalf("Write: %v", err)
	}
	if stats.TableCounts["members"] != 1 || stats.TableCounts["attendance_records"] != 1 || stats.TableCounts["pmb_sponsorships"] != 1 {
		t.Fatalf("table counts = %#v", stats.TableCounts)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()
	var party string
	if err := db.QueryRow("SELECT party FROM members WHERE id = ?", "89156").Scan(&party); err != nil {
		t.Fatalf("query member: %v", err)
	}
	if party != "Liberal" {
		t.Fatalf("party = %q", party)
	}
}

type fixedClock struct{}

func (fixedClock) Now() time.Time {
	return time.Date(2026, 6, 10, 12, 0, 0, 0, time.UTC)
}
