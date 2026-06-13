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

func TestHandleRequestReadsSenatorsArtifact(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, senatorsArtifactKey, `{"items":[{"PersonOfficialFirstName":"Charles","PersonOfficialLastName":"Adler"}]}`)
	t.Setenv("ARTIFACTS_DIR", dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d body = %s, want 200", resp.StatusCode, resp.Body)
	}
	if !strings.Contains(resp.Body, `"PersonOfficialFirstName":"Charles"`) {
		t.Fatalf("unexpected body: %s", resp.Body)
	}
}

func TestHandleRequestMissingArtifactReturns404(t *testing.T) {
	t.Setenv("ARTIFACTS_DIR", t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
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
