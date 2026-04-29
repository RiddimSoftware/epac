// search Lambda — GET /search?query=<terms> or /search/speeches?q=<terms>
//
// Uses PostgreSQL GIN full-text indexes for English and French speech search.
// Falls back to the legacy English expression index if bilingual vectors are not yet present.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type SearchResult struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Snippet     string  `json:"snippet"`
	SittingDate *string `json:"sitting_date,omitempty"`
	Subject     *string `json:"subject,omitempty"`
	MemberId    *string `json:"member_id,omitempty"`
}

type SearchResponse struct {
	Query        string         `json:"query"`
	LanguageHint string         `json:"language_hint"`
	Results      []SearchResult `json:"results"`
}

type SearchParams struct {
	Query    string
	UserID   string
	FromDate *time.Time
	ToDate   *time.Time
}

type RankingConfig struct {
	TextWeight        float64
	RecencyWeight     float64
	FollowWeight      float64
	RecencyHalfLife   float64
	LanguageHintBoost float64
	MyMPBoost         float64
	BillBoost         float64
	TopicBoost        float64
}

var dbConn *pgx.Conn

func getDBConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, fmt.Errorf("DATABASE_URL not set")
	}
	// Log connection attempt (mask password before connecting)
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

func search(ctx context.Context, conn *pgx.Conn, params SearchParams, cfg RankingConfig) ([]SearchResult, error) {
	languageHint := detectQueryLanguage(params.Query)

	// PostgreSQL full-text search using language-specific GIN indexes.
	// ts_headline generates a snippet with matched terms highlighted (stripped of tags here).
	rows, err := conn.Query(ctx, rankedSpeechSearchSQL,
		params.Query,
		languageHint,
		params.UserID,
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
		rows, err = conn.Query(ctx, legacySpeechSearchSQL,
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

const rankedSpeechSearchSQL = `
		WITH query AS (
			SELECT
				plainto_tsquery('english', $1) AS english_query,
				plainto_tsquery('french', $1) AS french_query
		),
		user_context AS (
			SELECT
				my_mp_member_id,
				topic_ids,
				bill_ids
			FROM device_subscriptions
			WHERE token = NULLIF($3, '')
			LIMIT 1
		),
		context AS (
			SELECT
				COALESCE((SELECT my_mp_member_id FROM user_context), '') AS my_mp_member_id,
				COALESCE((SELECT topic_ids FROM user_context), ARRAY[]::TEXT[]) AS topic_ids,
				COALESCE((SELECT bill_ids FROM user_context), ARRAY[]::TEXT[]) AS bill_ids
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
						'MaxWords=50, MinWords=10, StartSel=, StopSel='
					)
				ELSE ts_headline(
					'english', s.content,
					query.english_query,
					'MaxWords=50, MinWords=10, StartSel=, StopSel='
				)
				END AS snippet,
			s.sitting_date,
			s.subject_title,
			s.member_id,
			(
				$6 * GREATEST(
					CASE
						WHEN s.search_vector_en @@ query.english_query
							THEN ts_rank(s.search_vector_en, query.english_query) *
								CASE WHEN $2 = 'en' THEN $10 ELSE 1.0 END
						ELSE 0
					END,
					CASE
						WHEN s.search_vector_fr @@ query.french_query
							THEN ts_rank(s.search_vector_fr, query.french_query) *
								CASE WHEN $2 = 'fr' THEN $10 ELSE 1.0 END
						ELSE 0
					END
				)
			) + (
				$7 * CASE
					WHEN s.sitting_date IS NULL THEN 0
					ELSE POWER(
						0.5::DOUBLE PRECISION,
						GREATEST(
							0::DOUBLE PRECISION,
							EXTRACT(EPOCH FROM (CURRENT_DATE::TIMESTAMP - s.sitting_date::TIMESTAMP)) / 86400.0
						) / NULLIF($9, 0)
					)
				END
			) + (
				$8 * CASE
					WHEN $3 = '' THEN 0
					ELSE (
						CASE
							WHEN context.my_mp_member_id <> ''
								AND s.member_id = context.my_mp_member_id
								THEN $11
							ELSE 0
						END
						+ CASE
							WHEN COALESCE(s.related_bill_ids, ARRAY[]::TEXT[]) && context.bill_ids
								THEN $12
							ELSE 0
						END
						+ CASE
							WHEN EXISTS (
								SELECT 1
								FROM unnest(context.topic_ids) AS followed_topic(topic_id)
								WHERE followed_topic.topic_id <> ''
									AND (
										LOWER(COALESCE(s.subject_title, '')) LIKE '%' || REPLACE(LOWER(followed_topic.topic_id), '-', ' ') || '%'
										OR LOWER(COALESCE(s.content, '')) LIKE '%' || REPLACE(LOWER(followed_topic.topic_id), '-', ' ') || '%'
									)
							)
								THEN $13
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
			AND ($4::DATE IS NULL OR s.sitting_date >= $4::DATE)
			AND ($5::DATE IS NULL OR s.sitting_date <= $5::DATE)
		)
		SELECT intervention_id, title, snippet, sitting_date, subject_title, member_id
		FROM matches
		ORDER BY rank_score DESC, sitting_date DESC NULLS LAST
		LIMIT 50`

const legacySpeechSearchSQL = `
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
					'MaxWords=50, MinWords=10, StartSel=, StopSel='
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

func detectQueryLanguage(query string) string {
	lower := strings.ToLower(query)
	if strings.ContainsAny(lower, "àâçéèêëîïôùûüÿœ") {
		return "fr"
	}

	words := strings.FieldsFunc(lower, func(r rune) bool {
		return r < 'a' || r > 'z'
	})
	frenchMarkers := map[string]bool{
		"des": true, "les": true, "une": true, "avec": true, "pour": true,
		"aux": true, "sur": true, "dans": true, "budgetaire": true,
		"gouvernement": true, "logement": true, "sante": true,
	}
	for _, word := range words {
		if frenchMarkers[word] {
			return "fr"
		}
	}
	return "en"
}

func scanResults(rows pgx.Rows) ([]SearchResult, error) {
	var results []SearchResult
	for rows.Next() {
		var (
			id       string
			title    string
			snippet  string
			date     *time.Time
			subject  *string
			memberId *string
		)
		if err := rows.Scan(&id, &title, &snippet, &date, &subject, &memberId); err != nil {
			return nil, fmt.Errorf("scan error: %w", err)
		}
		r := SearchResult{
			ID:       id,
			Title:    title,
			Snippet:  snippet,
			Subject:  subject,
			MemberId: memberId,
		}
		if date != nil {
			s := date.Format("2006-01-02")
			r.SittingDate = &s
		}
		results = append(results, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}
	return results, nil
}

func paramsFromRequest(request events.APIGatewayProxyRequest) (SearchParams, error) {
	values := request.QueryStringParameters
	query := strings.TrimSpace(values["q"])
	if query == "" {
		query = strings.TrimSpace(values["query"])
	}
	if query == "" {
		return SearchParams{}, fmt.Errorf("missing 'q' parameter")
	}

	fromDate, err := parseDateParam(values["from_date"])
	if err != nil {
		return SearchParams{}, fmt.Errorf("invalid from_date: %w", err)
	}
	toDate, err := parseDateParam(values["to_date"])
	if err != nil {
		return SearchParams{}, fmt.Errorf("invalid to_date: %w", err)
	}
	if fromDate != nil && toDate != nil && fromDate.After(*toDate) {
		return SearchParams{}, fmt.Errorf("from_date must be on or before to_date")
	}

	return SearchParams{
		Query:    query,
		UserID:   strings.TrimSpace(values["user_id"]),
		FromDate: fromDate,
		ToDate:   toDate,
	}, nil
}

func parseDateParam(value string) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}

func rankingConfigFromEnv() RankingConfig {
	return RankingConfig{
		TextWeight:        envFloatAtLeast("SEARCH_TEXT_WEIGHT", 0.72, 0),
		RecencyWeight:     envFloatAtLeast("SEARCH_RECENCY_WEIGHT", 0.20, 0),
		FollowWeight:      envFloatAtLeast("SEARCH_FOLLOW_WEIGHT", 0.08, 0),
		RecencyHalfLife:   envFloatAbove("SEARCH_RECENCY_HALFLIFE_DAYS", 90, 0),
		LanguageHintBoost: envFloatAtLeast("SEARCH_LANGUAGE_HINT_BOOST", 1.15, 0),
		MyMPBoost:         envFloatAtLeast("SEARCH_MY_MP_BOOST", 1.0, 0),
		BillBoost:         envFloatAtLeast("SEARCH_BILL_BOOST", 0.85, 0),
		TopicBoost:        envFloatAtLeast("SEARCH_TOPIC_BOOST", 0.65, 0),
	}
}

func envFloatAtLeast(name string, fallback float64, min float64) float64 {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil || parsed < min {
		return fallback
	}
	return parsed
}

func envFloatAbove(name string, fallback float64, min float64) float64 {
	value := strings.TrimSpace(os.Getenv(name))
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil || parsed <= min {
		return fallback
	}
	return parsed
}

func HandleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	params, err := paramsFromRequest(request)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	conn, err := getDBConn(ctx)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       fmt.Sprintf(`{"error": "%v"}`, err),
		}, nil
	}

	results, err := search(ctx, conn, params, rankingConfigFromEnv())
	if err != nil {
		fmt.Printf("Search error: %v\n", err)
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       fmt.Sprintf(`{"error": "Search failed: %v"}`, err),
		}, nil
	}

	if results == nil {
		results = []SearchResult{}
	}

	resp := SearchResponse{
		Query:        params.Query,
		LanguageHint: detectQueryLanguage(params.Query),
		Results:      results,
	}
	body, err := json.Marshal(resp)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       `{"error": "Failed to encode response"}`,
		}, nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func jsonError(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("search", HandleRequest))
}
