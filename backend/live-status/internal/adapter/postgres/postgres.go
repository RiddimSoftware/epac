// Package postgres is the Postgres-backed adapter satisfying the live-status
// LiveParliamentStatusFetching port. SQL semantics are preserved exactly as
// they were before the boundary was introduced; only the location changed.
package postgres

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"time"

	"live-status/internal/usecase"

	"github.com/jackc/pgx/v5"
)

const pipelineName = "live-status"

func Connect(ctx context.Context) (*pgx.Conn, error) {
	connStr := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if connStr == "" {
		return nil, errors.New("DATABASE_URL environment variable is not set")
	}
	return pgx.Connect(ctx, connStr)
}

type LiveParliamentStatusRepository struct {
	conn *pgx.Conn
}

func NewLiveParliamentStatusFetching(conn *pgx.Conn) *LiveParliamentStatusRepository {
	return &LiveParliamentStatusRepository{conn: conn}
}

func (r *LiveParliamentStatusRepository) CachedSittingDay(ctx context.Context, date string, now time.Time) (bool, bool, error) {
	var isSitting bool
	var fetchedAt time.Time
	err := r.conn.QueryRow(ctx, `
		SELECT is_sitting, fetched_at
		FROM live_sitting_day
		WHERE sitting_date = $1
	`, date).Scan(&isSitting, &fetchedAt)
	if err == nil && now.Sub(fetchedAt) < usecase.CalendarCacheTTL {
		return isSitting, true, nil
	}
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return false, false, err
	}
	return false, false, nil
}

func (r *LiveParliamentStatusRepository) UpsertAnnualSittingCalendar(ctx context.Context, year int, sittingDays map[string]bool, source string, fetchedAt time.Time) error {
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
	results := r.conn.SendBatch(ctx, batch)
	defer results.Close()
	for range 365 + usecase.LeapDay(year) {
		if _, err := results.Exec(); err != nil {
			return err
		}
	}
	return nil
}

func (r *LiveParliamentStatusRepository) LatestCalendarFetchedAt(ctx context.Context, year int) (time.Time, bool, error) {
	var fetchedAt time.Time
	err := r.conn.QueryRow(ctx, `
		SELECT fetched_at
		FROM live_sitting_day
		WHERE sitting_date >= $1 AND sitting_date < $2
		ORDER BY fetched_at DESC
		LIMIT 1
	`, time.Date(year, time.January, 1, 0, 0, 0, 0, time.UTC), time.Date(year+1, time.January, 1, 0, 0, 0, 0, time.UTC)).Scan(&fetchedAt)
	if err == nil {
		return fetchedAt, true, nil
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return time.Time{}, false, nil
	}
	return time.Time{}, false, err
}

func (r *LiveParliamentStatusRepository) ReadHouseCalendar(ctx context.Context, start time.Time, end time.Time) ([]usecase.CalendarEvent, error) {
	rows, err := r.conn.Query(ctx, `
		SELECT sitting_date, source_url
		FROM live_sitting_day
		WHERE is_sitting = TRUE
		  AND sitting_date >= $1
		  AND sitting_date < $2
		ORDER BY sitting_date
	`, start, end)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []usecase.CalendarEvent
	for rows.Next() {
		var event usecase.CalendarEvent
		if err := rows.Scan(&event.Date, &event.SourceURL); err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *LiveParliamentStatusRepository) UpsertLiveStatus(ctx context.Context, status usecase.LiveStatus) error {
	snapshot, err := json.Marshal(status.SourceSnapshot)
	if err != nil {
		return err
	}
	now := status.CheckedAt.UTC()
	_, err = r.conn.Exec(ctx, `
		INSERT INTO live_session (
			id, is_sitting, business_type, current_item_title, current_bill_number,
			current_speaker_name, division_in_progress, source_url, source_snapshot,
			last_polled_at, last_changed_at, sitting_date
		)
		VALUES (TRUE, $1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $9, $10)
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
			-- Preserve the most recent sitting_date when a non-sitting poll lands.
			sitting_date         = COALESCE(EXCLUDED.sitting_date, live_session.sitting_date),
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
		status.CurrentSpeakerName, status.DivisionInProgress, status.SourceURL, string(snapshot), now, status.SittingDate)
	return err
}

func (r *LiveParliamentStatusRepository) ReadLiveStatus(ctx context.Context, fallback time.Time) (usecase.LiveStatus, error) {
	var status usecase.LiveStatus
	var snapshotBytes []byte
	var sittingDate *time.Time
	err := r.conn.QueryRow(ctx, `
		SELECT is_sitting, business_type, current_item_title, current_bill_number,
		       current_speaker_name, division_in_progress, source_url, source_snapshot,
		       last_polled_at, last_changed_at, sitting_date
		FROM live_session
		WHERE id = TRUE
	`).Scan(&status.IsSitting, &status.BusinessType, &status.CurrentItemTitle, &status.CurrentBillNumber,
		&status.CurrentSpeakerName, &status.DivisionInProgress, &status.SourceURL, &snapshotBytes,
		&status.LastPolledAt, &status.LastChangedAt, &sittingDate)
	if errors.Is(err, pgx.ErrNoRows) {
		return usecase.DefaultLiveStatus(fallback), nil
	}
	if err != nil {
		return usecase.LiveStatus{}, err
	}
	if len(snapshotBytes) > 0 {
		_ = json.Unmarshal(snapshotBytes, &status.SourceSnapshot)
	}
	if sittingDate != nil {
		formatted := sittingDate.Format("2006-01-02")
		status.SittingDate = &formatted
	}
	return status, nil
}

func (r *LiveParliamentStatusRepository) RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time) {
	var errMsg *string
	var successAt *time.Time
	var recordCount *int
	if runErr == nil {
		successAt = &recordedAt
		recordCount = &count
	} else {
		s := runErr.Error()
		errMsg = &s
	}
	_, _ = r.conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
		VALUES ($1, $2, $3, $4, $5, 1)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, recordedAt.UTC(), successAt, errMsg, recordCount)
}
