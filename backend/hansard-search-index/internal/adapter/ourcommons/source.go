package ourcommons

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"epac/hansard-search-index/internal/usecase"
)

const (
	DefaultBaseURL   = "https://www.ourcommons.ca/Content/House"
	DefaultCacheDir  = "/tmp/raw"
	DefaultUserAgent = "epac-hansard-search-index/1.0 (sunny@riddimsoftware.com)"
	MaxRetries       = 4
	MaxBackoff       = 30 * time.Second
)

type Source struct {
	client    *http.Client
	baseURL   string
	cacheDir  string
	userAgent string
	logger    Logger
	sleep     func(context.Context, time.Duration) error
}

type SourceOption func(*Source)

func NewSource(options ...SourceOption) *Source {
	source := &Source{
		client:    &http.Client{Timeout: 30 * time.Second},
		baseURL:   DefaultBaseURL,
		cacheDir:  DefaultCacheDir,
		userAgent: DefaultUserAgent,
		logger:    discardLogger{},
		sleep:     sleepContext,
	}
	for _, option := range options {
		option(source)
	}
	source.baseURL = strings.TrimRight(source.baseURL, "/")
	source.logger = defaultLogger(source.logger)
	return source
}

func WithHTTPClient(client *http.Client) SourceOption {
	return func(source *Source) {
		if client != nil {
			source.client = client
		}
	}
}

func WithBaseURL(baseURL string) SourceOption {
	return func(source *Source) {
		if strings.TrimSpace(baseURL) != "" {
			source.baseURL = baseURL
		}
	}
}

func WithCacheDir(cacheDir string) SourceOption {
	return func(source *Source) {
		if strings.TrimSpace(cacheDir) != "" {
			source.cacheDir = cacheDir
		}
	}
}

func WithLogger(logger Logger) SourceOption {
	return func(source *Source) {
		source.logger = logger
	}
}

func WithSleep(sleep func(context.Context, time.Duration) error) SourceOption {
	return func(source *Source) {
		if sleep != nil {
			source.sleep = sleep
		}
	}
}

func (s *Source) FetchSitting(ctx context.Context, parliament, session, sitting int) ([]byte, error) {
	start := time.Now()
	filename := Filename(parliament, session, sitting)
	cachePath := filepath.Join(s.cacheDir, filename)
	if body, err := os.ReadFile(cachePath); err == nil {
		s.logFetch("cache_hit", sitting, http.StatusOK, start)
		return body, nil
	} else if !os.IsNotExist(err) {
		return nil, fmt.Errorf("read cached XML %s: %w", cachePath, err)
	}

	url := URL(s.baseURL, parliament, session, sitting)
	var lastStatus int
	var lastErr error
	for attempt := 0; attempt <= MaxRetries; attempt++ {
		body, status, retryAfter, err := s.fetch(ctx, url)
		lastStatus = status
		lastErr = err
		if err != nil {
			if attempt == MaxRetries {
				break
			}
			if err := s.sleep(ctx, backoff(attempt, retryAfter)); err != nil {
				return nil, err
			}
			continue
		}

		s.logFetch("fetch", sitting, status, start)
		switch status {
		case http.StatusOK:
			if err := os.MkdirAll(s.cacheDir, 0o755); err != nil {
				return nil, fmt.Errorf("create raw XML cache dir: %w", err)
			}
			if err := os.WriteFile(cachePath, body, 0o644); err != nil {
				return nil, fmt.Errorf("write cached XML %s: %w", cachePath, err)
			}
			return body, nil
		case http.StatusNotFound:
			return nil, usecase.ErrSittingNotFound
		case http.StatusTooManyRequests:
			if attempt == MaxRetries {
				return nil, fmt.Errorf("%s returned 429 after retries", url)
			}
			if err := s.sleep(ctx, backoff(attempt, retryAfter)); err != nil {
				return nil, err
			}
		default:
			return nil, fmt.Errorf("%s returned status %d", url, status)
		}
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("%s returned status %d", url, lastStatus)
}

func (s *Source) fetch(ctx context.Context, url string) ([]byte, int, time.Duration, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, 0, 0, err
	}
	req.Header.Set("User-Agent", s.userAgent)
	resp, err := s.client.Do(req)
	if err != nil {
		return nil, 0, 0, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, resp.StatusCode, retryAfter(resp.Header.Get("Retry-After")), err
	}
	if resp.StatusCode == http.StatusOK && !looksLikeXML(resp.Header.Get("Content-Type"), body) {
		return nil, http.StatusNotFound, 0, nil
	}
	return body, resp.StatusCode, retryAfter(resp.Header.Get("Retry-After")), nil
}

func (s *Source) logFetch(event string, sitting, status int, start time.Time) {
	s.logger.Info(event, map[string]any{
		"sitting":     sitting,
		"status_code": status,
		"duration_ms": time.Since(start).Milliseconds(),
	})
}

func Filename(parliament, session, sitting int) string {
	return fmt.Sprintf("%d-%d-HAN%03d-E.XML", parliament, session, sitting)
}

func URL(baseURL string, parliament, session, sitting int) string {
	return fmt.Sprintf("%s/%d%d/Debates/%03d/HAN%03d-E.XML", strings.TrimRight(baseURL, "/"), parliament, session, sitting, sitting)
}

func looksLikeXML(contentType string, body []byte) bool {
	if strings.Contains(strings.ToLower(contentType), "xml") {
		return true
	}
	return bytes.Contains(bytes.TrimSpace(body[:min(len(body), 128)]), []byte("<?xml"))
}

func retryAfter(value string) time.Duration {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if seconds, err := strconv.Atoi(value); err == nil {
		return time.Duration(seconds) * time.Second
	}
	if t, err := http.ParseTime(value); err == nil {
		return time.Until(t)
	}
	return 0
}

func backoff(attempt int, retryAfter time.Duration) time.Duration {
	delay := time.Duration(1<<attempt) * time.Second
	if retryAfter > delay {
		delay = retryAfter
	}
	if delay > MaxBackoff {
		return MaxBackoff
	}
	if delay < 0 {
		return 0
	}
	return delay
}

func sleepContext(ctx context.Context, delay time.Duration) error {
	if delay <= 0 {
		return nil
	}
	timer := time.NewTimer(delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}
