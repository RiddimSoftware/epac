// Package postgres is the Postgres-backed adapter satisfying the estimates
// EstimatesRepository port. SQL semantics are preserved exactly as they were
// before the boundary was introduced; only the location of the code changed.
package postgres

import (
	"context"
	"errors"
	"os"
	"time"

	"epac/estimates/internal/usecase"

	"github.com/jackc/pgx/v5"
)

const pipelineName = "main-estimates-ingest"

func Connect(ctx context.Context) (*pgx.Conn, error) {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, errors.New("DATABASE_URL not set")
	}
	return ConnectWithURL(ctx, connStr)
}

func ConnectWithURL(ctx context.Context, connStr string) (*pgx.Conn, error) {
	return pgx.Connect(ctx, connStr)
}

type EstimatesRepository struct {
	conn *pgx.Conn
}

func NewEstimatesRepository(conn *pgx.Conn) *EstimatesRepository {
	return &EstimatesRepository{conn: conn}
}

func (r *EstimatesRepository) FetchEstimates(ctx context.Context, filter usecase.EstimatesFilter) ([]usecase.Estimate, error) {
	var rows pgx.Rows
	var err error
	if filter.All {
		rows, err = r.conn.Query(ctx, `
			SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
			FROM estimates e
			JOIN organizations o ON e.organization_id = o.id
			ORDER BY e.fiscal_year DESC, o.name, e.vote_number`)
	} else if filter.OrgID != nil {
		if filter.FiscalYear != nil {
			rows, err = r.conn.Query(ctx, `
				SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
				FROM estimates e
				JOIN organizations o ON e.organization_id = o.id
				WHERE e.organization_id = $1 AND e.fiscal_year = $2
				ORDER BY e.vote_number`, *filter.OrgID, *filter.FiscalYear)
		} else {
			rows, err = r.conn.Query(ctx, `
				SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
				FROM estimates e
				JOIN organizations o ON e.organization_id = o.id
				WHERE e.organization_id = $1
				ORDER BY e.fiscal_year DESC, e.vote_number`, *filter.OrgID)
		}
	} else if filter.FiscalYear != nil {
		rows, err = r.conn.Query(ctx, `
			SELECT e.fiscal_year, e.organization_id, o.name, e.vote_number, e.vote_description, e.authorities, e.source
			FROM estimates e
			JOIN organizations o ON e.organization_id = o.id
			WHERE e.fiscal_year = $1
			ORDER BY o.name, e.vote_number`, *filter.FiscalYear)
	} else {
		return nil, usecase.ErrInvalidFilter
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var estimates []usecase.Estimate
	for rows.Next() {
		var estimate usecase.Estimate
		if err := rows.Scan(&estimate.FiscalYear, &estimate.OrganizationID, &estimate.OrganizationName, &estimate.VoteNumber, &estimate.VoteDescription, &estimate.Authorities, &estimate.Source); err != nil {
			continue
		}
		estimates = append(estimates, estimate)
	}
	return estimates, rows.Err()
}

func (r *EstimatesRepository) UpsertOrganization(ctx context.Context, org usecase.OrgRecord) error {
	_, err := r.conn.Exec(ctx, `
			INSERT INTO organizations (id, name, legal_title, abbr, dept_id, status)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (id) DO UPDATE SET
				name = EXCLUDED.name,
				legal_title = EXCLUDED.legal_title,
				abbr = EXCLUDED.abbr,
				dept_id = EXCLUDED.dept_id,
				status = EXCLUDED.status`,
		org.ID, org.Name, org.LegalTitle, org.Abbr, org.DeptID, org.Status)
	return err
}

func (r *EstimatesRepository) UpsertEstimate(ctx context.Context, est usecase.Estimate) error {
	_, err := r.conn.Exec(ctx, `
			INSERT INTO estimates (fiscal_year, organization_id, vote_number, vote_description, authorities, source)
			VALUES ($1, $2, $3, $4, $5, $6)
			ON CONFLICT (fiscal_year, organization_id, vote_number, vote_description) DO UPDATE SET
				authorities = EXCLUDED.authorities,
				source = EXCLUDED.source`,
		est.FiscalYear, est.OrganizationID, est.VoteNumber, est.VoteDescription, est.Authorities, est.Source)
	return err
}

func (r *EstimatesRepository) RecordHealth(ctx context.Context, count int, runErr error) {
	now := time.Now().UTC()
	var errMsg *string
	var successAt *time.Time
	var recordCount *int
	if runErr == nil {
		successAt = &now
		recordCount = &count
	} else {
		s := runErr.Error()
		errMsg = &s
	}
	_, _ = r.conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
		VALUES ($1, $2, $3, $4, $5, 24)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, now, successAt, errMsg, recordCount)
}
