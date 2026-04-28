// riding-boundary Lambda - GET /api/v1/ridings/{slug}/boundary
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"golang.org/x/text/unicode/norm"
)

const (
	boundarySetPath  = "/boundaries/federal-electoral-districts-2023-representation-order"
	sourceTitle      = "Elections Canada - Federal Electoral District Boundary Files"
	sourceURL        = "https://www.elections.ca/content.aspx?dir=cir%2FmapsCorner%2Fvector&document=index&lang=e&section=res"
	defaultTolerance = 0.00012
)

var (
	representBaseURL = "https://represent.opennorth.ca"
	httpClient       = &http.Client{Timeout: 8 * time.Second}
)

type boundaryListResponse struct {
	Objects []boundaryListObject `json:"objects"`
}

type boundaryListObject struct {
	URL        string `json:"url"`
	Name       string `json:"name"`
	ExternalID string `json:"external_id"`
}

type boundaryDetail struct {
	Name       string     `json:"name"`
	ExternalID string     `json:"external_id"`
	Extent     []float64  `json:"extent"`
	Centroid   geoPoint   `json:"centroid"`
	Metadata   detailMeta `json:"metadata"`
}

type detailMeta struct {
	RepresentationOrder string `json:"REP_ORDER"`
	EnglishName         string `json:"ED_NAMEE"`
	FrenchName          string `json:"ED_NAMEF"`
}

type geoPoint struct {
	Type        string    `json:"type"`
	Coordinates []float64 `json:"coordinates"`
}

type rawGeometry struct {
	Type        string          `json:"type"`
	Coordinates json.RawMessage `json:"coordinates"`
}

type geoGeometry struct {
	Type        string          `json:"type"`
	Coordinates json.RawMessage `json:"coordinates"`
}

type boundaryResponse struct {
	Slug                string      `json:"slug"`
	Name                string      `json:"name"`
	ExternalID          string      `json:"external_id"`
	RepresentationOrder string      `json:"representation_order"`
	Source              string      `json:"source"`
	SourceURL           string      `json:"source_url"`
	SourceNote          string      `json:"source_note"`
	Extent              []float64   `json:"extent"`
	Centroid            []float64   `json:"centroid"`
	Geometry            geoGeometry `json:"geometry"`
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	slug := strings.TrimSpace(req.PathParameters["slug"])
	if slug == "" {
		slug = slugFromPath(req.Path)
	}
	if slug == "" {
		return jsonError(http.StatusBadRequest, "missing riding slug"), nil
	}

	match, err := resolveBoundary(ctx, slug)
	if err != nil {
		return jsonError(http.StatusBadGateway, err.Error()), nil
	}
	if match.ExternalID == "" {
		return jsonError(http.StatusNotFound, "riding boundary not found"), nil
	}

	detail, err := fetchBoundaryDetail(ctx, match.ExternalID)
	if err != nil {
		return jsonError(http.StatusBadGateway, err.Error()), nil
	}
	geometry, err := fetchBoundaryGeometry(ctx, match.ExternalID)
	if err != nil {
		return jsonError(http.StatusBadGateway, err.Error()), nil
	}
	simplified, err := simplifyGeometry(geometry, defaultTolerance)
	if err != nil {
		return jsonError(http.StatusBadGateway, err.Error()), nil
	}

	name := detail.Name
	if name == "" {
		name = match.Name
	}
	body, err := json.Marshal(boundaryResponse{
		Slug:                slugify(name),
		Name:                name,
		ExternalID:          match.ExternalID,
		RepresentationOrder: firstNonEmpty(detail.Metadata.RepresentationOrder, "2023"),
		Source:              sourceTitle,
		SourceURL:           sourceURL,
		SourceNote:          "Boundary geometry is resolved through Open North Represent's 2023 federal electoral district set, which mirrors the official Elections Canada 45th general election vector boundary files.",
		Extent:              detail.Extent,
		Centroid:            detail.Centroid.Coordinates,
		Geometry:            simplified,
	})
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=86400",
		},
		Body: string(body),
	}, nil
}

func resolveBoundary(ctx context.Context, slug string) (boundaryListObject, error) {
	var listing boundaryListResponse
	if err := getJSON(ctx, boundarySetPath+"/?limit=400&format=json", &listing); err != nil {
		return boundaryListObject{}, err
	}
	target := slugify(slug)
	for _, object := range listing.Objects {
		if object.ExternalID == slug || slugify(object.Name) == target {
			return object, nil
		}
	}
	return boundaryListObject{}, nil
}

func fetchBoundaryDetail(ctx context.Context, externalID string) (boundaryDetail, error) {
	var detail boundaryDetail
	err := getJSON(ctx, fmt.Sprintf("%s/%s/?format=json", boundarySetPath, url.PathEscape(externalID)), &detail)
	return detail, err
}

func fetchBoundaryGeometry(ctx context.Context, externalID string) (rawGeometry, error) {
	var geometry rawGeometry
	err := getJSON(ctx, fmt.Sprintf("%s/%s/simple_shape?format=json", boundarySetPath, url.PathEscape(externalID)), &geometry)
	return geometry, err
}

func getJSON(ctx context.Context, path string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, representBaseURL+path, nil)
	if err != nil {
		return err
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("boundary provider returned HTTP %d", resp.StatusCode)
	}
	limited := io.LimitReader(resp.Body, 8<<20)
	return json.NewDecoder(limited).Decode(target)
}

func simplifyGeometry(geometry rawGeometry, tolerance float64) (geoGeometry, error) {
	switch geometry.Type {
	case "Polygon":
		var polygon [][][]float64
		if err := json.Unmarshal(geometry.Coordinates, &polygon); err != nil {
			return geoGeometry{}, err
		}
		body, err := json.Marshal(simplifyPolygon(polygon, tolerance))
		return geoGeometry{Type: geometry.Type, Coordinates: body}, err
	case "MultiPolygon":
		var multiPolygon [][][][]float64
		if err := json.Unmarshal(geometry.Coordinates, &multiPolygon); err != nil {
			return geoGeometry{}, err
		}
		for i := range multiPolygon {
			multiPolygon[i] = simplifyPolygon(multiPolygon[i], tolerance)
		}
		body, err := json.Marshal(multiPolygon)
		return geoGeometry{Type: geometry.Type, Coordinates: body}, err
	default:
		return geoGeometry{}, fmt.Errorf("unsupported geometry type %q", geometry.Type)
	}
}

func simplifyPolygon(polygon [][][]float64, tolerance float64) [][][]float64 {
	for i := range polygon {
		polygon[i] = simplifyRing(polygon[i], tolerance)
	}
	return polygon
}

func simplifyRing(ring [][]float64, tolerance float64) [][]float64 {
	if len(ring) <= 4 {
		return ring
	}
	closed := samePoint(ring[0], ring[len(ring)-1])
	points := ring
	if closed {
		points = ring[:len(ring)-1]
	}
	simplified := douglasPeucker(points, tolerance)
	if len(simplified) < 3 {
		simplified = points
	}
	if closed {
		first := append([]float64(nil), simplified[0]...)
		simplified = append(simplified, first)
	}
	return simplified
}

func douglasPeucker(points [][]float64, tolerance float64) [][]float64 {
	if len(points) <= 2 {
		return points
	}
	maxDistance := 0.0
	index := 0
	for i := 1; i < len(points)-1; i++ {
		distance := perpendicularDistance(points[i], points[0], points[len(points)-1])
		if distance > maxDistance {
			index = i
			maxDistance = distance
		}
	}
	if maxDistance <= tolerance {
		return [][]float64{points[0], points[len(points)-1]}
	}
	left := douglasPeucker(points[:index+1], tolerance)
	right := douglasPeucker(points[index:], tolerance)
	return append(left[:len(left)-1], right...)
}

func perpendicularDistance(point, start, end []float64) float64 {
	if len(point) < 2 || len(start) < 2 || len(end) < 2 {
		return 0
	}
	dx := end[0] - start[0]
	dy := end[1] - start[1]
	if dx == 0 && dy == 0 {
		return math.Hypot(point[0]-start[0], point[1]-start[1])
	}
	return math.Abs(dy*point[0]-dx*point[1]+end[0]*start[1]-end[1]*start[0]) / math.Hypot(dx, dy)
}

func samePoint(a, b []float64) bool {
	return len(a) >= 2 && len(b) >= 2 && a[0] == b[0] && a[1] == b[1]
}

func slugFromPath(path string) string {
	const prefix = "/api/v1/ridings/"
	if !strings.HasPrefix(path, prefix) || !strings.HasSuffix(path, "/boundary") {
		return ""
	}
	return strings.TrimSuffix(strings.TrimPrefix(path, prefix), "/boundary")
}

func slugify(value string) string {
	decoded, err := url.PathUnescape(value)
	if err == nil {
		value = decoded
	}
	value = strings.NewReplacer("—", "-", "–", "-", "‑", "-", "'", "", "’", "").Replace(value)
	value = norm.NFD.String(value)
	var builder strings.Builder
	lastDash := false
	for _, r := range strings.ToLower(value) {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			builder.WriteRune(r)
			lastDash = false
			continue
		}
		if !lastDash {
			builder.WriteByte('-')
			lastDash = true
		}
	}
	return strings.Trim(builder.String(), "-")
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func jsonError(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("riding-boundary", HandleRequest))
}
