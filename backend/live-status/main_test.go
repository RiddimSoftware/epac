package main

import (
	"context"
	"net/http"
	"net/http/httptest"
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
