// search Lambda — GET /search?query=<terms>
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

func search(ctx context.Context, conn *pgx.Conn, query string) ([]SearchResult, error) {
	languageHint := detectQueryLanguage(query)

	// PostgreSQL full-text search using language-specific GIN indexes.
	// ts_headline generates a snippet with matched terms highlighted (stripped of tags here).
	rows, err := conn.Query(ctx, `
		WITH query AS (
			SELECT
				plainto_tsquery('english', $1) AS english_query,
				plainto_tsquery('french', $1) AS french_query
		)
		SELECT
			s.intervention_id,
			COALESCE(s.speaker_name, ''),
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
			END,
			s.sitting_date,
			s.subject_title,
			s.member_id
		FROM speeches s, query
		WHERE
			(s.search_vector_en @@ query.english_query)
			OR (s.search_vector_fr @@ query.french_query)
		ORDER BY GREATEST(
			CASE
				WHEN s.search_vector_en @@ query.english_query
					THEN ts_rank(s.search_vector_en, query.english_query) *
						CASE WHEN $2 = 'en' THEN 1.15 ELSE 1.0 END
				ELSE 0
			END,
			CASE
				WHEN s.search_vector_fr @@ query.french_query
					THEN ts_rank(s.search_vector_fr, query.french_query) *
						CASE WHEN $2 = 'fr' THEN 1.15 ELSE 1.0 END
				ELSE 0
			END
		) DESC,
		s.sitting_date DESC NULLS LAST
		LIMIT 50`,
		query, languageHint,
	)
	if err != nil {
		rows, err = conn.Query(ctx, `
			SELECT
				intervention_id,
				COALESCE(speaker_name, ''),
				ts_headline(
					'english', content,
					plainto_tsquery('english', $1),
					'MaxWords=50, MinWords=10, StartSel=, StopSel='
				),
				sitting_date,
				subject_title,
				member_id
			FROM speeches
			WHERE to_tsvector('english', COALESCE(content, '')) @@ plainto_tsquery('english', $1)
			ORDER BY ts_rank(
				to_tsvector('english', COALESCE(content, '')),
				plainto_tsquery('english', $1)
			) DESC
			LIMIT 50`,
			query,
		)
	}
	if err != nil {
		return nil, fmt.Errorf("fts query error: %w", err)
	}
	defer rows.Close()

	return scanResults(rows)
}

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

func HandleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	query := strings.TrimSpace(request.QueryStringParameters["query"])
	if query == "" {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusBadRequest,
			Body:       `{"error": "Missing 'query' parameter"}`,
		}, nil
	}

	conn, err := getDBConn(ctx)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       fmt.Sprintf(`{"error": "%v"}`, err),
		}, nil
	}

	results, err := search(ctx, conn, query)
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
		Query:        query,
		LanguageHint: detectQueryLanguage(query),
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

func main() {
	lambda.Start(observability.WrapAPIGateway("search", HandleRequest))
}
