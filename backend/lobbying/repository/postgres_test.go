package repository

import (
	"context"
	"errors"
	"strings"
	"testing"

	"epac/lobbying/application"

	"github.com/jackc/pgx/v5"
)

func TestNewPostgresLobbyistOrganizationRepositoryStoresQueryer(t *testing.T) {
	queryer := stubQueryer{}
	repo := NewPostgresLobbyistOrganizationRepository(queryer)

	if repo.db != queryer {
		t.Fatal("repository did not store queryer")
	}
}

type stubQueryer struct {
	Queryer
}

func TestBrowseLobbyistOrganizationsAppliesSearchSectorAndSort(t *testing.T) {
	queryer := &capturingQueryer{err: errors.New("stop after capture")}
	repo := NewPostgresLobbyistOrganizationRepository(queryer)

	_, err := repo.BrowseLobbyistOrganizations(context.Background(), application.BrowseLobbyistOrganizationsInput{
		Search:        "energy",
		Sector:        "Energy",
		Limit:         25,
		Offset:        50,
		SortDirection: "asc",
	})
	if !errors.Is(err, queryer.err) {
		t.Fatalf("BrowseLobbyistOrganizations err = %v, want capture error", err)
	}
	if !strings.Contains(queryer.sql, "name ILIKE '%' || $1 || '%'") {
		t.Fatalf("query missing name search predicate: %s", queryer.sql)
	}
	if !strings.Contains(queryer.sql, "LOWER(sector) = LOWER($2)") {
		t.Fatalf("query missing sector filter: %s", queryer.sql)
	}
	if !strings.Contains(queryer.sql, "ORDER BY communication_volume_current_parliament ASC") {
		t.Fatalf("query missing ascending communication sort: %s", queryer.sql)
	}
	wantArgs := []any{"energy", "Energy", 25, 50}
	if len(queryer.args) != len(wantArgs) {
		t.Fatalf("query args = %#v, want %#v", queryer.args, wantArgs)
	}
	for i := range wantArgs {
		if queryer.args[i] != wantArgs[i] {
			t.Fatalf("query arg %d = %#v, want %#v", i, queryer.args[i], wantArgs[i])
		}
	}
}

type capturingQueryer struct {
	Queryer
	sql  string
	args []any
	err  error
}

func (q *capturingQueryer) Query(_ context.Context, sql string, args ...any) (pgx.Rows, error) {
	q.sql = sql
	q.args = args
	return nil, q.err
}
