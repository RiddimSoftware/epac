// Package postgres is the Postgres-backed adapter satisfying the
// member-speeches HansardRepository port. SQL semantics are preserved
// exactly as they were before the boundary was introduced; only the
// location of the code changed.
package postgres

import (
	"context"
	"time"

	"epac/member-speeches/internal/usecase"

	"github.com/jackc/pgx/v5"
)

type HansardRepository struct {
	conn *pgx.Conn
}

func NewHansardRepository(conn *pgx.Conn) *HansardRepository {
	return &HansardRepository{conn: conn}
}

func (r *HansardRepository) CountMemberSpeeches(ctx context.Context, memberId, topic string) (int, error) {
	var total int
	var err error
	if topic != "" {
		err = r.conn.QueryRow(ctx,
			`SELECT COUNT(*) FROM speeches WHERE member_id = $1 AND subject_title ILIKE $2`,
			memberId, "%"+topic+"%",
		).Scan(&total)
	} else {
		err = r.conn.QueryRow(ctx,
			`SELECT COUNT(*) FROM speeches WHERE member_id = $1`,
			memberId,
		).Scan(&total)
	}
	return total, err
}

func (r *HansardRepository) FetchMemberSpeeches(ctx context.Context, memberId string, page, perPage int, topic string) ([]usecase.SpeechEntry, error) {
	offset := (page - 1) * perPage

	var rows pgx.Rows
	var err error
	if topic != "" {
		rows, err = r.conn.Query(ctx, `
			SELECT intervention_id, sitting_date, parliament_num, session_num,
			       subject_title, content, word_count, filename
			FROM speeches
			WHERE member_id = $1 AND subject_title ILIKE $2
			ORDER BY sitting_date DESC NULLS LAST, intervention_seq ASC
			LIMIT $3 OFFSET $4`,
			memberId, "%"+topic+"%", perPage, offset,
		)
	} else {
		rows, err = r.conn.Query(ctx, `
			SELECT intervention_id, sitting_date, parliament_num, session_num,
			       subject_title, content, word_count, filename
			FROM speeches
			WHERE member_id = $1
			ORDER BY sitting_date DESC NULLS LAST, intervention_seq ASC
			LIMIT $2 OFFSET $3`,
			memberId, perPage, offset,
		)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	speeches := make([]usecase.SpeechEntry, 0)
	for rows.Next() {
		var (
			id           string
			date         *time.Time
			parlNum      *int
			sessNum      *int
			subjectTitle *string
			content      *string
			wordCount    *int
			filename     *string
		)
		if err := rows.Scan(&id, &date, &parlNum, &sessNum, &subjectTitle, &content, &wordCount, &filename); err != nil {
			return nil, err
		}

		entry := usecase.SpeechEntry{
			InterventionId: id,
			ParliamentNum:  parlNum,
			SessionNum:     sessNum,
			SubjectTitle:   subjectTitle,
			WordCount:      wordCount,
		}
		if filename != nil {
			entry.Filename = *filename
		}
		if date != nil {
			s := date.Format("2006-01-02")
			entry.SittingDate = &s
		}
		if content != nil {
			runes := []rune(*content)
			if len(runes) > 150 {
				entry.Preview = string(runes[:150])
			} else {
				entry.Preview = *content
			}
		}
		speeches = append(speeches, entry)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return speeches, nil
}

func (r *HansardRepository) MemberStats(ctx context.Context, memberId string) (usecase.MemberStats, error) {
	stats := usecase.MemberStats{}
	r.conn.QueryRow(ctx, `
		SELECT
			COUNT(*),
			COALESCE(AVG(word_count)::int, 0)
		FROM speeches
		WHERE member_id = $1`, memberId,
	).Scan(&stats.TotalSpeeches, &stats.AvgWordCount)

	r.conn.QueryRow(ctx, `
		SELECT COALESCE(subject_title, '')
		FROM speeches
		WHERE member_id = $1 AND subject_title IS NOT NULL AND subject_title != ''
		GROUP BY subject_title
		ORDER BY COUNT(*) DESC
		LIMIT 1`, memberId,
	).Scan(&stats.TopTopic)

	return stats, nil
}
