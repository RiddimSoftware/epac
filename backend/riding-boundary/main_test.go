package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/aws/aws-lambda-go/events"
)

func TestHandleRequestReturnsBoundary(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case boundarySetPath + "/":
			_, _ = w.Write([]byte(`{"objects":[{"url":"/boundaries/federal-electoral-districts-2023-representation-order/35100/","name":"Spadina—Harbourfront","external_id":"35100"}]}`))
		case boundarySetPath + "/35100/":
			_, _ = w.Write([]byte(`{"name":"Spadina—Harbourfront","external_id":"35100","metadata":{"REP_ORDER":"2023"},"extent":[-79.41,43.62,-79.36,43.66],"centroid":{"type":"Point","coordinates":[-79.39,43.64]}}`))
		case boundarySetPath + "/35100/simple_shape":
			_, _ = w.Write([]byte(`{"type":"MultiPolygon","coordinates":[[[[-79.41,43.62],[-79.40,43.63],[-79.39,43.64],[-79.38,43.65],[-79.36,43.66],[-79.41,43.62]]]]}`))
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()
	t.Cleanup(func() { representBaseURL = "https://represent.opennorth.ca" })
	representBaseURL = server.URL

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
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"objects":[]}`))
	}))
	defer server.Close()
	t.Cleanup(func() { representBaseURL = "https://represent.opennorth.ca" })
	representBaseURL = server.URL

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
