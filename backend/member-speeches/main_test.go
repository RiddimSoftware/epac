package main

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"epac/member-content"
	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequest_MissingMemberId(t *testing.T) {
	ctx := context.Background()
	req := events.APIGatewayProxyRequest{
		PathParameters: map[string]string{},
	}
	resp, err := HandleRequest(ctx, req)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got status %d, want %d", resp.StatusCode, http.StatusBadRequest)
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
			name:           "http api memberId",
			pathParameters: map[string]string{"memberId": "279135"},
			want:           "279135",
		},
		{
			name:           "id takes precedence",
			pathParameters: map[string]string{"id": "278707", "memberId": "279135"},
			want:           "278707",
		},
		{
			name:           "trims value",
			pathParameters: map[string]string{"memberId": " 279135 "},
			want:           "279135",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := memberIDFromPath(tt.pathParameters)
			if got != tt.want {
				t.Fatalf("got %q, want %q", got, tt.want)
			}
		})
	}
}

func TestJsonError(t *testing.T) {
	resp := jsonError(http.StatusNotFound, "speech not found")
	if resp.StatusCode != http.StatusNotFound {
		t.Errorf("got status %d, want 404", resp.StatusCode)
	}
	if resp.Headers["Content-Type"] != "application/json" {
		t.Errorf("got Content-Type %q, want application/json", resp.Headers["Content-Type"])
	}
	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
	if body["error"] != "speech not found" {
		t.Errorf("got error %q, want 'speech not found'", body["error"])
	}
}

func TestJsonError_BadRequest(t *testing.T) {
	resp := jsonError(http.StatusBadRequest, "missing member id")
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("got status %d, want 400", resp.StatusCode)
	}
	var body map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("body is not valid JSON: %v", err)
	}
	if body["error"] != "missing member id" {
		t.Errorf("got error %q, want 'missing member id'", body["error"])
	}
}

func TestHandleRequest_ReadsSpeechFixture(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("ARTIFACTS_DIR", dir)
	repository = nil
	t.Cleanup(func() { repository = nil })

	dateOld := "2024-01-01"
	dateNew := "2024-01-02"
	topic := "Housing"
	otherTopic := "Budget"
	wordCount := 150
	seqOne := 1
	seqTwo := 2
	store := membercontent.FileStore{Root: dir}
	if _, err := membercontent.WriteMemberSpeechesArtifacts(context.Background(), store, membercontent.MemberSpeechesArtifact{
		MemberID: "278707",
		Speeches: []membercontent.SpeechRecord{
			{
				InterventionID:  "old",
				SittingDate:     &dateOld,
				SubjectTitle:    &otherTopic,
				Preview:         "older speech",
				WordCount:       &wordCount,
				Filename:        "HAN001-E.XML",
				InterventionSeq: &seqOne,
			},
			{
				InterventionID:  "new",
				SittingDate:     &dateNew,
				SubjectTitle:    &topic,
				Preview:         "newer speech",
				WordCount:       &wordCount,
				Filename:        "HAN002-E.XML",
				InterventionSeq: &seqTwo,
			},
		},
	}); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"id": "278707"},
		QueryStringParameters: map[string]string{
			"page":     "1",
			"per_page": "1",
			"topic":    "housing",
		},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}

	var body membercontent.MemberSpeechesResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if body.Total != 1 {
		t.Fatalf("total = %d, want 1", body.Total)
	}
	if len(body.Speeches) != 1 || body.Speeches[0].InterventionID != "new" {
		t.Fatalf("speeches = %+v, want only newer housing speech", body.Speeches)
	}
	if body.Stats.TotalSpeeches != 2 {
		t.Fatalf("stats.total_speeches = %d, want 2", body.Stats.TotalSpeeches)
	}
}
