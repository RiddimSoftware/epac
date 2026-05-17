// Package postgres is the Postgres-backed adapter satisfying the
// on-this-day HansardRepository port. SQL semantics are preserved
// exactly as they were before the boundary was introduced; only the
// location of the code changed.
package postgres

import (
	"context"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"epac/on-this-day/internal/usecase"

	"github.com/jackc/pgx/v5"
)

type HansardRepository struct {
	conn *pgx.Conn
}

func NewHansardRepository(conn *pgx.Conn) *HansardRepository {
	return &HansardRepository{conn: conn}
}

func (r *HansardRepository) OnThisDay(ctx context.Context, date time.Time, limit int) ([]usecase.OnThisDayItem, error) {
	rows, err := r.conn.Query(ctx, `
		SELECT
			s.intervention_id,
			EXTRACT(YEAR FROM s.sitting_date)::int AS year,
			s.sitting_date,
			COALESCE(s.speaker_name, ''),
			COALESCE(s.subject_title, ''),
			COALESCE(s.content, ''),
			s.member_id,
			s.source_url
		FROM speeches s
		LEFT JOIN members m ON m.person_id = s.member_id
		WHERE s.sitting_date IS NOT NULL
			AND EXTRACT(MONTH FROM s.sitting_date) = EXTRACT(MONTH FROM $1::date)
			AND EXTRACT(DAY FROM s.sitting_date) = EXTRACT(DAY FROM $1::date)
			AND s.sitting_date < $1::date
			AND COALESCE(s.content, '') <> ''
		ORDER BY
			CASE WHEN m.person_id IS NOT NULL AND (m.to_date IS NULL OR m.to_date >= CURRENT_DATE) THEN 1 ELSE 0 END DESC,
			COALESCE(cardinality(s.related_bill_ids), 0) DESC,
			COALESCE(cardinality(s.related_vote_ids), 0) DESC,
			s.sitting_date DESC,
			s.intervention_seq ASC NULLS LAST
		LIMIT $2`,
		date.Format("2006-01-02"), limit,
	)
	if err != nil && isOptionalRankingSchemaError(err) {
		rows, err = r.conn.Query(ctx, `
			SELECT
				s.intervention_id,
				EXTRACT(YEAR FROM s.sitting_date)::int AS year,
				s.sitting_date,
				COALESCE(s.speaker_name, ''),
				COALESCE(s.subject_title, ''),
				COALESCE(s.content, ''),
				s.member_id,
				s.source_url
			FROM speeches s
			WHERE s.sitting_date IS NOT NULL
				AND EXTRACT(MONTH FROM s.sitting_date) = EXTRACT(MONTH FROM $1::date)
				AND EXTRACT(DAY FROM s.sitting_date) = EXTRACT(DAY FROM $1::date)
				AND s.sitting_date < $1::date
				AND COALESCE(s.content, '') <> ''
			ORDER BY
				s.sitting_date DESC,
				s.intervention_seq ASC NULLS LAST
			LIMIT $2`,
			date.Format("2006-01-02"), limit,
		)
	}
	if err != nil {
		return nil, fmt.Errorf("on-this-day query error: %w", err)
	}
	defer rows.Close()

	items := make([]usecase.OnThisDayItem, 0)
	for rows.Next() {
		item, err := ScanSpeechItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}
	return items, nil
}

// IsOptionalRankingSchemaError returns true for SQL errors caused by an
// optional ranking column or table not yet present in the schema. Exported
// for the integration test fallback branch.
func IsOptionalRankingSchemaError(err error) bool {
	return isOptionalRankingSchemaError(err)
}

func isOptionalRankingSchemaError(err error) bool {
	message := err.Error()
	return strings.Contains(message, "related_") || strings.Contains(message, `relation "members" does not exist`)
}

// RowScanner abstracts pgx.Row / pgx.Rows for row mapping so the helper can
// be unit tested with a fake row implementation.
type RowScanner interface {
	Scan(dest ...any) error
}

// ScanSpeechItem maps one Hansard speech row into a domain OnThisDayItem.
func ScanSpeechItem(row RowScanner) (usecase.OnThisDayItem, error) {
	var (
		id           string
		year         int
		date         time.Time
		speakerName  string
		subjectTitle string
		content      string
		memberID     *string
		sourceURL    *string
	)
	if err := row.Scan(&id, &year, &date, &speakerName, &subjectTitle, &content, &memberID, &sourceURL); err != nil {
		return usecase.OnThisDayItem{}, fmt.Errorf("scan speech item: %w", err)
	}
	title := subjectTitle
	if title == "" {
		title = "Hansard speech"
	}
	return usecase.OnThisDayItem{
		ID:             "speech:" + id,
		Kind:           "speech",
		Year:           year,
		Date:           date.Format("2006-01-02"),
		Title:          title,
		Excerpt:        OneLineExcerpt(content, 180),
		SpeakerName:    stringPtrIfNotEmpty(speakerName),
		MemberID:       memberID,
		SubjectTitle:   stringPtrIfNotEmpty(subjectTitle),
		InterventionID: stringPtrIfNotEmpty(id),
		SourceURL:      sourceURL,
	}, nil
}

// OneLineExcerpt collapses whitespace and truncates value at a rune boundary.
func OneLineExcerpt(value string, maxRunes int) string {
	cleaned := strings.Join(strings.Fields(value), " ")
	if maxRunes <= 0 || utf8.RuneCountInString(cleaned) <= maxRunes {
		return cleaned
	}
	runes := []rune(cleaned)
	truncated := strings.TrimSpace(string(runes[:maxRunes]))
	if idx := strings.LastIndex(truncated, " "); idx > 0 {
		truncated = truncated[:idx]
	}
	return truncated + "..."
}

func stringPtrIfNotEmpty(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}
