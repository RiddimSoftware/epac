//go:build integration

package postgres

import (
	"context"
	"testing"

	"epac/_testdb"
	"epac/lobbying/internal/usecase"

	"github.com/jackc/pgx/v5"
)

func TestRepositoryListByOCLCodesReturnsCommunicationsAndRegistrationsPaged(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		resetLobbyingRows(t, conn)
		seedLobbyingRows(t, conn)

		repo := New(conn)
		page, err := repo.ListByOCLCodes(context.Background(), []usecase.OCLTopicMapping{
			{OCLCode: "SMT-44", EpacTopicSlug: "housing", Confidence: 1},
		}, usecase.Pagination{Page: 1, PerPage: 1})
		if err != nil {
			t.Fatalf("ListByOCLCodes page 1: %v", err)
		}
		if page.Total != 2 || len(page.Rows) != 1 {
			t.Fatalf("page 1 = %#v", page)
		}
		if page.Rows[0].Kind != "communication" || page.Rows[0].OCLID != "COM-2" {
			t.Fatalf("unexpected first row: %#v", page.Rows[0])
		}
		if page.Rows[0].Citation != usecase.Citation || page.Rows[0].SourceURL == "" {
			t.Fatalf("first row missing source fields: %#v", page.Rows[0])
		}

		page, err = repo.ListByOCLCodes(context.Background(), []usecase.OCLTopicMapping{
			{OCLCode: "SMT-44", EpacTopicSlug: "housing", Confidence: 1},
		}, usecase.Pagination{Page: 2, PerPage: 1})
		if err != nil {
			t.Fatalf("ListByOCLCodes page 2: %v", err)
		}
		if page.Total != 2 || len(page.Rows) != 1 {
			t.Fatalf("page 2 = %#v", page)
		}
		if page.Rows[0].Kind != "registration" || page.Rows[0].OCLID != "REG-1" {
			t.Fatalf("unexpected second row: %#v", page.Rows[0])
		}
	})
}

func TestRepositoryListByOCLCodesEmpty(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		resetLobbyingRows(t, conn)

		page, err := New(conn).ListByOCLCodes(context.Background(), []usecase.OCLTopicMapping{
			{OCLCode: "SMT-18", EpacTopicSlug: "healthcare", Confidence: 1},
		}, usecase.Pagination{Page: 1, PerPage: 50})
		if err != nil {
			t.Fatalf("ListByOCLCodes: %v", err)
		}
		if page.Total != 0 || len(page.Rows) != 0 {
			t.Fatalf("page = %#v, want empty", page)
		}
	})
}

func resetLobbyingRows(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `
		TRUNCATE TABLE lobbyist_subject_matters, lobbyist_communications, lobbyist_registrations
	`)
	if err != nil {
		t.Fatalf("reset lobbying rows: %v", err)
	}
}

func seedLobbyingRows(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `
		INSERT INTO lobbyist_communications (
			comlog_id, organization_name, registrant_name, registrant_type,
			communication_date, posted_date
		) VALUES
			('COM-1', 'Older Housing Org', 'Alex Lobbyist', '1', '2026-01-15', '2026-01-20'),
			('COM-2', 'Newer Housing Org', 'Blair Lobbyist', '2', '2026-03-15', '2026-03-20');

		INSERT INTO lobbyist_registrations (
			reg_id, registration_number, organization_name, registrant_name, registrant_type,
			effective_date, posted_date
		) VALUES
			('REG-1', '123-1', 'Housing Registration Org', 'Casey Registrant', '3', '2026-02-10', '2026-02-12');

		INSERT INTO lobbyist_subject_matters (
			source_type, source_id, ocl_code, subject_text, custom_subject_text
		) VALUES
			('communication', 'COM-1', 'SMT-18', 'Health', ''),
			('communication', 'COM-2', 'SMT-44', 'Housing', ''),
			('registration', 'REG-1', 'SMT-44', 'Housing', 'Affordable housing supply'),
			('registration', 'REG-1', 'SMT-18', 'Health', '');
	`)
	if err != nil {
		t.Fatalf("seed lobbying rows: %v", err)
	}
}
