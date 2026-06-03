//go:build integration

package repository

import (
	"context"
	"testing"
	"time"

	"epac/_testdb"
	"epac/lobbying/application"
	"epac/lobbying/domain"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

func TestPostgresMPLobbyingRepositoryRefreshesAndLoadsExposure(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		resetMPLobbyingRows(t, conn)
		seedMPLobbyingRows(t, conn)

		repo := NewPostgresMPLobbyingRepository(&pgxQueryer{conn: conn})
		err := repo.RefreshMPLobbyingSummaries(context.Background(), application.RefreshMPLobbyingSummariesInput{
			Parliament:   45,
			QuarterStart: mustRepoDate(t, "2026-04-01"),
			QuarterEnd:   mustRepoDate(t, "2026-06-30"),
			UpdatedAt:    mustRepoTime(t, "2026-06-30T12:00:00Z"),
		})
		if err != nil {
			t.Fatalf("RefreshMPLobbyingSummaries: %v", err)
		}

		summary, found, err := repo.LoadMPLobbyingSummary(context.Background(), application.LoadMPLobbyingSummaryInput{
			MemberID:   "278707",
			Parliament: 45,
			Window:     domain.LobbyingExposureWindow3M,
		})
		if err != nil {
			t.Fatalf("LoadMPLobbyingSummary: %v", err)
		}
		if !found {
			t.Fatal("summary not found")
		}
		if summary.TotalCommunicationCount != 2 || summary.UniqueOrganizationsCount != 2 {
			t.Fatalf("summary counts = %#v", summary)
		}
		if summary.MostFrequentSubjectMatter != "Housing" {
			t.Fatalf("most frequent subject = %q", summary.MostFrequentSubjectMatter)
		}
		if len(summary.TopOrganizations) != 2 || summary.TopOrganizations[0].Name != "Example Housing Association" {
			t.Fatalf("top organizations = %#v", summary.TopOrganizations)
		}
		if summary.TrendVsPreviousParliament.PreviousParliament != 1 || summary.TrendVsPreviousParliament.Delta != 1 {
			t.Fatalf("trend = %#v", summary.TrendVsPreviousParliament)
		}
		if summary.PartyAverageCommunications != 1 || summary.NationalAverageCommunications != 1 {
			t.Fatalf("averages party=%v national=%v", summary.PartyAverageCommunications, summary.NationalAverageCommunications)
		}

		subjects, err := repo.ListMPLobbyingSubjectDistribution(context.Background(), application.ListMPLobbyingSubjectDistributionInput{
			MemberID:   "278707",
			Parliament: 45,
			Window:     domain.LobbyingExposureWindow3M,
		})
		if err != nil {
			t.Fatalf("ListMPLobbyingSubjectDistribution: %v", err)
		}
		if len(subjects) != 2 || subjects[0].SubjectMatter != "Housing" || subjects[0].CommunicationCount != 1 {
			t.Fatalf("subjects = %#v", subjects)
		}

		fromDate := mustRepoDate(t, "2026-05-15")
		page, err := repo.ListMPLobbyingTimeline(context.Background(), application.ListMPLobbyingTimelineInput{
			MemberID:   "278707",
			Parliament: 45,
			FromDate:   &fromDate,
			Page:       1,
			PerPage:    1,
		})
		if err != nil {
			t.Fatalf("ListMPLobbyingTimeline: %v", err)
		}
		if page.Total != 1 || len(page.Rows) != 1 {
			t.Fatalf("timeline page = %#v", page)
		}
		if page.Rows[0].CommunicationID != "COM-2" || page.Rows[0].Citation != domain.OCLCitation {
			t.Fatalf("timeline row = %#v", page.Rows[0])
		}

		emptyPage, err := repo.ListMPLobbyingTimeline(context.Background(), application.ListMPLobbyingTimelineInput{
			MemberID:   "278707",
			Parliament: 45,
			Page:       10,
			PerPage:    1,
		})
		if err != nil {
			t.Fatalf("ListMPLobbyingTimeline beyond range: %v", err)
		}
		if emptyPage.Total != 3 || len(emptyPage.Rows) != 0 {
			t.Fatalf("empty timeline page = %#v", emptyPage)
		}
	})
}

type pgxQueryer struct {
	conn *pgx.Conn
}

func (q *pgxQueryer) Exec(ctx context.Context, query string, args ...any) (QueryExecResult, error) {
	tag, err := q.conn.Exec(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	return pgxQueryResult{tag: tag}, nil
}

func (q *pgxQueryer) Query(ctx context.Context, query string, args ...any) (QueryRows, error) {
	rows, err := q.conn.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	return &pgxQueryRows{rows: rows}, nil
}

func (q *pgxQueryer) QueryRow(ctx context.Context, query string, args ...any) QueryRow {
	return pgxQueryRow{row: q.conn.QueryRow(ctx, query, args...)}
}

type pgxQueryResult struct {
	tag pgconn.CommandTag
}

func (r pgxQueryResult) RowsAffected() (int64, error) {
	return int64(r.tag.RowsAffected()), nil
}

type pgxQueryRows struct {
	rows pgx.Rows
}

func (r pgxQueryRows) Close() {
	r.rows.Close()
}

func (r pgxQueryRows) Next() bool {
	return r.rows.Next()
}

func (r pgxQueryRows) Scan(dest ...any) error {
	return r.rows.Scan(dest...)
}

func (r pgxQueryRows) Err() error {
	return r.rows.Err()
}

type pgxQueryRow struct {
	row pgx.Row
}

func (r pgxQueryRow) Scan(dest ...any) error {
	return r.row.Scan(dest...)
}

func resetMPLobbyingRows(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `
		TRUNCATE TABLE
			mp_lobbying_subject_breakdowns,
			mp_lobbying_summaries,
			mp_lobbying_timeline_entries,
			members
	`)
	if err != nil {
		t.Fatalf("reset MP lobbying rows: %v", err)
	}
}

func seedMPLobbyingRows(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	_, err := conn.Exec(context.Background(), `
		INSERT INTO members (person_id, first_name, last_name, caucus, from_date, to_date)
		VALUES
			('278707', 'Example', 'MP', 'Liberal', '2025-01-01', NULL),
			('999999', 'No', 'Exposure', 'Liberal', '2025-01-01', NULL);

		INSERT INTO mp_lobbying_timeline_entries (
			member_id, parliament, communication_id, communication_date,
			organization_name, organization_sector, subject_matter, communication_type,
			bill_number, bill_title, bill_url, bill_mapping_confidence
		) VALUES
			('278707', 45, 'COM-2', '2026-05-20',
			 'Example Housing Association', 'Housing', 'Housing', 'meeting',
			 'C-1', 'Example Bill', 'https://www.parl.ca/legisinfo/en/bill/45-1/c-1', 0.92),
			('278707', 45, 'COM-1', '2026-05-01',
			 'Transport Coalition', 'Transport', 'Transport', 'written',
			 NULL, NULL, NULL, NULL),
			('278707', 45, 'COM-OLD', '2026-01-15',
			 'Older Org', 'Industry', 'Industry', 'meeting',
			 NULL, NULL, NULL, NULL),
			('278707', 44, 'COM-PREV', '2024-11-10',
			 'Previous Parliament Org', 'Housing', 'Housing', 'meeting',
			 NULL, NULL, NULL, NULL);
	`)
	if err != nil {
		t.Fatalf("seed MP lobbying rows: %v", err)
	}
}

func mustRepoDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return parsed
}

func mustRepoTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatalf("parse time %q: %v", value, err)
	}
	return parsed
}
