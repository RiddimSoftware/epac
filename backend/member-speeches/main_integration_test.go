//go:build integration

package main

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"epac/_testdb"
	"github.com/jackc/pgx/v5"
)

// seedN inserts count speeches for memberID, each on a distinct date starting at baseDate (oldest).
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

func TestMemberSpeechesHappyPath_ReturnsPagedResults(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		// 25 speeches dated 2024-01-01 (oldest) … 2024-01-25 (newest)
		seedN(t, conn, "m-001", "sp", "Budget", 25, base)

		out, err := queryMemberSpeeches(context.Background(), conn, "m-001", 1, 10, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		if out.Total != 25 {
			t.Errorf("total: got %d, want 25", out.Total)
		}
		if out.Pages != 3 {
			t.Errorf("pages: got %d, want 3", out.Pages)
		}
		if len(out.Speeches) != 10 {
			t.Fatalf("len(speeches): got %d, want 10", len(out.Speeches))
		}
		// Page 1 must be the 10 most-recent: sp-025 … sp-016 (sitting_date DESC)
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

		out, err := queryMemberSpeeches(context.Background(), conn, "m-001", 3, 10, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

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

		out, err := queryMemberSpeeches(context.Background(), conn, "m-001", 10, 10, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

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
		out, err := queryMemberSpeeches(context.Background(), conn, "unknown-member-xyz", 1, defaultPerPage, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		if out.Total != 0 {
			t.Errorf("total: got %d, want 0", out.Total)
		}
		if out.Pages != 0 {
			t.Errorf("pages: got %d, want 0", out.Pages)
		}
		if len(out.Speeches) != 0 {
			t.Errorf("len(speeches): got %d, want 0", len(out.Speeches))
		}
		// stats must be a non-null object — staging-smoke contract:
		// MemberStats is a value type so it is always serialised as a JSON object, never null.
		// Verify each field is the zero value for an unknown member.
		if out.Stats.TotalSpeeches != 0 || out.Stats.AvgWordCount != 0 || out.Stats.TopTopic != "" {
			t.Errorf("stats should be zero-value for unknown member, got %+v", out.Stats)
		}
		// Extra belt-and-suspenders: the JSON representation must not contain "stats":null.
		if strings.Contains(fmt.Sprintf("%+v", out), "null") {
			// This can only trip if the type is changed to a pointer in future.
			t.Error("stats must be a non-null JSON object, got null")
		}
	})
}

func TestMemberSpeechesPerPageBound(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		base := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
		// Seed more speeches than maxPerPage to prove the cap is enforced.
		seedN(t, conn, "m-002", "bound", "Bills", maxPerPage+50, base)

		// per_page=999 exceeds maxPerPage; the handler clamps it to maxPerPage (100).
		out, err := queryMemberSpeeches(context.Background(), conn, "m-002", 1, maxPerPage, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		// Exactly maxPerPage speeches returned — the declared cap is enforced.
		if len(out.Speeches) != maxPerPage {
			t.Errorf("len(speeches): got %d, want %d (maxPerPage)", len(out.Speeches), maxPerPage)
		}
		if out.PerPage != maxPerPage {
			t.Errorf("per_page: got %d, want %d", out.PerPage, maxPerPage)
		}
	})
}

func TestMemberSpeechesStats_AggregatesCorrectly(t *testing.T) {
	_testdb.WithTx(t, func(conn *pgx.Conn) {
		d1 := time.Date(2024, 3, 1, 0, 0, 0, 0, time.UTC)
		d2 := time.Date(2024, 3, 2, 0, 0, 0, 0, time.UTC)
		d3 := time.Date(2024, 3, 3, 0, 0, 0, 0, time.UTC)

		// 4 speeches on topic "Bills" across 2 dates, 2 speeches on "Budget" on 1 date
		_testdb.SeedSpeech(t, conn, "stats-1", "content", "Speaker", "m-stats", "Bills", &d1)
		_testdb.SeedSpeech(t, conn, "stats-2", "content", "Speaker", "m-stats", "Bills", &d1)
		_testdb.SeedSpeech(t, conn, "stats-3", "content", "Speaker", "m-stats", "Bills", &d2)
		_testdb.SeedSpeech(t, conn, "stats-4", "content", "Speaker", "m-stats", "Bills", &d2)
		_testdb.SeedSpeech(t, conn, "stats-5", "content", "Speaker", "m-stats", "Budget", &d3)
		_testdb.SeedSpeech(t, conn, "stats-6", "content", "Speaker", "m-stats", "Budget", &d3)

		out, err := queryMemberSpeeches(context.Background(), conn, "m-stats", 1, 10, "")
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}

		if out.Stats.TotalSpeeches != 6 {
			t.Errorf("stats.total_speeches: got %d, want 6", out.Stats.TotalSpeeches)
		}
		if out.Stats.TopTopic != "Bills" {
			t.Errorf("stats.top_topic: got %q, want %q", out.Stats.TopTopic, "Bills")
		}
	})
}
