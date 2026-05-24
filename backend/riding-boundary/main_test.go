package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequestReturnsBoundary(t *testing.T) {
	dir := t.TempDir()
	writeFixture(t, dir, "ridings/v1/boundary/spadina-harbourfront.json", `{
		"slug":"spadina-harbourfront",
		"name":"Spadina—Harbourfront",
		"external_id":"35100",
		"representation_order":"2023",
		"source":"Elections Canada - Federal Electoral District Boundary Files",
		"source_url":"https://www.elections.ca/content.aspx?dir=cir%2FmapsCorner%2Fvector&document=index&lang=e&section=res",
		"source_note":"Boundary geometry is resolved through Open North Represent's 2023 federal electoral district set, which mirrors the official Elections Canada 45th general election vector boundary files.",
		"extent":[-79.41,43.62,-79.36,43.66],
		"centroid":[-79.39,43.64],
		"geometry":{"type":"MultiPolygon","coordinates":[[[[-79.41,43.62],[-79.36,43.66],[-79.41,43.62]]]]}
	}`)
	t.Setenv("ARTIFACTS_DIR", dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"slug": "spadina-harbourfront"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body boundaryResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("response is not valid JSON: %v", err)
	}
	if body.ExternalID != "35100" {
		t.Fatalf("external id = %q, want 35100", body.ExternalID)
	}
	if body.Geometry.Type != "MultiPolygon" {
		t.Fatalf("geometry type = %q, want MultiPolygon", body.Geometry.Type)
	}
	if body.Source != sourceTitle {
		t.Fatalf("source = %q, want %q", body.Source, sourceTitle)
	}
}

func TestHandleRequestNotFound(t *testing.T) {
	t.Setenv("ARTIFACTS_DIR", t.TempDir())

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		PathParameters: map[string]string{"slug": "missing-riding"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestSlugifyHandlesCanadianRidingPunctuation(t *testing.T) {
	tests := map[string]string{
		"Scarborough Centre—Don Valley East": "scarborough-centre-don-valley-east",
		"Longueuil—Saint‑Hubert":             "longueuil-saint-hubert",
		"Québec Centre":                      "quebec-centre",
	}
	for input, want := range tests {
		if got := slugify(input); got != want {
			t.Fatalf("slugify(%q) = %q, want %q", input, got, want)
		}
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
