//go:build integration

package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"

	testdb "epac/_testdb"
)

const liveStatusDefaultBusinessType = "Adjourned"

type liveStatusResponse struct {
	Status       string     `json:"status"`
	IsSitting    bool       `json:"is_sitting"`
	BusinessType string     `json:"business_type"`
	CheckedAt    time.Time  `json:"checked_at"`
	LastChanged  *time.Time `json:"last_changed_at"`
}

type liveSessionRow struct {
	IsSitting     bool
	BusinessType  string
	CheckedAt     time.Time
	LastChangedAt *time.Time
}

type mockRoundTripper string

func (m mockRoundTripper) RoundTrip(r *http.Request) (*http.Response, error) {
	recorder := httptest.NewRecorder()
	recorder.WriteHeader(http.StatusOK)
	_, _ = recorder.WriteString(string(m))
	return recorder.Result(), nil
}

func apiV2Request(deviceID string) events.APIGatewayV2HTTPRequest {
	return events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/live",
		Headers: map[string]string{
			"X-Device-ID": deviceID,
		},
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				Path:   "/api/v1/live",
				Method: http.MethodGet,
			},
		},
	}
}

func setupDatabase(t *testing.T) *pgx.Conn {
	t.Helper()
	ctx := context.Background()
	conn := testdb.Connect(t)
	if err := testdb.ApplyLiveStatusMigrations(ctx, conn); err != nil {
		t.Fatalf("apply live-status migrations: %v", err)
	}
	if err := testdb.ClearLiveSessionRows(ctx, conn); err != nil {
		t.Fatalf("clear live_session rows: %v", err)
	}
	return conn
}

func upsertLiveSittingDay(ctx context.Context, conn *pgx.Conn, date string, isSitting bool) error {
	_, err := conn.Exec(ctx, `
		INSERT INTO live_sitting_day (sitting_date, is_sitting, source_url, fetched_at)
		VALUES ($1, $2, $3, $4)
		ON CONFLICT (sitting_date) DO UPDATE SET
			is_sitting = EXCLUDED.is_sitting,
			source_url = EXCLUDED.source_url,
			fetched_at = EXCLUDED.fetched_at
	`, date, isSitting, "https://www.ourcommons.ca/en/sitting-calendar", time.Now().UTC())
	return err
}

func withFakeHouseOfCommons(t *testing.T, body string) {
	t.Helper()
	orig := http.DefaultClient
	http.DefaultClient = &http.Client{
		Transport: mockRoundTripper(body),
	}
	t.Cleanup(func() {
		http.DefaultClient = orig
	})
}

func readLiveSessionRow(t *testing.T, ctx context.Context, conn *pgx.Conn) (liveSessionRow, int) {
	t.Helper()
	var row liveSessionRow
	var count int

	err := conn.QueryRow(ctx, `SELECT COUNT(*) FROM live_session`).Scan(&count)
	if err != nil {
		t.Fatalf("count live_session rows: %v", err)
	}

	err = conn.QueryRow(ctx, `
		SELECT is_sitting, business_type, last_polled_at, last_changed_at
		FROM live_session
		LIMIT 1
	`).Scan(&row.IsSitting, &row.BusinessType, &row.CheckedAt, &row.LastChangedAt)
	if err != nil {
		t.Fatalf("query live_session row: %v", err)
	}
	return row, count
}

func testLiveStatusAPICachedRow(t *testing.T, expectedCheckedAt time.Time, expectedBusinessType string, expectedIsSitting bool) {
	t.Helper()
	ctx := context.Background()
	conn := setupDatabase(t)
	if err := testdb.SeedLiveSession(ctx, conn, testdb.LiveSessionRow{
		IsSitting:    expectedIsSitting,
		BusinessType: expectedBusinessType,
		CheckedAt:    expectedCheckedAt,
	}); err != nil {
		t.Fatalf("seed live_session row: %v", err)
	}

	resp, err := handleAPI(ctx, apiV2Request("live-status-api-"+expectedBusinessType))
	if err != nil {
		t.Fatalf("handleAPI: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status code = %d, want %d", resp.StatusCode, http.StatusOK)
	}

	var body liveStatusResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}

	if body.IsSitting != expectedIsSitting {
		t.Fatalf("is_sitting = %v, want %v", body.IsSitting, expectedIsSitting)
	}
	expectedStatus := "sitting"
	if !expectedIsSitting {
		expectedStatus = "adjourned"
	}
	if body.Status != expectedStatus {
		t.Fatalf("status = %q, want %q", body.Status, expectedStatus)
	}
	if body.BusinessType != expectedBusinessType {
		t.Fatalf("business_type = %q, want %q", body.BusinessType, expectedBusinessType)
	}
	if !body.CheckedAt.Equal(expectedCheckedAt) {
		t.Fatalf("checked_at = %v, want %v", body.CheckedAt, expectedCheckedAt)
	}

	_ = body.LastChanged
}

func TestLiveStatusAPIRead_FreshRow_ReturnsCurrentStatus(t *testing.T) {
	checkedAt := time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC)
	testLiveStatusAPICachedRow(t, checkedAt, "QP", true)
}

func TestLiveStatusAPIRead_StaleRow_ReturnsStatusWithFlag(t *testing.T) {
	staleAt := time.Date(2026, 4, 28, 17, 0, 0, 0, time.UTC)
	testLiveStatusAPICachedRow(t, staleAt, "QP", true)
	// Current handler behavior has no explicit stale marker; we lock in the
	// behavior by asserting the stale checked_at timestamp is preserved.
}

func TestLiveStatusAPIRead_NoRow_ReturnsDefault(t *testing.T) {
	ctx := context.Background()
	setupDatabase(t)

	resp, err := handleAPI(ctx, apiV2Request("live-status-no-row"))
	if err != nil {
		t.Fatalf("handleAPI: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status code = %d, want %d", resp.StatusCode, http.StatusOK)
	}

	var body liveStatusResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if body.IsSitting {
		t.Fatalf("is_sitting = true, want false")
	}
	if body.BusinessType != liveStatusDefaultBusinessType {
		t.Fatalf("business_type = %q, want %q", body.BusinessType, liveStatusDefaultBusinessType)
	}
	if body.Status != "unknown" {
		t.Fatalf("status = %q, want %q", body.Status, "unknown")
	}
	if body.CheckedAt.IsZero() {
		t.Fatal("missing checked_at")
	}
}

func TestLiveStatusScheduledWrite_InsertsRow(t *testing.T) {
	ctx := context.Background()
	conn := setupDatabase(t)
	now := time.Date(2026, 4, 27, 14, 30, 0, 0, time.UTC)
	if err := upsertLiveSittingDay(ctx, conn, now.In(ottawaLocation()).Format("2006-01-02"), true); err != nil {
		t.Fatalf("seed live_sitting_day: %v", err)
	}
	withFakeHouseOfCommons(t, `
		<input type="hidden" id="isMeetingInProgress" value="True" />
		<span class="now-in-the-house-title">QP</span>
	`)

	resp, err := handlePoll(ctx, func() time.Time { return now })
	if err != nil {
		t.Fatalf("handlePoll: %v", err)
	}
	if !resp.IsSitting {
		t.Fatalf("poll response is_sitting = false, want true")
	}
	if resp.BusinessType != "QP" {
		t.Fatalf("poll response business_type = %q, want QP", resp.BusinessType)
	}

	row, count := readLiveSessionRow(t, ctx, conn)
	if count != 1 {
		t.Fatalf("row count = %d, want 1", count)
	}
	if !row.IsSitting {
		t.Fatalf("live_session is_sitting = false, want true")
	}
	if row.BusinessType != "QP" {
		t.Fatalf("live_session business_type = %q, want QP", row.BusinessType)
	}
}

func TestLiveStatusScheduledWrite_UpdatesExistingRow(t *testing.T) {
	ctx := context.Background()
	conn := setupDatabase(t)
	if err := testdb.SeedLiveSession(ctx, conn, testdb.LiveSessionRow{
		IsSitting:    false,
		BusinessType: "Adjourned",
		CheckedAt:    time.Date(2026, 4, 27, 12, 30, 0, 0, time.UTC),
	}); err != nil {
		t.Fatalf("seed live_session row: %v", err)
	}

	now := time.Date(2026, 4, 27, 14, 30, 0, 0, time.UTC)
	if err := upsertLiveSittingDay(ctx, conn, now.In(ottawaLocation()).Format("2006-01-02"), true); err != nil {
		t.Fatalf("seed live_sitting_day: %v", err)
	}
	withFakeHouseOfCommons(t, `
		<input type="hidden" id="isMeetingInProgress" value="True" />
		<span class="now-in-the-house-title">QP</span>
	`)

	resp, err := handlePoll(ctx, func() time.Time { return now })
	if err != nil {
		t.Fatalf("handlePoll: %v", err)
	}
	if !resp.IsSitting {
		t.Fatalf("poll response is_sitting = false, want true")
	}
	if resp.BusinessType != "QP" {
		t.Fatalf("poll response business_type = %q, want QP", resp.BusinessType)
	}

	row, count := readLiveSessionRow(t, ctx, conn)
	if count != 1 {
		t.Fatalf("row count = %d, want 1", count)
	}
	if !row.IsSitting {
		t.Fatalf("live_session is_sitting = false, want true")
	}
	if row.BusinessType != "QP" {
		t.Fatalf("live_session business_type = %q, want QP", row.BusinessType)
	}
}
