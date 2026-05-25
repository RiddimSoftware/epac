package sqlitefts5_test

import (
	"context"
	"database/sql"
	"errors"
	"path/filepath"
	"testing"

	"epac/hansard-search/internal/adapter/sqlitefts5"
	"epac/hansard-search/internal/usecase"

	_ "modernc.org/sqlite"
)

func TestRepositorySearchSimpleWordMatch(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	results, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "climate"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if results.Total != 2 || len(results.Hits) != 2 {
		t.Fatalf("results = %#v, want 2 hits", results)
	}
	if results.Hits[0].Snippet == "" || results.Hits[1].Snippet == "" {
		t.Fatalf("expected snippets for all hits: %#v", results.Hits)
	}
}

func TestRepositorySearchPhraseMatch(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	results, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "\"climate change\""},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if results.Total != 2 || len(results.Hits) != 2 {
		t.Fatalf("results = %#v, want 2 phrase hits", results)
	}
}

func TestRepositorySearchSupportsBooleanOperators(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	tests := []struct {
		name        string
		query       string
		wantTotal   int
		wantMessage string
	}{
		{name: "and", query: "climate AND parliament", wantTotal: 1, wantMessage: "message-1"},
		{name: "or", query: "energy OR housing", wantTotal: 3},
		{name: "not", query: "climate NOT parliament", wantTotal: 1, wantMessage: "message-4"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			results, err := sqlitefts5.New(db).Search(
				context.Background(),
				usecase.SearchQuery{Query: tt.query},
				usecase.Pagination{Page: 1, PerPage: 10},
			)
			if err != nil {
				t.Fatalf("Search returned error: %v", err)
			}
			if results.Total != tt.wantTotal || len(results.Hits) != tt.wantTotal {
				t.Fatalf("results = %#v, want %d hits", results, tt.wantTotal)
			}
			if tt.wantMessage != "" && results.Hits[0].MessageID != tt.wantMessage {
				t.Fatalf("message id = %q, want %q", results.Hits[0].MessageID, tt.wantMessage)
			}
		})
	}
}

func TestRepositorySearchSupportsSpeakerFilter(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	results, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "climate", Speaker: "jAnE"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if results.Total != 2 || len(results.Hits) != 2 {
		t.Fatalf("results = %#v, want 2 speaker-filtered hits", results)
	}
}

func TestRepositorySearchSupportsTopicFilter(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	results, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "climate", Topic: "housing"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if results.Total != 1 || len(results.Hits) != 1 {
		t.Fatalf("results = %#v, want 1 topic-filtered hit", results)
	}
	if results.Hits[0].MessageID != "message-4" {
		t.Fatalf("message id = %q, want message-4", results.Hits[0].MessageID)
	}
}

func TestRepositorySearchSupportsPagination(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	pageOne, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "climate"},
		usecase.Pagination{Page: 1, PerPage: 1},
	)
	if err != nil {
		t.Fatalf("page 1 Search returned error: %v", err)
	}
	pageTwo, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "climate"},
		usecase.Pagination{Page: 2, PerPage: 1},
	)
	if err != nil {
		t.Fatalf("page 2 Search returned error: %v", err)
	}

	if pageOne.Total != 2 || pageTwo.Total != 2 {
		t.Fatalf("totals = %d and %d, want 2", pageOne.Total, pageTwo.Total)
	}
	if len(pageOne.Hits) != 1 || len(pageTwo.Hits) != 1 {
		t.Fatalf("page sizes = %d and %d, want 1 each", len(pageOne.Hits), len(pageTwo.Hits))
	}
	if pageOne.Hits[0].MessageID == pageTwo.Hits[0].MessageID {
		t.Fatalf("expected distinct paginated hits, got %q twice", pageOne.Hits[0].MessageID)
	}
}

func TestRepositorySearchReturnsEmptyResults(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	results, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "fisheries"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Search returned error: %v", err)
	}
	if results.Total != 0 || len(results.Hits) != 0 {
		t.Fatalf("results = %#v, want no hits", results)
	}
}

func TestRepositorySearchReturnsInvalidQuerySyntax(t *testing.T) {
	db := openFixtureDB(t)
	defer db.Close()

	_, err := sqlitefts5.New(db).Search(
		context.Background(),
		usecase.SearchQuery{Query: "\"unclosed"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if !errors.Is(err, usecase.ErrInvalidQuerySyntax) {
		t.Fatalf("error = %v, want ErrInvalidQuerySyntax", err)
	}
}

func openFixtureDB(t *testing.T) *sql.DB {
	t.Helper()

	path := filepath.Join(t.TempDir(), "fixture.sqlite")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}

	statements := []string{
		`CREATE TABLE interventions (
			rowid INTEGER PRIMARY KEY,
			parliament_number INTEGER NOT NULL,
			session_number INTEGER NOT NULL,
			sitting_date TEXT NOT NULL,
			intervention_id TEXT NOT NULL UNIQUE,
			speaker_name TEXT NOT NULL,
			party_abbreviation TEXT NOT NULL DEFAULT '',
			riding_name TEXT NOT NULL DEFAULT '',
			topic TEXT NOT NULL DEFAULT ''
		)`,
		`CREATE TABLE messages (
			rowid INTEGER PRIMARY KEY,
			intervention_rowid INTEGER NOT NULL REFERENCES interventions(rowid),
			message_id TEXT NOT NULL UNIQUE,
			position INTEGER NOT NULL,
			content TEXT NOT NULL
		)`,
		`CREATE VIRTUAL TABLE messages_fts USING fts5(content)`,
		`INSERT INTO interventions (rowid, parliament_number, session_number, sitting_date, intervention_id, speaker_name, party_abbreviation, riding_name, topic) VALUES
			(1, 45, 1, '2026-05-20', 'intervention-1', 'Jane Smith', 'LIB', 'Ottawa Centre', 'Climate Action'),
			(2, 45, 1, '2026-05-21', 'intervention-2', 'Bob Brown', 'CPC', 'Calgary West', 'Energy Policy'),
			(3, 45, 1, '2026-05-22', 'intervention-3', 'Alice Green', 'NDP', 'Toronto Centre', 'Housing'),
			(4, 45, 1, '2026-05-23', 'intervention-4', 'Jane Smith', 'LIB', 'Ottawa Centre', 'Climate Housing')`,
		`INSERT INTO messages (rowid, intervention_rowid, message_id, position, content) VALUES
			(1, 1, 'message-1', 1, 'Climate change demands urgent action from Parliament.'),
			(2, 2, 'message-2', 1, 'Reliable energy policy should protect workers.'),
			(3, 3, 'message-3', 1, 'Housing affordability is central to this debate.'),
			(4, 4, 'message-4', 1, 'Climate change affects housing supply.')`,
		`INSERT INTO messages_fts (rowid, content) VALUES
			(1, 'Climate change demands urgent action from Parliament.'),
			(2, 'Reliable energy policy should protect workers.'),
			(3, 'Housing affordability is central to this debate.'),
			(4, 'Climate change affects housing supply.')`,
	}

	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			db.Close()
			t.Fatalf("exec %q: %v", statement, err)
		}
	}

	return db
}
