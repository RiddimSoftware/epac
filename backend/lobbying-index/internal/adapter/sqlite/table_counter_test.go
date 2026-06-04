package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"

	_ "modernc.org/sqlite"
)

func TestCountTables(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "counts.sqlite")
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if _, err := db.Exec(`
CREATE TABLE first_table (id TEXT PRIMARY KEY);
CREATE TABLE second_table (id TEXT PRIMARY KEY);
INSERT INTO first_table (id) VALUES ('a'), ('b');
INSERT INTO second_table (id) VALUES ('c');`); err != nil {
		t.Fatalf("seed sqlite: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite fixture: %v", err)
	}

	counts, err := CountTables(context.Background(), dbPath)
	if err != nil {
		t.Fatalf("CountTables returned error: %v", err)
	}
	if counts["first_table"] != 2 {
		t.Fatalf("expected first_table count 2, got %d", counts["first_table"])
	}
	if counts["second_table"] != 1 {
		t.Fatalf("expected second_table count 1, got %d", counts["second_table"])
	}
}
