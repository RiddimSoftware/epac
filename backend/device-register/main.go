// device-register Lambda — POST /api/v1/device/register
//
// Called by the iOS app when its APNs token changes or its topic
// subscription preferences change.
//
// Upserts a row in device_subscriptions. Safe to call on every launch.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"

	"epac/device-register/application"
	"epac/device-register/repository"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

var dbConn *pgx.Conn

func getConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	var err error
	dbConn, err = pgx.Connect(ctx, os.Getenv("DATABASE_URL"))
	return dbConn, err
}

type UseCase interface {
	Execute(ctx context.Context, req application.RegisterRequest) error
}

type Handler struct {
	useCase UseCase
}

func (h *Handler) HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	var useCaseReq application.RegisterRequest
	if err := json.Unmarshal([]byte(req.Body), &useCaseReq); err != nil {
		return errResp(http.StatusBadRequest, "invalid JSON"), nil
	}

	err := h.useCase.Execute(ctx, useCaseReq)
	if err != nil {
		if errors.Is(err, application.ErrTokenRequired) {
			return errResp(http.StatusBadRequest, err.Error()), nil
		}
		return errResp(http.StatusInternalServerError, fmt.Sprintf("upsert: %v", err)), nil
	}

	body, _ := json.Marshal(map[string]string{"status": "ok"})
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func errResp(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func LambdaHandler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	conn, err := getConn(ctx)
	if err != nil {
		return errResp(http.StatusInternalServerError, fmt.Sprintf("db: %v", err)), nil
	}

	repo := repository.NewPostgresDeviceRepository(conn)
	useCase := application.NewRegisterUseCase(repo)
	handler := &Handler{useCase: useCase}

	return handler.HandleRequest(ctx, req)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("device-register", LambdaHandler))
}
