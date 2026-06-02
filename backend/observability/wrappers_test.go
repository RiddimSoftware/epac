package observability

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
)

func TestWrapAPIGatewayAppliesRateLimitBeforeHandler(t *testing.T) {
	previous := defaultRateLimiter
	now := time.Date(2026, 4, 28, 15, 30, 0, 0, time.UTC)
	defaultRateLimiter = newRateLimiter(func() time.Time { return now })
	defer func() { defaultRateLimiter = previous }()

	calls := 0
	wrapped := WrapAPIGateway("calendar", func(context.Context, events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
		calls++
		return events.APIGatewayProxyResponse{StatusCode: 204}, nil
	})
	req := events.APIGatewayProxyRequest{
		Path: "/api/v1/calendar/house.ics",
		RequestContext: events.APIGatewayProxyRequestContext{
			Identity: events.APIGatewayRequestIdentity{SourceIP: "203.0.113.10"},
		},
	}

	if resp, err := wrapped(context.Background(), req); err != nil || resp.StatusCode != 204 {
		t.Fatalf("first response = (%d, %v), want (204, nil)", resp.StatusCode, err)
	}
	resp, err := wrapped(context.Background(), req)
	if err != nil {
		t.Fatalf("rate-limited response returned error: %v", err)
	}
	if resp.StatusCode != 429 {
		t.Fatalf("rate-limited status = %d, want 429", resp.StatusCode)
	}
	if calls != 1 {
		t.Fatalf("handler calls = %d, want 1", calls)
	}
}

func TestWrapAPIGatewayV2RecoversPanicAsError(t *testing.T) {
	wrapped := WrapAPIGatewayV2("panic-test", func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
		panic("boom")
	})

	_, err := wrapped(context.Background(), events.APIGatewayV2HTTPRequest{})
	if err == nil {
		t.Fatal("panic did not return an error")
	}
	if !strings.Contains(err.Error(), "panic: boom") {
		t.Fatalf("panic error = %q, want panic detail", err.Error())
	}
}

func TestWrapEventReturnsHandlerError(t *testing.T) {
	want := errors.New("handler failed")
	wrapped := WrapEvent("event-test", func(context.Context, string) error {
		return want
	})

	if got := wrapped(context.Background(), "payload"); !errors.Is(got, want) {
		t.Fatalf("wrapped error = %v, want %v", got, want)
	}
}
