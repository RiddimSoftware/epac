package main

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequestReadsICSArtifact(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, houseCalendarArtifactKey, "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n")
	t.Setenv("ARTIFACTS_DIR", dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d body = %s, want 200", resp.StatusCode, resp.Body)
	}
	if !strings.HasPrefix(resp.Body, "BEGIN:VCALENDAR\r\n") {
		t.Fatalf("body is not an ICS calendar: %q", resp.Body)
	}
	if got := resp.Headers["Content-Type"]; got != "text/calendar; charset=utf-8" {
		t.Fatalf("content-type = %q", got)
	}
}

func TestHandleRequestMissingArtifactReturns404(t *testing.T) {
	t.Setenv("ARTIFACTS_DIR", t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d body = %s, want 404", resp.StatusCode, resp.Body)
	}
}

func writeFixture(t *testing.T, root, key, body string) {
	t.Helper()
	path := filepath.Join(root, filepath.FromSlash(key))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir fixture: %v", err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}
}
