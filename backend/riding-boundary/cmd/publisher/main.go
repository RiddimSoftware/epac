// riding-boundary publisher fetches federal riding boundaries once and emits
// CDN-ready GeoJSON artifacts.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

const (
	boundarySetPath  = "/boundaries/federal-electoral-districts-2023-representation-order"
	sourceTitle      = "Elections Canada - Federal Electoral District Boundary Files"
	sourceURL        = "https://www.elections.ca/content.aspx?dir=cir%2FmapsCorner%2Fvector&document=index&lang=e&section=res"
	defaultTolerance = 0.00012
)

type boundaryListResponse struct {
	Objects []boundaryListObject `json:"objects"`
}

type boundaryListObject struct {
	Name       string `json:"name"`
	ExternalID string `json:"external_id"`
}

type boundaryIndex struct {
	Ridings []boundaryIndexEntry `json:"ridings"`
}

type boundaryIndexEntry struct {
	Slug       string `json:"slug"`
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
}

type geoPoint struct {
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

func main() {
	output := flag.String("output", "../../../build/artifacts/ridings", "artifact output directory")
	sourceBase := flag.String("source-url", envOrDefault("REPRESENT_BASE_URL", "https://represent.opennorth.ca"), "Represent API base URL")
	tolerance := flag.Float64("tolerance", envFloat("RIDING_BOUNDARY_TOLERANCE", defaultTolerance), "Douglas-Peucker simplification tolerance")
	flag.Parse()

	ctx := context.Background()
	client := &http.Client{Timeout: 20 * time.Second}
	responses, err := buildBoundaryArtifacts(ctx, client, *sourceBase, *tolerance)
	if err != nil {
		fmt.Fprintf(os.Stderr, "build boundary artifacts: %v\n", err)
		os.Exit(1)
	}
	if err := writeArtifacts(*output, responses); err != nil {
		fmt.Fprintf(os.Stderr, "write boundary artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d riding boundaries\n", len(responses))
}

func buildBoundaryArtifacts(ctx context.Context, client *http.Client, baseURL string, tolerance float64) ([]boundaryResponse, error) {
	var listing boundaryListResponse
	if err := getJSON(ctx, client, baseURL, boundarySetPath+"/?limit=400&format=json", &listing); err != nil {
		return nil, err
	}
	responses := make([]boundaryResponse, 0, len(listing.Objects))
	for _, object := range listing.Objects {
		if strings.TrimSpace(object.ExternalID) == "" {
			continue
		}
		detail, err := fetchBoundaryDetail(ctx, client, baseURL, object.ExternalID)
		if err != nil {
			return nil, err
		}
		geometry, err := fetchBoundaryGeometry(ctx, client, baseURL, object.ExternalID)
		if err != nil {
			return nil, err
		}
		simplified, err := simplifyGeometry(geometry, tolerance)
		if err != nil {
			return nil, err
		}
		name := firstNonEmpty(detail.Name, object.Name)
		responses = append(responses, boundaryResponse{
			Slug:                slugify(name),
			Name:                name,
			ExternalID:          object.ExternalID,
			RepresentationOrder: firstNonEmpty(detail.Metadata.RepresentationOrder, "2023"),
			Source:              sourceTitle,
			SourceURL:           sourceURL,
			SourceNote:          fmt.Sprintf("Boundary geometry is resolved through Open North Represent's 2023 federal electoral district set, which mirrors the official Elections Canada 45th general election vector boundary files. Coordinates are simplified with Douglas-Peucker tolerance %.5f for mobile map rendering.", tolerance),
			Extent:              detail.Extent,
			Centroid:            detail.Centroid.Coordinates,
			Geometry:            simplified,
		})
	}
	return responses, nil
}

func fetchBoundaryDetail(ctx context.Context, client *http.Client, baseURL string, externalID string) (boundaryDetail, error) {
	var detail boundaryDetail
	err := getJSON(ctx, client, baseURL, fmt.Sprintf("%s/%s/?format=json", boundarySetPath, url.PathEscape(externalID)), &detail)
	return detail, err
}

func fetchBoundaryGeometry(ctx context.Context, client *http.Client, baseURL string, externalID string) (rawGeometry, error) {
	var geometry rawGeometry
	err := getJSON(ctx, client, baseURL, fmt.Sprintf("%s/%s/simple_shape?format=json", boundarySetPath, url.PathEscape(externalID)), &geometry)
	return geometry, err
}

func getJSON(ctx context.Context, client *http.Client, baseURL string, path string, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(baseURL, "/")+path, nil)
	if err != nil {
		return err
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("boundary provider returned HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(target)
}

func writeArtifacts(output string, boundaries []boundaryResponse) error {
	index := boundaryIndex{Ridings: make([]boundaryIndexEntry, 0, len(boundaries))}
	for _, boundary := range boundaries {
		index.Ridings = append(index.Ridings, boundaryIndexEntry{
			Slug:       boundary.Slug,
			Name:       boundary.Name,
			ExternalID: boundary.ExternalID,
		})
		if err := writeJSON(filepath.Join(output, "v1", "boundary", boundary.Slug+".json"), boundary); err != nil {
			return err
		}
	}
	return writeJSON(filepath.Join(output, "v1", "index.json"), index)
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

func writeJSON(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}

func envOrDefault(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}

func envFloat(name string, fallback float64) float64 {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		var parsed float64
		if _, err := fmt.Sscanf(value, "%f", &parsed); err == nil {
			return parsed
		}
	}
	return fallback
}
