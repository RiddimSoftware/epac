package subjects

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestFetcher_ParsesFixtureHTML(t *testing.T) {
	rows := parseSubjectMatterRows(`<table><tr><td>Energy</td><td><a href="foo?adv_2001_subjectMatter=SMT-14">14</a></td></tr><tr><td>Culture</td><td><a href="foo?adv_2001_subjectMatter=SMT-99">99</a></td></tr></table>`)
	if got, want := len(rows), 2; got != want {
		t.Fatalf("unexpected parsed rows: got %d want %d", got, want)
	}
	if got := rows["SMT-14"]; got != "Energy" {
		t.Fatalf("unexpected subject description: %s", got)
	}
	if got := rows["SMT-99"]; got != "Culture" {
		t.Fatalf("unexpected subject description: %s", got)
	}
}

func TestFetcher_Integration(t *testing.T) {
	if os.Getenv("OCL_INTEGRATION") != "1" {
		t.Skip("OCL_INTEGRATION not set")
	}

	fetcher := NewFetcher()
	rows, err := fetcher.FetchSubjectMatters(context.Background())
	if err != nil {
		t.Fatalf("fetch subject matters: %v", err)
	}
	if len(rows) == 0 {
		t.Fatalf("expected subject matter rows")
	}
}

func TestFetcher_ParsesFixturesViaHTTP(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.RawQuery == "lang=eng" {
			_, _ = w.Write([]byte(`<table><tr><td>Energy</td><td><a href="foo?adv_2001_subjectMatter=SMT-14">14</a></td></tr></table>`))
			return
		}
		_, _ = w.Write([]byte(`<table><tr><td>Énergie</td><td><a href="foo?adv_2001_subjectMatter=SMT-14">14</a></td></tr></table>`))
	}))
	defer srv.Close()

	fetcher := NewFetcher(
		WithHTTPClient(srv.Client()),
		WithBaseURL(srv.URL),
		WithPaths("?lang=eng", "?lang=fra"),
	)
	rows, err := fetcher.FetchSubjectMatters(context.Background())
	if err != nil {
		t.Fatalf("fetch subject matters: %v", err)
	}
	if got, want := len(rows), 1; got != want {
		t.Fatalf("unexpected rows: got %d want %d", got, want)
	}
	if rows[0].SmtEnDesc == "" {
		t.Fatalf("expected description")
	}
}
