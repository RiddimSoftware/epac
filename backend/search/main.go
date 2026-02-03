package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// SearchResult represents a single search result.
type SearchResult struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Snippet string `json:"snippet"`
}

// SearchResponse represents the full response from the search provider.
type SearchResponse struct {
	Query   string         `json:"query"`
	Results []SearchResult `json:"results"`
}

// SearchProvider defines the interface for searching.
type SearchProvider interface {
	Search(ctx context.Context, query string) ([]SearchResult, error)
}

// SupabaseSearchProvider implements SearchProvider using pgx.
type SupabaseSearchProvider struct {
	conn *pgx.Conn
}

func (s *SupabaseSearchProvider) Search(ctx context.Context, query string) ([]SearchResult, error) {
	// Simple ILIKE search for now. Could be upgraded to full-text search (tsvector).
	searchPattern := "%" + query + "%"
	rows, err := s.conn.Query(ctx,
		"SELECT intervention_id, speaker_name, content FROM speeches WHERE content ILIKE $1 OR speaker_name ILIKE $1 LIMIT 50",
		searchPattern,
	)
	if err != nil {
		return nil, fmt.Errorf("query error: %w", err)
	}
	defer rows.Close()

	var results []SearchResult
	for rows.Next() {
		var id, title, content string
		if err := rows.Scan(&id, &title, &content); err != nil {
			return nil, fmt.Errorf("scan error: %w", err)
		}

		snippet := content
		if len(snippet) > 200 {
			snippet = snippet[:197] + "..."
		}

		results = append(results, SearchResult{
			ID:      id,
			Title:   title,
			Snippet: snippet,
		})
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}

	return results, nil
}

var dbConn *pgx.Conn

func getDBConn(ctx context.Context) (*pgx.Conn, error) {
	fmt.Printf("getDBConn called, current dbConn is nil: %v\n", dbConn == nil)
	if dbConn != nil {
		fmt.Printf("Pinging existing connection...\n")
		if err := dbConn.Ping(ctx); err == nil {
			fmt.Printf("Existing connection is alive.\n")
			return dbConn, nil
		}
		fmt.Printf("Existing connection is dead, closing it.\n")
		dbConn.Close(ctx)
		dbConn = nil
	}

	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, fmt.Errorf("DATABASE_URL environment variable is not set")
	}

	// Mask password for logging
	maskedConnStr := connStr
	if parts := strings.Split(connStr, "@"); len(parts) > 1 {
		if subparts := strings.Split(parts[0], ":"); len(subparts) > 2 {
			maskedConnStr = subparts[0] + ":" + subparts[1] + ":****@" + parts[1]
		}
	}
	fmt.Printf("Connecting to database with URL: %s\n", maskedConnStr)

	var err error
	dbConn, err = pgx.Connect(ctx, connStr)
	if err != nil {
		fmt.Printf("pgx.Connect failed: %v\n", err)
		return nil, fmt.Errorf("unable to connect to database: %w", err)
	}

	fmt.Printf("Successfully connected to database.\n")
	return dbConn, nil
}

func HandleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	query := request.QueryStringParameters["query"]
	if query == "" {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusBadRequest,
			Body:       `{"error": "Missing 'query' parameter"}`,
		},
		nil
	}

	conn, err := getDBConn(ctx)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       fmt.Sprintf(`{"error": "%v"}`, err),
		},
		nil
	}

	provider := &SupabaseSearchProvider{conn: conn}
	results, err := provider.Search(ctx, query)
	if err != nil {
		fmt.Printf("Search error: %v\n", err)
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       fmt.Sprintf(`{"error": "Failed to perform search: %v"}`, err),
		},
		nil
	}

	response := SearchResponse{
		Query:   query,
		Results: results,
	}

	body, err := json.Marshal(response)
	if err != nil {
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Body:       `{"error": "Failed to encode response"}`,
		},
		nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
		Body: string(body),
	},
	nil
}

func main() {
	lambda.Start(HandleRequest)
}
