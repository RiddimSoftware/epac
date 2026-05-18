//go:build integration

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"epac/_testdb"
	"epac/on-this-day/internal/adapter/postgres"
	"epac/on-this-day/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
)

// resetOnThisDaySpeeches deletes all rows from speeches to isolate each test.
func resetOnThisDaySpeeches(t *testing.T, conn *pgx.Conn) {
	t.Helper()
	if _, err := conn.Exec(context.Background(), "DELETE FROM speeches"); err != nil {
		t.Fatalf("reset speeches: %v", err)
	}
}

// seedSpeechOnDate inserts a speech row with the given sitting_date.
func seedSpeechOnDate(t *testing.T, conn *pgx.Conn, id string, sittingDate time.Time) {
	t.Helper()
	_testdb.SeedSpeech(t, conn, id,
		"This is a speech about parliamentary procedures and governance in the House of Commons.",
		"Test Speaker", "", "Test Subject", &sittingDate)
}

// mustParseDate parses "YYYY-MM-DD" or fatals.
func mustParseDate(t *testing.T, s string) time.Time {
	t.Helper()
	d, err := time.Parse("2006-01-02", s)
	if err != nil {
		t.Fatalf("parse date %q: %v", s, err)
	}
	return d
}

// callOnThisDaySQL wires the postgres adapter to the use case directly against
// the test DB connection, bypassing the package-level dbConn and DATABASE_URL.
func callOnThisDaySQL(t *testing.T, conn *pgx.Conn, dateStr string, limit int) ([]usecase.OnThisDayItem, error) {
	t.Helper()
	date, err := parseDate(dateStr)
	if err != nil {
		return nil, fmt.Errorf("parse date: %w", err)
	}
	repo := postgres.NewHansardRepository(conn)
	uc := usecase.New(repo)
	return uc.Execute(context.Background(), date, limit)
}

// callHandlerHTTP sends an APIGateway request through HandleRequest and returns the response.
// Use this only for tests that verify HTTP-layer behavior (status codes, JSON shape)
// where the date check happens before any DB access (e.g., 400 cases).
func callHandlerHTTP(t *testing.T, params map[string]string) events.APIGatewayProxyResponse {
	t.Helper()
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: params,
	})
	if err != nil {
		t.Fatalf("HandleRequest returned unexpected error: %v", err)
	}
	return resp
}

// TestOnThisDayHappyPath_ReturnsMatchingSittings seeds speeches on March 15 across
// two prior years and unrelated dates, then asserts only March-15 records appear
// when querying date=2026-03-15.
func TestOnThisDayHappyPath_ReturnsMatchingSittings(t *testing.T) {
	conn := _testdb.Connect(t)
	resetOnThisDaySpeeches(t, conn)

	// 3 speeches on 2010-03-15
	for i := 0; i < 3; i++ {
		seedSpeechOnDate(t, conn, fmt.Sprintf("march-2010-%d", i), mustParseDate(t, "2010-03-15"))
	}
	// 2 speeches on 2015-03-15
	for i := 0; i < 2; i++ {
		seedSpeechOnDate(t, conn, fmt.Sprintf("march-2015-%d", i), mustParseDate(t, "2015-03-15"))
	}
	// 5 speeches on other dates — none should appear in results
	otherDates := []string{"2010-04-15", "2015-02-15", "2018-03-16", "2020-01-01", "2012-07-04"}
	for i, d := range otherDates {
		seedSpeechOnDate(t, conn, fmt.Sprintf("other-%d", i), mustParseDate(t, d))
	}

	items, err := callOnThisDaySQL(t, conn, "2026-03-15", 10)
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}

	if len(items) != 5 {
		t.Fatalf("got %d items, want 5 (3 from 2010-03-15 + 2 from 2015-03-15)", len(items))
	}
	for _, item := range items {
		// Date field is formatted as "YYYY-MM-DD"; verify MM-DD is 03-15.
		if len(item.Date) < 10 || item.Date[5:10] != "03-15" {
			t.Errorf("item %q has date %q — want March 15", item.ID, item.Date)
		}
	}
}

// TestOnThisDayLeapYearFeb29 covers two leap-year sub-cases:
//   - Speeches seeded on 2020-02-29 must be returned when querying 2024-02-29.
//   - 2023-02-29 is not a valid calendar date; Go's time.Parse rejects it,
//     so the handler returns HTTP 400 before touching the DB.
func TestOnThisDayLeapYearFeb29(t *testing.T) {
	conn := _testdb.Connect(t)
	resetOnThisDaySpeeches(t, conn)

	feb29 := mustParseDate(t, "2020-02-29")
	seedSpeechOnDate(t, conn, "leap-2020-0", feb29)
	seedSpeechOnDate(t, conn, "leap-2020-1", feb29)

	// Part 1: valid leap date 2024-02-29 — 2020 speeches must appear.
	items, err := callOnThisDaySQL(t, conn, "2024-02-29", 10)
	if err != nil {
		t.Fatalf("unexpected error for 2024-02-29: %v", err)
	}
	if len(items) != 2 {
		t.Fatalf("got %d items for 2024-02-29, want 2", len(items))
	}
	for _, item := range items {
		if item.Date != "2020-02-29" {
			t.Errorf("item %q has date %q, want 2020-02-29", item.ID, item.Date)
		}
	}

	// Part 2: 2023-02-29 is rejected as HTTP 400.
	// time.Parse("2006-01-02", "2023-02-29") returns "day out of range" in Go,
	// so parseDate fails and HandleRequest returns 400 before any DB access.
	resp := callHandlerHTTP(t, map[string]string{"date": "2023-02-29"})
	if resp.StatusCode != 400 {
		t.Fatalf("date=2023-02-29: got status %d, want 400", resp.StatusCode)
	}
	var errBody map[string]string
	if err := json.Unmarshal([]byte(resp.Body), &errBody); err != nil {
		t.Fatalf("parse error body: %v (body=%s)", err, resp.Body)
	}
	if errBody["error"] == "" {
		t.Errorf("response missing non-empty 'error' field: %s", resp.Body)
	}
}

// TestOnThisDayNoMatchingDate_ReturnsEmptyShape verifies that when no speeches exist
// for the requested calendar date, the handler returns HTTP 200 with an items field
// that is an empty (non-null) JSON array and a date field that echoes the input.
func TestOnThisDayNoMatchingDate_ReturnsEmptyShape(t *testing.T) {
	conn := _testdb.Connect(t)
	resetOnThisDaySpeeches(t, conn)

	// Seed a speech on a different calendar date to confirm the filter is active.
	seedSpeechOnDate(t, conn, "noise-001", mustParseDate(t, "2020-06-15"))

	// No speeches on January 1 of any prior year — expect empty results.
	items, err := callOnThisDaySQL(t, conn, "1999-01-01", 10)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if items == nil {
		t.Fatal("items must be non-nil even when empty")
	}
	if len(items) != 0 {
		t.Fatalf("got %d items, want 0", len(items))
	}

	// Verify the HTTP response shape via the full handler path.
	// DATABASE_URL is set in the integration-test environment; the handler connects
	// to the same DB that has no Jan-1 speeches after the DELETE above.
	resp := callHandlerHTTP(t, map[string]string{"date": "1999-01-01"})
	if resp.StatusCode != 200 {
		t.Fatalf("got status %d, want 200", resp.StatusCode)
	}
	var body usecase.OnThisDayResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("parse response: %v (body=%s)", err, resp.Body)
	}
	if body.Date != "1999-01-01" {
		t.Errorf("date field = %q, want 1999-01-01", body.Date)
	}
	if body.Items == nil {
		t.Error("items must be a non-null JSON array, not null")
	}
	if len(body.Items) != 0 {
		t.Errorf("got %d items in HTTP response, want 0", len(body.Items))
	}
}

// TestOnThisDayLimitBound verifies that limit=1 returns exactly 1 item and that
// limit=999 is clamped to the handler's declared MaxLimit (20).
func TestOnThisDayLimitBound(t *testing.T) {
	conn := _testdb.Connect(t)
	resetOnThisDaySpeeches(t, conn)

	sittingDate := mustParseDate(t, "2010-06-01")
	for i := 0; i < 50; i++ {
		seedSpeechOnDate(t, conn, fmt.Sprintf("limit-test-%02d", i), sittingDate)
	}

	// limit=1: exactly 1 item returned.
	items, err := callOnThisDaySQL(t, conn, "2026-06-01", 1)
	if err != nil {
		t.Fatalf("limit=1 query failed: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("limit=1: got %d items, want 1", len(items))
	}

	// parseLimit("999") must clamp to MaxLimit before any SQL executes.
	clamped := parseLimit("999")
	if clamped != usecase.MaxLimit {
		t.Fatalf("parseLimit(999) = %d, want %d (MaxLimit)", clamped, usecase.MaxLimit)
	}

	// Confirm the clamped limit is enforced end-to-end: 50 seeded rows, limit=MaxLimit → MaxLimit items.
	items, err = callOnThisDaySQL(t, conn, "2026-06-01", usecase.MaxLimit)
	if err != nil {
		t.Fatalf("limit=MaxLimit query failed: %v", err)
	}
	if len(items) != usecase.MaxLimit {
		t.Fatalf("limit=MaxLimit: got %d items with 50 seeded rows, want %d", len(items), usecase.MaxLimit)
	}
}

// TestOnThisDayInvalidDateFormat_Returns400 asserts that malformed date strings
// cause the handler to return HTTP 400 with a non-empty "error" field.
// These cases fail parseDate before getDBConn is called, so no DB access occurs.
func TestOnThisDayInvalidDateFormat_Returns400(t *testing.T) {
	cases := []string{
		"not-a-date", // length 10, time.Parse fails
		"2026/06/01", // length 10, wrong separator
		"20260601",   // length 8, fails length check
		"2026-6-1",   // length 8, fails length check
	}
	for _, dateStr := range cases {
		t.Run(dateStr, func(t *testing.T) {
			resp := callHandlerHTTP(t, map[string]string{"date": dateStr})
			if resp.StatusCode != 400 {
				t.Fatalf("date=%q: got status %d, want 400", dateStr, resp.StatusCode)
			}
			var body map[string]string
			if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
				t.Fatalf("parse response: %v (body=%s)", err, resp.Body)
			}
			if body["error"] == "" {
				t.Errorf("date=%q: response missing non-empty 'error' field: %s", dateStr, resp.Body)
			}
		})
	}
}

// TestOnThisDayTimezoneBoundary verifies that sitting_date comparisons are
// calendar-date-only. The sitting_date column is DATE (not TIMESTAMP), so a speech
// seeded as 2020-03-15 must appear for date=2026-03-15 regardless of the UTC offset
// of the process or Postgres server.
func TestOnThisDayTimezoneBoundary(t *testing.T) {
	conn := _testdb.Connect(t)
	resetOnThisDaySpeeches(t, conn)

	// pgx stores time.Time as a DATE value using the calendar date, not a TIMESTAMP.
	// We seed using UTC midnight to confirm the DATE column stores the calendar date.
	sittingDate := mustParseDate(t, "2020-03-15")
	seedSpeechOnDate(t, conn, "tz-boundary-001", sittingDate)

	items, err := callOnThisDaySQL(t, conn, "2026-03-15", 10)
	if err != nil {
		t.Fatalf("query failed: %v", err)
	}
	if len(items) != 1 {
		t.Fatalf("got %d items, want 1", len(items))
	}
	if items[0].Date != "2020-03-15" {
		t.Errorf("item Date = %q, want 2020-03-15", items[0].Date)
	}
	if items[0].ID != "speech:tz-boundary-001" {
		t.Errorf("item ID = %q, want speech:tz-boundary-001", items[0].ID)
	}
}
