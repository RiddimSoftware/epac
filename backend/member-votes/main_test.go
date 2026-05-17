package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"epac/member-content"
	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_MissingMemberID(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestHandleRequest_ReadsVotesFixture(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("ARTIFACTS_DIR", dir)
	repository = nil
	t.Cleanup(func() { repository = nil })

	oldDate := "2024-01-01"
	newDate := "2024-01-02"
	store := membercontent.FileStore{Root: dir}
	if _, err := membercontent.WriteMemberVotesArtifacts(context.Background(), store, membercontent.MemberVotesArtifact{
		MemberID: "278707",
		Votes: []membercontent.VoteEntry{
			{
				VoteID:     "100",
				Date:       &oldDate,
				BillNumber: "C-1",
				Summary:    "Older vote",
				Vote:       "Nay",
				SourceURL:  "https://www.ourcommons.ca/members/en/votes",
			},
			{
				VoteID:     "101",
				Date:       &newDate,
				BillNumber: "C-2",
				Summary:    "Newer vote",
				Vote:       "Yea",
				SourceURL:  "https://www.ourcommons.ca/members/en/votes",
			},
		},
	}); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"memberId": "278707"},
		QueryStringParameters: map[string]string{
			"page":     "1",
			"per_page": "1",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}

	var body membercontent.MemberVotesResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Total != 2 || body.Pages != 2 {
		t.Fatalf("total/pages = %d/%d, want 2/2", body.Total, body.Pages)
	}
	if len(body.Votes) != 1 || body.Votes[0].VoteID != "101" {
		t.Fatalf("votes = %+v, want newest vote first", body.Votes)
	}
}

func TestHandleRequest_UnknownMemberReturnsEmptyShape(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("ARTIFACTS_DIR", dir)
	repository = nil
	t.Cleanup(func() { repository = nil })

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"id": "unknown"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}

	var body membercontent.MemberVotesResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Total != 0 || len(body.Votes) != 0 {
		t.Fatalf("body = %+v, want empty votes response", body)
	}
}
