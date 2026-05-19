package observability

import (
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"
)

func TestRateLimiterBlocksAfterRuleLimitAndReportsRetryAfter(t *testing.T) {
	now := time.Date(2026, 4, 28, 15, 30, 0, 0, time.UTC)
	limiter := newRateLimiter(func() time.Time { return now })
	rule := rateLimitRule{Name: "test", Limit: 2, Window: time.Minute, Match: func(string) bool { return true }}

	if decision := limiter.Allow(rule, "ip:203.0.113.10"); !decision.Allowed {
		t.Fatal("first request was unexpectedly blocked")
	}
	if decision := limiter.Allow(rule, "ip:203.0.113.10"); !decision.Allowed {
		t.Fatal("second request was unexpectedly blocked")
	}

	decision := limiter.Allow(rule, "ip:203.0.113.10")
	if decision.Allowed {
		t.Fatal("third request was allowed, want blocked")
	}
	if decision.RetryAfter != time.Minute {
		t.Fatalf("retry after = %s, want 1m", decision.RetryAfter)
	}
}

func TestRateLimiterResetsWhenWindowExpires(t *testing.T) {
	now := time.Date(2026, 4, 28, 15, 30, 0, 0, time.UTC)
	limiter := newRateLimiter(func() time.Time { return now })
	rule := rateLimitRule{Name: "test", Limit: 1, Window: time.Minute, Match: func(string) bool { return true }}

	if decision := limiter.Allow(rule, "ip:203.0.113.10"); !decision.Allowed {
		t.Fatal("first request was unexpectedly blocked")
	}
	if decision := limiter.Allow(rule, "ip:203.0.113.10"); decision.Allowed {
		t.Fatal("second request was allowed before the window expired")
	}

	now = now.Add(time.Minute)
	if decision := limiter.Allow(rule, "ip:203.0.113.10"); !decision.Allowed {
		t.Fatal("request after window expiry was blocked")
	}
}

func TestRateLimitKeyPrefersDeviceIDOverSharedIP(t *testing.T) {
	headers := map[string]string{
		"x-device-id":     "device-a",
		"X-Forwarded-For": "203.0.113.10, 198.51.100.1",
	}

	got := rateLimitKey(headers, "198.51.100.2")
	if got != "device:device-a" {
		t.Fatalf("rateLimitKey() = %q, want device key", got)
	}
}

func TestAPIGatewayV2RateLimitUsesEndpointSpecificRules(t *testing.T) {
	previous := defaultRateLimiter
	now := time.Date(2026, 4, 28, 15, 30, 0, 0, time.UTC)
	defaultRateLimiter = newRateLimiter(func() time.Time { return now })
	defer func() { defaultRateLimiter = previous }()

	req := events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/calendar/house.ics",
		RequestContext: events.APIGatewayV2HTTPRequestContext{
			HTTP: events.APIGatewayV2HTTPRequestContextHTTPDescription{
				SourceIP: "203.0.113.10",
			},
		},
	}

	if _, limited := CheckAPIGatewayV2RateLimit(req); limited {
		t.Fatal("first calendar request was unexpectedly blocked")
	}
	resp, limited := CheckAPIGatewayV2RateLimit(req)
	if !limited {
		t.Fatal("second calendar request was allowed, want 429")
	}
	if resp.StatusCode != 429 {
		t.Fatalf("status = %d, want 429", resp.StatusCode)
	}
	if resp.Headers["Retry-After"] == "" {
		t.Fatal("Retry-After header was not set")
	}
}
