package usecase

import (
	"context"
	"testing"
	"time"
)

type fixedClock time.Time

func (c fixedClock) Now() time.Time {
	return time.Time(c)
}

type memoryLiveStatusRepository struct {
	status LiveStatus
}

func (r memoryLiveStatusRepository) ReadLiveStatus(ctx context.Context, fallback time.Time) (LiveStatus, error) {
	if r.status.BusinessType == "" {
		return DefaultLiveStatus(fallback), nil
	}
	return r.status, nil
}

func (r memoryLiveStatusRepository) UpsertLiveStatus(ctx context.Context, status LiveStatus) error {
	return nil
}

func (r memoryLiveStatusRepository) CachedSittingDay(ctx context.Context, date string, now time.Time) (bool, bool, error) {
	return false, false, nil
}

func (r memoryLiveStatusRepository) LatestCalendarFetchedAt(ctx context.Context, year int) (time.Time, bool, error) {
	return time.Time{}, false, nil
}

func (r memoryLiveStatusRepository) UpsertAnnualSittingCalendar(ctx context.Context, year int, sittingDays map[string]bool, source string, fetchedAt time.Time) error {
	return nil
}

func (r memoryLiveStatusRepository) ReadHouseCalendar(ctx context.Context, start time.Time, end time.Time) ([]CalendarEvent, error) {
	return nil, nil
}

func (r memoryLiveStatusRepository) RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time) {
}

func TestCurrentStatusUsesRepositoryPort(t *testing.T) {
	now := time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC)
	resp, err := New(memoryLiveStatusRepository{
		status: LiveStatus{
			IsSitting:    true,
			BusinessType: "Oral Questions",
			SourceURL:    SourceURL,
		},
	}, fixedClock(now)).CurrentStatus(context.Background())
	if err != nil {
		t.Fatalf("CurrentStatus() error = %v", err)
	}
	if resp.Status != "sitting" {
		t.Fatalf("Status = %q, want sitting", resp.Status)
	}
	if resp.CheckedAt != now {
		t.Fatalf("CheckedAt = %v, want %v", resp.CheckedAt, now)
	}
}

func TestParseHomepageExtractsSittingDate(t *testing.T) {
	status := ParseHomepage(`<input type="hidden" id="isMeetingInProgress" value="True" />`, time.Date(2026, 4, 28, 18, 0, 0, 0, time.UTC))
	if status.SittingDate == nil || *status.SittingDate != "2026-04-28" {
		t.Fatalf("SittingDate = %#v, want 2026-04-28", status.SittingDate)
	}
}
