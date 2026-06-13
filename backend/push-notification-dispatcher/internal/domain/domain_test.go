package domain

import (
	"errors"
	"testing"
)

func TestParsePushNotificationPayloadRequiresLiveVoteFields(t *testing.T) {
	tests := []struct {
		name string
		raw  string
	}{
		{name: "empty object", raw: `{}`},
		{name: "missing division", raw: `{"parliament":45,"session":1,"result":"carried","status":"concluded"}`},
		{name: "missing parliament", raw: `{"division_id":42,"session":1,"result":"carried","status":"concluded"}`},
		{name: "missing session", raw: `{"division_id":42,"parliament":45,"result":"carried","status":"concluded"}`},
		{name: "missing result", raw: `{"division_id":42,"parliament":45,"session":1,"status":"concluded"}`},
		{name: "missing status", raw: `{"division_id":42,"parliament":45,"session":1,"result":"carried"}`},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if _, err := ParsePushNotificationPayload([]byte(tt.raw)); !errors.Is(err, ErrInvalidPushNotificationPayload) {
				t.Fatalf("ParsePushNotificationPayload error = %v, want %v", err, ErrInvalidPushNotificationPayload)
			}
		})
	}
}

func TestParsePushNotificationPayloadRejectsMalformedInput(t *testing.T) {
	tests := []string{
		``,
		`[]`,
		`{"division_id":`,
	}

	for _, raw := range tests {
		if _, err := ParsePushNotificationPayload([]byte(raw)); !errors.Is(err, ErrInvalidPushNotificationPayload) {
			t.Fatalf("ParsePushNotificationPayload(%q) error = %v, want %v", raw, err, ErrInvalidPushNotificationPayload)
		}
	}
}

func TestNewLiveVoteNotificationBuildsConcludedVoteCopy(t *testing.T) {
	payload := mustParsePayload(t, `{
		"division_id": 42,
		"parliament": 45,
		"session": 1,
		"result": "carried",
		"status": "concluded"
	}`)

	notification, err := NewLiveVoteNotification(payload)
	if err != nil {
		t.Fatalf("NewLiveVoteNotification: %v", err)
	}

	if notification.Title != "Vote result posted" {
		t.Fatalf("Title = %q, want %q", notification.Title, "Vote result posted")
	}
	if notification.Body != "Division 42 result: carried." {
		t.Fatalf("Body = %q, want %q", notification.Body, "Division 42 result: carried.")
	}
	if notification.DivisionID != 42 || notification.Parliament != 45 || notification.Session != 1 {
		t.Fatalf("source identifiers = division %d parliament %d session %d, want 42/45/1", notification.DivisionID, notification.Parliament, notification.Session)
	}
	if notification.Result != "carried" || notification.Status != "concluded" {
		t.Fatalf("source result/status = %q/%q, want carried/concluded", notification.Result, notification.Status)
	}
}

func mustParsePayload(t *testing.T, raw string) PushNotificationPayload {
	t.Helper()
	payload, err := ParsePushNotificationPayload([]byte(raw))
	if err != nil {
		t.Fatalf("ParsePushNotificationPayload: %v", err)
	}
	return payload
}
