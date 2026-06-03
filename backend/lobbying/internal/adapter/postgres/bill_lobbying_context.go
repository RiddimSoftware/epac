package postgres

import (
	"context"
	"fmt"
	"strings"

	"epac/lobbying/internal/usecase"
)

func (r *Repository) LoadBillSubjectContext(ctx context.Context, legisInfoID string) (usecase.BillSubjectContext, error) {
	legisInfoID = strings.TrimSpace(legisInfoID)
	if legisInfoID == "" {
		return usecase.BillSubjectContext{SubjectTags: []string{}}, nil
	}

	row := r.conn.QueryRow(ctx, billSubjectContextSQL, legisInfoID)
	var tags []string
	var topicSlugs []string
	var mostRecentReadingDate string
	if err := row.Scan(&tags, &topicSlugs, &mostRecentReadingDate); err != nil {
		return usecase.BillSubjectContext{}, fmt.Errorf("query bill subject context: %w", err)
	}
	if tags == nil {
		tags = []string{}
	}
	if topicSlugs == nil {
		topicSlugs = []string{}
	}
	return usecase.BillSubjectContext{
		LegisInfoID:           legisInfoID,
		SubjectTags:           tags,
		TopicSlugs:            topicSlugs,
		MostRecentReadingDate: mostRecentReadingDate,
	}, nil
}

func (r *Repository) ListBillLobbyingCommunications(ctx context.Context, mappings []usecase.OCLTopicMapping, window usecase.DateWindow) ([]usecase.BillLobbyingCommunication, error) {
	if len(mappings) == 0 {
		return []usecase.BillLobbyingCommunication{}, nil
	}

	codes := make([]string, 0, len(mappings))
	for _, mapping := range mappings {
		code := usecase.NormalizeOCLCode(mapping.OCLCode)
		if code != "" {
			codes = append(codes, code)
		}
	}
	if len(codes) == 0 {
		return []usecase.BillLobbyingCommunication{}, nil
	}

	rows, err := r.conn.Query(ctx, billLobbyingCommunicationsSQL, codes, window.StartDate, window.EndDate)
	if err != nil {
		return nil, fmt.Errorf("query bill lobbying communications: %w", err)
	}
	defer rows.Close()

	communications := []usecase.BillLobbyingCommunication{}
	for rows.Next() {
		var communication usecase.BillLobbyingCommunication
		if err := rows.Scan(
			&communication.ID,
			&communication.OrganizationName,
			&communication.SubjectMatter,
			&communication.OCLCode,
			&communication.CommunicationDate,
		); err != nil {
			return nil, fmt.Errorf("scan bill lobbying communication: %w", err)
		}
		communication.OCLCode = usecase.NormalizeOCLCode(communication.OCLCode)
		communications = append(communications, communication)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill lobbying communications: %w", err)
	}
	return communications, nil
}

const billSubjectContextSQL = `
SELECT
	COALESCE(
		ARRAY_AGG(DISTINCT BTRIM(subject_tag) ORDER BY BTRIM(subject_tag))
			FILTER (WHERE NULLIF(BTRIM(subject_tag), '') IS NOT NULL),
		ARRAY[]::TEXT[]
	) AS subject_tags,
	COALESCE(
		ARRAY_AGG(DISTINCT BTRIM(epac_topic_slug) ORDER BY BTRIM(epac_topic_slug))
			FILTER (WHERE NULLIF(BTRIM(epac_topic_slug), '') IS NOT NULL),
		ARRAY[]::TEXT[]
	) AS epac_topic_slugs,
	COALESCE((
		SELECT to_char(MAX(reading_date), 'YYYY-MM-DD')
		FROM legisinfo_bill_readings readings
		WHERE readings.legisinfo_id = $1
	), '') AS most_recent_reading_date
FROM legisinfo_bill_subject_tags
WHERE legisinfo_id = $1
  AND confidence >= 0.80
`

const billLobbyingCommunicationsSQL = `
WITH requested AS (
	SELECT DISTINCT unnest($1::text[]) AS ocl_code
),
matched AS (
	SELECT
		lc.comlog_id AS id,
		COALESCE(lc.organization_name, '') AS organization_name,
		COALESCE(NULLIF(lsm.custom_subject_text, ''), NULLIF(lsm.subject_text, ''), lsm.ocl_code) AS subject_matter,
		lsm.ocl_code,
		COALESCE(to_char(lc.communication_date, 'YYYY-MM-DD'), '') AS communication_date,
		ROW_NUMBER() OVER (
			PARTITION BY lc.comlog_id, lsm.ocl_code
			ORDER BY COALESCE(NULLIF(lsm.custom_subject_text, ''), NULLIF(lsm.subject_text, ''), lsm.ocl_code)
		) AS duplicate_rank
	FROM lobbyist_subject_matters lsm
	JOIN requested ON requested.ocl_code = lsm.ocl_code
	JOIN lobbyist_communications lc
		ON lsm.source_type = 'communication' AND lc.comlog_id = lsm.source_id
	WHERE lc.communication_date >= $2::date
	  AND lc.communication_date <= $3::date
)
SELECT
	id,
	organization_name,
	subject_matter,
	ocl_code,
	communication_date
FROM matched
WHERE duplicate_rank = 1
ORDER BY communication_date DESC NULLS LAST, id, ocl_code
`
