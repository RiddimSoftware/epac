package usecase

import (
	"context"
	"errors"
	"testing"
)

type stubAggregator struct {
	err          error
	called       bool
	databasePath string
}

func (s *stubAggregator) BuildMPLobbyingTables(_ context.Context, databasePath string) error {
	s.called = true
	s.databasePath = databasePath
	return s.err
}

func TestNewBuildMPLobbyingTablesRequiresAggregator(t *testing.T) {
	_, err := NewBuildMPLobbyingTables(nil, "/tmp/x.sqlite")
	if !errors.Is(err, ErrAggregatorRequired) {
		t.Fatalf("expected ErrAggregatorRequired, got %v", err)
	}
}

func TestNewBuildMPLobbyingTablesDefaultsDatabasePath(t *testing.T) {
	useCase, err := NewBuildMPLobbyingTables(&stubAggregator{}, "  ")
	if err != nil {
		t.Fatalf("NewBuildMPLobbyingTables returned error: %v", err)
	}
	if _, err := useCase.Execute(context.Background()); err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
}

func TestBuildMPLobbyingTablesExecuteCallsAggregator(t *testing.T) {
	aggregator := &stubAggregator{}
	useCase, err := NewBuildMPLobbyingTables(aggregator, "/tmp/mp-lobbying.sqlite")
	if err != nil {
		t.Fatalf("NewBuildMPLobbyingTables returned error: %v", err)
	}

	result, err := useCase.Execute(context.Background())
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if !aggregator.called {
		t.Fatal("expected aggregator to be called")
	}
	if aggregator.databasePath != "/tmp/mp-lobbying.sqlite" {
		t.Fatalf("expected aggregator to receive configured database path, got %q", aggregator.databasePath)
	}
	if result.DatabasePath != "/tmp/mp-lobbying.sqlite" {
		t.Fatalf("expected result.DatabasePath %q, got %q", "/tmp/mp-lobbying.sqlite", result.DatabasePath)
	}
}

func TestBuildMPLobbyingTablesExecutePropagatesError(t *testing.T) {
	sentinel := errors.New("aggregator boom")
	aggregator := &stubAggregator{err: sentinel}
	useCase, err := NewBuildMPLobbyingTables(aggregator, "/tmp/mp-lobbying.sqlite")
	if err != nil {
		t.Fatalf("NewBuildMPLobbyingTables returned error: %v", err)
	}
	if _, err := useCase.Execute(context.Background()); !errors.Is(err, sentinel) {
		t.Fatalf("expected wrapped sentinel error, got %v", err)
	}
}
