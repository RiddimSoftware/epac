package repository

import (
	"context"
	"fmt"
	"time"

	"epac/hansard-subjects-index/application"
	"github.com/jackc/pgx/v5"
)

type Queryer interface {
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type PostgresSubjectsRepository struct {
	db Queryer
}

func NewPostgresSubjectsRepository(db Queryer) *PostgresSubjectsRepository {
	return &PostgresSubjectsRepository{db: db}
}

func (r *PostgresSubjectsRepository) DefaultWindow(ctx context.Context, to time.Time, parliamentCount int) (application.Window, error) {
	if parliamentCount < 1 {
		parliamentCount = application.DefaultParliamentCount
	}

	var maxParliament int
	if err := r.db.QueryRow(ctx, `
		SELECT COALESCE(MAX(parliament_num), 0)
		FROM speeches
		WHERE parliament_num IS NOT NULL
			AND sitting_date IS NOT NULL
			AND sitting_date <= $1::DATE
	`, to).Scan(&maxParliament); err != nil {
		return application.Window{}, fmt.Errorf("load current parliament: %w", err)
	}

	var cutoff *int
	if maxParliament > 0 {
		value := maxParliament - parliamentCount + 1
		cutoff = &value
	}

	var fromDate time.Time
	var toDate time.Time
	if err := r.db.QueryRow(ctx, `
		SELECT COALESCE(MIN(sitting_date), $1::DATE), COALESCE(MAX(sitting_date), $1::DATE)
		FROM speeches
		WHERE sitting_date IS NOT NULL
			AND sitting_date <= $1::DATE
			AND ($2::INT IS NULL OR parliament_num >= $2::INT)
	`, to, cutoff).Scan(&fromDate, &toDate); err != nil {
		return application.Window{}, fmt.Errorf("load default window dates: %w", err)
	}

	return application.Window{From: fromDate, To: toDate, ParliamentCutoff: cutoff}, nil
}

func (r *PostgresSubjectsRepository) ListSubjects(ctx context.Context, window application.Window) ([]application.HansardSubject, error) {
	subjectIDExpr, err := r.subjectIDExpression(ctx)
	if err != nil {
		return nil, err
	}

	rows, err := r.db.Query(ctx, fmt.Sprintf(`
		WITH candidates AS (
			SELECT
				%s AS subject_key,
				BTRIM(subject_title) AS subject_title,
				sitting_date::DATE AS hansard_date,
				intervention_id
			FROM speeches
			WHERE sitting_date IS NOT NULL
				AND sitting_date >= $1::DATE
				AND sitting_date <= $2::DATE
				AND ($3::INT IS NULL OR parliament_num >= $3::INT)
				AND NULLIF(BTRIM(subject_title), '') IS NOT NULL
		),
		deduped AS (
			SELECT
				subject_key,
				(ARRAY_AGG(subject_title ORDER BY hansard_date DESC, intervention_id ASC))[1] AS subject_title,
				MAX(hansard_date) AS hansard_date
			FROM candidates
			GROUP BY subject_key
		)
		SELECT subject_key, subject_title, hansard_date
		FROM deduped
		ORDER BY hansard_date DESC, subject_key ASC
	`, subjectIDExpr), window.From, window.To, window.ParliamentCutoff)
	if err != nil {
		return nil, fmt.Errorf("query subjects: %w", err)
	}
	defer rows.Close()

	var subjects []application.HansardSubject
	for rows.Next() {
		var subject application.HansardSubject
		if err := rows.Scan(&subject.SubjectID, &subject.SubjectTitle, &subject.HansardDate); err != nil {
			return nil, fmt.Errorf("scan subject: %w", err)
		}
		subjects = append(subjects, subject)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate subjects: %w", err)
	}
	return subjects, nil
}

func (r *PostgresSubjectsRepository) subjectIDExpression(ctx context.Context) (string, error) {
	const legacyExpr = "'legacy:' || TO_CHAR(sitting_date, 'YYYY-MM-DD') || ':' || MD5(LOWER(BTRIM(subject_title)))"

	var hasSubjectID bool
	if err := r.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM information_schema.columns
			WHERE table_schema = 'public'
				AND table_name = 'speeches'
				AND column_name = 'subject_id'
		)
	`).Scan(&hasSubjectID); err != nil {
		return "", fmt.Errorf("inspect speeches.subject_id: %w", err)
	}
	if !hasSubjectID {
		return legacyExpr, nil
	}
	return "COALESCE(NULLIF(BTRIM(subject_id), ''), " + legacyExpr + ")", nil
}
