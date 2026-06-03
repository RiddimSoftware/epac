// lobbying Lambda - GET /api/v1/lobbying/by-topic/{slug}
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	ocltopicmap "epac/lobbying/internal/adapter/ocltopicmap"
	postgresadapter "epac/lobbying/internal/adapter/postgres"
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

type closeFunc func(context.Context)

var newByTopicService = newProductionByTopicService

func HandleRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
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
		return jsonError(http.StatusServiceUnavailable, "lobbying data unavailable"), nil
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

func newProductionByTopicService(ctx context.Context) (byTopicExecutor, closeFunc, error) {
	source, err := ocltopicmap.NewSource(topicMapJSON)
	if err != nil {
		return nil, noopClose, err
	}
	conn, err := postgresadapter.Connect(ctx)
	if err != nil {
		return nil, noopClose, err
	}
	repo := postgresadapter.New(conn)
	return usecase.New(repo, source, slogLowConfidenceLogger{}), func(closeCtx context.Context) {
		_ = conn.Close(closeCtx)
	}, nil
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

func jsonError(status int, message string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("lobbying", HandleRequest))
}
