package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"testing"

	"epac/bills/internal/usecase"

	_ "modernc.org/sqlite"
)

func TestRepositoryGetBillVersionDiffMapsCurrentArtifactSchema(t *testing.T) {
	db := openDiffFixtureDB(t)
	defer db.Close()
	repo := New(db)

	diff, err := repo.GetBillVersionDiff(context.Background(), "C-2", "v1", "v2")
	if err != nil {
		t.Fatalf("GetBillVersionDiff error: %v", err)
	}
	if diff == nil {
		t.Fatal("diff = nil")
	}
	if diff.From.ID != "v1" || diff.From.Label != "First Reading" || diff.From.Stage != "First Reading" {
		t.Fatalf("from version = %+v", diff.From)
	}
	// Label mirrors the stage name (the producer has no separate label column),
	// and SourceURL is read from the producer's html_url column.
	if diff.From.SourceURL != "https://www.parl.ca/v1" {
		t.Fatalf("from source_url = %q", diff.From.SourceURL)
	}
	if diff.To.ID != "v2" || diff.To.Label != "Third Reading" {
		t.Fatalf("to version = %+v", diff.To)
	}
	if len(diff.Clauses) != 2 {
		t.Fatalf("clauses = %+v", diff.Clauses)
	}
	if diff.Clauses[0].ID != "clause-1" || diff.Clauses[0].ChangeType != "added" || diff.Clauses[0].FromText != "" {
		t.Fatalf("first clause = %+v", diff.Clauses[0])
	}
	if diff.Clauses[1].ID != "clause-2" || diff.Clauses[1].HansardAnchorURL == nil || *diff.Clauses[1].HansardAnchorURL != "https://hansard.test/clause-2" {
		t.Fatalf("second clause = %+v", diff.Clauses[1])
	}
}

func TestRepositoryGetBillVersionDiffReturnsVersionNotFoundForUnknownVersionPair(t *testing.T) {
	db := openDiffFixtureDB(t)
	defer db.Close()
	repo := New(db)

	diff, err := repo.GetBillVersionDiff(context.Background(), "C-2", "v1", "missing")
	if !errors.Is(err, usecase.ErrVersionNotFound) {
		t.Fatalf("error = %v, want ErrVersionNotFound", err)
	}
	if diff != nil {
		t.Fatalf("diff = %+v, want nil", diff)
	}
}

func TestRepositoryGetBillVersionDiffReturnsNilWhenVersionsExistButNoDiff(t *testing.T) {
	db := openDiffFixtureDB(t)
	defer db.Close()
	repo := New(db)

	diff, err := repo.GetBillVersionDiff(context.Background(), "C-2", "v2", "v1")
	if err != nil {
		t.Fatalf("GetBillVersionDiff error: %v", err)
	}
	if diff != nil {
		t.Fatalf("diff = %+v, want nil", diff)
	}
}

func TestRepositoryGetBillVersionDiffReturnsNilWhenDiffTablesAreAbsent(t *testing.T) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	db.SetMaxOpenConns(1)
	defer db.Close()
	if _, err := db.Exec(`
		CREATE TABLE bills (id TEXT PRIMARY KEY, number TEXT NOT NULL);
		INSERT INTO bills (id, number) VALUES ('13543613', 'C-2');
	`); err != nil {
		t.Fatalf("seed db: %v", err)
	}
	repo := New(db)

	diff, err := repo.GetBillVersionDiff(context.Background(), "C-2", "v1", "v2")
	if err != nil {
		t.Fatalf("GetBillVersionDiff error: %v", err)
	}
	if diff != nil {
		t.Fatalf("diff = %+v, want nil", diff)
	}
}

func TestRepositoryGetBillVersionDiffReturnsBillNotFound(t *testing.T) {
	db := openDiffFixtureDB(t)
	defer db.Close()
	repo := New(db)

	diff, err := repo.GetBillVersionDiff(context.Background(), "C-404", "v1", "v2")
	if !errors.Is(err, usecase.ErrBillNotFound) {
		t.Fatalf("error = %v, want ErrBillNotFound", err)
	}
	if diff != nil {
		t.Fatalf("diff = %+v, want nil", diff)
	}
}

func openDiffFixtureDB(t *testing.T) *sql.DB {
	t.Helper()

	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open db: %v", err)
	}
	db.SetMaxOpenConns(1)
	statements := []string{
		`CREATE TABLE bills (
			id TEXT PRIMARY KEY,
			number TEXT NOT NULL
		)`,
		`CREATE TABLE bill_versions (
			bill_id TEXT NOT NULL,
			id TEXT NOT NULL,
			stage TEXT NOT NULL DEFAULT '',
			html_url TEXT NOT NULL DEFAULT '',
			published_date TEXT,
			sort_order INTEGER NOT NULL DEFAULT 0
		)`,
		`CREATE TABLE bill_diffs (
			bill_id TEXT NOT NULL,
			id TEXT NOT NULL,
			from_version_id TEXT NOT NULL,
			to_version_id TEXT NOT NULL,
			source_url TEXT NOT NULL DEFAULT '',
			PRIMARY KEY (bill_id, id)
		)`,
		`CREATE TABLE bill_clause_diffs (
			bill_id TEXT NOT NULL,
			diff_id TEXT NOT NULL,
			id TEXT NOT NULL,
			label TEXT,
			change_type TEXT NOT NULL,
			from_text TEXT,
			to_text TEXT,
			hansard_anchor_url TEXT,
			sort_order INTEGER NOT NULL,
			PRIMARY KEY (bill_id, diff_id, id)
		)`,
		`INSERT INTO bills (id, number) VALUES ('13543613', 'C-2')`,
		`INSERT INTO bill_versions (bill_id, id, stage, html_url, published_date, sort_order) VALUES
			('13543613', 'v1', 'First Reading', 'https://www.parl.ca/v1', '2026-06-01', 1),
			('13543613', 'v2', 'Third Reading', 'https://www.parl.ca/v2', '2026-06-10', 2)`,
		`INSERT INTO bill_diffs (bill_id, id, from_version_id, to_version_id, source_url)
			VALUES ('13543613', 'diff-1', 'v1', 'v2', 'https://www.parl.ca/diff')`,
		`INSERT INTO bill_clause_diffs (
			bill_id, diff_id, id, label, change_type, from_text, to_text, hansard_anchor_url, sort_order
		) VALUES
			('13543613', 'diff-1', 'clause-2', 'Clause 2', 'modified', 'Old text', 'New text', 'https://hansard.test/clause-2', 2),
			('13543613', 'diff-1', 'clause-1', 'Clause 1', 'added', NULL, 'Inserted text', NULL, 1)`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			_ = db.Close()
			t.Fatalf("exec fixture statement: %v", err)
		}
	}
	return db
}
