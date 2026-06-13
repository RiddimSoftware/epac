package apns

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"epac/push-notification-dispatcher/internal/domain"
)

func TestDeliverPostsAPNSAlertPayload(t *testing.T) {
	var contentType string
	var posted payloadSnapshot
	var decodeErr error
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		contentType = r.Header.Get("Content-Type")
		body, err := io.ReadAll(r.Body)
		if err != nil {
			decodeErr = err
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		if err := json.Unmarshal(body, &posted); err != nil {
			decodeErr = err
			w.WriteHeader(http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	client := NewClient(server.URL)
	notification := domain.LiveVoteNotification{
		Title:      "Vote result posted",
		Body:       "Division 42 result: carried.",
		DivisionID: 42,
		Parliament: 45,
		Session:    1,
		Result:     "carried",
		Status:     "concluded",
	}

	if err := client.Deliver(context.Background(), domain.NewDeviceSubscription("test-token", "", nil, nil), notification); err != nil {
		t.Fatalf("Deliver: %v", err)
	}

	if decodeErr != nil {
		t.Fatalf("decode posted body: %v", decodeErr)
	}
	if contentType != "application/json" {
		t.Fatalf("Content-Type = %q, want application/json", contentType)
	}
	if posted.Aps.Alert.Title != "Vote result posted" {
		t.Fatalf("aps.alert.title = %q, want Vote result posted", posted.Aps.Alert.Title)
	}
	if posted.Aps.Alert.Body != "Division 42 result: carried." {
		t.Fatalf("aps.alert.body = %q, want Division 42 result: carried.", posted.Aps.Alert.Body)
	}
	if posted.DivisionID != 42 || posted.Parliament != 45 || posted.Session != 1 {
		t.Fatalf("source identifiers = division %d parliament %d session %d, want 42/45/1", posted.DivisionID, posted.Parliament, posted.Session)
	}
	if posted.Result != "carried" || posted.Status != "concluded" {
		t.Fatalf("result/status = %q/%q, want carried/concluded", posted.Result, posted.Status)
	}
}

type payloadSnapshot struct {
	Aps struct {
		Alert struct {
			Title string `json:"title"`
			Body  string `json:"body"`
		} `json:"alert"`
	} `json:"aps"`
	DivisionID int    `json:"division_id"`
	Parliament int    `json:"parliament"`
	Session    int    `json:"session"`
	Result     string `json:"result"`
	Status     string `json:"status"`
}
