package main

import (
	"context"
	"errors"
	"os"
	"strings"

	"epac/observability"
	"epac/push-notification-dispatcher/internal/adapter/apns"
	"epac/push-notification-dispatcher/internal/adapter/postgres"
	"epac/push-notification-dispatcher/internal/domain"
	"epac/push-notification-dispatcher/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const pipelineName = "push-notification-dispatcher"

var errDatabaseURLNotSet = errors.New("DATABASE_URL not set")

func main() {
	lambda.Start(observability.WrapAPIGateway(pipelineName, HandleRequest))
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	payload, err := domain.ParsePushNotificationPayload([]byte(req.Body))
	if err != nil {
		return events.APIGatewayProxyResponse{StatusCode: 400, Body: `{"error": "bad request"}`}, nil
	}

	dispatcher, cleanup, err := buildDispatcher(ctx)
	if err != nil {
		return mapBuildError(err), nil
	}
	defer cleanup(ctx)

	if _, err := dispatcher.Execute(ctx, payload); err != nil {
		return mapDispatchError(err), nil
	}

	return events.APIGatewayProxyResponse{StatusCode: 202, Body: `{"ok":true}`}, nil
}

func buildDispatcher(ctx context.Context) (*usecase.DispatchPushNotification, func(context.Context), error) {
	connStr := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if connStr == "" {
		return nil, nil, errDatabaseURLNotSet
	}

	conn, err := postgres.Connect(ctx, connStr)
	if err != nil {
		return nil, nil, err
	}

	repository := postgres.NewDeviceSubscriptionRepository(conn)
	client := apns.NewClient(apnsBaseURLFromEnv())
	dispatcher := usecase.NewDispatchPushNotification(repository, client)
	cleanup := func(ctx context.Context) {
		conn.Close(ctx)
	}

	return dispatcher, cleanup, nil
}

func apnsBaseURLFromEnv() string {
	baseURL := strings.TrimSpace(os.Getenv("EPAC_APNS_URL"))
	if baseURL == "" {
		return apns.DefaultBaseURL
	}
	return baseURL
}

func mapBuildError(err error) events.APIGatewayProxyResponse {
	if errors.Is(err, errDatabaseURLNotSet) {
		return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error": "DATABASE_URL not set"}`}
	}
	return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error": "db connect failed"}`}
}

func mapDispatchError(err error) events.APIGatewayProxyResponse {
	if errors.Is(err, usecase.ErrInvalidPayload) {
		return events.APIGatewayProxyResponse{StatusCode: 400, Body: `{"error": "bad request"}`}
	}
	return events.APIGatewayProxyResponse{StatusCode: 500, Body: `{"error": "query failed"}`}
}
