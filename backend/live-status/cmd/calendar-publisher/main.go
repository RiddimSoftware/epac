// calendar-publisher emits the static House sitting calendar ICS artifact.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"live-status/internal/usecase"
)

func main() {
	output := flag.String("output", "../../../build/artifacts/calendar", "artifact output directory")
	year := flag.Int("year", time.Now().In(usecase.OttawaLocation()).Year(), "sitting calendar year")
	sourceURL := flag.String("source-url", "", "optional ourcommons sitting-calendar URL override")
	flag.Parse()

	ctx := context.Background()
	url := *sourceURL
	if strings.TrimSpace(url) == "" {
		url = fmt.Sprintf("https://www.ourcommons.ca/en/sitting-calendar/%d", *year)
	}
	days, err := fetchAnnualSittingCalendar(ctx, http.DefaultClient, url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "fetch sitting calendar: %v\n", err)
		os.Exit(1)
	}
	events := calendarEvents(days, url)
	ics := usecase.BuildHouseCalendarICS(events, time.Now().UTC())
	if err := validateICS(ics); err != nil {
		fmt.Fprintf(os.Stderr, "validate ICS: %v\n", err)
		os.Exit(1)
	}
	if err := writeICS(*output, *year, ics); err != nil {
		fmt.Fprintf(os.Stderr, "write calendar artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published House calendar with %d sitting days\n", len(events))
}

func fetchAnnualSittingCalendar(ctx context.Context, client *http.Client, url string) (map[string]bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", usecase.DefaultUserAgent)
	req.Header.Set("Accept", "text/html,application/xhtml+xml")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, fmt.Errorf("sitting calendar status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 4<<20))
	if err != nil {
		return nil, err
	}
	return usecase.ParseAnnualSittingCalendar(string(body)), nil
}

func calendarEvents(days map[string]bool, sourceURL string) []usecase.CalendarEvent {
	dates := make([]string, 0, len(days))
	for date, isSitting := range days {
		if isSitting {
			dates = append(dates, date)
		}
	}
	sort.Strings(dates)
	events := make([]usecase.CalendarEvent, 0, len(dates))
	for _, date := range dates {
		parsed, err := time.Parse("2006-01-02", date)
		if err != nil {
			continue
		}
		events = append(events, usecase.CalendarEvent{Date: parsed, SourceURL: sourceURL})
	}
	return events
}

func validateICS(ics string) error {
	if !strings.HasPrefix(ics, "BEGIN:VCALENDAR\r\n") {
		return fmt.Errorf("calendar must start with BEGIN:VCALENDAR")
	}
	if !strings.HasSuffix(ics, "END:VCALENDAR\r\n") {
		return fmt.Errorf("calendar must end with END:VCALENDAR")
	}
	for _, line := range strings.Split(strings.TrimSuffix(ics, "\r\n"), "\r\n") {
		if len(line) > 75 {
			return fmt.Errorf("line exceeds RFC 5545 75-octet fold limit: %q", line)
		}
	}
	return nil
}

func writeICS(output string, year int, ics string) error {
	if err := os.MkdirAll(filepath.Join(output, "v1"), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(output, "v1", "house.ics"), []byte(ics), 0o644); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(output, "v1", fmt.Sprintf("house-%d.ics", year)), []byte(ics), 0o644)
}
