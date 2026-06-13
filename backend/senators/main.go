// senators Lambda — GET /api/v1/senators
package main

import (
	"context"
	"net/http"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const senatorsArtifactKey = "senators/v1/all.json"

var newArtifactStore = artifacts.NewFromEnv

func HandleRequest(ctx context.Context, _ events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return jsonError(http.StatusServiceUnavailable, err.Error()), nil
	}
	data, err := store.Get(ctx, senatorsArtifactKey)
	if err != nil {
		status := http.StatusInternalServerError
		if artifacts.IsNotFound(err) {
			status = http.StatusNotFound
		}
		return jsonError(status, err.Error()), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(data),
	}, nil
}

func jsonError(status int, message string) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       `{"error":"` + message + `"}`,
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("senators", HandleRequest))
}
