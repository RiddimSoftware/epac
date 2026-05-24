// calendar Lambda — GET /api/v1/calendar/house.ics
package main

import (
	"context"
	"encoding/json"
	"net/http"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const houseCalendarArtifactKey = "calendar/v1/house.ics"

var newArtifactStore = artifacts.NewFromEnv

func HandleRequest(ctx context.Context, _ events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return textError(http.StatusServiceUnavailable, err.Error()), nil
	}
	data, err := store.Get(ctx, houseCalendarArtifactKey)
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return textError(status, err.Error()), nil
	}
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "text/calendar; charset=utf-8",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(data),
	}, nil
}

func textError(status int, message string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("calendar", HandleRequest))
}
