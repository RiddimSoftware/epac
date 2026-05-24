// member-speeches Lambda — GET /api/v1/members/{id}/speeches
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"epac/member-speeches/internal/adapter/artifact"
	"epac/member-speeches/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

var repository usecase.MemberContentRepository

func getRepository(ctx context.Context) (usecase.MemberContentRepository, error) {
	if repository != nil {
		return repository, nil
	}
	repo, err := artifact.NewMemberContentRepositoryFromEnv(ctx)
	if err != nil {
		return nil, err
	}
	repository = repo
	return repository, nil
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	memberID := memberIDFromPath(req.PathParameters)
	if memberID == "" {
		return jsonError(http.StatusBadRequest, "missing member id"), nil
	}

	page := usecase.ParsePositiveInt(req.QueryStringParameters["page"], 1)
	perPage := usecase.ParsePositiveInt(req.QueryStringParameters["per_page"], usecase.DefaultPerPage)
	topic := strings.TrimSpace(req.QueryStringParameters["topic"])

	repo, err := getRepository(ctx)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	resp, err := usecase.New(repo).Execute(ctx, memberID, page, perPage, topic)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	body, err := json.Marshal(resp)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func memberIDFromPath(pathParameters map[string]string) string {
	if memberID := strings.TrimSpace(pathParameters["id"]); memberID != "" {
		return memberID
	}
	return strings.TrimSpace(pathParameters["memberId"])
}

func jsonError(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("member-speeches", HandleRequest))
}
