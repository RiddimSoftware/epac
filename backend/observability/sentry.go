package observability

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"
	"github.com/getsentry/sentry-go"
)

const (
	defaultTraceSampleRate = 0.10
	errorFlushTimeout      = 2 * time.Second
)

var (
	initOnce sync.Once
	initErr  error

	postalCodePattern = regexp.MustCompile(`(?i)\b[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z][ -]?\d[ABCEGHJ-NPRSTV-Z]\d\b`)
)

// Init configures Sentry once per Lambda execution environment. The DSN can be
// supplied directly as SENTRY_DSN or loaded from AWS Secrets Manager via
// SENTRY_DSN_SECRET_ID. SecretString may be either a raw DSN or JSON containing
// SENTRY_DSN, sentry_dsn, or dsn.
func Init(ctx context.Context) error {
	initOnce.Do(func() {
		dsn, err := sentryDSN(ctx)
		if err != nil {
			initErr = err
			return
		}

		sampleRate := defaultTraceSampleRate
		if raw := strings.TrimSpace(os.Getenv("SENTRY_TRACES_SAMPLE_RATE")); raw != "" {
			if parsed, err := strconv.ParseFloat(raw, 64); err == nil && parsed >= 0 && parsed <= 1 {
				sampleRate = parsed
			}
		}

		initErr = sentry.Init(sentry.ClientOptions{
			Dsn:              dsn,
			Environment:      envOrDefault("SENTRY_ENVIRONMENT", envOrDefault("ENVIRONMENT", "production")),
			Release:          strings.TrimSpace(os.Getenv("SENTRY_RELEASE")),
			SampleRate:       1.0,
			EnableTracing:    true,
			TracesSampleRate: sampleRate,
			SendDefaultPII:   false,
			BeforeSend:       scrubEvent,
			Tags: map[string]string{
				"runtime": "aws-lambda",
			},
		})
	})
	return initErr
}

func sentryDSN(ctx context.Context) (string, error) {
	if dsn := strings.TrimSpace(os.Getenv("SENTRY_DSN")); dsn != "" {
		return dsn, nil
	}

	secretID := strings.TrimSpace(os.Getenv("SENTRY_DSN_SECRET_ID"))
	if secretID == "" {
		return "", nil
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return "", fmt.Errorf("load AWS config for Sentry DSN: %w", err)
	}

	out, err := secretsmanager.NewFromConfig(cfg).GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: aws.String(secretID),
	})
	if err != nil {
		return "", fmt.Errorf("read Sentry DSN secret %q: %w", secretID, err)
	}
	if out.SecretString == nil {
		return "", fmt.Errorf("Sentry DSN secret %q has no SecretString", secretID)
	}

	raw := strings.TrimSpace(*out.SecretString)
	var payload map[string]string
	if err := json.Unmarshal([]byte(raw), &payload); err == nil {
		for _, key := range []string{"SENTRY_DSN", "sentry_dsn", "dsn"} {
			if dsn := strings.TrimSpace(payload[key]); dsn != "" {
				return dsn, nil
			}
		}
	}
	return raw, nil
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func WrapAPIGateway(service string, handler func(context.Context, events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error)) func(context.Context, events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	return func(ctx context.Context, req events.APIGatewayProxyRequest) (resp events.APIGatewayProxyResponse, err error) {
		hub := invocationHub(ctx, service, req.RequestContext.RequestID, req.HTTPMethod, req.Path)
		defer recoverPanic(ctx, hub, &err)

		if limitedResp, limited := CheckAPIGatewayRateLimit(req); limited {
			captureResult(hub, nil, limitedResp.StatusCode, limitedResp.Body)
			return limitedResp, nil
		}

		resp, err = handler(ctx, req)
		captureResult(hub, err, resp.StatusCode, resp.Body)
		return resp, err
	}
}

func WrapAPIGatewayV2(service string, handler func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error)) func(context.Context, events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	return func(ctx context.Context, req events.APIGatewayV2HTTPRequest) (resp events.APIGatewayV2HTTPResponse, err error) {
		hub := invocationHub(ctx, service, req.RequestContext.RequestID, req.RequestContext.HTTP.Method, req.RawPath)
		defer recoverPanic(ctx, hub, &err)

		if limitedResp, limited := CheckAPIGatewayV2RateLimit(req); limited {
			captureResult(hub, nil, limitedResp.StatusCode, limitedResp.Body)
			return limitedResp, nil
		}

		resp, err = handler(ctx, req)
		captureResult(hub, err, resp.StatusCode, resp.Body)
		return resp, err
	}
}

func WrapEvent[T any](service string, handler func(context.Context, T) error) func(context.Context, T) error {
	return func(ctx context.Context, req T) (err error) {
		hub := invocationHub(ctx, service, "", "", "")
		defer recoverPanic(ctx, hub, &err)

		err = handler(ctx, req)
		captureResult(hub, err, 0, "")
		return err
	}
}

func WrapNoEvent(service string, handler func(context.Context) error) func(context.Context) error {
	return func(ctx context.Context) (err error) {
		hub := invocationHub(ctx, service, "", "", "")
		defer recoverPanic(ctx, hub, &err)

		err = handler(ctx)
		captureResult(hub, err, 0, "")
		return err
	}
}

func invocationHub(ctx context.Context, service, requestID, method, path string) *sentry.Hub {
	if err := Init(ctx); err != nil {
		fmt.Printf("sentry init failed: %v\n", err)
	}

	hub := sentry.CurrentHub().Clone()
	hub.ConfigureScope(func(scope *sentry.Scope) {
		scope.SetTag("source", service)
		if requestID != "" {
			scope.SetTag("request_id", requestID)
		}
		if method != "" {
			scope.SetTag("http.method", method)
		}
		if path != "" {
			scope.SetTag("http.path", path)
		}
		scope.AddBreadcrumb(&sentry.Breadcrumb{
			Category: "lambda",
			Message:  "invoke",
			Level:    sentry.LevelInfo,
			Data: map[string]interface{}{
				"source":     service,
				"request_id": requestID,
			},
		}, 20)
	})
	return hub
}

func captureResult(hub *sentry.Hub, err error, statusCode int, body string) {
	if err != nil {
		hub.CaptureException(err)
		hub.Flush(errorFlushTimeout)
		return
	}
	if statusCode >= http.StatusInternalServerError {
		event := sentry.NewEvent()
		event.Level = sentry.LevelError
		event.Message = fmt.Sprintf("lambda returned HTTP %d", statusCode)
		event.Extra = map[string]interface{}{
			"status_code": statusCode,
			"body":        scrubString(body),
		}
		hub.CaptureEvent(event)
		hub.Flush(errorFlushTimeout)
	}
}

func recoverPanic(ctx context.Context, hub *sentry.Hub, err *error) {
	if recovered := recover(); recovered != nil {
		hub.RecoverWithContext(ctx, recovered)
		hub.Flush(errorFlushTimeout)
		*err = fmt.Errorf("panic: %v", recovered)
	}
}

func scrubEvent(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
	event.Message = scrubString(event.Message)
	event.User.ID = ""
	event.User.Email = ""
	event.User.Username = ""
	event.User.IPAddress = ""
	event.User.Data = scrubStringMap(event.User.Data)
	event.Tags = scrubStringMap(event.Tags)
	event.Extra = scrubMap(event.Extra)

	if event.Request != nil {
		event.Request.URL = scrubString(event.Request.URL)
		event.Request.QueryString = scrubString(event.Request.QueryString)
		for _, key := range []string{"Authorization", "Cookie", "X-Forwarded-For", "X-Real-IP"} {
			delete(event.Request.Headers, key)
		}
	}

	for _, breadcrumb := range event.Breadcrumbs {
		breadcrumb.Message = scrubString(breadcrumb.Message)
		breadcrumb.Data = scrubMap(breadcrumb.Data)
	}

	return event
}

func scrubStringMap(values map[string]string) map[string]string {
	if values == nil {
		return nil
	}
	out := make(map[string]string, len(values))
	for key, value := range values {
		if sensitiveKey(key) {
			out[key] = "[Filtered]"
			continue
		}
		out[key] = scrubString(value)
	}
	return out
}

func scrubMap(values map[string]interface{}) map[string]interface{} {
	if values == nil {
		return nil
	}
	out := make(map[string]interface{}, len(values))
	for key, value := range values {
		if sensitiveKey(key) {
			out[key] = "[Filtered]"
			continue
		}
		out[key] = scrubValue(value)
	}
	return out
}

func sensitiveKey(key string) bool {
	lowerKey := strings.ToLower(key)
	return strings.Contains(lowerKey, "postal") ||
		strings.Contains(lowerKey, "postcode") ||
		strings.Contains(lowerKey, "zip") ||
		strings.Contains(lowerKey, "email") ||
		strings.Contains(lowerKey, "token") ||
		strings.Contains(lowerKey, "authorization") ||
		strings.Contains(lowerKey, "cookie") ||
		strings.Contains(lowerKey, "user_id")
}

func scrubValue(value interface{}) interface{} {
	switch typed := value.(type) {
	case string:
		return scrubString(typed)
	case map[string]interface{}:
		return scrubMap(typed)
	case []interface{}:
		out := make([]interface{}, len(typed))
		for i, item := range typed {
			out[i] = scrubValue(item)
		}
		return out
	default:
		return value
	}
}

func scrubString(value string) string {
	return postalCodePattern.ReplaceAllString(value, "[postal-code]")
}
