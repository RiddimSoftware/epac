// bills Lambda - GET /api/v1/bills, GET /api/v1/bills/{id},
// GET /api/v1/bills/{id}/diff, and GET /api/v1/bills/{id}/committee-stage
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"sync"

	s3adapter "epac/bills/internal/adapter/s3"
	sqliteadapter "epac/bills/internal/adapter/sqlite"
	"epac/bills/internal/domain"
	"epac/bills/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "modernc.org/sqlite"
)

const (
	billsRetryAfter   = "5"
	sqliteReadOnlyDSN = "file:%s?mode=ro&_pragma=query_only(1)"
)

type BillsResponse struct {
	Bills []domain.Bill `json:"bills"`
}

type BillDepthResponse struct {
	Bill domain.Bill `json:"bill"`
}

type Bill = domain.Bill
type BillStage = domain.BillStage
type BillVersion = domain.BillVersion
type BillVersionDiff = domain.BillVersionDiff
type BillClauseDiff = domain.BillClauseDiff
type BillAmendment = domain.BillAmendment
type BillCommitteeStage = domain.BillCommitteeStage

type openBillsIndexFunc func(context.Context) (usecase.BillsIndex, error)
type openDBFunc func(context.Context, string) (*sql.DB, error)
type newBillRepositoryFunc func(*sql.DB) usecase.BillRepository

type billsRuntime struct {
	mu      sync.Mutex
	open    openBillsIndexFunc
	openDB  openDBFunc
	newRepo newBillRepositoryFunc
	repo    usecase.BillRepository
}

var billData = newBillsRuntime(
	openBillsIndexFromEnv,
	openSQLiteReadOnly,
	func(db *sql.DB) usecase.BillRepository {
		return sqliteadapter.New(db)
	},
)

func newBillsRuntime(open openBillsIndexFunc, openDB openDBFunc, newRepo newBillRepositoryFunc) *billsRuntime {
	return &billsRuntime{open: open, openDB: openDB, newRepo: newRepo}
}

func (r *billsRuntime) repository(ctx context.Context) (usecase.BillRepository, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.repo != nil {
		return r.repo, nil
	}
	index, err := r.open(ctx)
	if err != nil {
		return nil, err
	}
	db, err := r.openDB(ctx, index.LocalPath)
	if err != nil {
		return nil, fmt.Errorf("open sqlite index: %w", err)
	}
	r.repo = r.newRepo(db)
	return r.repo, nil
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	if id := billVersionDiffIDFromRequest(req); id != "" {
		fromVersionID, toVersionID, message := billVersionDiffQueryFromRequest(req)
		if message != "" {
			return jsonError(http.StatusBadRequest, message), nil
		}
		repo, err := billData.repository(ctx)
		if err != nil {
			return mapInitializationError(err), nil
		}
		diff, err := usecase.NewLoadBillVersionDiff(repo).Execute(ctx, usecase.LoadBillVersionDiffInput{
			BillID:        id,
			FromVersionID: fromVersionID,
			ToVersionID:   toVersionID,
		})
		if err != nil {
			return mapBillVersionDiffError(err), nil
		}
		if diff == nil {
			return noContentResponse(), nil
		}
		return jsonResponse(http.StatusOK, diff), nil
	}

	repo, err := billData.repository(ctx)
	if err != nil {
		return mapInitializationError(err), nil
	}

	if id := billCommitteeStageIDFromRequest(req); id != "" {
		stage, err := usecase.NewGetBillCommitteeStage(repo).Execute(ctx, id)
		if err != nil {
			return mapBillError(err), nil
		}
		if stage == nil {
			return noContentResponse(), nil
		}
		return jsonResponse(http.StatusOK, stage), nil
	}

	if id := billIDFromRequest(req); id != "" {
		bill, err := usecase.NewGetBillDepth(repo).Execute(ctx, id)
		if err != nil {
			return mapBillError(err), nil
		}
		return jsonResponse(http.StatusOK, BillDepthResponse{Bill: bill}), nil
	}

	bills, err := usecase.NewListBills(repo).Execute(ctx, usecase.ListBillsInput{
		Status:     req.QueryStringParameters["status"],
		Parliament: req.QueryStringParameters["parliament"],
	})
	if err != nil {
		slog.Error("list bills request failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}
	return jsonResponse(http.StatusOK, BillsResponse{Bills: bills}), nil
}

func billIDFromRequest(req events.APIGatewayProxyRequest) string {
	for _, key := range []string{"id", "bill_id"} {
		if id := strings.TrimSpace(req.PathParameters[key]); id != "" {
			return id
		}
	}
	path := strings.Trim(req.Path, "/")
	for _, prefix := range []string{"api/v1/bills/", "bills/"} {
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			if rest == "" || strings.Contains(rest, "/") {
				return ""
			}
			return strings.TrimSpace(rest)
		}
	}
	return ""
}

func billVersionDiffIDFromRequest(req events.APIGatewayProxyRequest) string {
	path := strings.Trim(req.Path, "/")
	for _, prefix := range []string{"api/v1/bills/", "bills/"} {
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			if !strings.HasSuffix(rest, "/diff") {
				return ""
			}
			id := strings.TrimSuffix(rest, "/diff")
			if id == "" || strings.Contains(id, "/") {
				return ""
			}
			return strings.TrimSpace(id)
		}
	}
	if strings.Contains(req.Resource, "/diff") {
		for _, key := range []string{"id", "bill_id", "legisinfo_id"} {
			if id := strings.TrimSpace(req.PathParameters[key]); id != "" {
				return id
			}
		}
	}
	return ""
}

func billVersionDiffQueryFromRequest(req events.APIGatewayProxyRequest) (string, string, string) {
	fromVersionID := strings.TrimSpace(req.QueryStringParameters["from"])
	toVersionID := strings.TrimSpace(req.QueryStringParameters["to"])
	missing := make([]string, 0, 2)
	if fromVersionID == "" {
		missing = append(missing, "from")
	}
	if toVersionID == "" {
		missing = append(missing, "to")
	}
	if len(missing) == 1 {
		return "", "", "missing required query parameter: " + missing[0]
	}
	if len(missing) > 1 {
		return "", "", "missing required query parameters: " + strings.Join(missing, ", ")
	}
	return fromVersionID, toVersionID, ""
}

func billCommitteeStageIDFromRequest(req events.APIGatewayProxyRequest) string {
	path := strings.Trim(req.Path, "/")
	for _, prefix := range []string{"api/v1/bills/", "bills/"} {
		if strings.HasPrefix(path, prefix) {
			rest := strings.TrimPrefix(path, prefix)
			if !strings.HasSuffix(rest, "/committee-stage") {
				return ""
			}
			id := strings.TrimSuffix(rest, "/committee-stage")
			if id == "" || strings.Contains(id, "/") {
				return ""
			}
			return strings.TrimSpace(id)
		}
	}
	if strings.Contains(req.Resource, "/committee-stage") {
		for _, key := range []string{"id", "bill_id", "legisinfo_id"} {
			if id := strings.TrimSpace(req.PathParameters[key]); id != "" {
				return id
			}
		}
	}
	return ""
}

func openBillsIndexFromEnv(ctx context.Context) (usecase.BillsIndex, error) {
	manifestLoader, err := s3adapter.NewManifestLoaderFromEnv(ctx)
	if err != nil {
		return usecase.BillsIndex{}, err
	}
	indexDownloader, err := s3adapter.NewIndexDownloaderFromEnv(ctx)
	if err != nil {
		return usecase.BillsIndex{}, err
	}
	return usecase.NewOpenBillsIndex(manifestLoader, indexDownloader).Execute(ctx)
}

func openSQLiteReadOnly(ctx context.Context, path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", fmt.Sprintf(sqliteReadOnlyDSN, path))
	if err != nil {
		return nil, err
	}
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

func mapInitializationError(err error) events.APIGatewayProxyResponse {
	switch {
	case errors.Is(err, usecase.ErrManifestNotFound):
		return jsonError(http.StatusNotFound, err.Error())
	case errors.Is(err, usecase.ErrChecksumMismatch),
		errors.Is(err, usecase.ErrSchemaMismatch):
		return jsonError(http.StatusServiceUnavailable, err.Error(), map[string]string{"Retry-After": billsRetryAfter})
	default:
		slog.Error("bills service initialization failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error")
	}
}

func mapBillError(err error) events.APIGatewayProxyResponse {
	if errors.Is(err, usecase.ErrBillNotFound) {
		return jsonError(http.StatusNotFound, "bill not found")
	}
	slog.Error("get bill depth request failed", "error", err)
	return jsonError(http.StatusInternalServerError, "internal error")
}

func mapBillVersionDiffError(err error) events.APIGatewayProxyResponse {
	switch {
	case errors.Is(err, usecase.ErrDiffMissingFrom):
		return jsonError(http.StatusBadRequest, "missing required query parameter: from")
	case errors.Is(err, usecase.ErrDiffMissingTo):
		return jsonError(http.StatusBadRequest, "missing required query parameter: to")
	case errors.Is(err, usecase.ErrBillNotFound):
		return jsonError(http.StatusNotFound, "bill not found")
	default:
		slog.Error("load bill version diff request failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error")
	}
}

func jsonResponse(status int, payload any, extraHeaders ...map[string]string) events.APIGatewayProxyResponse {
	body, err := json.Marshal(payload)
	if err != nil {
		slog.Error("marshal bills response", "error", err)
		return events.APIGatewayProxyResponse{
			StatusCode: http.StatusInternalServerError,
			Headers:    map[string]string{"Content-Type": "application/json"},
			Body:       `{"error":"internal error"}`,
		}
	}

	headers := map[string]string{
		"Content-Type":  "application/json",
		"Cache-Control": "public, max-age=300",
	}
	if len(extraHeaders) > 0 {
		for key, value := range extraHeaders[0] {
			headers[key] = value
		}
	}
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    headers,
		Body:       string(body),
	}
}

func noContentResponse() events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusNoContent,
		Headers: map[string]string{
			"Cache-Control": "public, max-age=300",
		},
	}
}

func jsonError(status int, message string, extraHeaders ...map[string]string) events.APIGatewayProxyResponse {
	headers := map[string]string(nil)
	if len(extraHeaders) > 0 {
		headers = extraHeaders[0]
	}
	return jsonResponse(status, map[string]string{"error": message}, headers)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("bills", HandleRequest))
}
