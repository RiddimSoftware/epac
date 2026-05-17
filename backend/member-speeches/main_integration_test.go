//go:build integration

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"testing"
	"time"

	"epac/member-content"
	"github.com/aws/aws-lambda-go/events"
)

func seedSpeechFixture(t *testing.T, memberID string, count int) string {
	t.Helper()
	dir := t.TempDir()
	t.Setenv("ARTIFACTS_DIR", dir)
	repository = nil
	t.Cleanup(func() { repository = nil })

	base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	speeches := make([]membercontent.SpeechRecord, 0, count)
	for i := range count {
		id := fmt.Sprintf("sp-%03d", i+1)
		date := base.AddDate(0, 0, i).Format("2006-01-02")
		topic := "Budget"
		seq := i + 1
		speeches = append(speeches, membercontent.SpeechRecord{
			InterventionID:  id,
			SittingDate:     &date,
			SubjectTitle:    &topic,
			Preview:         "speech content",
			Filename:        "HAN001-E.XML",
			InterventionSeq: &seq,
		})
	}

	store := membercontent.FileStore{Root: dir}
	if _, err := membercontent.WriteMemberSpeechesArtifacts(context.Background(), store, membercontent.MemberSpeechesArtifact{
		MemberID: memberID,
		Speeches: speeches,
	}); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
	return dir
}

func executeSpeechFixtureRequest(t *testing.T, memberID string, query map[string]string) membercontent.MemberSpeechesResponse {
	t.Helper()
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters:        map[string]string{"id": memberID},
		QueryStringParameters: query,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200: %s", resp.StatusCode, resp.Body)
	}
	var out membercontent.MemberSpeechesResponse
	if err := json.Unmarshal([]byte(resp.Body), &out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return out
}

func TestMemberSpeechesHappyPath_ReturnsPagedResults(t *testing.T) {
	seedSpeechFixture(t, "m-001", 25)

	out := executeSpeechFixtureRequest(t, "m-001", map[string]string{
		"page":     "1",
		"per_page": "10",
	})

	if out.Total != 25 {
		t.Errorf("total: got %d, want 25", out.Total)
	}
	if out.Pages != 3 {
		t.Errorf("pages: got %d, want 3", out.Pages)
	}
	if len(out.Speeches) != 10 {
		t.Fatalf("len(speeches): got %d, want 10", len(out.Speeches))
	}
	for i, s := range out.Speeches {
		want := fmt.Sprintf("sp-%03d", 25-i)
		if s.InterventionID != want {
			t.Errorf("speeches[%d].id: got %q, want %q", i, s.InterventionID, want)
		}
	}
}

func TestMemberSpeechesPagination_LastPagePartial(t *testing.T) {
	seedSpeechFixture(t, "m-001", 25)

	out := executeSpeechFixtureRequest(t, "m-001", map[string]string{
		"page":     "3",
		"per_page": "10",
	})

	if len(out.Speeches) != 5 {
		t.Errorf("len(speeches): got %d, want 5", len(out.Speeches))
	}
	if out.Pages != 3 {
		t.Errorf("pages: got %d, want 3", out.Pages)
	}
}

func TestMemberSpeechesPagination_PageBeyondLast_ReturnsEmpty(t *testing.T) {
	seedSpeechFixture(t, "m-001", 25)

	out := executeSpeechFixtureRequest(t, "m-001", map[string]string{
		"page":     "10",
		"per_page": "10",
	})

	if len(out.Speeches) != 0 {
		t.Errorf("len(speeches): got %d, want 0", len(out.Speeches))
	}
	if out.Total != 25 {
		t.Errorf("total: got %d, want 25", out.Total)
	}
}

func TestMemberSpeechesUnknownMember_ReturnsEmptyShape(t *testing.T) {
	seedSpeechFixture(t, "m-001", 1)

	out := executeSpeechFixtureRequest(t, "unknown-member-xyz", nil)

	if out.Total != 0 {
		t.Errorf("total: got %d, want 0", out.Total)
	}
	if out.Pages != 0 {
		t.Errorf("pages: got %d, want 0", out.Pages)
	}
	if len(out.Speeches) != 0 {
		t.Errorf("len(speeches): got %d, want 0", len(out.Speeches))
	}
	if out.Stats.TotalSpeeches != 0 || out.Stats.AvgWordCount != 0 || out.Stats.TopTopic != "" {
		t.Errorf("stats should be zero-value for unknown member, got %+v", out.Stats)
	}
}

func TestMemberSpeechesPerPageBound(t *testing.T) {
	seedSpeechFixture(t, "m-002", membercontent.MaxPerPage+50)

	out := executeSpeechFixtureRequest(t, "m-002", map[string]string{
		"per_page": "999",
	})

	if len(out.Speeches) != membercontent.MaxPerPage {
		t.Errorf("len(speeches): got %d, want %d", len(out.Speeches), membercontent.MaxPerPage)
	}
	if out.PerPage != membercontent.MaxPerPage {
		t.Errorf("per_page: got %d, want %d", out.PerPage, membercontent.MaxPerPage)
	}
}
