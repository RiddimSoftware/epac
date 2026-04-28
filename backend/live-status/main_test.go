package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestParseHomepageSitting(t *testing.T) {
	now := time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC)
	markup := `
		<input type="hidden" id="isMeetingInProgress" value="True" />
		<span class="sync-view">The House is currently sitting.</span>
		<span class="now-in-the-house-title">Oral Questions</span>
		<div>
			<span>Current Member Speaking</span>
			<span class="profile-name"><a href="/Members/en/1">Steven MacKinnon</a></span>
		</div>
		<a data-analytics-eventlabel="2026-04-28 12:00:00 a.m.">House Sitting Day</a>
	`

	status := parseHomepage(markup, now)

	if !status.IsSitting {
		t.Fatal("expected sitting status")
	}
	if status.BusinessType != "Oral Questions" {
		t.Fatalf("business type = %q, want Oral Questions", status.BusinessType)
	}
	if status.CurrentSpeakerName == nil || *status.CurrentSpeakerName != "Steven MacKinnon" {
		t.Fatalf("speaker = %#v, want Steven MacKinnon", status.CurrentSpeakerName)
	}
	if !status.SittingDays["2026-04-28"] {
		t.Fatal("expected 2026-04-28 to be parsed as sitting day")
	}
	if status.DivisionInProgress {
		t.Fatal("did not expect division in progress")
	}
	if status.SittingDate == nil || *status.SittingDate != "2026-04-28" {
		t.Fatalf("sitting_date = %#v, want 2026-04-28", status.SittingDate)
	}
}

func TestParseHomepageAdjournedHasNoSittingDate(t *testing.T) {
	status := parseHomepage(`
		<input type="hidden" id="isMeetingInProgress" value="False" />
		<span class="sync-view">The House stands adjourned until tomorrow.</span>
	`, time.Date(2026, 4, 28, 22, 0, 0, 0, time.UTC))

	if status.SittingDate != nil {
		t.Fatalf("sitting_date = %#v, want nil for non-sitting poll", status.SittingDate)
	}
}

func TestToResponseRoundTripsSittingDate(t *testing.T) {
	date := "2026-04-28"
	polled := time.Date(2026, 4, 28, 23, 30, 0, 0, time.UTC)
	resp := toResponse(liveStatus{
		IsSitting:    false,
		BusinessType: defaultBusiness,
		SittingDate:  &date,
		LastPolledAt: &polled,
		SourceURL:    sourceURL,
	})
	if resp.SittingDate == nil || *resp.SittingDate != date {
		t.Fatalf("sitting_date = %#v, want %q", resp.SittingDate, date)
	}
	// API contract: the field is present even after the sitting ends so iOS
	// can transition the Home card to "TODAY IN PARLIAMENT" once Hansard
	// publishes — clients perform the 24h cutoff against today's date.
	if resp.IsSitting {
		t.Fatal("expected is_sitting=false in this fixture")
	}
}

func TestParseHomepageAdjourned(t *testing.T) {
	status := parseHomepage(`
		<input type="hidden" id="isMeetingInProgress" value="False" />
		<span class="sync-view">The House stands adjourned until tomorrow.</span>
	`, time.Date(2026, 4, 28, 22, 0, 0, 0, time.UTC))

	if status.IsSitting {
		t.Fatal("expected non-sitting status")
	}
	if status.BusinessType != defaultBusiness {
		t.Fatalf("business type = %q, want %q", status.BusinessType, defaultBusiness)
	}
}

func TestParseHomepageBillNumberAndDivision(t *testing.T) {
	status := parseHomepage(`
		<input type="hidden" id="isMeetingInProgress" value="True" />
		<span class="now-in-the-house-title">Deferred Recorded Division on Bill C-12</span>
	`, time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC))

	if status.CurrentBillNumber == nil || *status.CurrentBillNumber != "C-12" {
		t.Fatalf("bill number = %#v, want C-12", status.CurrentBillNumber)
	}
	if !status.DivisionInProgress {
		t.Fatal("expected division in progress")
	}
}

func TestParseAnnualSittingCalendar(t *testing.T) {
	markup := `
		<td valign="top" class="2026-04-27 chamber-meeting"></td>
		<td valign="top" class="2026-04-28 chamber-meeting"></td>
		<td valign="top" class="2026-05-02"></td>
	`

	days := parseAnnualSittingCalendar(markup)

	if !days["2026-04-27"] || !days["2026-04-28"] {
		t.Fatalf("expected sitting days, got %#v", days)
	}
	if days["2026-05-02"] {
		t.Fatal("did not expect non-chamber-meeting day to be marked sitting")
	}
}

func TestBuildHouseCalendarICS(t *testing.T) {
	now := time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC)
	ics := buildHouseCalendarICS([]calendarEvent{
		{
			Date:      time.Date(2026, 4, 29, 0, 0, 0, 0, time.UTC),
			SourceURL: "https://www.ourcommons.ca/en/sitting-calendar/2026",
		},
	}, now)

	required := []string{
		"BEGIN:VCALENDAR\r\n",
		"VERSION:2.0\r\n",
		"X-WR-CALNAME:House of Commons Sitting Days\r\n",
		"UID:house-sitting-2026-04-29@epac.riddimsoftware.com\r\n",
		"DTSTART;VALUE=DATE:20260429\r\n",
		"DTEND;VALUE=DATE:20260430\r\n",
		"SUMMARY:House of Commons — Sitting Day\r\n",
		"URL:https://epac.riddimsoftware.com/sitting/2026-04-29\r\n",
		"END:VCALENDAR\r\n",
	}
	for _, want := range required {
		if !strings.Contains(ics, want) {
			t.Fatalf("ICS missing %q in:\n%s", want, ics)
		}
	}
}

func TestICSEscape(t *testing.T) {
	got := icsEscape(`one,two;three\four` + "\r\n" + "five" + "\r" + "six")
	want := `one\,two\;three\\four\nfive\nsix`
	if got != want {
		t.Fatalf("icsEscape() = %q, want %q", got, want)
	}
}

func TestFoldICSLinePreservesRunesAndLineLimit(t *testing.T) {
	got := foldICSLine("DESCRIPTION:" + strings.Repeat("calendar ", 10) + "séance")
	for _, line := range strings.Split(got, "\r\n") {
		trimmed := strings.TrimPrefix(line, " ")
		if len(line) > 75 {
			t.Fatalf("folded line has %d bytes, want <= 75: %q", len(line), line)
		}
		if !strings.Contains(got, "séance") || strings.Contains(trimmed, "�") {
			t.Fatalf("folded line corrupted UTF-8: %q", got)
		}
	}
}

func TestSittingWindow(t *testing.T) {
	loc := ottawaLocation()
	cases := []struct {
		name string
		at   time.Time
		want bool
	}{
		{"monday before", time.Date(2026, 4, 27, 10, 29, 0, 0, loc), false},
		{"monday during", time.Date(2026, 4, 27, 10, 30, 0, 0, loc), true},
		{"tuesday during", time.Date(2026, 4, 28, 9, 30, 0, 0, loc), true},
		{"friday after", time.Date(2026, 5, 1, 15, 0, 0, 0, loc), false},
		{"saturday", time.Date(2026, 5, 2, 11, 0, 0, 0, loc), false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isWithinSittingWindow(tc.at); got != tc.want {
				t.Fatalf("isWithinSittingWindow() = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestFetchLiveStatusUsesUserAgent(t *testing.T) {
	t.Setenv("PARLIAMENT_USER_AGENT", "epac-test-agent")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("User-Agent"); got != "epac-test-agent" {
			t.Fatalf("User-Agent = %q, want epac-test-agent", got)
		}
		_, _ = w.Write([]byte(`<input type="hidden" id="isMeetingInProgress" value="False" />`))
	}))
	defer server.Close()

	status, err := fetchLiveStatusFromURL(context.Background(), server.Client(), server.URL, time.Now())
	if err != nil {
		t.Fatalf("fetchLiveStatusFromURL() error = %v", err)
	}
	if status.SourceURL != server.URL {
		t.Fatalf("source URL = %q, want %q", status.SourceURL, server.URL)
	}
}
