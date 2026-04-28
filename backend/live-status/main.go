package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

const (
	pipelineName      = "live-status"
	sourceURL         = "https://www.ourcommons.ca/en"
	defaultUserAgent  = "epac/1.0 (mailto:sunny@riddimsoftware.com)"
	defaultBusiness   = "Adjourned"
	defaultCacheValue = "max-age=90"
	calendarCacheTTL  = 24 * time.Hour
)

var (
	isMeetingRe        = regexp.MustCompile(`(?is)<input[^>]+id=["']isMeetingInProgress["'][^>]+value=["']([^"']+)["']`)
	syncViewRe         = regexp.MustCompile(`(?is)<span[^>]+class=["'][^"']*\bsync-view\b[^"']*["'][^>]*>(.*?)</span>`)
	titleRe            = regexp.MustCompile(`(?is)<span[^>]+class=["'][^"']*\bnow-in-the-house-title\b[^"']*["'][^>]*>(.*?)</span>`)
	billNumberRe       = regexp.MustCompile(`\b[CS]-\d+\b`)
	calendarDayRe      = regexp.MustCompile(`(?is)class=["'][^"']*\b([0-9]{4}-[0-9]{2}-[0-9]{2})\b[^"']*\bchamber-meeting\b`)
	tagsRe             = regexp.MustCompile(`(?is)<[^>]+>`)
	spaceRe            = regexp.MustCompile(`\s+`)
	sittingCalendarRe  = regexp.MustCompile(`(?is)data-analytics-eventlabel=["']([0-9]{4}-[0-9]{2}-[0-9]{2}) 12:00:00 a\.m\.["'][^>]*>.*?House Sitting Day`)
	currentSpeakerRe   = regexp.MustCompile(`(?is)Current Member Speaking.*?<span[^>]+class=["'][^"']*\bprofile-name\b[^"']*["'][^>]*>\s*<a[^>]*>(.*?)</a>`)
	liveDivisionTextRe = regexp.MustCompile(`(?i)\b(division|vote|deferred recorded division)\b`)
)

type liveStatus struct {
	IsSitting          bool            `json:"is_sitting"`
	BusinessType       string          `json:"business_type"`
	CurrentItemTitle   *string         `json:"current_item_title,omitempty"`
	CurrentBillNumber  *string         `json:"current_bill_number,omitempty"`
	CurrentSpeakerName *string         `json:"current_speaker_name,omitempty"`
	DivisionInProgress bool            `json:"division_in_progress"`
	SourceURL          string          `json:"source_url"`
	SourceSnapshot     sourceSnapshot  `json:"source_snapshot"`
	LastPolledAt       *time.Time      `json:"last_polled_at,omitempty"`
	LastChangedAt      *time.Time      `json:"last_changed_at,omitempty"`
	RawStatusText      string          `json:"-"`
	SittingDays        map[string]bool `json:"-"`
	CheckedAt          time.Time       `json:"-"`
}

type sourceSnapshot struct {
	RawStatusText string    `json:"raw_status_text,omitempty"`
	ParsedAt      time.Time `json:"parsed_at"`
}

type liveResponse struct {
	Status             string     `json:"status"`
	IsSitting          bool       `json:"is_sitting"`
	BusinessType       string     `json:"business_type"`
	CurrentItemTitle   *string    `json:"current_item_title,omitempty"`
	CurrentBillNumber  *string    `json:"current_bill_number,omitempty"`
	CurrentSpeakerName *string    `json:"current_speaker_name,omitempty"`
	DivisionInProgress bool       `json:"division_in_progress"`
	CheckedAt          time.Time  `json:"checked_at"`
	LastChangedAt      *time.Time `json:"last_changed_at,omitempty"`
	SourceURL          string     `json:"source_url"`
}

type pollResponse struct {
	Status       string    `json:"status"`
	Polled       bool      `json:"polled"`
	Reason       string    `json:"reason,omitempty"`
	IsSitting    bool      `json:"is_sitting"`
	BusinessType string    `json:"business_type"`
	RecordedAt   time.Time `json:"recorded_at"`
	SourceURL    string    `json:"source_url"`
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

	conn, err := connectDB(ctx)
	if err != nil {
		return apiError(http.StatusServiceUnavailable, err.Error()), nil
	}
	defer conn.Close(ctx)

	status, err := readLiveStatus(ctx, conn, time.Now().UTC())
	if err != nil {
		return apiError(http.StatusServiceUnavailable, fmt.Sprintf("query live status: %v", err)), nil
	}

	body, _ := json.Marshal(toResponse(status))
	return events.APIGatewayV2HTTPResponse{
		StatusCode: http.StatusOK,
		Headers: map[string]string{
			"Content-Type":  "application/json",
			"Cache-Control": defaultCacheValue,
		},
		Body: string(body),
	}, nil
}

func handlePoll(ctx context.Context, now func() time.Time) (pollResponse, error) {
	conn, err := connectDB(ctx)
	if err != nil {
		return pollResponse{}, err
	}
	defer conn.Close(ctx)

	runAt := now().UTC()
	local := runAt.In(ottawaLocation())
	if !isWithinSittingWindow(local) {
		status := defaultLiveStatus(runAt)
		if err := upsertLiveStatus(ctx, conn, status); err != nil {
			recordHealth(ctx, conn, 0, err)
			return pollResponse{}, err
		}
		recordHealth(ctx, conn, 1, nil)
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

	sittingDay, err := confirmedSittingDay(ctx, conn, http.DefaultClient, local, runAt)
	if err != nil {
		recordHealth(ctx, conn, 0, err)
		return pollResponse{}, err
	}
	if !sittingDay {
		status := defaultLiveStatus(runAt)
		status.SourceSnapshot.RawStatusText = "current date not marked as a House Sitting Day"
		if err := upsertLiveStatus(ctx, conn, status); err != nil {
			recordHealth(ctx, conn, 0, err)
			return pollResponse{}, err
		}
		recordHealth(ctx, conn, 1, nil)
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
		recordHealth(ctx, conn, 0, err)
		return pollResponse{}, err
	}
	if len(status.SittingDays) > 0 && !status.SittingDays[local.Format("2006-01-02")] {
		status = defaultLiveStatus(runAt)
		status.SourceSnapshot.RawStatusText = "current date not marked as a House Sitting Day"
	}
	if err := upsertLiveStatus(ctx, conn, status); err != nil {
		recordHealth(ctx, conn, 0, err)
		return pollResponse{}, err
	}
	recordHealth(ctx, conn, 1, nil)

	return pollResponse{
		Status:       "ok",
		Polled:       true,
		IsSitting:    status.IsSitting,
		BusinessType: status.BusinessType,
		RecordedAt:   runAt,
		SourceURL:    status.SourceURL,
	}, nil
}

func connectDB(ctx context.Context) (*pgx.Conn, error) {
	connStr := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if connStr == "" {
		return nil, errors.New("DATABASE_URL environment variable is not set")
	}
	return pgx.Connect(ctx, connStr)
}

func confirmedSittingDay(ctx context.Context, conn *pgx.Conn, client *http.Client, local time.Time, now time.Time) (bool, error) {
	date := local.Format("2006-01-02")
	var isSitting bool
	var fetchedAt time.Time
	err := conn.QueryRow(ctx, `
		SELECT is_sitting, fetched_at
		FROM live_sitting_day
		WHERE sitting_date = $1
	`, date).Scan(&isSitting, &fetchedAt)
	if err == nil && now.Sub(fetchedAt) < calendarCacheTTL {
		return isSitting, nil
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return false, err
	}
	days, calendarURL, err := fetchAnnualSittingCalendar(ctx, client, local.Year())
	if err != nil {
		return false, err
	}
	if err := upsertAnnualSittingCalendar(ctx, conn, local.Year(), days, calendarURL, now); err != nil {
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
	days := map[string]bool{}
	for _, match := range calendarDayRe.FindAllStringSubmatch(markup, -1) {
		if len(match) == 2 {
			days[match[1]] = true
		}
	}
	return days
}

func upsertAnnualSittingCalendar(ctx context.Context, conn *pgx.Conn, year int, sittingDays map[string]bool, source string, fetchedAt time.Time) error {
	jan1 := time.Date(year, 1, 1, 0, 0, 0, 0, time.UTC)
	nextYear := jan1.AddDate(1, 0, 0)
	batch := &pgx.Batch{}
	for day := jan1; day.Before(nextYear); day = day.AddDate(0, 0, 1) {
		date := day.Format("2006-01-02")
		batch.Queue(`
			INSERT INTO live_sitting_day (sitting_date, is_sitting, source_url, fetched_at)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (sitting_date) DO UPDATE SET
				is_sitting = EXCLUDED.is_sitting,
				source_url = EXCLUDED.source_url,
				fetched_at = EXCLUDED.fetched_at
		`, date, sittingDays[date], source, fetchedAt.UTC())
	}
	results := conn.SendBatch(ctx, batch)
	defer results.Close()
	for range 365 + leapDay(year) {
		if _, err := results.Exec(); err != nil {
			return err
		}
	}
	return nil
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
	status := defaultLiveStatus(now)
	status.SittingDays = parseSittingDays(markup)

	if match := isMeetingRe.FindStringSubmatch(markup); len(match) == 2 {
		status.IsSitting = strings.EqualFold(strings.TrimSpace(match[1]), "true")
	}
	if match := syncViewRe.FindStringSubmatch(markup); len(match) == 2 {
		status.RawStatusText = cleanText(match[1])
		status.SourceSnapshot.RawStatusText = status.RawStatusText
		if strings.Contains(strings.ToLower(status.RawStatusText), "currently sitting") {
			status.IsSitting = true
		}
	}
	if title := firstTitle(markup); title != "" {
		status.BusinessType = title
		status.CurrentItemTitle = stringPtr(title)
		if bill := billNumberRe.FindString(title); bill != "" {
			status.CurrentBillNumber = stringPtr(bill)
		}
	} else if status.IsSitting {
		status.BusinessType = "Sitting"
	}
	if speaker := firstCurrentSpeaker(markup); speaker != "" {
		status.CurrentSpeakerName = stringPtr(speaker)
	}
	status.DivisionInProgress = liveDivisionTextRe.MatchString(status.BusinessType)
	return status
}

func defaultLiveStatus(now time.Time) liveStatus {
	return liveStatus{
		IsSitting:      false,
		BusinessType:   defaultBusiness,
		SourceURL:      sourceURL,
		SourceSnapshot: sourceSnapshot{ParsedAt: now.UTC()},
		CheckedAt:      now.UTC(),
	}
}

func firstTitle(markup string) string {
	for _, match := range titleRe.FindAllStringSubmatch(markup, -1) {
		if len(match) != 2 {
			continue
		}
		title := cleanText(match[1])
		if title != "" {
			return title
		}
	}
	return ""
}

func firstCurrentSpeaker(markup string) string {
	match := currentSpeakerRe.FindStringSubmatch(markup)
	if len(match) != 2 {
		return ""
	}
	return cleanText(match[1])
}

func parseSittingDays(markup string) map[string]bool {
	days := map[string]bool{}
	for _, match := range sittingCalendarRe.FindAllStringSubmatch(markup, -1) {
		if len(match) == 2 {
			days[match[1]] = true
		}
	}
	return days
}

func cleanText(value string) string {
	value = tagsRe.ReplaceAllString(value, " ")
	value = html.UnescapeString(value)
	return strings.TrimSpace(spaceRe.ReplaceAllString(value, " "))
}

func isWithinSittingWindow(t time.Time) bool {
	minutes := t.Hour()*60 + t.Minute()
	switch t.Weekday() {
	case time.Monday:
		return minutes >= 10*60+30 && minutes < 19*60
	case time.Tuesday, time.Wednesday, time.Thursday:
		return minutes >= 9*60+30 && minutes < 19*60
	case time.Friday:
		return minutes >= 9*60+30 && minutes < 15*60
	default:
		return false
	}
}

func ottawaLocation() *time.Location {
	loc, err := time.LoadLocation("America/Toronto")
	if err != nil {
		return time.FixedZone("ET", -5*60*60)
	}
	return loc
}

func leapDay(year int) int {
	if year%400 == 0 || (year%4 == 0 && year%100 != 0) {
		return 1
	}
	return 0
}

func upsertLiveStatus(ctx context.Context, conn *pgx.Conn, status liveStatus) error {
	snapshot, err := json.Marshal(status.SourceSnapshot)
	if err != nil {
		return err
	}
	now := status.CheckedAt.UTC()
	_, err = conn.Exec(ctx, `
		INSERT INTO live_session (
			id, is_sitting, business_type, current_item_title, current_bill_number,
			current_speaker_name, division_in_progress, source_url, source_snapshot,
			last_polled_at, last_changed_at
		)
		VALUES (TRUE, $1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $9)
		ON CONFLICT (id) DO UPDATE SET
			is_sitting           = EXCLUDED.is_sitting,
			business_type        = EXCLUDED.business_type,
			current_item_title   = EXCLUDED.current_item_title,
			current_bill_number  = EXCLUDED.current_bill_number,
			current_speaker_name = EXCLUDED.current_speaker_name,
			division_in_progress = EXCLUDED.division_in_progress,
			source_url           = EXCLUDED.source_url,
			source_snapshot      = EXCLUDED.source_snapshot,
			last_polled_at       = EXCLUDED.last_polled_at,
			last_changed_at      = CASE
				WHEN live_session.is_sitting IS DISTINCT FROM EXCLUDED.is_sitting
				  OR live_session.business_type IS DISTINCT FROM EXCLUDED.business_type
				  OR live_session.current_item_title IS DISTINCT FROM EXCLUDED.current_item_title
				  OR live_session.current_bill_number IS DISTINCT FROM EXCLUDED.current_bill_number
				  OR live_session.current_speaker_name IS DISTINCT FROM EXCLUDED.current_speaker_name
				  OR live_session.division_in_progress IS DISTINCT FROM EXCLUDED.division_in_progress
				THEN EXCLUDED.last_changed_at
				ELSE live_session.last_changed_at
			END
	`, status.IsSitting, status.BusinessType, status.CurrentItemTitle, status.CurrentBillNumber,
		status.CurrentSpeakerName, status.DivisionInProgress, status.SourceURL, string(snapshot), now)
	return err
}

func readLiveStatus(ctx context.Context, conn *pgx.Conn, fallback time.Time) (liveStatus, error) {
	var status liveStatus
	var snapshotBytes []byte
	err := conn.QueryRow(ctx, `
		SELECT is_sitting, business_type, current_item_title, current_bill_number,
		       current_speaker_name, division_in_progress, source_url, source_snapshot,
		       last_polled_at, last_changed_at
		FROM live_session
		WHERE id = TRUE
	`).Scan(&status.IsSitting, &status.BusinessType, &status.CurrentItemTitle, &status.CurrentBillNumber,
		&status.CurrentSpeakerName, &status.DivisionInProgress, &status.SourceURL, &snapshotBytes,
		&status.LastPolledAt, &status.LastChangedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return defaultLiveStatus(fallback), nil
	}
	if err != nil {
		return liveStatus{}, err
	}
	if len(snapshotBytes) > 0 {
		_ = json.Unmarshal(snapshotBytes, &status.SourceSnapshot)
	}
	return status, nil
}

func toResponse(status liveStatus) liveResponse {
	checkedAt := time.Now().UTC()
	if status.LastPolledAt != nil {
		checkedAt = status.LastPolledAt.UTC()
	}
	state := "adjourned"
	if status.IsSitting {
		state = "sitting"
	} else if status.LastPolledAt == nil {
		state = "unknown"
	}
	return liveResponse{
		Status:             state,
		IsSitting:          status.IsSitting,
		BusinessType:       status.BusinessType,
		CurrentItemTitle:   status.CurrentItemTitle,
		CurrentBillNumber:  status.CurrentBillNumber,
		CurrentSpeakerName: status.CurrentSpeakerName,
		DivisionInProgress: status.DivisionInProgress,
		CheckedAt:          checkedAt,
		LastChangedAt:      status.LastChangedAt,
		SourceURL:          status.SourceURL,
	}
}

func apiError(code int, msg string) events.APIGatewayV2HTTPResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayV2HTTPResponse{
		StatusCode: code,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func recordHealth(ctx context.Context, conn *pgx.Conn, count int, runErr error) {
	now := time.Now().UTC()
	var errMsg *string
	var successAt *time.Time
	var recordCount *int
	if runErr == nil {
		successAt = &now
		recordCount = &count
	} else {
		s := runErr.Error()
		errMsg = &s
	}
	_, _ = conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
		VALUES ($1, $2, $3, $4, $5, 1)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, now, successAt, errMsg, recordCount)
}

func userAgent() string {
	if value := strings.TrimSpace(os.Getenv("PARLIAMENT_USER_AGENT")); value != "" {
		return value
	}
	return defaultUserAgent
}

func stringPtr(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return &value
}

func main() {
	lambda.Start(handleLambda)
}
