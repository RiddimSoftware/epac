//go:build integration

package main

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"

	testdb "epac/_testdb"
	"epac/device-register/application"
	"epac/device-register/repository"
)

// deviceSubscriptionRow holds the columns read back from device_subscriptions for assertions.
type deviceSubscriptionRow struct {
	Token        string
	TopicIds     []string
	BillIds      []string
	MyMPMemberId *string
}

func buildHandler(conn *pgx.Conn) *Handler {
	repo := repository.NewPostgresDeviceRepository(conn)
	uc := application.NewRegisterUseCase(repo)
	return &Handler{useCase: uc}
}

func makeRequest(body string) events.APIGatewayProxyRequest {
	return events.APIGatewayProxyRequest{
		HTTPMethod: http.MethodPost,
		Path:       "/api/v1/device/register",
		Body:       body,
	}
}

func readSubscription(t *testing.T, conn *pgx.Conn, token string) (deviceSubscriptionRow, bool) {
	t.Helper()
	var row deviceSubscriptionRow
	err := conn.QueryRow(context.Background(), `
		SELECT token, topic_ids, bill_ids, my_mp_member_id
		FROM device_subscriptions WHERE token = $1
	`, token).Scan(&row.Token, &row.TopicIds, &row.BillIds, &row.MyMPMemberId)
	if err == pgx.ErrNoRows {
		return deviceSubscriptionRow{}, false
	}
	if err != nil {
		t.Fatalf("read device_subscriptions: %v", err)
	}
	return row, true
}

func countSubscriptions(t *testing.T, conn *pgx.Conn, token string) int {
	t.Helper()
	var n int
	if err := conn.QueryRow(context.Background(),
		`SELECT COUNT(*) FROM device_subscriptions WHERE token = $1`, token,
	).Scan(&n); err != nil {
		t.Fatalf("count device_subscriptions: %v", err)
	}
	return n
}

// TestDeviceRegisterHappyPath_InsertsRow verifies that a valid registration request
// inserts exactly one row with all fields (token, my_mp_member_id, topic_ids, bill_ids) populated.
func TestDeviceRegisterHappyPath_InsertsRow(t *testing.T) {
	testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()
		handler := buildHandler(conn)

		body, _ := json.Marshal(map[string]interface{}{
			"token":           "happy-path-token",
			"my_mp_member_id": "mp-123",
			"topic_ids":       []string{"t1", "t2"},
			"bill_ids":        []string{"b1"},
		})

		resp, err := handler.HandleRequest(ctx, makeRequest(string(body)))
		if err != nil {
			t.Fatalf("handler returned error: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", resp.StatusCode, resp.Body)
		}

		row, ok := readSubscription(t, conn, "happy-path-token")
		if !ok {
			t.Fatal("expected a row in device_subscriptions, got none")
		}
		if row.Token != "happy-path-token" {
			t.Errorf("token: want %q, got %q", "happy-path-token", row.Token)
		}
		if row.MyMPMemberId == nil || *row.MyMPMemberId != "mp-123" {
			t.Errorf("my_mp_member_id: want \"mp-123\", got %v", row.MyMPMemberId)
		}
		if len(row.TopicIds) != 2 || row.TopicIds[0] != "t1" || row.TopicIds[1] != "t2" {
			t.Errorf("topic_ids: want [t1 t2], got %v", row.TopicIds)
		}
		if len(row.BillIds) != 1 || row.BillIds[0] != "b1" {
			t.Errorf("bill_ids: want [b1], got %v", row.BillIds)
		}
	})
}

// TestDeviceRegisterUpsert_SameTokenUpdates verifies that a second POST with the same token
// updates the existing row (ON CONFLICT DO UPDATE) rather than inserting a duplicate.
func TestDeviceRegisterUpsert_SameTokenUpdates(t *testing.T) {
	testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()
		testdb.SeedDeviceSubscription(t, conn, "upsert-token", "mp-old", []string{"old-topic"}, nil)

		handler := buildHandler(conn)
		body, _ := json.Marshal(map[string]interface{}{
			"token":     "upsert-token",
			"topic_ids": []string{"new-topic"},
		})

		resp, err := handler.HandleRequest(ctx, makeRequest(string(body)))
		if err != nil {
			t.Fatalf("handler returned error: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", resp.StatusCode, resp.Body)
		}

		if n := countSubscriptions(t, conn, "upsert-token"); n != 1 {
			t.Fatalf("want exactly 1 row after upsert, got %d", n)
		}

		row, ok := readSubscription(t, conn, "upsert-token")
		if !ok {
			t.Fatal("expected row after upsert, got none")
		}
		if len(row.TopicIds) != 1 || row.TopicIds[0] != "new-topic" {
			t.Errorf("topic_ids: want [new-topic], got %v", row.TopicIds)
		}
	})
}

// TestDeviceRegisterMissingToken_Returns400 verifies that a body without a token
// field is rejected with HTTP 400 and an error message mentioning "token".
func TestDeviceRegisterMissingToken_Returns400(t *testing.T) {
	testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()
		handler := buildHandler(conn)

		resp, err := handler.HandleRequest(ctx, makeRequest(`{}`))
		if err != nil {
			t.Fatalf("handler returned error: %v", err)
		}
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("want 400, got %d: %s", resp.StatusCode, resp.Body)
		}

		var errBody map[string]string
		if err := json.Unmarshal([]byte(resp.Body), &errBody); err != nil {
			t.Fatalf("unmarshal error body: %v", err)
		}
		if msg := errBody["error"]; !strings.Contains(strings.ToLower(msg), "token") {
			t.Errorf("error body should mention \"token\", got %q", msg)
		}
	})
}

// TestDeviceRegisterMalformedJSON_Returns400 verifies that a non-JSON body is
// rejected with HTTP 400 before any database write occurs.
func TestDeviceRegisterMalformedJSON_Returns400(t *testing.T) {
	testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()
		handler := buildHandler(conn)

		resp, err := handler.HandleRequest(ctx, makeRequest(`not-valid-json`))
		if err != nil {
			t.Fatalf("handler returned error: %v", err)
		}
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("want 400, got %d: %s", resp.StatusCode, resp.Body)
		}

		// JSON parsing fails before any DB call; verify no row was written
		// by asserting the table has no rows visible within this transaction.
		var n int
		if err := conn.QueryRow(context.Background(),
			`SELECT COUNT(*) FROM device_subscriptions`,
		).Scan(&n); err != nil {
			t.Fatalf("count device_subscriptions: %v", err)
		}
		if n != 0 {
			t.Errorf("want 0 rows written after malformed JSON, got %d", n)
		}
	})
}

// TestDeviceRegisterEmptyFollows_StoresEmptyArrays verifies that omitting topic_ids
// and bill_ids stores non-NULL empty arrays ({} in Postgres TEXT[]), not NULLs.
func TestDeviceRegisterEmptyFollows_StoresEmptyArrays(t *testing.T) {
	testdb.WithTx(t, func(conn *pgx.Conn) {
		ctx := context.Background()
		handler := buildHandler(conn)

		body, _ := json.Marshal(map[string]interface{}{
			"token": "empty-follows-token",
		})

		resp, err := handler.HandleRequest(ctx, makeRequest(string(body)))
		if err != nil {
			t.Fatalf("handler returned error: %v", err)
		}
		if resp.StatusCode != http.StatusOK {
			t.Fatalf("want 200, got %d: %s", resp.StatusCode, resp.Body)
		}

		row, ok := readSubscription(t, conn, "empty-follows-token")
		if !ok {
			t.Fatal("expected row, got none")
		}
		if row.TopicIds == nil {
			t.Error("topic_ids: want empty array, got nil")
		}
		if len(row.TopicIds) != 0 {
			t.Errorf("topic_ids: want [], got %v", row.TopicIds)
		}
		if row.BillIds == nil {
			t.Error("bill_ids: want empty array, got nil")
		}
		if len(row.BillIds) != 0 {
			t.Errorf("bill_ids: want [], got %v", row.BillIds)
		}
	})
}
