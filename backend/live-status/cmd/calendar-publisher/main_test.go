package main

import (
	"strings"
	"testing"
)

func TestCalendarEventsSortsDates(t *testing.T) {
	events := calendarEvents(map[string]bool{
		"2026-04-30": true,
		"2026-04-29": true,
		"2026-05-01": false,
	}, "https://www.ourcommons.ca/en/sitting-calendar/2026")
	if len(events) != 2 {
		t.Fatalf("len(events) = %d, want 2", len(events))
	}
	if events[0].Date.Format("2006-01-02") != "2026-04-29" {
		t.Fatalf("first date = %s, want 2026-04-29", events[0].Date.Format("2006-01-02"))
	}
}

func TestValidateICS(t *testing.T) {
	valid := "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n"
	if err := validateICS(valid); err != nil {
		t.Fatalf("validateICS valid calendar: %v", err)
	}
	if err := validateICS(strings.ReplaceAll(valid, "\r\n", "\n")); err == nil {
		t.Fatal("validateICS accepted LF-only calendar")
	}
}
