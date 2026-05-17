// sittings Lambda — GET /api/v1/sittings and GET /api/v1/sittings/{date}/speeches
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"epac/observability"
	"epac/shared/artifacts"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const (
	sittingsArtifactKey = "sittings/v1/all.json"
	defaultPerPage      = 20
	maxPerPage          = 100
)

type Sitting struct {
	Date          string `json:"date"`
	ParliamentNum *int   `json:"parliament_num,omitempty"`
	SessionNum    *int   `json:"session_num,omitempty"`
	SittingNum    *int   `json:"sitting_num,omitempty"`
	SourceURL     string `json:"source_url"`
}

type SittingsResponse struct {
	Page     int       `json:"page"`
	PerPage  int       `json:"per_page"`
	Total    int       `json:"total"`
	Sittings []Sitting `json:"sittings"`
}

type Speech struct {
	ID           string  `json:"id"`
	SpeakerName  *string `json:"speaker_name,omitempty"`
	MemberID     *string `json:"member_id,omitempty"`
	SubjectTitle *string `json:"subject_title,omitempty"`
	Content      *string `json:"content,omitempty"`
	SourceURL    *string `json:"source_url,omitempty"`
}

type SpeechesResponse struct {
	Date     string   `json:"date"`
	Page     int      `json:"page"`
	PerPage  int      `json:"per_page"`
	Total    int      `json:"total"`
	Speeches []Speech `json:"speeches"`
}

var newArtifactStore = artifacts.NewFromEnv

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	path := normalizedPath(req.Path)
	if strings.HasSuffix(path, "/speeches") {
		return handleSittingSpeeches(ctx, req)
	}
	return handleListSittings(ctx, req)
}

func handleListSittings(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	all, err := readSittings(ctx)
	if err != nil {
		return artifactError(err), nil
	}
	from, err := optionalDate(req.QueryStringParameters["from_date"])
	if err != nil {
		return jsonError(http.StatusBadRequest, "from_date must be YYYY-MM-DD"), nil
	}
	to, err := optionalDate(req.QueryStringParameters["to_date"])
	if err != nil {
		return jsonError(http.StatusBadRequest, "to_date must be YYYY-MM-DD"), nil
	}
	page, perPage := pagination(req.QueryStringParameters)
	filtered := filterSittings(all.Sittings, from, to)
	paged := pageSittings(filtered, page, perPage)

	body, err := json.Marshal(SittingsResponse{
		Page:     page,
		PerPage:  perPage,
		Total:    len(filtered),
		Sittings: paged,
	})
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func handleSittingSpeeches(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	date := sittingDateFromRequest(req)
	if _, err := time.Parse("2006-01-02", date); err != nil {
		return jsonError(http.StatusBadRequest, "date must be YYYY-MM-DD"), nil
	}
	page, perPage := pagination(req.QueryStringParameters)
	resp, err := readSittingSpeeches(ctx, date)
	if err != nil {
		if artifacts.IsNotFound(err) {
			return jsonError(http.StatusNotFound, "sitting speeches artifact not found"), nil
		}
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}
	if resp.Speeches == nil {
		resp.Speeches = []Speech{}
	}
	total := len(resp.Speeches)
	resp.Date = date
	resp.Page = page
	resp.PerPage = perPage
	resp.Total = total
	resp.Speeches = pageSpeeches(resp.Speeches, page, perPage)

	body, err := json.Marshal(resp)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func readSittings(ctx context.Context) (SittingsResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return SittingsResponse{}, err
	}
	data, err := store.Get(ctx, sittingsArtifactKey)
	if err != nil {
		return SittingsResponse{}, err
	}
	var resp SittingsResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return SittingsResponse{}, err
	}
	if resp.Sittings == nil {
		resp.Sittings = []Sitting{}
	}
	return resp, nil
}

func readSittingSpeeches(ctx context.Context, date string) (SpeechesResponse, error) {
	store, err := newArtifactStore(ctx)
	if err != nil {
		return SpeechesResponse{}, err
	}
	data, err := store.Get(ctx, fmt.Sprintf("sittings/v1/by-date/%s.json", date))
	if err != nil {
		return SpeechesResponse{}, err
	}
	var resp SpeechesResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return SpeechesResponse{}, err
	}
	return resp, nil
}

func filterSittings(sittings []Sitting, from, to *time.Time) []Sitting {
	filtered := make([]Sitting, 0, len(sittings))
	for _, sitting := range sittings {
		date, err := time.Parse("2006-01-02", sitting.Date)
		if err != nil {
			continue
		}
		if from != nil && date.Before(*from) {
			continue
		}
		if to != nil && date.After(*to) {
			continue
		}
		filtered = append(filtered, sitting)
	}
	return filtered
}

func optionalDate(value string) (*time.Time, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}

func pagination(params map[string]string) (int, int) {
	page := 1
	if parsed, err := strconv.Atoi(params["page"]); err == nil && parsed > 0 {
		page = parsed
	}
	perPage := defaultPerPage
	if parsed, err := strconv.Atoi(params["per_page"]); err == nil && parsed > 0 {
		perPage = parsed
	}
	if perPage > maxPerPage {
		perPage = maxPerPage
	}
	return page, perPage
}

func pageSittings(sittings []Sitting, page, perPage int) []Sitting {
	start, end := pageBounds(len(sittings), page, perPage)
	return sittings[start:end]
}

func pageSpeeches(speeches []Speech, page, perPage int) []Speech {
	start, end := pageBounds(len(speeches), page, perPage)
	return speeches[start:end]
}

func pageBounds(length, page, perPage int) (int, int) {
	start := (page - 1) * perPage
	if start > length {
		return length, length
	}
	end := start + perPage
	if end > length {
		end = length
	}
	return start, end
}

func sittingDateFromRequest(req events.APIGatewayProxyRequest) string {
	if date := strings.TrimSpace(req.PathParameters["date"]); date != "" {
		return date
	}
	path := normalizedPath(req.Path)
	const prefix = "/api/v1/sittings/"
	const suffix = "/speeches"
	return strings.TrimSuffix(strings.TrimPrefix(path, prefix), suffix)
}

func normalizedPath(raw string) string {
	raw = "/" + strings.Trim(strings.TrimSpace(raw), "/")
	if raw == "/" {
		return raw
	}
	return strings.TrimSuffix(raw, "/")
}

func artifactError(err error) events.APIGatewayProxyResponse {
	status := http.StatusInternalServerError
	if artifacts.IsNotFound(err) {
		status = http.StatusNotFound
	}
	return jsonError(status, err.Error())
}

func jsonResponse(status int, body []byte) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": "public, max-age=300",
		},
		Body: string(body),
	}
}

func jsonError(status int, message string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": message})
	return jsonResponse(status, body)
}

func main() {
	lambda.Start(observability.WrapAPIGateway("sittings", HandleRequest))
}
