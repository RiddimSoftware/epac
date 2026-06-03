package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	ocltopicmap "epac/lobbying/internal/adapter/ocltopicmap"
	postgresadapter "epac/lobbying/internal/adapter/postgres"
	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
)

type billLobbyingContextExecutor interface {
	Execute(context.Context, usecase.BillLobbyingContextInput) (usecase.BillLobbyingContext, error)
}

var newBillLobbyingContextService = newProductionBillLobbyingContextService

func handleBillLobbyingContext(ctx context.Context, req events.APIGatewayV2HTTPRequest, legisInfoID string) (events.APIGatewayV2HTTPResponse, error) {
	windowMonths, err := parsePositiveInt(
		req.QueryStringParameters["window_months"],
		usecase.DefaultBillLobbyingWindowMonths,
		"window_months",
	)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	service, closeService, err := newBillLobbyingContextService(ctx)
	if err != nil {
		slog.Error("bill lobbying context service initialization failed", "error", err)
		return jsonError(http.StatusServiceUnavailable, "lobbying data unavailable"), nil
	}
	defer closeService(ctx)

	result, err := service.Execute(ctx, usecase.BillLobbyingContextInput{
		LegisInfoID:  legisInfoID,
		WindowMonths: windowMonths,
	})
	if err != nil {
		if errors.Is(err, usecase.ErrBillLobbyingContextMissingBillID) {
			return jsonError(http.StatusBadRequest, "missing bill id"), nil
		}
		slog.Error("bill lobbying context request failed", "error", err, "legisinfo_id", legisInfoID)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}

	body, err := json.Marshal(result)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func newProductionBillLobbyingContextService(ctx context.Context) (billLobbyingContextExecutor, closeFunc, error) {
	source, err := ocltopicmap.NewSource(topicMapJSON)
	if err != nil {
		return nil, noopClose, err
	}
	conn, err := postgresadapter.Connect(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := postgresadapter.New(conn)
	service := usecase.NewLoadBillLobbyingContext(repo, repo, source, usecase.SystemClock{})
	return service, func(closeCtx context.Context) {
		_ = conn.Close(closeCtx)
	}, nil
}

func billLobbyingContextIDFromRequest(req events.APIGatewayV2HTTPRequest) string {
	for _, key := range []string{"legisinfo_id", "legisinfoId", "bill_id", "billId"} {
		if value := strings.TrimSpace(req.PathParameters[key]); value != "" {
			return unescapePathPart(value)
		}
	}

	path := requestPath(req)
	for _, prefix := range []string{"/api/v1/bills/", "/bills/"} {
		if !strings.HasPrefix(path, prefix) {
			continue
		}
		remainder := strings.TrimPrefix(path, prefix)
		if !strings.HasSuffix(remainder, "/lobbying-context") {
			continue
		}
		legisInfoID := strings.TrimSuffix(remainder, "/lobbying-context")
		if legisInfoID == "" || strings.Contains(legisInfoID, "/") {
			continue
		}
		return unescapePathPart(legisInfoID)
	}
	return ""
}
