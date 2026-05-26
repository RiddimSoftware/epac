package observability

import (
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-lambda-go/events"
)

type rateLimitRule struct {
	Name   string
	Limit  int
	Window time.Duration
	Match  func(string) bool
}

type rateLimitDecision struct {
	Allowed    bool
	RetryAfter time.Duration
	Limit      int
	Window     time.Duration
	RuleName   string
}

type rateLimitBucket struct {
	WindowStart time.Time
	Count       int
}

type rateLimiter struct {
	now     func() time.Time
	mu      sync.Mutex
	buckets map[string]rateLimitBucket
}

var (
	apiRateLimitRules = []rateLimitRule{
		{
			Name:   "calendar-subscription",
			Limit:  1,
			Window: 5 * time.Minute,
			Match:  func(path string) bool { return path == "/api/v1/calendar/house.ics" },
		},
		{
			Name:   "members",
			Limit:  10,
			Window: time.Minute,
			Match: func(path string) bool {
				return path == "/api/v1/members" || strings.HasPrefix(path, "/api/v1/members/")
			},
		},
		{
			Name:   "telemetry",
			Limit:  30,
			Window: time.Minute,
			Match:  func(path string) bool { return path == "/api/v1/telemetry" },
		},
		{
			Name:   "general",
			Limit:  100,
			Window: time.Minute,
			Match:  func(path string) bool { return strings.HasPrefix(path, "/api/v1/") },
		},
	}

	defaultRateLimiter = newRateLimiter(time.Now)
)

func newRateLimiter(now func() time.Time) *rateLimiter {
	return &rateLimiter{
		now:     now,
		buckets: make(map[string]rateLimitBucket),
	}
}

func CheckAPIGatewayRateLimit(req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, bool) {
	path := normalizeAPIPath(req.Path)
	if path == "/" {
		path = normalizeAPIPath(req.RequestContext.Path)
	}
	rule, ok := matchingRateLimitRule(path)
	if !ok {
		return events.APIGatewayProxyResponse{}, false
	}

	key := rateLimitKey(req.Headers, req.RequestContext.Identity.SourceIP)
	decision := defaultRateLimiter.Allow(rule, key)
	if decision.Allowed {
		return events.APIGatewayProxyResponse{}, false
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusTooManyRequests,
		Headers:    rateLimitHeaders(decision),
		Body:       rateLimitBody(decision),
	}, true
}

func CheckAPIGatewayV2RateLimit(req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, bool) {
	path := normalizeAPIPath(req.RawPath)
	if path == "/" {
		path = normalizeAPIPath(req.RequestContext.HTTP.Path)
	}
	rule, ok := matchingRateLimitRule(path)
	if !ok {
		return events.APIGatewayV2HTTPResponse{}, false
	}

	key := rateLimitKey(req.Headers, req.RequestContext.HTTP.SourceIP)
	decision := defaultRateLimiter.Allow(rule, key)
	if decision.Allowed {
		return events.APIGatewayV2HTTPResponse{}, false
	}

	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusTooManyRequests,
		Headers:    rateLimitHeaders(decision),
		Body:       rateLimitBody(decision),
	}, true
}

func (limiter *rateLimiter) Allow(rule rateLimitRule, key string) rateLimitDecision {
	now := limiter.now().UTC()
	bucketKey := rule.Name + ":" + key

	limiter.mu.Lock()
	defer limiter.mu.Unlock()

	limiter.prune(now)

	bucket := limiter.buckets[bucketKey]
	if bucket.WindowStart.IsZero() || now.Sub(bucket.WindowStart) >= rule.Window {
		limiter.buckets[bucketKey] = rateLimitBucket{WindowStart: now, Count: 1}
		return rateLimitDecision{Allowed: true, Limit: rule.Limit, Window: rule.Window, RuleName: rule.Name}
	}

	if bucket.Count >= rule.Limit {
		retryAfter := rule.Window - now.Sub(bucket.WindowStart)
		if retryAfter < time.Second {
			retryAfter = time.Second
		}
		return rateLimitDecision{
			Allowed:    false,
			RetryAfter: retryAfter,
			Limit:      rule.Limit,
			Window:     rule.Window,
			RuleName:   rule.Name,
		}
	}

	bucket.Count++
	limiter.buckets[bucketKey] = bucket
	return rateLimitDecision{Allowed: true, Limit: rule.Limit, Window: rule.Window, RuleName: rule.Name}
}

func (limiter *rateLimiter) prune(now time.Time) {
	for key, bucket := range limiter.buckets {
		if now.Sub(bucket.WindowStart) > 10*time.Minute {
			delete(limiter.buckets, key)
		}
	}
}

func matchingRateLimitRule(path string) (rateLimitRule, bool) {
	for _, rule := range apiRateLimitRules {
		if rule.Match(path) {
			return rule, true
		}
	}
	return rateLimitRule{}, false
}

func normalizeAPIPath(path string) string {
	path = "/" + strings.Trim(strings.TrimSpace(path), "/")
	if path == "/" {
		return path
	}
	return strings.TrimSuffix(path, "/")
}

func rateLimitKey(headers map[string]string, sourceIP string) string {
	if deviceID := strings.TrimSpace(headerValue(headers, "X-Device-ID")); deviceID != "" {
		return "device:" + deviceID
	}
	if sourceIP = strings.TrimSpace(sourceIP); sourceIP != "" {
		return "ip:" + sourceIP
	}
	if forwardedFor := strings.TrimSpace(headerValue(headers, "X-Forwarded-For")); forwardedFor != "" {
		ip := strings.TrimSpace(strings.Split(forwardedFor, ",")[0])
		if ip != "" {
			return "ip:" + ip
		}
	}
	return "anonymous"
}

func headerValue(headers map[string]string, name string) string {
	for key, value := range headers {
		if strings.EqualFold(key, name) {
			return value
		}
	}
	return ""
}

func rateLimitHeaders(decision rateLimitDecision) map[string]string {
	retryAfterSeconds := int(math.Ceil(decision.RetryAfter.Seconds()))
	if retryAfterSeconds < 1 {
		retryAfterSeconds = 1
	}
	return map[string]string{
		"Content-Type":      "application/json",
		"Retry-After":       strconv.Itoa(retryAfterSeconds),
		"X-RateLimit-Limit": strconv.Itoa(decision.Limit),
	}
}

func rateLimitBody(decision rateLimitDecision) string {
	body, _ := json.Marshal(map[string]any{
		"error":          "rate limit exceeded",
		"limit":          decision.Limit,
		"window_seconds": int(decision.Window.Seconds()),
		"scope":          decision.RuleName,
	})
	return string(body)
}
