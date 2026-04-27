// search Lambda — GET /search?query=<terms>
//
// Uses PostgreSQL GIN full-text index (to_tsvector) for fast speech search.
// Falls back to ILIKE if the FTS index is not yet present.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

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
	Query   string         `json:"query"`
	Results []SearchResult `json:"results"`
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
	// PostgreSQL full-text search using the GIN index.
	// ts_headline generates a snippet with matched terms highlighted (stripped of tags here).
	rows, err := conn.Query(ctx, `
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
	if err != nil {
		return nil, fmt.Errorf("fts query error: %w", err)
	}
	defer rows.Close()

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

	resp := SearchResponse{Query: query, Results: results}
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
	lambda.Start(HandleRequest)
}
