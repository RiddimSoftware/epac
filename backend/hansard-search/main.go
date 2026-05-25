// hansard-search Lambda — GET /api/v1/hansard/search
//
// D1 scaffold: returns HTTP 503 for every request.
// D2 adds the query use case + adapter; the HTTP handler wiring lands in D3.
package main

import (
	"context"
	"encoding/json"
	"net/http"

	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

func HandleRequest(_ context.Context, _ events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	return jsonError(http.StatusServiceUnavailable, "search index not yet available"), nil
}

func jsonError(status int, msg string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type": "application/json",
			"Retry-After":  "5",
		},
		Body: string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("hansard-search", HandleRequest))
}
