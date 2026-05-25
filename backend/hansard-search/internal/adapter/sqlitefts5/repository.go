package sqlitefts5

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"unicode"

	"epac/hansard-search/internal/usecase"

	sqlite "modernc.org/sqlite"
)

const searchSQL = `
SELECT
    i.parliament_number, i.session_number, i.sitting_date,
    i.intervention_id, m.message_id,
    i.speaker_name, i.party_abbreviation, i.riding_name, i.topic,
    snippet(messages_fts, 0, '<mark>', '</mark>', '…', 32) AS snippet,
    bm25(messages_fts) AS score
FROM messages_fts
JOIN messages m ON m.rowid = messages_fts.rowid
JOIN interventions i ON i.rowid = m.intervention_rowid
WHERE messages_fts MATCH ?
  AND (? = '' OR i.speaker_name LIKE '%' || ? || '%' COLLATE NOCASE)
  AND (? = '' OR i.topic LIKE '%' || ? || '%' COLLATE NOCASE)
-- bm25() typically returns negative numbers; lower scores rank better.
ORDER BY score ASC
LIMIT ? OFFSET ?
`

const countSQL = `
SELECT COUNT(*)
FROM messages_fts
JOIN messages m ON m.rowid = messages_fts.rowid
JOIN interventions i ON i.rowid = m.intervention_rowid
WHERE messages_fts MATCH ?
  AND (? = '' OR i.speaker_name LIKE '%' || ? || '%' COLLATE NOCASE)
  AND (? = '' OR i.topic LIKE '%' || ? || '%' COLLATE NOCASE)
`

type Repository struct {
	db *sql.DB
}

var _ usecase.HansardSearchRepository = (*Repository)(nil)

func New(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Search(ctx context.Context, q usecase.SearchQuery, p usecase.Pagination) (usecase.SearchResults, error) {
	if r.db == nil {
		return usecase.SearchResults{}, errors.New("sqlite database is required")
	}

	query := sanitizeQuery(q.Query)
	speaker := strings.TrimSpace(q.Speaker)
	topic := strings.TrimSpace(q.Topic)

	var total int
	if err := r.db.QueryRowContext(ctx, countSQL, query, speaker, speaker, topic, topic).Scan(&total); err != nil {
		return usecase.SearchResults{}, classifySearchError(err)
	}

	offset := (p.Page - 1) * p.PerPage
	rows, err := r.db.QueryContext(ctx, searchSQL, query, speaker, speaker, topic, topic, p.PerPage, offset)
	if err != nil {
		return usecase.SearchResults{}, classifySearchError(err)
	}
	defer rows.Close()

	hits := make([]usecase.SearchHit, 0)
	for rows.Next() {
		var hit usecase.SearchHit
		if err := rows.Scan(
			&hit.ParliamentNumber,
			&hit.SessionNumber,
			&hit.SittingDate,
			&hit.InterventionID,
			&hit.MessageID,
			&hit.SpeakerName,
			&hit.PartyAbbreviation,
			&hit.RidingName,
			&hit.Topic,
			&hit.Snippet,
			&hit.Score,
		); err != nil {
			return usecase.SearchResults{}, classifySearchError(err)
		}
		hits = append(hits, hit)
	}
	if err := rows.Err(); err != nil {
		return usecase.SearchResults{}, classifySearchError(err)
	}

	return usecase.SearchResults{
		Total: total,
		Hits:  hits,
	}, nil
}

func sanitizeQuery(query string) string {
	query = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, query)

	return strings.TrimSpace(query)
}

func classifySearchError(err error) error {
	if err == nil {
		return nil
	}
	if isInvalidQuerySyntax(err) {
		return usecase.ErrInvalidQuerySyntax
	}
	return fmt.Errorf("search hansard sqlite index: %w", err)
}

func isInvalidQuerySyntax(err error) bool {
	var sqliteErr *sqlite.Error
	if !errors.As(err, &sqliteErr) {
		return false
	}

	message := strings.ToLower(sqliteErr.Error())
	return strings.Contains(message, "fts5: syntax error") ||
		strings.Contains(message, "unterminated string") ||
		strings.Contains(message, "malformed match expression")
}
