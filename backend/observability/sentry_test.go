package observability

import (
	"testing"

	"github.com/getsentry/sentry-go"
)

func TestScrubStringRedactsCanadianPostalCodes(t *testing.T) {
	got := scrubString("lookup failed for K1A 0A6 and h0h0h0")
	want := "lookup failed for [postal-code] and [postal-code]"
	if got != want {
		t.Fatalf("scrubString() = %q, want %q", got, want)
	}
}

func TestScrubEventRemovesUserIdentifiersAndSensitiveRequestHeaders(t *testing.T) {
	event := &sentry.Event{
		Message: "request for M5V 2T6 failed",
		User: sentry.User{
			ID:        "user-123",
			Email:     "person@example.com",
			Username:  "person",
			IPAddress: "203.0.113.10",
			Data:      map[string]string{"postal_code": "K1A 0A6", "safe": "value"},
		},
		Extra: map[string]interface{}{
			"token": "apns-token",
			"note":  "postal H2X 1Y4",
		},
		Request: &sentry.Request{
			URL:         "https://example.test/search?postal=K1A0A6",
			QueryString: "postal=K1A0A6",
			Headers: map[string]string{
				"Authorization": "Bearer secret",
				"Cookie":        "session=secret",
				"Accept":        "application/json",
			},
		},
	}

	scrubbed := scrubEvent(event, nil)

	if scrubbed.User.ID != "" || scrubbed.User.Email != "" || scrubbed.User.Username != "" || scrubbed.User.IPAddress != "" {
		t.Fatalf("user identifiers were not fully scrubbed: %#v", scrubbed.User)
	}
	if scrubbed.User.Data["postal_code"] != "[Filtered]" {
		t.Fatalf("postal_code user data was not filtered: %#v", scrubbed.User.Data)
	}
	if scrubbed.User.Data["safe"] != "value" {
		t.Fatalf("safe user data changed unexpectedly: %#v", scrubbed.User.Data)
	}
	if scrubbed.Extra["token"] != "[Filtered]" {
		t.Fatalf("token extra was not filtered: %#v", scrubbed.Extra)
	}
	if scrubbed.Extra["note"] != "postal [postal-code]" {
		t.Fatalf("postal note was not redacted: %#v", scrubbed.Extra)
	}
	if _, ok := scrubbed.Request.Headers["Authorization"]; ok {
		t.Fatal("Authorization header was not removed")
	}
	if _, ok := scrubbed.Request.Headers["Cookie"]; ok {
		t.Fatal("Cookie header was not removed")
	}
	if scrubbed.Request.Headers["Accept"] != "application/json" {
		t.Fatalf("safe header changed unexpectedly: %#v", scrubbed.Request.Headers)
	}
}
