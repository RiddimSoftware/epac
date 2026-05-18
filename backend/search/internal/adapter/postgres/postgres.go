// Package postgres is the Postgres-backed adapter satisfying the search
// HansardRepository and MemberRepository ports. SQL semantics are preserved
// exactly as they were before the boundary was introduced; only the location
// of the code changed.
package postgres

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"epac-api/internal/usecase"

	"github.com/jackc/pgx/v5"
)

var dbConn *pgx.Conn

func GetDBConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, errors.New("DATABASE_URL not set")
	}
	masked := connStr
	if parts := strings.Split(connStr, "@"); len(parts) > 1 {
		if sub := strings.Split(parts[0], ":"); len(sub) > 2 {
			masked = sub[0] + ":" + sub[1] + ":****@" + parts[1]
		}
	}
	fmt.Printf("Connecting to database: %s\n", masked)

	var err error
	dbConn, err = pgx.Connect(ctx, connStr)
	return dbConn, err
}

type HansardRepository struct {
	conn *pgx.Conn
}

func NewHansardRepository(conn *pgx.Conn) *HansardRepository {
	return &HansardRepository{conn: conn}
}

type MemberRepository struct {
	conn *pgx.Conn
}

func NewMemberRepository(conn *pgx.Conn) *MemberRepository {
	return &MemberRepository{conn: conn}
}

func (r *HansardRepository) SearchSpeeches(ctx context.Context, params usecase.SearchParams, languageHint string, searchContext usecase.SearchContext, cfg usecase.RankingConfig) ([]usecase.SearchResult, error) {
	rows, err := r.conn.Query(ctx, RankedSpeechSearchSQL,
		params.Query,
		languageHint,
		searchContext.MyMPMemberID,
		searchContext.TopicKeywordHints,
		searchContext.BillIDs,
		params.FromDate,
		params.ToDate,
		cfg.TextWeight,
		cfg.RecencyWeight,
		cfg.FollowWeight,
		cfg.RecencyHalfLife,
		cfg.LanguageHintBoost,
		cfg.MyMPBoost,
		cfg.BillBoost,
		cfg.TopicBoost,
	)
	if err != nil {
		rows, err = r.conn.Query(ctx, LegacySpeechSearchSQL,
			params.Query,
			params.FromDate,
			params.ToDate,
			cfg.TextWeight,
			cfg.RecencyWeight,
			cfg.RecencyHalfLife,
		)
	}
	if err != nil {
		return nil, fmt.Errorf("fts query error: %w", err)
	}
	defer rows.Close()

	return scanResults(rows)
}

func (r *MemberRepository) LoadSearchContext(ctx context.Context, userID string) (usecase.SearchContext, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return usecase.SearchContext{}, nil
	}

	var searchContext usecase.SearchContext
	err := r.conn.QueryRow(ctx, `
		SELECT
			COALESCE(my_mp_member_id, ''),
			COALESCE(topic_ids, ARRAY[]::TEXT[]),
			COALESCE(bill_ids, ARRAY[]::TEXT[])
		FROM device_subscriptions
		WHERE token = $1
		LIMIT 1`,
		userID,
	).Scan(&searchContext.MyMPMemberID, &searchContext.TopicIDs, &searchContext.BillIDs)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return usecase.SearchContext{}, nil
		}
		return usecase.SearchContext{}, fmt.Errorf("load search context: %w", err)
	}
	return searchContext, nil
}

const RankedSpeechSearchSQL = `
		-- Keep headline options explicit; do not pass empty selectors to ts_headline.
		WITH query AS (
			SELECT
				plainto_tsquery('english', $1) AS english_query,
				plainto_tsquery('french', $1) AS french_query
		),
		context AS (
			SELECT
				COALESCE($3, '') AS my_mp_member_id,
				COALESCE($4::TEXT[], ARRAY[]::TEXT[]) AS topic_keywords,
				COALESCE($5::TEXT[], ARRAY[]::TEXT[]) AS bill_ids
		),
		matches AS (
		SELECT
			s.intervention_id,
			COALESCE(s.speaker_name, '') AS title,
			CASE
				WHEN s.search_vector_fr @@ query.french_query
					AND ($2 = 'fr' OR COALESCE(NOT (s.search_vector_en @@ query.english_query), TRUE))
					THEN ts_headline(
						'french', s.content,
						query.french_query,
						'MaxWords=50, MinWords=10'
					)
				ELSE ts_headline(
					'english', s.content,
					query.english_query,
					'MaxWords=50, MinWords=10'
				)
				END AS snippet,
			s.sitting_date,
			s.subject_title,
			s.member_id,
			(
				$8 * GREATEST(
					CASE
						WHEN s.search_vector_en @@ query.english_query
							THEN ts_rank(s.search_vector_en, query.english_query) *
								CASE WHEN $2 = 'en' THEN $12 ELSE 1.0 END
						ELSE 0
					END,
					CASE
						WHEN s.search_vector_fr @@ query.french_query
							THEN ts_rank(s.search_vector_fr, query.french_query) *
								CASE WHEN $2 = 'fr' THEN $12 ELSE 1.0 END
						ELSE 0
					END
				)
			) + (
				$9 * CASE
					WHEN s.sitting_date IS NULL THEN 0
					ELSE POWER(
						0.5::DOUBLE PRECISION,
						GREATEST(
							0::DOUBLE PRECISION,
							EXTRACT(EPOCH FROM (CURRENT_DATE::TIMESTAMP - s.sitting_date::TIMESTAMP)) / 86400.0
						) / NULLIF($11, 0)
					)
				END
			) + (
				$10 * CASE
					WHEN context.my_mp_member_id = ''
						AND cardinality(context.topic_keywords) = 0
						AND cardinality(context.bill_ids) = 0
						THEN 0
					ELSE (
						CASE
							WHEN context.my_mp_member_id <> ''
								AND s.member_id = context.my_mp_member_id
								THEN $13
							ELSE 0
						END
						+ CASE
							WHEN COALESCE(s.related_bill_ids, ARRAY[]::TEXT[]) && context.bill_ids
								THEN $14
							ELSE 0
						END
						+ CASE
							WHEN EXISTS (
								SELECT 1
								FROM unnest(context.topic_keywords) AS followed_topic(keyword)
								WHERE followed_topic.keyword <> ''
									AND (
										LOWER(COALESCE(s.subject_title, '')) LIKE '%' || followed_topic.keyword || '%'
										OR LOWER(COALESCE(s.content, '')) LIKE '%' || followed_topic.keyword || '%'
									)
							)
								THEN $15
							ELSE 0
						END
					)
				END
			) AS rank_score
		FROM speeches s
		CROSS JOIN query
		CROSS JOIN context
		WHERE
			(
				(s.search_vector_en @@ query.english_query)
				OR (s.search_vector_fr @@ query.french_query)
			)
			AND ($6::DATE IS NULL OR s.sitting_date >= $6::DATE)
			AND ($7::DATE IS NULL OR s.sitting_date <= $7::DATE)
		)
		SELECT intervention_id, title, snippet, sitting_date, subject_title, member_id
		FROM matches
		ORDER BY rank_score DESC, sitting_date DESC NULLS LAST
		LIMIT 50`

const LegacySpeechSearchSQL = `
		SELECT
			intervention_id,
			title,
			snippet,
			sitting_date,
			subject_title,
			member_id
		FROM (
			SELECT
				intervention_id,
				COALESCE(speaker_name, '') AS title,
				ts_headline(
					'english', content,
					plainto_tsquery('english', $1),
					'MaxWords=50, MinWords=10'
				) AS snippet,
				sitting_date,
				subject_title,
				member_id,
				(
					$4 * ts_rank(
						to_tsvector('english', COALESCE(content, '')),
						plainto_tsquery('english', $1)
					)
				) + (
					$5 * CASE
						WHEN sitting_date IS NULL THEN 0
						ELSE POWER(
							0.5::DOUBLE PRECISION,
							GREATEST(
								0::DOUBLE PRECISION,
								EXTRACT(EPOCH FROM (CURRENT_DATE::TIMESTAMP - sitting_date::TIMESTAMP)) / 86400.0
							) / NULLIF($6, 0)
						)
					END
				) AS rank_score
			FROM speeches
			WHERE to_tsvector('english', COALESCE(content, '')) @@ plainto_tsquery('english', $1)
				AND ($2::DATE IS NULL OR sitting_date >= $2::DATE)
				AND ($3::DATE IS NULL OR sitting_date <= $3::DATE)
		) ranked
		ORDER BY rank_score DESC, sitting_date DESC NULLS LAST
		LIMIT 50`

func scanResults(rows pgx.Rows) ([]usecase.SearchResult, error) {
	var results []usecase.SearchResult
	for rows.Next() {
		var (
			id       string
			title    string
			snippet  string
			date     *time.Time
			subject  *string
			memberID *string
		)
		if err := rows.Scan(&id, &title, &snippet, &date, &subject, &memberID); err != nil {
			return nil, fmt.Errorf("scan error: %w", err)
		}
		result := usecase.SearchResult{
			ID:       id,
			Title:    title,
			Snippet:  snippet,
			Subject:  subject,
			MemberId: memberID,
		}
		if date != nil {
			s := date.Format("2006-01-02")
			result.SittingDate = &s
		}
		results = append(results, result)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}
	return results, nil
}
