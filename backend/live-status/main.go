package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"epac/observability"
	"live-status/internal/adapter/postgres"
	"live-status/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
)

const (
	sourceURL         = usecase.SourceURL
	defaultUserAgent  = usecase.DefaultUserAgent
	defaultBusiness   = usecase.DefaultBusiness
	defaultCacheValue = usecase.DefaultCacheValue
	calendarCacheTTL  = usecase.CalendarCacheTTL
	calendarEventName = usecase.CalendarEventName
)

type liveStatus = usecase.LiveStatus
type sourceSnapshot = usecase.SourceSnapshot
type liveResponse = usecase.LiveResponse
type pollResponse = usecase.PollResponse
type calendarEvent = usecase.CalendarEvent

type systemClock struct{}

func (systemClock) Now() time.Time {
	return time.Now()
}

type apiProbe struct {
	Version        string `json:"version"`
	RequestContext struct {
		HTTP struct {
			Method string `json:"method"`
		} `json:"http"`
	} `json:"requestContext"`
}

func handleLambda(ctx context.Context, raw json.RawMessage) (any, error) {
	_ = observability.Init(ctx)

	var probe apiProbe
	_ = json.Unmarshal(raw, &probe)
	if probe.Version == "2.0" || probe.RequestContext.HTTP.Method != "" {
		var req events.APIGatewayV2HTTPRequest
		if err := json.Unmarshal(raw, &req); err != nil {
			return apiError(http.StatusBadRequest, fmt.Sprintf("invalid API Gateway event: %v", err)), nil
		}
		return handleAPI(ctx, req)
	}
	return handlePoll(ctx, time.Now)
}

func handleAPI(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if limitedResp, limited := observability.CheckAPIGatewayV2RateLimit(req); limited {
		return limitedResp, nil
	}

	conn, err := postgres.Connect(ctx)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, err.Error()), nil
	}
	defer conn.Close(ctx)
	repo := postgres.NewLiveParliamentStatusFetching(conn)

	switch normalizedPath(req) {
	case "/calendar/house.ics", "/api/v1/calendar/house.ics":
		return handleHouseCalendar(ctx, repo, time.Now().UTC())
	}

	resp, err := usecase.New(repo, systemClock{}).CurrentStatus(ctx)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, fmt.Sprintf("query live status: %v", err)), nil
	}

	body, _ := json.Marshal(resp)
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": defaultCacheValue,
		},
		Body: string(body),
	}, nil
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

func handleHouseCalendar(ctx context.Context, repo usecase.LiveParliamentStatusFetching, now time.Time) (events.APIGatewayV2HTTPResponse, error) {
	calendarEvents, err := readHouseCalendar(ctx, repo, now)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, fmt.Sprintf("query sitting calendar: %v", err)), nil
	}
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "text/calendar; charset=utf-8",
			"Cache-Control": "public, max-age=300",
		},
		Body: buildHouseCalendarICS(calendarEvents, now),
	}, nil
}

func handlePoll(ctx context.Context, now func() time.Time) (pollResponse, error) {
	conn, err := postgres.Connect(ctx)
	if err != nil {
		return pollResponse{}, err
	}
	defer conn.Close(ctx)
	repo := postgres.NewLiveParliamentStatusFetching(conn)

	runAt := now().UTC()
	local := runAt.In(ottawaLocation())
	if !isWithinSittingWindow(local) {
		status := defaultLiveStatus(runAt)
		if err := repo.UpsertLiveStatus(ctx, status); err != nil {
			repo.RecordHealth(ctx, 0, err, time.Now().UTC())
			return pollResponse{}, err
		}
		repo.RecordHealth(ctx, 1, nil, time.Now().UTC())
		return pollResponse{
			Status:       "ok",
			Polled:       false,
			Reason:       "outside sitting window",
			IsSitting:    false,
			BusinessType: defaultBusiness,
			RecordedAt:   runAt,
			SourceURL:    sourceURL,
		}, nil
	}

	sittingDay, err := confirmedSittingDay(ctx, repo, http.DefaultClient, local, runAt)
	if err != nil {
		repo.RecordHealth(ctx, 0, err, time.Now().UTC())
		return pollResponse{}, err
	}
	if !sittingDay {
		status := defaultLiveStatus(runAt)
		status.SourceSnapshot.RawStatusText = "current date not marked as a House Sitting Day"
		if err := repo.UpsertLiveStatus(ctx, status); err != nil {
			repo.RecordHealth(ctx, 0, err, time.Now().UTC())
			return pollResponse{}, err
		}
		repo.RecordHealth(ctx, 1, nil, time.Now().UTC())
		return pollResponse{
			Status:       "ok",
			Polled:       false,
			Reason:       "confirmed non-sitting day",
			IsSitting:    false,
			BusinessType: defaultBusiness,
			RecordedAt:   runAt,
			SourceURL:    sourceURL,
		}, nil
	}

	status, err := fetchLiveStatus(ctx, http.DefaultClient, runAt)
	if err != nil {
		repo.RecordHealth(ctx, 0, err, time.Now().UTC())
		return pollResponse{}, err
	}
	if len(status.SittingDays) > 0 && !status.SittingDays[local.Format("2006-01-02")] {
		status = defaultLiveStatus(runAt)
		status.SourceSnapshot.RawStatusText = "current date not marked as a House Sitting Day"
	}
	if err := repo.UpsertLiveStatus(ctx, status); err != nil {
		repo.RecordHealth(ctx, 0, err, time.Now().UTC())
		return pollResponse{}, err
	}
	repo.RecordHealth(ctx, 1, nil, time.Now().UTC())

	return pollResponse{
		Status:       "ok",
		Polled:       true,
		IsSitting:    status.IsSitting,
		BusinessType: status.BusinessType,
		RecordedAt:   runAt,
		SourceURL:    status.SourceURL,
	}, nil
}

func confirmedSittingDay(ctx context.Context, repo usecase.LiveParliamentStatusFetching, client *http.Client, local time.Time, now time.Time) (bool, error) {
	date := local.Format("2006-01-02")
	isSitting, fresh, err := repo.CachedSittingDay(ctx, date, now)
	if err != nil {
		return false, err
	}
	if fresh {
		return isSitting, nil
	}
	days, calendarURL, err := fetchAnnualSittingCalendar(ctx, client, local.Year())
	if err != nil {
		return false, err
	}
	if err := repo.UpsertAnnualSittingCalendar(ctx, local.Year(), days, calendarURL, now); err != nil {
		return false, err
	}
	return days[date], nil
}

func fetchAnnualSittingCalendar(ctx context.Context, client *http.Client, year int) (map[string]bool, string, error) {
	url := fmt.Sprintf("https://www.ourcommons.ca/en/sitting-calendar/%d", year)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, "", err
	}
	req.Header.Set("User-Agent", userAgent())
	req.Header.Set("Accept", "text/html,application/xhtml+xml")

	resp, err := client.Do(req)
	if err != nil {
		return nil, "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, "", fmt.Errorf("sitting calendar status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, "", err
	}
	return parseAnnualSittingCalendar(string(body)), url, nil
}

func parseAnnualSittingCalendar(markup string) map[string]bool {
	return usecase.ParseAnnualSittingCalendar(markup)
}

func readHouseCalendar(ctx context.Context, repo usecase.LiveParliamentStatusFetching, now time.Time) ([]calendarEvent, error) {
	local := now.In(ottawaLocation())
	if err := ensureAnnualSittingCalendar(ctx, repo, http.DefaultClient, local.Year(), now); err != nil {
		return nil, err
	}

	start := time.Date(local.Year(), time.January, 1, 0, 0, 0, 0, time.UTC)
	end := start.AddDate(1, 0, 0)
	return repo.ReadHouseCalendar(ctx, start, end)
}

func ensureAnnualSittingCalendar(ctx context.Context, repo usecase.LiveParliamentStatusFetching, client *http.Client, year int, now time.Time) error {
	fetchedAt, found, err := repo.LatestCalendarFetchedAt(ctx, year)
	if err != nil {
		return err
	}
	if found && now.Sub(fetchedAt) < calendarCacheTTL {
		return nil
	}
	days, calendarURL, err := fetchAnnualSittingCalendar(ctx, client, year)
	if err != nil {
		return err
	}
	return repo.UpsertAnnualSittingCalendar(ctx, year, days, calendarURL, now)
}

func buildHouseCalendarICS(events []calendarEvent, generatedAt time.Time) string {
	return usecase.BuildHouseCalendarICS(events, generatedAt)
}

func writeICSLine(b *strings.Builder, name string, value string) {
	usecase.WriteICSLine(b, name, value)
}

func foldICSLine(line string) string {
	return usecase.FoldICSLine(line)
}

func icsEscape(value string) string {
	return usecase.ICSEscape(value)
}

func fetchLiveStatus(ctx context.Context, client *http.Client, now time.Time) (liveStatus, error) {
	return fetchLiveStatusFromURL(ctx, client, sourceURL, now)
}

func fetchLiveStatusFromURL(ctx context.Context, client *http.Client, url string, now time.Time) (liveStatus, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return liveStatus{}, err
	}
	req.Header.Set("User-Agent", userAgent())
	req.Header.Set("Accept", "text/html,application/xhtml+xml")

	resp, err := client.Do(req)
	if err != nil {
		return liveStatus{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return liveStatus{}, fmt.Errorf("ourcommons status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return liveStatus{}, err
	}
	status := parseHomepage(string(body), now)
	status.SourceURL = url
	return status, nil
}

func parseHomepage(markup string, now time.Time) liveStatus {
	return usecase.ParseHomepage(markup, now)
}

func defaultLiveStatus(now time.Time) liveStatus {
	return usecase.DefaultLiveStatus(now)
}

func firstTitle(markup string) string {
	return usecase.FirstTitle(markup)
}

func firstCurrentSpeaker(markup string) string {
	return usecase.FirstCurrentSpeaker(markup)
}

func parseSittingDays(markup string) map[string]bool {
	return usecase.ParseSittingDays(markup)
}

func cleanText(value string) string {
	return usecase.CleanText(value)
}

func isWithinSittingWindow(t time.Time) bool {
	return usecase.IsWithinSittingWindow(t)
}

func ottawaLocation() *time.Location {
	return usecase.OttawaLocation()
}

func leapDay(year int) int {
	return usecase.LeapDay(year)
}

func toResponse(status liveStatus) liveResponse {
	return usecase.ToResponseAt(status, time.Now().UTC())
}

func apiError(code int, msg string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: code,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func userAgent() string {
	if value := strings.TrimSpace(os.Getenv("PARLIAMENT_USER_AGENT")); value != "" {
		return value
	}
	return defaultUserAgent
}

func stringPtr(value string) *string {
	return usecase.StringPtr(value)
}

func main() {
	lambda.Start(handleLambda)
}
