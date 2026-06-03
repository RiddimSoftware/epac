package usecase

import (
	"database/sql"
	"errors"
	"testing"
)

type stubAggregator struct {
	err    error
	called bool
	db     *sql.DB
}

func (s *stubAggregator) BuildMPLobbyingTables(db *sql.DB) error {
	s.called = true
	s.db = db
	return s.err
}

func TestBuildMPLobbyingTables(t *testing.T) {
	db := &sql.DB{}
	aggregator := &stubAggregator{}

	if err := BuildMPLobbyingTables(db, aggregator); err != nil {
		t.Fatalf("BuildMPLobbyingTables returned error: %v", err)
	}
	if !aggregator.called {
		t.Fatal("expected aggregator to be called")
	}
	if aggregator.db != db {
		t.Fatal("expected open database to be passed through")
	}
}

func TestBuildMPLobbyingTablesRequiresDatabase(t *testing.T) {
	err := BuildMPLobbyingTables(nil, &stubAggregator{})
	if !errors.Is(err, ErrDatabaseRequired) {
		t.Fatalf("expected ErrDatabaseRequired, got %v", err)
	}
}

func TestBuildMPLobbyingTablesRequiresAggregator(t *testing.T) {
	err := BuildMPLobbyingTables(&sql.DB{}, nil)
	if !errors.Is(err, ErrAggregatorRequired) {
		t.Fatalf("expected ErrAggregatorRequired, got %v", err)
	}
}
