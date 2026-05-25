package sqlitefts5

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"

	"epac/hansard-search-index/internal/adapter/ourcommons"
	"epac/hansard-search-index/internal/domain"
)

func TestBuildCreatesSchemaAndMatchesInsertedMessages(t *testing.T) {
	path := filepath.Join(t.TempDir(), "index.sqlite")
	builder := NewBuilder(path, fixedClock{})
	_, stats, err := builder.Build(context.Background(), []domain.Intervention{sampleIntervention()})
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if stats.MessageCount != 2 {
		t.Fatalf("message count = %d, want 2", stats.MessageCount)
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	assertTableExists(t, db, "meta")
	assertTableExists(t, db, "interventions")
	assertTableExists(t, db, "messages")
	assertTableExists(t, db, "messages_fts")

	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH ?", "parliament").Scan(&count); err != nil {
		t.Fatalf("match query: %v", err)
	}
	if count != 1 {
		t.Fatalf("match count = %d, want 1", count)
	}

	var version string
	if err := db.QueryRow("SELECT value FROM meta WHERE key = 'version'").Scan(&version); err != nil {
		t.Fatalf("read meta version: %v", err)
	}
	if version != "v1" {
		t.Fatalf("version = %q, want v1", version)
	}
}

func TestFixtureToSQLiteIntegrationMatchesKnownPhrase(t *testing.T) {
	fixture := filepath.Join("..", "..", "..", "testdata", "hansard_451_001_slice.xml")
	body, err := os.ReadFile(fixture)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}
	interventions, err := ourcommons.NewParser(nil).Parse(body)
	if err != nil {
		t.Fatalf("parse fixture: %v", err)
	}

	path := filepath.Join(t.TempDir(), "index.sqlite")
	_, stats, err := NewBuilder(path, fixedClock{}).Build(context.Background(), interventions)
	if err != nil {
		t.Fatalf("Build: %v", err)
	}
	if stats.InterventionCount != 2 || stats.MessageCount != 3 {
		t.Fatalf("stats = %#v, want 2 interventions and 3 messages", stats)
	}

	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	var interventionID string
	err = db.QueryRow(`
SELECT i.intervention_id
FROM messages_fts f
JOIN messages m ON m.rowid = f.rowid
JOIN interventions i ON i.rowid = m.intervention_rowid
WHERE messages_fts MATCH ?
ORDER BY m.position
LIMIT 1`, "withdrawing").Scan(&interventionID)
	if err != nil {
		t.Fatalf("known phrase match: %v", err)
	}
	if interventionID != "13077673" {
		t.Fatalf("match intervention = %q, want 13077673", interventionID)
	}
}

func assertTableExists(t *testing.T, db *sql.DB, table string) {
	t.Helper()
	var count int
	if err := db.QueryRow("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?", table).Scan(&count); err != nil {
		t.Fatalf("table lookup %s: %v", table, err)
	}
	if count != 1 {
		t.Fatalf("table %s exists count = %d, want 1", table, count)
	}
}

func sampleIntervention() domain.Intervention {
	return domain.Intervention{
		ParliamentNumber:  45,
		SessionNumber:     1,
		SittingDate:       time.Date(2025, 5, 26, 0, 0, 0, 0, time.UTC),
		InterventionID:    "i-1",
		SpeakerFirstName:  "John",
		SpeakerLastName:   "Nater",
		PartyAbbreviation: "CPC",
		RidingName:        "Perth-Wellington",
		Topic:             "Election of Speaker",
		Messages: []domain.Message{
			{MessageID: "m-1", Position: 1, Text: "Parliament should test full text search."},
			{MessageID: "m-2", Position: 2, Text: "The index should keep message rows aligned."},
		},
	}
}

type fixedClock struct{}

func (fixedClock) Now() time.Time {
	return time.Date(2026, 5, 25, 17, 30, 0, 0, time.UTC)
}
