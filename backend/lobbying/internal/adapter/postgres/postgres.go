// Package postgres is the Postgres-backed adapter satisfying the
// LobbyingSubjectsRepository port.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"os"

	"epac/lobbying/internal/usecase"

	"github.com/jackc/pgx/v5"
)

func Connect(ctx context.Context) (*pgx.Conn, error) {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, errors.New("DATABASE_URL not set")
	}
	return pgx.Connect(ctx, connStr)
}

type Repository struct {
	conn *pgx.Conn
}

func New(conn *pgx.Conn) *Repository {
	return &Repository{conn: conn}
}

func (r *Repository) ListByOCLCodes(ctx context.Context, mappings []usecase.OCLTopicMapping, pagination usecase.Pagination) (usecase.LobbyingByTopicPage, error) {
	if len(mappings) == 0 {
		return usecase.LobbyingByTopicPage{Rows: []usecase.LobbyingByTopicRecord{}}, nil
	}

	codes := make([]string, 0, len(mappings))
	confidences := make([]float64, 0, len(mappings))
	for _, mapping := range mappings {
		codes = append(codes, mapping.OCLCode)
		confidences = append(confidences, mapping.Confidence)
	}

	rows, err := r.conn.Query(ctx, lobbyingByTopicSQL, codes, confidences, pagination.PerPage, (pagination.Page-1)*pagination.PerPage)
	if err != nil {
		return usecase.LobbyingByTopicPage{}, fmt.Errorf("query lobbying by topic: %w", err)
	}
	defer rows.Close()

	page := usecase.LobbyingByTopicPage{Rows: []usecase.LobbyingByTopicRecord{}}
	for rows.Next() {
		var record usecase.LobbyingByTopicRecord
		if err := rows.Scan(
			&page.Total,
			&record.Kind,
			&record.OCLID,
			&record.OCLCode,
			&record.MappingConfidence,
			&record.SubjectMatter,
			&record.SubjectDescription,
			&record.OrganizationName,
			&record.RegistrantName,
			&record.RegistrantType,
			&record.CommunicationDate,
			&record.PostedDate,
			&record.EffectiveDate,
			&record.EndDate,
			&record.SourceURL,
		); err != nil {
			return usecase.LobbyingByTopicPage{}, fmt.Errorf("scan lobbying row: %w", err)
		}
		record.Citation = usecase.Citation
		page.Rows = append(page.Rows, record)
	}
	if err := rows.Err(); err != nil {
		return usecase.LobbyingByTopicPage{}, fmt.Errorf("iterate lobbying rows: %w", err)
	}
	return page, nil
}

const lobbyingByTopicSQL = `
WITH requested AS (
	SELECT *
	FROM unnest($1::text[], $2::double precision[]) AS input(ocl_code, mapping_confidence)
),
matched AS (
	SELECT
		lsm.source_type,
		lsm.source_id,
		lsm.ocl_code,
		requested.mapping_confidence,
		COALESCE(NULLIF(lsm.custom_subject_text, ''), NULLIF(lsm.subject_text, ''), lsm.ocl_code) AS subject_matter,
		COALESCE(NULLIF(lsm.subject_text, ''), lsm.ocl_code) AS subject_description,
		COALESCE(lc.organization_name, lr.organization_name, '') AS organization_name,
		COALESCE(lc.registrant_name, lr.registrant_name, '') AS registrant_name,
		CASE COALESCE(lc.registrant_type, lr.registrant_type, '')
			WHEN '1' THEN 'Consultant'
			WHEN '2' THEN 'In-house (corporation)'
			WHEN '3' THEN 'In-house (organization)'
			ELSE COALESCE(lc.registrant_type, lr.registrant_type, '')
		END AS registrant_type,
		COALESCE(to_char(lc.communication_date, 'YYYY-MM-DD'), '') AS communication_date,
		COALESCE(to_char(COALESCE(lc.posted_date, lr.posted_date), 'YYYY-MM-DD'), '') AS posted_date,
		COALESCE(to_char(lr.effective_date, 'YYYY-MM-DD'), '') AS effective_date,
		COALESCE(to_char(lr.end_date, 'YYYY-MM-DD'), '') AS end_date,
		COALESCE(lsm.source_url, lc.source_url, lr.source_url, '` + usecase.SourceURL + `') AS source_url,
		COALESCE(lc.communication_date, lr.effective_date, lr.posted_date, lc.posted_date) AS sort_date,
		ROW_NUMBER() OVER (
			PARTITION BY lsm.source_type, lsm.source_id, lsm.ocl_code
			ORDER BY COALESCE(NULLIF(lsm.custom_subject_text, ''), NULLIF(lsm.subject_text, ''), lsm.ocl_code)
		) AS duplicate_rank
	FROM lobbyist_subject_matters lsm
	JOIN requested ON requested.ocl_code = lsm.ocl_code
	LEFT JOIN lobbyist_communications lc
		ON lsm.source_type = 'communication' AND lc.comlog_id = lsm.source_id
	LEFT JOIN lobbyist_registrations lr
		ON lsm.source_type = 'registration' AND lr.reg_id = lsm.source_id
	WHERE lsm.source_type IN ('communication', 'registration')
),
deduped AS (
	SELECT *
	FROM matched
	WHERE duplicate_rank = 1
)
SELECT
	COUNT(*) OVER()::int AS total,
	source_type,
	source_id,
	ocl_code,
	mapping_confidence,
	subject_matter,
	subject_description,
	organization_name,
	registrant_name,
	registrant_type,
	communication_date,
	posted_date,
	effective_date,
	end_date,
	source_url
FROM deduped
ORDER BY sort_date DESC NULLS LAST, source_type, source_id, ocl_code
LIMIT $3 OFFSET $4`
