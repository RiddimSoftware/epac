// members Lambda - GET /api/v1/members and GET /api/v1/members/{id}
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

	s3adapter "epac/members/internal/adapter/s3"
	sqliteadapter "epac/members/internal/adapter/sqlite"
	"epac/members/internal/domain"
	"epac/members/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	_ "modernc.org/sqlite"
)

const (
	membersRetryAfter = "5"
	sqliteReadOnlyDSN = "file:%s?mode=ro&_pragma=query_only(1)"
)

type MembersResponse struct {
	Members []domain.Member `json:"members"`
}

type MemberProfileResponse struct {
	Member domain.Member `json:"member"`
}

type Member = domain.Member
type AttendanceRecord = domain.AttendanceRecord

type openMembersIndexFunc func(context.Context) (usecase.MembersIndex, error)
type openDBFunc func(context.Context, string) (*sql.DB, error)
type newMemberRepositoryFunc func(*sql.DB) usecase.MemberRepository

type membersRuntime struct {
	mu      sync.Mutex
	open    openMembersIndexFunc
	openDB  openDBFunc
	newRepo newMemberRepositoryFunc
	repo    usecase.MemberRepository
}

var memberData = newMembersRuntime(
	openMembersIndexFromEnv,
	openSQLiteReadOnly,
	func(db *sql.DB) usecase.MemberRepository {
		return sqliteadapter.New(db)
	},
)

func newMembersRuntime(open openMembersIndexFunc, openDB openDBFunc, newRepo newMemberRepositoryFunc) *membersRuntime {
	return &membersRuntime{open: open, openDB: openDB, newRepo: newRepo}
}

func (r *membersRuntime) repository(ctx context.Context) (usecase.MemberRepository, error) {
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
	repo, err := memberData.repository(ctx)
	if err != nil {
		return mapInitializationError(err), nil
	}

	if id := memberIDFromRequest(req); id != "" {
		member, err := usecase.NewGetMemberProfile(repo).Execute(ctx, id)
		if err != nil {
			return mapMemberError(err), nil
		}
		return jsonResponse(http.StatusOK, MemberProfileResponse{Member: member}), nil
	}

	members, err := usecase.NewListMembers(repo).Execute(ctx, usecase.ListMembersInput{
		Province: req.QueryStringParameters["province"],
		Party:    req.QueryStringParameters["party"],
	})
	if err != nil {
		slog.Error("list members request failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}
	return jsonResponse(http.StatusOK, MembersResponse{Members: members}), nil
}

func memberIDFromRequest(req events.APIGatewayProxyRequest) string {
	for _, key := range []string{"id", "member_id", "memberId"} {
		if id := strings.TrimSpace(req.PathParameters[key]); id != "" {
			return id
		}
	}
	path := strings.Trim(req.Path, "/")
	for _, prefix := range []string{"api/v1/members/", "members/"} {
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

func openMembersIndexFromEnv(ctx context.Context) (usecase.MembersIndex, error) {
	manifestLoader, err := s3adapter.NewManifestLoaderFromEnv(ctx)
	if err != nil {
		return usecase.MembersIndex{}, err
	}
	indexDownloader, err := s3adapter.NewIndexDownloaderFromEnv(ctx)
	if err != nil {
		return usecase.MembersIndex{}, err
	}
	return usecase.NewOpenMembersIndex(manifestLoader, indexDownloader).Execute(ctx)
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
		return jsonError(http.StatusServiceUnavailable, err.Error(), map[string]string{"Retry-After": membersRetryAfter})
	default:
		slog.Error("members service initialization failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error")
	}
}

func mapMemberError(err error) events.APIGatewayProxyResponse {
	if errors.Is(err, usecase.ErrMemberNotFound) {
		return jsonError(http.StatusNotFound, "member not found")
	}
	slog.Error("get member profile request failed", "error", err)
	return jsonError(http.StatusInternalServerError, "internal error")
}

func jsonResponse(status int, payload any, extraHeaders ...map[string]string) events.APIGatewayProxyResponse {
	body, err := json.Marshal(payload)
	if err != nil {
		slog.Error("marshal members response", "error", err)
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

func jsonError(status int, message string, extraHeaders ...map[string]string) events.APIGatewayProxyResponse {
	headers := map[string]string(nil)
	if len(extraHeaders) > 0 {
		headers = extraHeaders[0]
	}
	return jsonResponse(status, map[string]string{"error": message}, headers)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("members", HandleRequest))
}
