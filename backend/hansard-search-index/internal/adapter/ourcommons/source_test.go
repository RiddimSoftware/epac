package ourcommons

import (
	"context"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
	"time"

	"epac/hansard-search-index/internal/usecase"
)

func TestURLMatchesLiveOurCommonsPattern(t *testing.T) {
	got := URL(DefaultBaseURL, 45, 1, 1)
	want := "https://www.ourcommons.ca/Content/House/451/Debates/001/HAN001-E.XML"
	if got != want {
		t.Fatalf("URL() = %q, want %q", got, want)
	}
}

func TestFilenameUsesSessionBreadcrumb(t *testing.T) {
	got := Filename(45, 1, 7)
	want := "45-1-HAN007-E.XML"
	if got != want {
		t.Fatalf("Filename() = %q, want %q", got, want)
	}
}

func TestFetchSittingDownloadsAndCachesXML(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if r.URL.Path != "/451/Debates/001/HAN001-E.XML" {
			t.Fatalf("path = %q", r.URL.Path)
		}
		if got := r.Header.Get("User-Agent"); got != DefaultUserAgent {
			t.Fatalf("user agent = %q", got)
		}
		w.Header().Set("Content-Type", "text/xml")
		_, _ = w.Write([]byte(`<?xml version="1.0"?><Hansard />`))
	}))
	defer server.Close()

	source := NewSource(
		WithBaseURL(server.URL),
		WithCacheDir(t.TempDir()),
		WithHTTPClient(server.Client()),
		WithSleep(func(context.Context, time.Duration) error { return nil }),
	)
	body, err := source.FetchSitting(context.Background(), 45, 1, 1)
	if err != nil {
		t.Fatalf("first FetchSitting: %v", err)
	}
	if string(body) == "" {
		t.Fatal("first body is empty")
	}
	body, err = source.FetchSitting(context.Background(), 45, 1, 1)
	if err != nil {
		t.Fatalf("cached FetchSitting: %v", err)
	}
	if string(body) == "" {
		t.Fatal("cached body is empty")
	}
	if requests != 1 {
		t.Fatalf("requests = %d, want 1 because second read should use cache", requests)
	}
}

func TestFetchSittingMaps404ToUseCaseNotFound(t *testing.T) {
	server := httptest.NewServer(http.NotFoundHandler())
	defer server.Close()
	source := NewSource(WithBaseURL(server.URL), WithCacheDir(t.TempDir()), WithHTTPClient(server.Client()))

	_, err := source.FetchSitting(context.Background(), 45, 1, 999)
	if err != usecase.ErrSittingNotFound {
		t.Fatalf("error = %v, want ErrSittingNotFound", err)
	}
}

func TestFetchSittingRetries429WithRetryAfter(t *testing.T) {
	requests := 0
	var slept []time.Duration
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if requests == 1 {
			w.Header().Set("Retry-After", "2")
			http.Error(w, "rate limited", http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "text/xml")
		_, _ = w.Write([]byte(`<?xml version="1.0"?><Hansard />`))
	}))
	defer server.Close()
	source := NewSource(
		WithBaseURL(server.URL),
		WithCacheDir(filepath.Join(t.TempDir(), "raw")),
		WithHTTPClient(server.Client()),
		WithSleep(func(_ context.Context, d time.Duration) error {
			slept = append(slept, d)
			return nil
		}),
	)

	if _, err := source.FetchSitting(context.Background(), 45, 1, 1); err != nil {
		t.Fatalf("FetchSitting: %v", err)
	}
	if requests != 2 {
		t.Fatalf("requests = %d, want 2", requests)
	}
	if len(slept) != 1 || slept[0] != 2*time.Second {
		t.Fatalf("slept = %v, want [2s]", slept)
	}
}
