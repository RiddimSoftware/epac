// member-votes Lambda — GET /api/v1/members/{id}/votes
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"epac/member-content"
	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

type memberContentRepository interface {
	ListMemberVotes(ctx context.Context, memberID string, page, perPage int) (membercontent.MemberVotesResponse, error)
}

type S3ArtifactMemberContentRepository struct {
	store membercontent.Store
}

func (r S3ArtifactMemberContentRepository) ListMemberVotes(ctx context.Context, memberID string, page, perPage int) (membercontent.MemberVotesResponse, error) {
	return membercontent.ListMemberVotes(ctx, r.store, memberID, page, perPage)
}

var repository memberContentRepository

func getRepository(ctx context.Context) (memberContentRepository, error) {
	if repository != nil {
		return repository, nil
	}
	store, err := membercontent.NewStoreFromEnv(ctx)
	if err != nil {
		return nil, err
	}
	repository = S3ArtifactMemberContentRepository{store: store}
	return repository, nil
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	memberID := memberIDFromPath(req.PathParameters)
	if memberID == "" {
		return jsonError(http.StatusBadRequest, "missing member id"), nil
	}

	page := membercontent.ParsePositiveInt(req.QueryStringParameters["page"], 1)
	perPage := membercontent.ParsePositiveInt(req.QueryStringParameters["per_page"], membercontent.DefaultPerPage)

	repo, err := getRepository(ctx)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	resp, err := repo.ListMemberVotes(ctx, memberID, page, perPage)
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
	lambda.Start(observability.WrapAPIGateway("member-votes", HandleRequest))
}
