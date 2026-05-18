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

	"epac-api/internal/adapter/postgres"
	"epac-api/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type SearchResult = usecase.SearchResult
type SearchResponse = usecase.SearchResponse
type SearchParams = usecase.SearchParams
type RankingConfig = usecase.RankingConfig
type SearchContext = usecase.SearchContext

const rankedSpeechSearchSQL = postgres.RankedSpeechSearchSQL
const legacySpeechSearchSQL = postgres.LegacySpeechSearchSQL

func search(ctx context.Context, conn *pgx.Conn, params SearchParams, cfg RankingConfig) ([]SearchResult, error) {
	uc := usecase.New(postgres.NewHansardRepository(conn), postgres.NewMemberRepository(conn))
	resp, err := uc.Execute(ctx, params, cfg)
	return resp.Results, err
}

func detectQueryLanguage(query string) string {
	return usecase.DetectQueryLanguage(query)
}

func followedTopicKeywords(ids []string) []string {
	return usecase.FollowedTopicKeywords(ids)
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

	conn, err := postgres.GetDBConn(ctx)
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
