package _testdb

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"sort"
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
