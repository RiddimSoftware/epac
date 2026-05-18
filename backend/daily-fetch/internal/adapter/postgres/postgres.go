// Package postgres is the Postgres-backed adapter satisfying the daily-fetch
// HansardRepository port. SQL semantics are preserved exactly as they were
// before the boundary was introduced; only the location of the code changed.
package postgres

import (
	"context"
	"errors"
	"os"
	"time"

	"daily-fetch/internal/usecase"

	"github.com/jackc/pgx/v5"
)

const pipelineName = "hansard-daily-fetch"

func Connect(ctx context.Context) (*pgx.Conn, error) {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, errors.New("DATABASE_URL environment variable is not set")
	}
	return pgx.Connect(ctx, connStr)
}

type HansardRepository struct {
	conn *pgx.Conn
}

func NewHansardRepository(conn *pgx.Conn) *HansardRepository {
	return &HansardRepository{conn: conn}
}

func (r *HansardRepository) LastSitting(ctx context.Context, parliamentNum, sessionNum int) (int, error) {
	var lastSitting int
	err := r.conn.QueryRow(ctx, `
		SELECT COALESCE(MAX(CAST(substring(filename FROM 'HAN([0-9]+)-E.XML') AS INTEGER)), 0)
		FROM speeches
		WHERE (parliament_num IS NULL OR (parliament_num = $1 AND session_num = $2))`,
		parliamentNum, sessionNum,
	).Scan(&lastSitting)
	return lastSitting, err
}

func (r *HansardRepository) UpsertSpeeches(ctx context.Context, interventions []usecase.Intervention) (int, error) {
	batch := &pgx.Batch{}
	valid := 0
	for _, inv := range interventions {
		if inv.Id == "" || inv.Content == "" {
			continue
		}
		var memberID *string
		if inv.MemberId != "" {
			memberID = &inv.MemberId
		}
		var date *time.Time
		if !inv.SittingDate.IsZero() {
			date = &inv.SittingDate
		}
		var parlNum, sessNum *int
		if inv.ParliamentNum > 0 {
			parlNum = &inv.ParliamentNum
		}
		if inv.SessionNum > 0 {
			sessNum = &inv.SessionNum
		}
		batch.Queue(`
			INSERT INTO speeches (
				intervention_id, filename, speaker_name, content,
				sitting_date, parliament_num, session_num, member_id,
				subject_id, subject_title, intervention_seq, word_count, language
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			ON CONFLICT (intervention_id) DO UPDATE SET
				speaker_name     = EXCLUDED.speaker_name,
				content          = EXCLUDED.content,
				sitting_date     = EXCLUDED.sitting_date,
				parliament_num   = EXCLUDED.parliament_num,
				session_num      = EXCLUDED.session_num,
				member_id        = EXCLUDED.member_id,
				subject_id       = EXCLUDED.subject_id,
				subject_title    = EXCLUDED.subject_title,
				intervention_seq = EXCLUDED.intervention_seq,
				word_count       = EXCLUDED.word_count,
				language         = EXCLUDED.language`,
			inv.Id, inv.Filename, inv.Speaker, inv.Content,
			date, parlNum, sessNum, memberID,
			inv.SubjectID, inv.SubjectTitle, inv.InterventionSeq, inv.WordCount, usecase.NormalizeLanguage(inv.Language),
		)
		valid++
	}

	results := r.conn.SendBatch(ctx, batch)
	defer results.Close()

	inserted := 0
	for i := 0; i < valid; i++ {
		if _, err := results.Exec(); err != nil {
			return inserted, err
		}
		inserted++
	}
	return inserted, nil
}

func (r *HansardRepository) RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time) {
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
		VALUES ($1, $2, $3, $4, $5, 24)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, recordedAt.UTC(), successAt, errMsg, recordCount)
}
