package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"epac/member-content"
	"epac/member-lobbying/internal/usecase"
	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_MissingMemberId(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusBadRequest)
	}
}

func TestMemberIDFromPath(t *testing.T) {
	tests := []struct {
		name           string
		pathParameters map[string]string
		want           string
	}{
		{
			name:           "rest route id",
			pathParameters: map[string]string{"id": "278707"},
			want:           "278707",
		},
		{
			name:           "api route memberId",
			pathParameters: map[string]string{"memberId": "279135"},
			want:           "279135",
		},
		{
			name:           "trimmed value",
			pathParameters: map[string]string{"memberId": " 279135 "},
			want:           "279135",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := memberIDFromPath(tc.pathParameters)
			if got != tc.want {
				t.Fatalf("got %q, want %q", got, tc.want)
			}
		})
	}
}

func TestHandleRequest_ReadsLobbyingFixture(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("ARTIFACTS_DIR", dir)
	repository = nil
	t.Cleanup(func() { repository = nil })

	store := membercontent.FileStore{Root: dir}
	artifact := usecase.MPLobbyingArtifact{
		MemberID: "278707",
		Summary: usecase.MPLobbyingSummary{
			TotalCommunications:           2,
			UniqueOrganizations:           2,
			MostFrequentSubject:           "Taxation",
			PreviousParliamentCommunications: 1,
			TrendVsPreviousParliament:     2,
		},
		CohortBaseline: usecase.CohortComparisonBaseline{
			Party: "Liberal",
			PartyAverage: 12,
			NationalAverage: 15,
		},
		AvailableSubjects: []string{"Taxation", "Transport"},
		TopOrganizations: []usecase.TopLobbyingOrganization{
			{OrganizationName: "ABC Corp", OrganizationSector: "Finance", Count: 2, OrganizationID: "abc"},
			{OrganizationName: "DEF Ltd", OrganizationSector: "Health", Count: 1, OrganizationID: "def"},
		},
		SubjectDistribution: []usecase.LobbyingSubjectDistribution{
			{Subject: "Taxation", Count: 2, Percentage: 67},
			{Subject: "Transport", Count: 1, Percentage: 33},
		},
		Timeline: []usecase.MPLobbyingTimelineEntry{
			{
				CommunicationDate:     "2026-04-02",
				OrganizationName:      "ABC Corp",
				OrganizationSector:    "Finance",
				SubjectMatter:         "Tax policy",
				CommunicationType:     "meeting",
				OrganizationProfileURL: "https://example.com/org/abc",
				RecordURL:             "https://lobbycanada.gc.ca/record/1",
				RelatedBillConfidenceUsed: true,
			},
			{
				CommunicationDate:     "2025-01-10",
				OrganizationName:      "DEF Ltd",
				OrganizationSector:    "Health",
				SubjectMatter:         "Medical devices",
				CommunicationType:     "written",
				OrganizationProfileURL: "",
				RecordURL:             "https://lobbycanada.gc.ca/record/2",
				RelatedBillConfidenceUsed: false,
			},
		},
	}
	body, err := json.Marshal(artifact)
	if err != nil {
		t.Fatalf("marshal fixture: %v", err)
	}
	if err := store.Put(context.Background(), "members/v1/by-id/278707/lobbying.json", body); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"id": "278707"},
		QueryStringParameters: map[string]string{
			"page":    "1",
			"per_page": "1",
			"subject": "tax",
			"range":   "all",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d: %s", resp.StatusCode, http.StatusOK, resp.Body)
	}

	var got usecase.MPLobbyingResponse
	if err := json.Unmarshal([]byte(resp.Body), &got); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if got.Total != 1 {
		t.Fatalf("total = %d, want 1", got.Total)
	}
	if got.Pages != 2 {
		t.Fatalf("pages = %d, want 2", got.Pages)
	}
	if got.Summary.TotalCommunications != 2 {
		t.Fatalf("total communications = %d, want 2", got.Summary.TotalCommunications)
	}
	if got.CohortComparison.Party != "Liberal" {
		t.Fatalf("cohort party = %q, want Liberal", got.CohortComparison.Party)
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
		t.Fatalf("status = %d, want %d: %s", resp.StatusCode, http.StatusOK, resp.Body)
	}

	var got usecase.MPLobbyingResponse
	if err := json.Unmarshal([]byte(resp.Body), &got); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if got.Total != 0 || len(got.Timeline) != 0 || got.MemberID != "unknown" {
		t.Fatalf("got = %+v, want empty response for unknown member", got)
	}
}
