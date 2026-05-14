//go:build integration

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"epac/_testdb"
	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
)

// seedN inserts count speeches for memberID, each on a distinct date starting at baseDate.
// IDs are <prefix>-NNN (1-indexed, zero-padded to 3 digits).
func seedN(t *testing.T, conn *pgx.Conn, memberID, prefix, subjectTitle string, count int, baseDate time.Time) []string {
	t.Helper()
	ids := make([]string, count)
	for i := range count {
		id := fmt.Sprintf("%s-%03d", prefix, i+1)
		d := baseDate.AddDate(0, 0, i)
		_testdb.SeedSpeech(t, conn, id, "speech content", "Speaker", memberID, subjectTitle, &d)
		ids[i] = id
	}
	return ids
}

// invoke calls HandleRequest with the given member ID and query params.
// It sets and unsets the package-level dbConn so the handler uses the test connection.
func invoke(t *testing.T, conn *pgx.Conn, memberID string, qp map[string]string) events.APIGatewayProxyResponse {
	t.Helper()
	dbConn = conn
	t.Cleanup(func() { dbConn = nil })

	req := events.APIGatewayProxyRequest{
		PathParameters:        map[string]string{"id": memberID},
		QueryStringParameters: qp,
	}
	resp, err := HandleRequest(context.Background(), req)
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	return resp
}

func decode(t *testing.T, resp events.APIGatewayProxyResponse) MemberSpeechesResponse {
	t.Helper()
	var out MemberSpeechesResponse
	if err := json.Unmarshal([]byte(resp.Body), &out); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return out
}

func TestMemberSpeechesHappyPath_ReturnsPagedResults(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		// 25 speeches dated 2024-01-01 (oldest) … 2024-01-25 (newest)
		seedN(t, conn, "m-001", "sp", "Budget", 25, base)

		resp := invoke(t, conn, "m-001", map[string]string{"page": "1", "per_page": "10"})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("status: got %d, want 200", resp.StatusCode)
		}
		out := decode(t, resp)

		if out.Total != 25 {
			t.Errorf("total: got %d, want 25", out.Total)
		}
		if out.Pages != 3 {
			t.Errorf("pages: got %d, want 3", out.Pages)
		}
		if len(out.Speeches) != 10 {
			t.Fatalf("len(speeches): got %d, want 10", len(out.Speeches))
		}
		// Page 1 must be the 10 most-recent: sp-025 … sp-016
		for i, s := range out.Speeches {
			want := fmt.Sprintf("sp-%03d", 25-i)
			if s.InterventionId != want {
				t.Errorf("speeches[%d].id: got %q, want %q", i, s.InterventionId, want)
			}
		}
	})
}

func TestMemberSpeechesPagination_LastPagePartial(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		seedN(t, conn, "m-001", "sp", "Budget", 25, base)

		out := decode(t, invoke(t, conn, "m-001", map[string]string{"page": "3", "per_page": "10"}))

		if len(out.Speeches) != 5 {
			t.Errorf("len(speeches): got %d, want 5", len(out.Speeches))
		}
		if out.Pages != 3 {
			t.Errorf("pages: got %d, want 3", out.Pages)
		}
	})
}

func TestMemberSpeechesPagination_PageBeyondLast_ReturnsEmpty(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		seedN(t, conn, "m-001", "sp", "Budget", 25, base)

		resp := invoke(t, conn, "m-001", map[string]string{"page": "10", "per_page": "10"})
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("status: got %d, want 200", resp.StatusCode)
		}
		out := decode(t, resp)

		if len(out.Speeches) != 0 {
			t.Errorf("len(speeches): got %d, want 0", len(out.Speeches))
		}
		if out.Total != 25 {
			t.Errorf("total: got %d, want 25", out.Total)
		}
	})
}

func TestMemberSpeechesUnknownMember_ReturnsEmptyShape(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		resp := invoke(t, conn, "unknown-member-xyz", nil)
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("status: got %d, want 200", resp.StatusCode)
		}
		out := decode(t, resp)

		if out.Total != 0 {
			t.Errorf("total: got %d, want 0", out.Total)
		}
		if out.Pages != 0 {
			t.Errorf("pages: got %d, want 0", out.Pages)
		}
		if len(out.Speeches) != 0 {
			t.Errorf("len(speeches): got %d, want 0", len(out.Speeches))
		}
		// stats must be a non-null JSON object — staging-smoke contract
		if strings.Contains(resp.Body, `"stats":null`) {
			t.Error("stats must be a non-null JSON object, got null")
		}
		if out.Stats.TotalSpeeches != 0 || out.Stats.AvgWordCount != 0 || out.Stats.TopTopic != "" {
			t.Errorf("stats should be zero-value for unknown member, got %+v", out.Stats)
		}
	})
}

func TestMemberSpeechesPerPageBound(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		seedN(t, conn, "m-002", "bound", "Bills", 5, base)

		// per_page=999 exceeds the declared max of 100; the handler ignores it and
		// falls back to the default of 20.
		out := decode(t, invoke(t, conn, "m-002", map[string]string{"per_page": "999"}))

		const defaultPerPage = 20
		if out.PerPage != defaultPerPage {
			t.Errorf("per_page: got %d, want %d (default fallback when >100)", out.PerPage, defaultPerPage)
		}
	})
}

func TestMemberSpeechesStats_AggregatesCorrectly(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		d1 := time.Date(2024, 3, 1, 0, 0, 0, 0, time.UTC)
		d2 := time.Date(2024, 3, 2, 0, 0, 0, 0, time.UTC)
		d3 := time.Date(2024, 3, 3, 0, 0, 0, 0, time.UTC)

		// 4 speeches on topic "Bills" across 2 dates, 2 speeches on topic "Budget" on 1 date
		_testdb.SeedSpeech(t, conn, "stats-1", "content", "Speaker", "m-stats", "Bills", &d1)
		_testdb.SeedSpeech(t, conn, "stats-2", "content", "Speaker", "m-stats", "Bills", &d1)
		_testdb.SeedSpeech(t, conn, "stats-3", "content", "Speaker", "m-stats", "Bills", &d2)
		_testdb.SeedSpeech(t, conn, "stats-4", "content", "Speaker", "m-stats", "Bills", &d2)
		_testdb.SeedSpeech(t, conn, "stats-5", "content", "Speaker", "m-stats", "Budget", &d3)
		_testdb.SeedSpeech(t, conn, "stats-6", "content", "Speaker", "m-stats", "Budget", &d3)

		out := decode(t, invoke(t, conn, "m-stats", map[string]string{"page": "1", "per_page": "10"}))

		if out.Stats.TotalSpeeches != 6 {
			t.Errorf("stats.total_speeches: got %d, want 6", out.Stats.TotalSpeeches)
		}
		if out.Stats.TopTopic != "Bills" {
			t.Errorf("stats.top_topic: got %q, want %q", out.Stats.TopTopic, "Bills")
		}
	})
}
