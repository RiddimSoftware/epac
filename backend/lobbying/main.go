// lobbying Lambda - OCL lobbying context and profile endpoints.
package main

import (
	"context"
	"database/sql"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"

	"epac/lobbying/application"
	ocltopicmap "epac/lobbying/internal/adapter/ocltopicmap"
	s3adapter "epac/lobbying/internal/adapter/s3"
	sqliteadapter "epac/lobbying/internal/adapter/sqlite"
	"epac/lobbying/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

//go:embed ocl_topic_map.json
var topicMapJSON []byte

type byTopicExecutor interface {
	Execute(context.Context, string, usecase.Pagination) (usecase.LobbyingByTopicResult, error)
}

type ministerPortfolioExecutor interface {
	Execute(context.Context, string) (usecase.MinisterLobbyingByPortfolioResult, error)
}

type cabinetOverviewExecutor interface {
	Execute(context.Context, usecase.CabinetLobbyingOverviewInput) (usecase.CabinetLobbyingOverviewResult, error)
}

type mpLobbyingExposureExecutor interface {
	Execute(context.Context, application.LoadMPLobbyingExposureInput) (application.MPLobbyingExposureResult, error)
}

type closeFunc func(context.Context)

type openLobbyingIndexFunc func(context.Context) (usecase.LobbyingIndex, error)
type openLobbyingDBFunc func(context.Context, string) (*sql.DB, error)

type lobbyingRuntime struct {
	mu        sync.Mutex
	openIndex openLobbyingIndexFunc
	openDB    openLobbyingDBFunc
	db        *sql.DB
}

const (
	lobbyingRetryAfter = "5"
	sqliteReadOnlyDSN  = "file:%s?mode=ro&_pragma=query_only(1)"
)

var newByTopicService = newProductionByTopicService
var newMinisterPortfolioService = newProductionMinisterPortfolioService
var newCabinetOverviewService = newProductionCabinetOverviewService
var newMPLobbyingExposureService = newProductionMPLobbyingExposureService
var lobbyingDB = newLobbyingRuntime(openLobbyingIndexFromEnv, openSQLiteReadOnly)

func newLobbyingRuntime(openIndex openLobbyingIndexFunc, openDB openLobbyingDBFunc) *lobbyingRuntime {
	return &lobbyingRuntime{openIndex: openIndex, openDB: openDB}
}

func (r *lobbyingRuntime) DB(ctx context.Context) (*sql.DB, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.db != nil {
		return r.db, nil
	}
	index, err := r.openIndex(ctx)
	if err != nil {
		return nil, err
	}
	db, err := r.openDB(ctx, index.LocalPath)
	if err != nil {
		return nil, fmt.Errorf("open sqlite index: %w", err)
	}
	r.db = db
	return db, nil
}

func HandleRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if legisInfoID := billLobbyingContextIDFromRequest(req); legisInfoID != "" {
		return handleBillLobbyingContext(ctx, req, legisInfoID)
	}
	if isOrganizationRequest(req) {
		return handleOrganizationRequest(ctx, req)
	}
	if memberID, ok := exposureMemberIDFromRequest(req); ok {
		return handleMPLobbyingExposure(ctx, req, memberID)
	}
	if memberID := ministerMemberIDFromRequest(req); memberID != "" {
		return handleMinisterPortfolio(ctx, req, memberID)
	}
	if isCabinetOverviewRequest(req) {
		return handleCabinetOverview(ctx, req)
	}

	slug := slugFromRequest(req)
	if slug == "" {
		return jsonError(http.StatusBadRequest, "missing topic slug"), nil
	}

	pagination, err := parsePagination(req.QueryStringParameters)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	service, closeService, err := newByTopicService(ctx)
	if err != nil {
		slog.Error("lobbying service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeService(ctx)

	result, err := service.Execute(ctx, slug, pagination)
	if err != nil {
		slog.Error("lobbying by-topic request failed", "error", err, "slug", slug)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}

	body, err := json.Marshal(result)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func handleMinisterPortfolio(ctx context.Context, _ events.APIGatewayV2HTTPRequest, memberID string) (events.APIGatewayV2HTTPResponse, error) {
	service, closeService, err := newMinisterPortfolioService(ctx)
	if err != nil {
		slog.Error("minister lobbying service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeService(ctx)

	result, err := service.Execute(ctx, memberID)
	if err != nil {
		if errors.Is(err, usecase.ErrMinisterNotFound) {
			return jsonError(http.StatusNotFound, "minister not found"), nil
		}
		slog.Error("minister lobbying by-portfolio request failed", "error", err, "member_id", memberID)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}
	body, err := json.Marshal(result)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func handleMPLobbyingExposure(ctx context.Context, req events.APIGatewayV2HTTPRequest, memberID string) (events.APIGatewayV2HTTPResponse, error) {
	input, err := parseMPLobbyingExposureInput(memberID, req.QueryStringParameters)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	service, closeService, err := newMPLobbyingExposureService(ctx)
	if err != nil {
		slog.Error("MP lobbying exposure service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeService(ctx)

	result, err := service.Execute(ctx, input)
	if err != nil {
		slog.Error("MP lobbying exposure request failed", "error", err, "member_id", input.MemberID, "parliament", input.Parliament)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}

	body, err := json.Marshal(result)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func handleCabinetOverview(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	input, err := parseCabinetOverviewInput(req.QueryStringParameters)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	service, closeService, err := newCabinetOverviewService(ctx)
	if err != nil {
		slog.Error("cabinet lobbying service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeService(ctx)

	result, err := service.Execute(ctx, input)
	if err != nil {
		slog.Error("cabinet lobbying overview request failed", "error", err, "parliament", input.Parliament)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}
	body, err := json.Marshal(result)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func newProductionByTopicService(ctx context.Context) (byTopicExecutor, closeFunc, error) {
	source, err := ocltopicmap.NewSource(topicMapJSON)
	if err != nil {
		return nil, noopClose, err
	}
	db, err := lobbyingDB.DB(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := sqliteadapter.New(db)
	return usecase.New(repo, source, slogLowConfidenceLogger{}), noopClose, nil
}

func newProductionMinisterPortfolioService(ctx context.Context) (ministerPortfolioExecutor, closeFunc, error) {
	source, err := ocltopicmap.NewSource(topicMapJSON)
	if err != nil {
		return nil, noopClose, err
	}
	db, err := lobbyingDB.DB(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := sqliteadapter.New(db)
	logger := slogPortfolioBoundaryGapLogger{recorder: repo}
	service := usecase.NewLoadMinisterLobbyingByPortfolio(repo, repo, repo, source, logger)
	return service, noopClose, nil
}

func newProductionCabinetOverviewService(ctx context.Context) (cabinetOverviewExecutor, closeFunc, error) {
	db, err := lobbyingDB.DB(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := sqliteadapter.New(db)
	logger := slogPortfolioBoundaryGapLogger{recorder: repo}
	service := usecase.NewLoadCabinetLobbyingOverview(repo, repo, logger)
	return service, noopClose, nil
}

func newProductionMPLobbyingExposureService(ctx context.Context) (mpLobbyingExposureExecutor, closeFunc, error) {
	db, err := lobbyingDB.DB(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := sqliteadapter.New(db)
	service, err := application.NewLoadMPLobbyingExposure(repo, repo)
	if err != nil {
		return nil, noopClose, err
	}
	return service, noopClose, nil
}

func openLobbyingIndexFromEnv(ctx context.Context) (usecase.LobbyingIndex, error) {
	manifestLoader, err := s3adapter.NewManifestLoaderFromEnv(ctx)
	if err != nil {
		return usecase.LobbyingIndex{}, err
	}
	indexDownloader, err := s3adapter.NewIndexDownloaderFromEnv(ctx)
	if err != nil {
		return usecase.LobbyingIndex{}, err
	}
	return usecase.NewOpenLobbyingIndex(manifestLoader, indexDownloader).Execute(ctx)
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

type slogLowConfidenceLogger struct{}

func (slogLowConfidenceLogger) WarnLowConfidenceMapping(ctx context.Context, mapping usecase.OCLTopicMapping) {
	slog.WarnContext(ctx,
		"low-confidence OCL topic mapping included in lobbying by-topic response",
		"ocl_code", mapping.OCLCode,
		"epac_topic_slug", mapping.EpacTopicSlug,
		"confidence", mapping.Confidence,
	)
}

type portfolioBoundaryGapRecorder interface {
	RecordPortfolioBoundaryGap(ctx context.Context, gap usecase.PortfolioBoundaryGap) error
}

type slogPortfolioBoundaryGapLogger struct {
	recorder portfolioBoundaryGapRecorder
}

func (l slogPortfolioBoundaryGapLogger) WarnPortfolioBoundaryGap(ctx context.Context, gap usecase.PortfolioBoundaryGap) {
	slog.WarnContext(ctx,
		"portfolio_boundary_gap",
		"member_id", gap.MemberID,
		"minister_name", gap.MinisterName,
		"reason", gap.Reason,
	)
	if l.recorder == nil {
		return
	}
	if err := l.recorder.RecordPortfolioBoundaryGap(ctx, gap); err != nil {
		slog.WarnContext(ctx, "portfolio_boundary_gap_run_history_write_failed", "error", err)
	}
}

func noopClose(context.Context) {}

func parsePagination(params map[string]string) (usecase.Pagination, error) {
	page, err := parsePositiveInt(params["page"], 1, "page")
	if err != nil {
		return usecase.Pagination{}, err
	}
	perPage, err := parsePositiveInt(params["per_page"], usecase.DefaultPerPage, "per_page")
	if err != nil {
		return usecase.Pagination{}, err
	}
	return usecase.NewPagination(page, perPage)
}

func parseCabinetOverviewInput(params map[string]string) (usecase.CabinetLobbyingOverviewInput, error) {
	if strings.TrimSpace(params["parliament"]) == "" {
		return usecase.CabinetLobbyingOverviewInput{}, fmt.Errorf("parliament must be an integer greater than or equal to 1")
	}
	parliament, err := parsePositiveInt(params["parliament"], 0, "parliament")
	if err != nil {
		return usecase.CabinetLobbyingOverviewInput{}, err
	}
	return usecase.CabinetLobbyingOverviewInput{
		Parliament: parliament,
		Portfolio:  strings.TrimSpace(params["portfolio"]),
	}, nil
}

func parsePositiveInt(raw string, defaultValue int, name string) (int, error) {
	if strings.TrimSpace(raw) == "" {
		return defaultValue, nil
	}
	value, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || value < 1 {
		return 0, fmt.Errorf("%s must be an integer greater than or equal to 1", name)
	}
	return value, nil
}

func parseRequiredPositiveInt(params map[string]string, name string) (int, error) {
	if strings.TrimSpace(params[name]) == "" {
		return 0, fmt.Errorf("%s is required", name)
	}
	return parsePositiveInt(params[name], 0, name)
}

func parseMPLobbyingExposureInput(memberID string, params map[string]string) (application.LoadMPLobbyingExposureInput, error) {
	memberID = strings.TrimSpace(memberID)
	if memberID == "" {
		return application.LoadMPLobbyingExposureInput{}, fmt.Errorf("missing member id")
	}
	parliament, err := parseRequiredPositiveInt(params, "parliament")
	if err != nil {
		return application.LoadMPLobbyingExposureInput{}, err
	}
	page, err := parsePositiveInt(params["page"], 1, "page")
	if err != nil {
		return application.LoadMPLobbyingExposureInput{}, err
	}
	window, err := application.ParseLobbyingWindow(params["window"])
	if err != nil {
		return application.LoadMPLobbyingExposureInput{}, err
	}
	return application.LoadMPLobbyingExposureInput{
		MemberID:   memberID,
		Parliament: parliament,
		Window:     window,
		Page:       page,
	}, nil
}

func exposureMemberIDFromRequest(req events.APIGatewayV2HTTPRequest) (string, bool) {
	path := requestPath(req)
	for _, prefix := range []string{"/api/v1/members/", "/members/"} {
		if strings.HasPrefix(path, prefix) && strings.HasSuffix(path, "/lobbying-exposure") {
			for _, key := range []string{"member_id", "memberId", "id"} {
				if memberID := strings.TrimSpace(req.PathParameters[key]); memberID != "" {
					return unescapePathPart(memberID), true
				}
			}
			memberID := strings.TrimSuffix(strings.TrimPrefix(path, prefix), "/lobbying-exposure")
			return unescapePathPart(memberID), true
		}
	}
	return "", false
}

func slugFromRequest(req events.APIGatewayV2HTTPRequest) string {
	if slug := strings.TrimSpace(req.PathParameters["slug"]); slug != "" {
		return unescapePathPart(slug)
	}

	path := req.RawPath
	if path == "" {
		path = req.RequestContext.HTTP.Path
	}
	path = normalizedPath(path)
	for _, prefix := range []string{"/api/v1/lobbying/by-topic/", "/lobbying/by-topic/"} {
		if strings.HasPrefix(path, prefix) {
			return unescapePathPart(strings.TrimPrefix(path, prefix))
		}
	}
	return ""
}

func ministerMemberIDFromRequest(req events.APIGatewayV2HTTPRequest) string {
	for _, key := range []string{"member_id", "memberId", "id"} {
		if memberID := strings.TrimSpace(req.PathParameters[key]); memberID != "" {
			return unescapePathPart(memberID)
		}
	}

	path := requestPath(req)
	for _, prefix := range []string{"/api/v1/ministers/", "/ministers/"} {
		if !strings.HasPrefix(path, prefix) {
			continue
		}
		remainder := strings.TrimPrefix(path, prefix)
		if !strings.HasSuffix(remainder, "/lobbying-by-portfolio") {
			continue
		}
		memberID := strings.TrimSuffix(remainder, "/lobbying-by-portfolio")
		if strings.Contains(memberID, "/") {
			continue
		}
		return unescapePathPart(memberID)
	}
	return ""
}

func isCabinetOverviewRequest(req events.APIGatewayV2HTTPRequest) bool {
	switch requestPath(req) {
	case "/api/v1/cabinet/lobbying-overview", "/cabinet/lobbying-overview":
		return true
	default:
		return false
	}
}

func requestPath(req events.APIGatewayV2HTTPRequest) string {
	path := req.RawPath
	if path == "" {
		path = req.RequestContext.HTTP.Path
	}
	return normalizedPath(path)
}

func normalizedPath(raw string) string {
	raw = "/" + strings.Trim(strings.TrimSpace(raw), "/")
	if raw == "/" {
		return raw
	}
	return strings.TrimSuffix(raw, "/")
}

func unescapePathPart(value string) string {
	decoded, err := url.PathUnescape(value)
	if err != nil {
		return value
	}
	return decoded
}

func jsonResponse(status int, body []byte) events.APIGatewayV2HTTPResponse {
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(body),
	}
}

func jsonError(status int, message string, extraHeaders ...map[string]string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	headers := map[string]string{"Content-Type": "application/json"}
	if len(extraHeaders) > 0 {
		for key, value := range extraHeaders[0] {
			headers[key] = value
		}
	}
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    headers,
		Body:       string(body),
	}
}

func serviceUnavailableError(err error) events.APIGatewayV2HTTPResponse {
	if errors.Is(err, usecase.ErrManifestNotFound) ||
		errors.Is(err, usecase.ErrChecksumMismatch) ||
		errors.Is(err, usecase.ErrSchemaMismatch) {
		return jsonError(http.StatusServiceUnavailable, err.Error(), map[string]string{"Retry-After": lobbyingRetryAfter})
	}
	return jsonError(http.StatusServiceUnavailable, "lobbying data unavailable")
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("lobbying", HandleRequest))
}
