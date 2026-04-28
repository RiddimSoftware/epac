// openapi Lambda — GET /openapi.json and auth-gated GET /docs.
//
// The backend is deployed as small Go Lambda handlers, so the API contract is
// checked in and served verbatim instead of generated from a single router.
package main

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"html"
	"net/http"
	"os"
	"strings"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

//go:embed openapi.json
var specFS embed.FS

func handler(_ context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	path := normalizedPath(req)
	switch path {
	case "/openapi.json", "/api/v1/openapi.json":
		spec, err := specFS.ReadFile("openapi.json")
		if err != nil {
			return jsonError(http.StatusInternalServerError, "openapi spec not embedded"), nil
		}
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusOK,
			Headers: map[string]string{
				"Content-Type":  "application/json; charset=utf-8",
				"Cache-Control": "public, max-age=300",
			},
			Body: string(spec),
		}, nil
	case "/docs", "/api/v1/docs":
		if ok, status, message := docsAuthorized(req); !ok {
			return jsonError(status, message), nil
		}
		specURL := "/openapi.json"
		if strings.HasPrefix(path, "/api/v1/") {
			specURL = "/api/v1/openapi.json"
		}
		return events.APIGatewayV2HTTPResponse{
			StatusCode: http.StatusOK,
			Headers:    map[string]string{"Content-Type": "text/html; charset=utf-8"},
			Body:       docsHTML(specURL),
		}, nil
	default:
		return jsonError(http.StatusNotFound, "not found"), nil
	}
}

func normalizedPath(req events.APIGatewayV2HTTPRequest) string {
	path := req.RawPath
	if path == "" {
		path = req.RequestContext.HTTP.Path
	}
	path = "/" + strings.Trim(path, "/")
	path = strings.TrimSuffix(path, "/")
	if path == "" {
		return "/"
	}
	return path
}

func docsAuthorized(req events.APIGatewayV2HTTPRequest) (bool, int, string) {
	want := os.Getenv("OPENAPI_DOCS_TOKEN")
	if want == "" {
		return false, http.StatusServiceUnavailable, "docs token not configured"
	}
	got := req.Headers["x-docs-token"]
	if got == "" {
		got = req.Headers["X-Docs-Token"]
	}
	if got == "" {
		got = req.QueryStringParameters["token"]
	}
	if got != want {
		return false, http.StatusUnauthorized, "docs token required"
	}
	return true, http.StatusOK, ""
}

func docsHTML(specURL string) string {
	escapedSpecURL := html.EscapeString(specURL)
	return fmt.Sprintf(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>epac API Docs</title>
  <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({ url: "%s", dom_id: "#swagger-ui" });
  </script>
</body>
</html>`, escapedSpecURL)
}

func jsonError(status int, message string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGatewayV2("openapi", handler))
}
