package _testdb

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

type LiveSessionRow struct {
	IsSitting          bool
	BusinessType       string
	CurrentItemTitle   *string
	CurrentBillNumber  *string
	CurrentSpeakerName *string
	DivisionInProgress bool
	SourceURL          string
	SourceSnapshot     json.RawMessage
	CheckedAt          time.Time
	LastChangedAt      *time.Time
	SittingDate        *string
}

func Connect(t testing.TB) *pgx.Conn {
	t.Helper()

	connStr := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL"))
	if connStr == "" {
		connStr = strings.TrimSpace(os.Getenv("DATABASE_URL"))
	}
	if connStr == "" {
		t.Fatal(`integration DB URL missing: set TEST_DATABASE_URL or DATABASE_URL`)
	}

	conn, err := pgx.Connect(context.Background(), connStr)
	if err != nil {
		t.Fatalf("connect to database: %v", err)
	}
	t.Cleanup(func() {
		_ = conn.Close(context.Background())
	})
	return conn
}

func ApplyLiveStatusMigrations(ctx context.Context, conn *pgx.Conn) error {
	for _, name := range []string{
		"007_live_session.sql",
		"008_live_session_sitting_date.sql",
	} {
		path := filepath.Join(testRoot(), "migrations", name)
		sql, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", name, err)
		}
		if _, err := conn.Exec(ctx, string(sql)); err != nil {
			return fmt.Errorf("apply migration %s: %w", name, err)
		}
	}
	return nil
}

func ClearLiveSessionRows(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `TRUNCATE TABLE live_session`)
	return err
}

func SeedLiveSession(ctx context.Context, conn *pgx.Conn, row LiveSessionRow) error {
	sourceURL := strings.TrimSpace(row.SourceURL)
	if sourceURL == "" {
		sourceURL = "https://www.ourcommons.ca/en"
	}
	snapshot := []byte("{}")
	if len(row.SourceSnapshot) > 0 {
		snapshot = row.SourceSnapshot
	}
	checkedAt := row.CheckedAt
	if checkedAt.IsZero() {
		checkedAt = time.Now().UTC()
	}

	_, err := conn.Exec(ctx, `
		INSERT INTO live_session (
			is_sitting, business_type, current_item_title, current_bill_number,
			current_speaker_name, division_in_progress, source_url, source_snapshot,
			last_polled_at, last_changed_at, sitting_date
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10, $11)
	`, row.IsSitting, row.BusinessType, row.CurrentItemTitle, row.CurrentBillNumber,
		row.CurrentSpeakerName, row.DivisionInProgress, sourceURL, string(snapshot),
		checkedAt, row.LastChangedAt, row.SittingDate)
	return err
}

func CountLiveSessionRows(ctx context.Context, conn *pgx.Conn) (int, error) {
	var count int
	err := conn.QueryRow(ctx, `SELECT COUNT(*) FROM live_session`).Scan(&count)
	return count, err
}

func testRoot() string {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		panic("unable to resolve test db file path")
	}
	return filepath.Join(filepath.Dir(file), "..")
}
