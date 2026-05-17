// member-votes-publisher writes per-member recorded-vote artifacts from Aurora.
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

const defaultVotesSourceURL = "https://www.ourcommons.ca/members/en/votes"

func main() {
	if err := run(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "member-votes-publisher: %v\n", err)
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

	memberIDs, err := voteMemberIDs(ctx, conn)
	if err != nil {
		return err
	}

	var artifactCount int
	for _, memberID := range memberIDs {
		artifact, err := loadMemberVoteArtifact(ctx, conn, memberID)
		if err != nil {
			return err
		}
		keys, err := membercontent.WriteMemberVotesArtifacts(ctx, store, artifact)
		if err != nil {
			return fmt.Errorf("write artifacts for member %s: %w", memberID, err)
		}
		artifactCount += len(keys)
	}

	fmt.Fprintf(os.Stderr, "published member votes for %d members (%d artifacts)\n", len(memberIDs), artifactCount)
	return nil
}

func voteMemberIDs(ctx context.Context, conn *pgx.Conn) ([]string, error) {
	rows, err := conn.Query(ctx, `
		SELECT DISTINCT member_id::text
		FROM member_votes
		WHERE member_id IS NOT NULL
		ORDER BY member_id::text`)
	if err != nil {
		return nil, fmt.Errorf("query vote member ids: %w", err)
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

func loadMemberVoteArtifact(ctx context.Context, conn *pgx.Conn, memberID string) (membercontent.MemberVotesArtifact, error) {
	rows, err := conn.Query(ctx, `
		SELECT mv.vote_id::text,
		       rv.date,
		       COALESCE(rv.bill_number_code, '') AS bill_number,
		       COALESCE(rv.description_en, '') AS summary,
		       mv.recorded_vote,
		       COALESCE(rv.source_url, '') AS source_url
		FROM member_votes mv
		LEFT JOIN recorded_votes rv ON rv.vote_id = mv.vote_id
		WHERE mv.member_id::text = $1
		ORDER BY rv.date ASC NULLS LAST, mv.vote_id ASC`,
		memberID,
	)
	if err != nil {
		return membercontent.MemberVotesArtifact{}, fmt.Errorf("query votes for member %s: %w", memberID, err)
	}
	defer rows.Close()

	artifact := membercontent.MemberVotesArtifact{MemberID: memberID}
	for rows.Next() {
		vote, err := scanVoteEntry(rows)
		if err != nil {
			return membercontent.MemberVotesArtifact{}, err
		}
		artifact.Votes = append(artifact.Votes, vote)
	}
	if err := rows.Err(); err != nil {
		return membercontent.MemberVotesArtifact{}, err
	}
	return artifact, nil
}

func scanVoteEntry(rows pgx.Rows) (membercontent.VoteEntry, error) {
	var (
		id         string
		date       *time.Time
		billNumber string
		summary    string
		ballot     string
		sourceURL  string
	)
	if err := rows.Scan(&id, &date, &billNumber, &summary, &ballot, &sourceURL); err != nil {
		return membercontent.VoteEntry{}, err
	}

	if strings.TrimSpace(sourceURL) == "" {
		sourceURL = defaultVotesSourceURL
	}
	entry := membercontent.VoteEntry{
		VoteID:     id,
		BillNumber: billNumber,
		Summary:    summary,
		Vote:       ballot,
		SourceURL:  sourceURL,
	}
	if date != nil {
		value := date.Format("2006-01-02")
		entry.Date = &value
	}
	return entry, nil
}
