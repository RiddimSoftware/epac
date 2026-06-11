// push-notification-dispatcher Lambda — receives internal events and dispatches
// them as push notifications via APNs.
//
// The composition root wires HandleRequest through observability.WrapAPIGateway
// so API Gateway invocations and acceptance tests share the same path.
//
// Implementation pending — see EPAC-2271.
package main

import (
	"context"

	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const pipelineName = "push-notification-dispatcher"

func main() {
	lambda.Start(observability.WrapAPIGateway(pipelineName, HandleRequest))
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return events.APIGatewayProxyResponse{StatusCode: 202, Body: `{"ok":true}`}, nil
}
