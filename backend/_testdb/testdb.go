package _testdb

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
)

var migrated sync.Once

const baseSchema = `
CREATE TABLE IF NOT EXISTS pipeline_health (
    name                    TEXT PRIMARY KEY,
    last_run_at             TIMESTAMPTZ,
    last_success_at         TIMESTAMPTZ,
    last_error              TEXT,
    record_count            INTEGER,
    expected_interval_hours INTEGER NOT NULL DEFAULT 24
);
CREATE TABLE IF NOT EXISTS members (
    person_id     TEXT PRIMARY KEY,
    honorific     TEXT,
    first_name    TEXT,
    last_name     TEXT,
    constituency  TEXT,
    province      TEXT,
    caucus        TEXT,
    from_date     TIMESTAMP,
    to_date       TIMESTAMP
);
CREATE TABLE IF NOT EXISTS speeches (
    intervention_id  TEXT PRIMARY KEY,
    filename         TEXT,
    speaker_name     TEXT,
    content          TEXT,
    sitting_date     DATE,
    parliament_num   INT,
    session_num      INT,
    member_id        TEXT,
    subject_title    TEXT,
    intervention_seq INT,
    word_count       INT
);
`

// Connect returns a pgx connection to the test database and applies migrations if this is the first call.
func Connect(t *testing.T) *pgx.Conn {
	t.Helper()

	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		t.Skip("DATABASE_URL not set; skipping integration test")
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		t.Fatalf("failed to connect to test db: %v", err)
	}

	migrated.Do(func() {
		if _, err := conn.Exec(ctx, baseSchema); err != nil {
			t.Fatalf("failed to apply base schema: %v", err)
		}

		_, filename, _, _ := runtime.Caller(0)
		migrationsDir := filepath.Join(filepath.Dir(filename), "..", "migrations")

		files, err := filepath.Glob(filepath.Join(migrationsDir, "*.sql"))
		if err != nil {
			t.Fatalf("failed to glob migration files: %v", err)
		}
		sort.Strings(files)

		for _, file := range files {
			sqlBytes, err := os.ReadFile(file)
			if err != nil {
				t.Fatalf("failed to read migration %s: %v", file, err)
			}
			if _, err := conn.Exec(ctx, string(sqlBytes)); err != nil {
				t.Fatalf("failed to apply migration %s: %v", filepath.Base(file), err)
			}
		}
	})

	t.Cleanup(func() {
		conn.Close(ctx)
	})

	return conn
}

// WithTx runs the provided function inside a transaction that is rolled back at the end of the test.
// We use raw BEGIN/ROLLBACK so that the raw *pgx.Conn can still be passed to handlers that expect it.
func WithTx(t *testing.T, fn func(*pgx.Conn)) {
	t.Helper()
	conn := Connect(t)
	ctx := context.Background()

	if _, err := conn.Exec(ctx, "BEGIN"); err != nil {
		t.Fatalf("failed to begin transaction: %v", err)
	}

	t.Cleanup(func() {
		conn.Exec(ctx, "ROLLBACK")
	})

	fn(conn)
}

// SeedSpeech creates a fixture row in the speeches table.
func SeedSpeech(t *testing.T, conn *pgx.Conn, interventionID, content, speakerName, memberID, subjectTitle string, sittingDate *time.Time) {
	t.Helper()
	ctx := context.Background()

	// language defaults to 'en', which sets up search_vector_en automatically due to GENERATED ALWAYS.
	_, err := conn.Exec(ctx, `
		INSERT INTO speeches (intervention_id, content, speaker_name, member_id, subject_title, sitting_date)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, interventionID, content, speakerName, memberID, subjectTitle, sittingDate)
	if err != nil {
		t.Fatalf("failed to seed speech: %v", err)
	}
}

// SeedDeviceSubscription creates a fixture row in the device_subscriptions table.
func SeedDeviceSubscription(t *testing.T, conn *pgx.Conn, token, myMPMemberID string, topicIDs, billIDs []string) {
	t.Helper()
	ctx := context.Background()

	if topicIDs == nil {
		topicIDs = []string{}
	}
	if billIDs == nil {
		billIDs = []string{}
	}

	_, err := conn.Exec(ctx, `
		INSERT INTO device_subscriptions (token, my_mp_member_id, topic_ids, bill_ids)
		VALUES ($1, $2, $3, $4)
	`, token, myMPMemberID, topicIDs, billIDs)
	if err != nil {
		t.Fatalf("failed to seed device subscription: %v", err)
	}
}

// LiveSessionRow represents a row in the live_session cache table.
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

func ClearLiveSessionRows(t *testing.T, conn *pgx.Conn) error {
	t.Helper()
	_, err := conn.Exec(context.Background(), `TRUNCATE TABLE live_session`)
	return err
}

func SeedLiveSession(t *testing.T, conn *pgx.Conn, row LiveSessionRow) error {
	t.Helper()
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

	_, err := conn.Exec(context.Background(), `
		INSERT INTO live_session (
			id, is_sitting, business_type, current_item_title, current_bill_number,
			current_speaker_name, division_in_progress, source_url, source_snapshot,
			last_polled_at, last_changed_at, sitting_date
		)
		VALUES (TRUE, $1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10, $11)
		ON CONFLICT (id) DO UPDATE SET
			is_sitting           = EXCLUDED.is_sitting,
			business_type        = EXCLUDED.business_type,
			current_item_title    = EXCLUDED.current_item_title,
			current_bill_number   = EXCLUDED.current_bill_number,
			current_speaker_name  = EXCLUDED.current_speaker_name,
			division_in_progress = EXCLUDED.division_in_progress,
			source_url           = EXCLUDED.source_url,
			source_snapshot      = EXCLUDED.source_snapshot,
			last_polled_at       = EXCLUDED.last_polled_at,
			last_changed_at      = EXCLUDED.last_changed_at,
			sitting_date         = COALESCE(EXCLUDED.sitting_date, live_session.sitting_date)
	`, row.IsSitting, row.BusinessType, row.CurrentItemTitle, row.CurrentBillNumber, row.CurrentSpeakerName,
		row.DivisionInProgress, sourceURL, string(snapshot), checkedAt, row.LastChangedAt, row.SittingDate)
	if err != nil {
		t.Fatalf("failed to seed live_session row: %v", err)
	}
	return nil
}

func CountLiveSessionRows(t *testing.T, conn *pgx.Conn) (int, error) {
	t.Helper()
	var count int
	err := conn.QueryRow(context.Background(), `SELECT COUNT(*) FROM live_session`).Scan(&count)
	return count, err
}
