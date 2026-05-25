// hansard-search Lambda — GET /api/v1/hansard/search
package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"

	"epac/hansard-search/internal/adapter/s3manifest"
	"epac/hansard-search/internal/adapter/sqlitefile"
	"epac/hansard-search/internal/adapter/sqlitefts5"
	"epac/hansard-search/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const (
	defaultPage       = 1
	defaultPerPage    = 20
	maxQueryLength    = 200
	maxSpeakerLength  = 100
	maxTopicLength    = 200
	searchRetryAfter  = "5"
	sqliteReadOnlyDSN = "file:%s?mode=ro&_pragma=query_only(1)"
)

type searchExecutor interface {
	Execute(context.Context, usecase.SearchQuery, usecase.Pagination) (usecase.SearchResults, error)
}

type openSearchIndexFunc func(context.Context) (usecase.SearchIndex, error)
type openDBFunc func(context.Context, string) (*sql.DB, error)
type newSearchExecutorFunc func(*sql.DB) searchExecutor

type searchRuntime struct {
	mu        sync.Mutex
	openIndex openSearchIndexFunc
	openDB    openDBFunc
	newSearch newSearchExecutorFunc
	searcher  searchExecutor
}

type searchResponse struct {
	Page    int                 `json:"page"`
	PerPage int                 `json:"per_page"`
	Total   int                 `json:"total"`
	Results []searchResponseHit `json:"results"`
}

type searchResponseHit struct {
	ParliamentNumber  int     `json:"parliament_number"`
	SessionNumber     int     `json:"session_number"`
	SittingDate       string  `json:"sitting_date"`
	InterventionID    string  `json:"intervention_id"`
	MessageID         string  `json:"message_id"`
	SpeakerName       string  `json:"speaker_name"`
	PartyAbbreviation string  `json:"party_abbreviation"`
	RidingName        string  `json:"riding_name"`
	Topic             string  `json:"topic"`
	Snippet           string  `json:"snippet"`
	Score             float64 `json:"score"`
}

var searchService searchExecutor = newSearchRuntime(
	openSearchIndexFromEnv,
	openSQLiteReadOnly,
	func(db *sql.DB) searchExecutor {
		return usecase.SearchHansard{Repo: sqlitefts5.New(db)}
	},
)

func newSearchRuntime(openIndex openSearchIndexFunc, openDB openDBFunc, newSearch newSearchExecutorFunc) *searchRuntime {
	return &searchRuntime{
		openIndex: openIndex,
		openDB:    openDB,
		newSearch: newSearch,
	}
}

func (r *searchRuntime) Execute(ctx context.Context, q usecase.SearchQuery, p usecase.Pagination) (usecase.SearchResults, error) {
	searcher, err := r.ensureSearcher(ctx)
	if err != nil {
		return usecase.SearchResults{}, err
	}
	return searcher.Execute(ctx, q, p)
}

func (r *searchRuntime) ensureSearcher(ctx context.Context) (searchExecutor, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.searcher != nil {
		return r.searcher, nil
	}

	index, err := r.openIndex(ctx)
	if err != nil {
		return nil, err
	}

	db, err := r.openDB(ctx, index.LocalPath)
	if err != nil {
		return nil, fmt.Errorf("open sqlite index: %w", err)
	}

	r.searcher = r.newSearch(db)
	return r.searcher, nil
}

func HandleRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	query, pagination, err := parseRequest(req)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	results, err := searchService.Execute(ctx, query, pagination)
	if err != nil {
		return mapSearchError(err), nil
	}

	return jsonResponse(http.StatusOK, mapSearchResults(pagination, results), nil), nil
}

func parseRequest(req events.APIGatewayV2HTTPRequest) (usecase.SearchQuery, usecase.Pagination, error) {
	query := strings.TrimSpace(req.QueryStringParameters["q"])
	if query == "" {
		return usecase.SearchQuery{}, usecase.Pagination{}, errors.New("q is required")
	}
	if utf8.RuneCountInString(query) > maxQueryLength {
		return usecase.SearchQuery{}, usecase.Pagination{}, fmt.Errorf("q must be at most %d characters", maxQueryLength)
	}

	speaker := strings.TrimSpace(req.QueryStringParameters["speaker"])
	if utf8.RuneCountInString(speaker) > maxSpeakerLength {
		return usecase.SearchQuery{}, usecase.Pagination{}, fmt.Errorf("speaker must be at most %d characters", maxSpeakerLength)
	}

	topic := strings.TrimSpace(req.QueryStringParameters["topic"])
	if utf8.RuneCountInString(topic) > maxTopicLength {
		return usecase.SearchQuery{}, usecase.Pagination{}, fmt.Errorf("topic must be at most %d characters", maxTopicLength)
	}

	page, err := parsePositiveInt(req.QueryStringParameters["page"], defaultPage, "page")
	if err != nil {
		return usecase.SearchQuery{}, usecase.Pagination{}, err
	}

	perPage, err := parseBoundedInt(req.QueryStringParameters["per_page"], defaultPerPage, 1, 100, "per_page")
	if err != nil {
		return usecase.SearchQuery{}, usecase.Pagination{}, err
	}

	return usecase.SearchQuery{
			Query:   query,
			Speaker: speaker,
			Topic:   topic,
		}, usecase.Pagination{
			Page:    page,
			PerPage: perPage,
		}, nil
}

func parsePositiveInt(raw string, defaultValue int, name string) (int, error) {
	if strings.TrimSpace(raw) == "" {
		return defaultValue, nil
	}

	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || value < 1 {
		return 0, fmt.Errorf("%s must be an integer greater than or equal to 1", name)
	}
	return value, nil
}

func parseBoundedInt(raw string, defaultValue, minValue, maxValue int, name string) (int, error) {
	if strings.TrimSpace(raw) == "" {
		return defaultValue, nil
	}

	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || value < minValue || value > maxValue {
		return 0, fmt.Errorf("%s must be an integer between %d and %d", name, minValue, maxValue)
	}
	return value, nil
}

func mapSearchResults(p usecase.Pagination, results usecase.SearchResults) searchResponse {
	response := searchResponse{
		Page:    p.Page,
		PerPage: p.PerPage,
		Total:   results.Total,
		Results: make([]searchResponseHit, 0, len(results.Hits)),
	}

	for _, hit := range results.Hits {
		response.Results = append(response.Results, searchResponseHit{
			ParliamentNumber:  hit.ParliamentNumber,
			SessionNumber:     hit.SessionNumber,
			SittingDate:       hit.SittingDate,
			InterventionID:    hit.InterventionID,
			MessageID:         hit.MessageID,
			SpeakerName:       hit.SpeakerName,
			PartyAbbreviation: hit.PartyAbbreviation,
			RidingName:        hit.RidingName,
			Topic:             hit.Topic,
			Snippet:           hit.Snippet,
			Score:             hit.Score,
		})
	}

	return response
}

func mapSearchError(err error) events.APIGatewayV2HTTPResponse {
	switch {
	case errors.Is(err, usecase.ErrInvalidQuery),
		errors.Is(err, usecase.ErrInvalidPagination),
		errors.Is(err, usecase.ErrInvalidQuerySyntax):
		return jsonError(http.StatusBadRequest, err.Error())
	case errors.Is(err, usecase.ErrManifestNotFound),
		errors.Is(err, usecase.ErrChecksumMismatch),
		errors.Is(err, usecase.ErrSchemaMismatch):
		return jsonError(http.StatusServiceUnavailable, err.Error(), map[string]string{"Retry-After": searchRetryAfter})
	default:
		slog.Error("hansard-search request failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error")
	}
}

func openSearchIndexFromEnv(ctx context.Context) (usecase.SearchIndex, error) {
	manifestLoader, err := s3manifest.NewManifestLoaderFromEnv(ctx)
	if err != nil {
		return usecase.SearchIndex{}, err
	}

	indexDownloader, err := sqlitefile.NewIndexDownloaderFromEnv(ctx)
	if err != nil {
		return usecase.SearchIndex{}, err
	}

	return usecase.NewOpenSearchIndex(manifestLoader, indexDownloader).Execute(ctx)
}

func openSQLiteReadOnly(ctx context.Context, path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", fmt.Sprintf(sqliteReadOnlyDSN, path))
	if err != nil {
		return nil, err
	}
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

func jsonResponse(status int, payload any, extraHeaders map[string]string) events.APIGatewayV2HTTPResponse {
	body, err := marshalJSON(payload)
	if err != nil {
		slog.Error("marshal hansard-search response", "error", err)
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusInternalServerError,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       `{"error":"internal error"}`,
		}
	}

	headers := map[string]string{"Content-Type": "application/json"}
	for key, value := range extraHeaders {
		headers[key] = value
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    headers,
		Body:       body,
	}
}

func jsonError(status int, message string, extraHeaders ...map[string]string) events.APIGatewayV2HTTPResponse {
	var headers map[string]string
	if len(extraHeaders) > 0 {
		headers = extraHeaders[0]
	}
	return jsonResponse(status, map[string]string{"error": message}, headers)
}

func marshalJSON(payload any) (string, error) {
	var body bytes.Buffer
	encoder := json.NewEncoder(&body)
	encoder.SetEscapeHTML(false)
	if err := encoder.Encode(payload); err != nil {
		return "", err
	}
	return strings.TrimSpace(body.String()), nil
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("hansard-search", HandleRequest))
}
