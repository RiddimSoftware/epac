// Package usecase implements FetchLiveParliamentStatus application policy.
//
// It depends only on LiveParliamentStatusFetching and Clock ports; it must not
// import database driver, Lambda runtime, or cloud SDK packages.
package usecase

import (
	"context"
	"html"
	"regexp"
	"strings"
	"time"
)

const (
	SourceURL         = "https://www.ourcommons.ca/en"
	DefaultUserAgent  = "epac/1.0 (mailto:epac@riddimsoftware.com)"
	DefaultBusiness   = "Adjourned"
	DefaultCacheValue = "max-age=90"
	CalendarCacheTTL  = 24 * time.Hour
	CalendarEventName = "House of Commons — Sitting Day"
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

type LiveStatus struct {
	IsSitting          bool            `json:"is_sitting"`
	BusinessType       string          `json:"business_type"`
	CurrentItemTitle   *string         `json:"current_item_title,omitempty"`
	CurrentBillNumber  *string         `json:"current_bill_number,omitempty"`
	CurrentSpeakerName *string         `json:"current_speaker_name,omitempty"`
	DivisionInProgress bool            `json:"division_in_progress"`
	SourceURL          string          `json:"source_url"`
	SourceSnapshot     SourceSnapshot  `json:"source_snapshot"`
	LastPolledAt       *time.Time      `json:"last_polled_at,omitempty"`
	LastChangedAt      *time.Time      `json:"last_changed_at,omitempty"`
	SittingDate        *string         `json:"sitting_date,omitempty"`
	RawStatusText      string          `json:"-"`
	SittingDays        map[string]bool `json:"-"`
	CheckedAt          time.Time       `json:"-"`
}

type SourceSnapshot struct {
	RawStatusText string    `json:"raw_status_text,omitempty"`
	ParsedAt      time.Time `json:"parsed_at"`
}

type LiveResponse struct {
	Status             string     `json:"status"`
	IsSitting          bool       `json:"is_sitting"`
	BusinessType       string     `json:"business_type"`
	CurrentItemTitle   *string    `json:"current_item_title,omitempty"`
	CurrentBillNumber  *string    `json:"current_bill_number,omitempty"`
	CurrentSpeakerName *string    `json:"current_speaker_name,omitempty"`
	DivisionInProgress bool       `json:"division_in_progress"`
	CheckedAt          time.Time  `json:"checked_at"`
	LastChangedAt      *time.Time `json:"last_changed_at,omitempty"`
	SittingDate        *string    `json:"sitting_date,omitempty"`
	SourceURL          string     `json:"source_url"`
}

type PollResponse struct {
	Status       string    `json:"status"`
	Polled       bool      `json:"polled"`
	Reason       string    `json:"reason,omitempty"`
	IsSitting    bool      `json:"is_sitting"`
	BusinessType string    `json:"business_type"`
	RecordedAt   time.Time `json:"recorded_at"`
	SourceURL    string    `json:"source_url"`
}

type CalendarEvent struct {
	Date      time.Time
	SourceURL string
}

// LiveParliamentStatusFetching is the outbound port for the live-status cache
// and sitting-calendar data. Matches the catalog's
// `LiveParliamentStatusFetching` port.
type LiveParliamentStatusFetching interface {
	ReadLiveStatus(ctx context.Context, fallback time.Time) (LiveStatus, error)
	UpsertLiveStatus(ctx context.Context, status LiveStatus) error
	CachedSittingDay(ctx context.Context, date string, now time.Time) (bool, bool, error)
	LatestCalendarFetchedAt(ctx context.Context, year int) (time.Time, bool, error)
	UpsertAnnualSittingCalendar(ctx context.Context, year int, sittingDays map[string]bool, source string, fetchedAt time.Time) error
	ReadHouseCalendar(ctx context.Context, start time.Time, end time.Time) ([]CalendarEvent, error)
	RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time)
}

// Clock is the outbound port for current timestamps. Matches the catalog's
// `Clock` port.
type Clock interface {
	Now() time.Time
}

type FetchLiveParliamentStatus struct {
	repo  LiveParliamentStatusFetching
	clock Clock
}

func New(repo LiveParliamentStatusFetching, clock Clock) *FetchLiveParliamentStatus {
	return &FetchLiveParliamentStatus{repo: repo, clock: clock}
}

func (u *FetchLiveParliamentStatus) CurrentStatus(ctx context.Context) (LiveResponse, error) {
	now := u.clock.Now().UTC()
	status, err := u.repo.ReadLiveStatus(ctx, now)
	if err != nil {
		return LiveResponse{}, err
	}
	return ToResponseAt(status, now), nil
}

func ParseHomepage(markup string, now time.Time) LiveStatus {
	status := DefaultLiveStatus(now)
	status.SittingDays = ParseSittingDays(markup)

	if match := isMeetingRe.FindStringSubmatch(markup); len(match) == 2 {
		status.IsSitting = strings.EqualFold(strings.TrimSpace(match[1]), "true")
	}
	if match := syncViewRe.FindStringSubmatch(markup); len(match) == 2 {
		status.RawStatusText = CleanText(match[1])
		status.SourceSnapshot.RawStatusText = status.RawStatusText
		if strings.Contains(strings.ToLower(status.RawStatusText), "currently sitting") {
			status.IsSitting = true
		}
	}
	if title := FirstTitle(markup); title != "" {
		status.BusinessType = title
		status.CurrentItemTitle = StringPtr(title)
		if bill := billNumberRe.FindString(title); bill != "" {
			status.CurrentBillNumber = StringPtr(bill)
		}
	} else if status.IsSitting {
		status.BusinessType = "Sitting"
	}
	if speaker := FirstCurrentSpeaker(markup); speaker != "" {
		status.CurrentSpeakerName = StringPtr(speaker)
	}
	status.DivisionInProgress = liveDivisionTextRe.MatchString(status.BusinessType)
	if status.IsSitting {
		date := now.In(OttawaLocation()).Format("2006-01-02")
		status.SittingDate = &date
	}
	return status
}

func DefaultLiveStatus(now time.Time) LiveStatus {
	return LiveStatus{
		IsSitting:      false,
		BusinessType:   DefaultBusiness,
		SourceURL:      SourceURL,
		SourceSnapshot: SourceSnapshot{ParsedAt: now.UTC()},
		CheckedAt:      now.UTC(),
	}
}

func FirstTitle(markup string) string {
	for _, match := range titleRe.FindAllStringSubmatch(markup, -1) {
		if len(match) != 2 {
			continue
		}
		title := CleanText(match[1])
		if title != "" {
			return title
		}
	}
	return ""
}

func FirstCurrentSpeaker(markup string) string {
	match := currentSpeakerRe.FindStringSubmatch(markup)
	if len(match) != 2 {
		return ""
	}
	return CleanText(match[1])
}

func ParseSittingDays(markup string) map[string]bool {
	days := map[string]bool{}
	for _, match := range sittingCalendarRe.FindAllStringSubmatch(markup, -1) {
		if len(match) == 2 {
			days[match[1]] = true
		}
	}
	return days
}

func ParseAnnualSittingCalendar(markup string) map[string]bool {
	days := map[string]bool{}
	for _, match := range calendarDayRe.FindAllStringSubmatch(markup, -1) {
		if len(match) == 2 {
			days[match[1]] = true
		}
	}
	return days
}

func CleanText(value string) string {
	value = tagsRe.ReplaceAllString(value, " ")
	value = html.UnescapeString(value)
	return strings.TrimSpace(spaceRe.ReplaceAllString(value, " "))
}

func IsWithinSittingWindow(t time.Time) bool {
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

func OttawaLocation() *time.Location {
	loc, err := time.LoadLocation("America/Toronto")
	if err != nil {
		return time.FixedZone("ET", -5*60*60)
	}
	return loc
}

func LeapDay(year int) int {
	if year%400 == 0 || (year%4 == 0 && year%100 != 0) {
		return 1
	}
	return 0
}

func BuildHouseCalendarICS(events []CalendarEvent, generatedAt time.Time) string {
	var b strings.Builder
	dtstamp := generatedAt.UTC().Format("20060102T150405Z")
	WriteICSLine(&b, "BEGIN", "VCALENDAR")
	WriteICSLine(&b, "VERSION", "2.0")
	WriteICSLine(&b, "PRODID", "-//Riddim Software//epac Parliament Calendar//EN")
	WriteICSLine(&b, "CALSCALE", "GREGORIAN")
	WriteICSLine(&b, "METHOD", "PUBLISH")
	WriteICSLine(&b, "X-WR-CALNAME", "House of Commons Sitting Days")
	WriteICSLine(&b, "X-WR-TIMEZONE", "America/Toronto")
	for _, event := range events {
		start := event.Date.UTC()
		end := start.AddDate(0, 0, 1)
		dateString := start.Format("2006-01-02")
		WriteICSLine(&b, "BEGIN", "VEVENT")
		WriteICSLine(&b, "UID", "house-sitting-"+dateString+"@epac.riddimsoftware.com")
		WriteICSLine(&b, "DTSTAMP", dtstamp)
		WriteICSLine(&b, "DTSTART;VALUE=DATE", start.Format("20060102"))
		WriteICSLine(&b, "DTEND;VALUE=DATE", end.Format("20060102"))
		WriteICSLine(&b, "SUMMARY", CalendarEventName)
		WriteICSLine(&b, "DESCRIPTION", ICSEscape("House of Commons sitting day. Source: "+event.SourceURL))
		WriteICSLine(&b, "URL", "https://epac.riddimsoftware.com/sitting/"+dateString)
		WriteICSLine(&b, "END", "VEVENT")
	}
	WriteICSLine(&b, "END", "VCALENDAR")
	return b.String()
}

func WriteICSLine(b *strings.Builder, name string, value string) {
	b.WriteString(FoldICSLine(name + ":" + value))
	b.WriteString("\r\n")
}

func FoldICSLine(line string) string {
	const maxLineBytes = 75
	if len(line) <= maxLineBytes {
		return line
	}
	var b strings.Builder
	lineBytes := 0
	for _, r := range line {
		chunk := string(r)
		if lineBytes > 0 && lineBytes+len(chunk) > maxLineBytes {
			b.WriteString("\r\n ")
			lineBytes = 1
		}
		b.WriteString(chunk)
		lineBytes += len(chunk)
	}
	return b.String()
}

func ICSEscape(value string) string {
	value = strings.ReplaceAll(value, `\`, `\\`)
	value = strings.ReplaceAll(value, "\r\n", `\n`)
	value = strings.ReplaceAll(value, "\n", `\n`)
	value = strings.ReplaceAll(value, "\r", `\n`)
	value = strings.ReplaceAll(value, ";", `\;`)
	value = strings.ReplaceAll(value, ",", `\,`)
	return value
}

func ToResponseAt(status LiveStatus, checkedAt time.Time) LiveResponse {
	if status.LastPolledAt != nil {
		checkedAt = status.LastPolledAt.UTC()
	}
	state := "adjourned"
	if status.IsSitting {
		state = "sitting"
	} else if status.LastPolledAt == nil {
		state = "unknown"
	}
	return LiveResponse{
		Status:             state,
		IsSitting:          status.IsSitting,
		BusinessType:       status.BusinessType,
		CurrentItemTitle:   status.CurrentItemTitle,
		CurrentBillNumber:  status.CurrentBillNumber,
		CurrentSpeakerName: status.CurrentSpeakerName,
		DivisionInProgress: status.DivisionInProgress,
		CheckedAt:          checkedAt,
		LastChangedAt:      status.LastChangedAt,
		SittingDate:        status.SittingDate,
		SourceURL:          status.SourceURL,
	}
}

func StringPtr(value string) *string {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return &value
}
