package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// VoteRecord matches the Vancouver Open Data council-voting-records dataset.
type VoteRecord struct {
	VoteNumber      string
	MotionTitle     string
	VoteDate        time.Time
	CouncillorFirst string
	CouncillorLast  string
	VoteDetail      string // "In Favour", "Opposed", "Absent", "Abstain"
	Category        string
}

const pipelineName = "vancouver-council-votes"

// Vancouver Open Data ODATA v2.1 API endpoint for council voting records.
const openDataURL = "https://opendata.vancouver.ca/api/explore/v2.1/catalog/datasets/council-voting-records/records?limit=100&order_by=vote_date%20desc"

func main() {
	lambda.Start(observability.WrapNoEvent(pipelineName, HandleRequest))
}

func recordHealth(ctx context.Context, conn *pgx.Conn, count int, runErr error) {
	now := time.Now().UTC()
	var errMsg *string
	var successAt *time.Time
	var recordCount *int
	if runErr == nil {
		successAt = &now
		recordCount = &count
	} else {
		s := runErr.Error()
		errMsg = &s
	}
	_, _ = conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_success_at, last_error, record_count, expected_interval_hours)
		VALUES ($1, $2, $3, $4, $5, 24)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, now, successAt, errMsg, recordCount)
}

func HandleRequest(ctx context.Context) error {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return fmt.Errorf("DATABASE_URL environment variable is not set")
	}

	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return fmt.Errorf("unable to connect to database: %w", err)
	}
	defer conn.Close(ctx)

	if err := ensureSchema(ctx, conn); err != nil {
		fetchErr := fmt.Errorf("failed to ensure schema: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}

	votes, err := fetchVotes()
	if err != nil {
		fetchErr := fmt.Errorf("failed to fetch Vancouver council votes: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}

	if len(votes) == 0 {
		fmt.Println("No Vancouver council votes returned from Open Data portal.")
		recordHealth(ctx, conn, 0, nil)
		return nil
	}

	n, err := upsertVotes(ctx, conn, votes)
	if err != nil {
		insertErr := fmt.Errorf("failed to upsert Vancouver council votes: %w", err)
		recordHealth(ctx, conn, 0, insertErr)
		return insertErr
	}

	recordHealth(ctx, conn, n, nil)
	fmt.Printf("Successfully upserted %d Vancouver council vote records\n", n)
	return nil
}

// ensureSchema creates the vancouver_council_votes table if it doesn't exist.
func ensureSchema(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS vancouver_council_votes (
			vote_id           TEXT NOT NULL,
			vote_number       TEXT NOT NULL,
			motion_title      TEXT NOT NULL,
			vote_date         DATE,
			councillor_first  TEXT NOT NULL,
			councillor_last   TEXT NOT NULL,
			vote_detail       TEXT NOT NULL,
			category          TEXT NOT NULL DEFAULT 'Other',
			PRIMARY KEY (vote_id)
		);
		CREATE INDEX IF NOT EXISTS idx_vcv_vote_number ON vancouver_council_votes(vote_number);
		CREATE INDEX IF NOT EXISTS idx_vcv_vote_date   ON vancouver_council_votes(vote_date DESC);
		CREATE INDEX IF NOT EXISTS idx_vcv_category    ON vancouver_council_votes(category);
	`)
	return err
}

// fetchVotes retrieves recent vote records from Vancouver Open Data.
func fetchVotes() ([]VoteRecord, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", openDataURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "epac-civic/1.0 (civic engagement app; contact: sunny)")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status from Vancouver Open Data: %d", resp.StatusCode)
	}

	return parseVotes(resp.Body)
}

func parseVotes(r io.Reader) ([]VoteRecord, error) {
	var payload struct {
		Results []map[string]any `json:"results"`
	}
	if err := json.NewDecoder(r).Decode(&payload); err != nil {
		return nil, fmt.Errorf("failed to decode Vancouver Open Data response: %w", err)
	}

	dateParser := func(s string) time.Time {
		// Try RFC3339 first (with or without fractional seconds)
		for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02"} {
			if t, err := time.Parse(layout, s); err == nil {
				return t
			}
		}
		return time.Time{}
	}

	var votes []VoteRecord
	for _, rec := range payload.Results {
		voteNum  := stringField(rec, "vote_number")
		title    := stringField(rec, "agenda_description")
		first    := stringField(rec, "vote_first_name")
		last     := stringField(rec, "vote_last_name")
		detail   := stringField(rec, "vote_detail")
		dateStr  := stringField(rec, "vote_date")
		if voteNum == "" || first == "" || last == "" || detail == "" {
			continue
		}
		voteDate := dateParser(dateStr)
		votes = append(votes, VoteRecord{
			VoteNumber:      voteNum,
			MotionTitle:     title,
			VoteDate:        voteDate,
			CouncillorFirst: first,
			CouncillorLast:  last,
			VoteDetail:      detail,
			Category:        classifyVote(title),
		})
	}
	return votes, nil
}

func stringField(m map[string]any, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return strings.TrimSpace(s)
		}
	}
	return ""
}

// classifyVote maps a motion title to a topic category.
func classifyVote(title string) string {
	t := strings.ToLower(title)
	switch {
	case contains(t, "housing", "rental", "affordable"):
		return "Housing"
	case contains(t, "zoning", "rezoning", "development", "heritage"):
		return "Development"
	case contains(t, "transit", "transportation", "bike", "cycling", "traffic"):
		return "Transportation"
	case contains(t, "environment", "climate", "tree", "park", "green"):
		return "Environment"
	case contains(t, "budget", "finance", "tax", "fee", "grant"):
		return "Finance"
	case contains(t, "homelessness", "shelter", "social", "community"):
		return "Social Services"
	default:
		return "Other"
	}
}

func contains(s string, keywords ...string) bool {
	for _, kw := range keywords {
		if strings.Contains(s, kw) {
			return true
		}
	}
	return false
}

func upsertVotes(ctx context.Context, conn *pgx.Conn, votes []VoteRecord) (int, error) {
	batch := &pgx.Batch{}
	valid := 0
	for _, v := range votes {
		id := fmt.Sprintf("%s-%s", v.VoteNumber, strings.ToLower(v.CouncillorLast))
		var voteDate *time.Time
		if !v.VoteDate.IsZero() {
			voteDate = &v.VoteDate
		}
		batch.Queue(`
			INSERT INTO vancouver_council_votes (
				vote_id, vote_number, motion_title, vote_date,
				councillor_first, councillor_last, vote_detail, category
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
			ON CONFLICT (vote_id) DO UPDATE SET
				motion_title     = EXCLUDED.motion_title,
				vote_date        = EXCLUDED.vote_date,
				vote_detail      = EXCLUDED.vote_detail,
				category         = EXCLUDED.category`,
			id, v.VoteNumber, v.MotionTitle, voteDate,
			v.CouncillorFirst, v.CouncillorLast, v.VoteDetail, v.Category,
		)
		valid++
	}

	br := conn.SendBatch(ctx, batch)
	defer br.Close()

	inserted := 0
	for i := 0; i < valid; i++ {
		if _, err := br.Exec(); err != nil {
			return inserted, err
		}
		inserted++
	}
	return inserted, nil
}
