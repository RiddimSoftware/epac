// member-speeches-publisher writes per-member speech artifacts from Aurora.
package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"epac/member-content"
	"github.com/jackc/pgx/v5"
)

func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "member-speeches-publisher: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	connStr := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if connStr == "" {
		return fmt.Errorf("DATABASE_URL not set")
	}

	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return fmt.Errorf("connect database: %w", err)
	}
	defer conn.Close(ctx)

	store, err := membercontent.NewStoreFromEnv(ctx)
	if err != nil {
		return fmt.Errorf("artifact store: %w", err)
	}

	memberIDs, err := speechMemberIDs(ctx, conn)
	if err != nil {
		return err
	}

	var artifactCount int
	for _, memberID := range memberIDs {
		artifact, err := loadMemberSpeechArtifact(ctx, conn, memberID)
		if err != nil {
			return err
		}
		keys, err := membercontent.WriteMemberSpeechesArtifacts(ctx, store, artifact)
		if err != nil {
			return fmt.Errorf("write artifacts for member %s: %w", memberID, err)
		}
		artifactCount += len(keys)
	}

	fmt.Fprintf(os.Stderr, "published member speeches for %d members (%d artifacts)\n", len(memberIDs), artifactCount)
	return nil
}

func speechMemberIDs(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	rows, err := conn.Query(ctx, `
		SELECT DISTINCT member_id
		FROM speeches
		WHERE member_id IS NOT NULL AND member_id <> ''
		ORDER BY member_id`)
	if err != nil {
		return nil, fmt.Errorf("query speech member ids: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return ids, nil
}

func loadMemberSpeechArtifact(ctx context.Context, conn *pgx.Conn, memberID string) (membercontent.MemberSpeechesArtifact, error) {
	rows, err := conn.Query(ctx, `
		SELECT intervention_id, sitting_date, parliament_num, session_num,
		       subject_title, content, word_count, filename, intervention_seq
		FROM speeches
		WHERE member_id = $1
		ORDER BY sitting_date ASC NULLS LAST, intervention_seq ASC`,
		memberID,
	)
	if err != nil {
		return membercontent.MemberSpeechesArtifact{}, fmt.Errorf("query speeches for member %s: %w", memberID, err)
	}
	defer rows.Close()

	artifact := membercontent.MemberSpeechesArtifact{MemberID: memberID}
	for rows.Next() {
		record, err := scanSpeechRecord(rows)
		if err != nil {
			return membercontent.MemberSpeechesArtifact{}, err
		}
		artifact.Speeches = append(artifact.Speeches, record)
	}
	if err := rows.Err(); err != nil {
		return membercontent.MemberSpeechesArtifact{}, err
	}
	artifact.Stats = membercontent.ComputeSpeechStats(artifact.Speeches)
	return artifact, nil
}

func scanSpeechRecord(rows pgx.Rows) (membercontent.SpeechRecord, error) {
	var (
		id           string
		date         *time.Time
		parlNum      *int
		sessNum      *int
		subjectTitle *string
		content      *string
		wordCount    *int
		filename     *string
		seq          *int
	)
	if err := rows.Scan(&id, &date, &parlNum, &sessNum, &subjectTitle, &content, &wordCount, &filename, &seq); err != nil {
		return membercontent.SpeechRecord{}, err
	}

	record := membercontent.SpeechRecord{
		InterventionID:  id,
		ParliamentNum:   parlNum,
		SessionNum:      sessNum,
		SubjectTitle:    subjectTitle,
		WordCount:       wordCount,
		InterventionSeq: seq,
	}
	if filename != nil {
		record.Filename = *filename
	}
	if date != nil {
		value := date.Format("2006-01-02")
		record.SittingDate = &value
	}
	if content != nil {
		record.Preview = membercontent.Preview(*content, 150)
	}
	return record, nil
}
