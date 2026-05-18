// on-this-day Lambda - GET /api/v1/on-this-day?date=YYYY-MM-DD&limit=5
//
// Returns prior-year Hansard moments from the same calendar day, ranked toward
// current MPs and speeches linked to bills or recorded votes.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"epac/observability"
	artifactadapter "epac/on-this-day/internal/adapter/artifacts"
	"epac/on-this-day/internal/usecase"
	"epac/shared/artifacts"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

var newArtifactStore = artifacts.NewFromEnv

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	date, err := parseDate(req.QueryStringParameters["date"])
	if err != nil {
		return jsonError(http.StatusBadRequest, "date must be YYYY-MM-DD"), nil
	}
	limit := parseLimit(req.QueryStringParameters["limit"])

	store, err := newArtifactStore(ctx)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	repo := artifactadapter.NewHansardRepository(store)
	uc := usecase.New(repo)
	items, err := uc.Execute(ctx, date, limit)
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return jsonError(status, err.Error()), nil
	}

	body, err := json.Marshal(usecase.OnThisDayResponse{
		Date:  date.Format("2006-01-02"),
		Items: items,
	})
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(body),
	}, nil
}

func parseDate(value string) (time.Time, error) {
	if value == "" {
		return time.Now().UTC(), nil
	}
	if len(value) != len("2006-01-02") {
		return time.Time{}, fmt.Errorf("invalid date")
	}
	date, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, err
	}
	return date, nil
}

func parseLimit(value string) int {
	limit := usecase.DefaultLimit
	if value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if limit > usecase.MaxLimit {
		return usecase.MaxLimit
	}
	return limit
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
	lambda.Start(observability.WrapAPIGateway("on-this-day", HandleRequest))
}
