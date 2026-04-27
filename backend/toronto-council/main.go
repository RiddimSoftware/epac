package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// VoteRecord matches the Open Data Toronto current-term voting record dataset.
type VoteRecord struct {
	SourceID         string
	AgendaItemNumber string
	AgendaItemTitle  string
	MotionType       string
	VoteDescription  string
	Result           string
	VoteDate         time.Time
	CouncillorFirst  string
	CouncillorLast   string
	VoteDetail       string
	Category         string
}

const pipelineName = "toronto-council-votes"
const voteResourceID = "55ead013-2331-4686-9895-9e8145b94189"
const openDataBaseURL = "https://ckan0.cf.opendata.inter.prod-toronto.ca/api/3/action/datastore_search"
const sourceURL = "https://open.toronto.ca/dataset/members-of-toronto-city-council-voting-record/"

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
		schemaErr := fmt.Errorf("failed to ensure schema: %w", err)
		recordHealth(ctx, conn, 0, schemaErr)
		return schemaErr
	}

	votes, err := fetchVotes(5000)
	if err != nil {
		fetchErr := fmt.Errorf("failed to fetch Toronto council votes: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}
	if len(votes) == 0 {
		fmt.Println("No Toronto council votes returned from Open Data Toronto.")
		recordHealth(ctx, conn, 0, nil)
		return nil
	}

	n, err := upsertVotes(ctx, conn, votes)
	if err != nil {
		insertErr := fmt.Errorf("failed to upsert Toronto council votes: %w", err)
		recordHealth(ctx, conn, 0, insertErr)
		return insertErr
	}

	recordHealth(ctx, conn, n, nil)
	fmt.Printf("Successfully upserted %d Toronto council vote records\n", n)
	return nil
}

func ensureSchema(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS toronto_council_votes (
			vote_id            TEXT NOT NULL,
			source_id          TEXT NOT NULL,
			agenda_item_number TEXT NOT NULL,
			agenda_item_title  TEXT NOT NULL,
			motion_type        TEXT NOT NULL DEFAULT '',
			vote_description   TEXT NOT NULL DEFAULT '',
			result             TEXT NOT NULL DEFAULT '',
			vote_date          TIMESTAMPTZ,
			councillor_first   TEXT NOT NULL,
			councillor_last    TEXT NOT NULL,
			vote_detail        TEXT NOT NULL,
			category           TEXT NOT NULL DEFAULT 'Other',
			source_url         TEXT NOT NULL,
			PRIMARY KEY (vote_id)
		);
		CREATE INDEX IF NOT EXISTS idx_tcv_agenda_item ON toronto_council_votes(agenda_item_number);
		CREATE INDEX IF NOT EXISTS idx_tcv_vote_date   ON toronto_council_votes(vote_date DESC);
		CREATE INDEX IF NOT EXISTS idx_tcv_category    ON toronto_council_votes(category);
	`)
	return err
}

func fetchVotes(pageSize int) ([]VoteRecord, error) {
	var all []VoteRecord
	for offset := 0; ; offset += pageSize {
		page, err := fetchVotesPage(pageSize, offset)
		if err != nil {
			return nil, err
		}
		all = append(all, page...)
		if len(page) < pageSize {
			return all, nil
		}
	}
}

func fetchVotesPage(limit int, offset int) ([]VoteRecord, error) {
	u, err := url.Parse(openDataBaseURL)
	if err != nil {
		return nil, err
	}
	q := u.Query()
	q.Set("resource_id", voteResourceID)
	q.Set("limit", fmt.Sprintf("%d", limit))
	q.Set("offset", fmt.Sprintf("%d", offset))
	q.Set("sort", "Date/Time desc")
	u.RawQuery = q.Encode()

	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", u.String(), nil)
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
		return nil, fmt.Errorf("unexpected status from Open Data Toronto: %d", resp.StatusCode)
	}

	return parseVotes(resp.Body)
}

func parseVotes(r io.Reader) ([]VoteRecord, error) {
	var payload struct {
		Result struct {
			Records []map[string]any `json:"records"`
		} `json:"result"`
	}
	if err := json.NewDecoder(r).Decode(&payload); err != nil {
		return nil, fmt.Errorf("failed to decode Open Data Toronto response: %w", err)
	}

	var votes []VoteRecord
	for _, rec := range payload.Result.Records {
		sourceID := fmt.Sprint(rec["_id"])
		first := stringField(rec, "First Name")
		last := stringField(rec, "Last Name")
		itemNumber := stringField(rec, "Agenda Item #")
		title := stringField(rec, "Agenda Item Title")
		vote := normalizeVote(stringField(rec, "Vote"))
		if sourceID == "" || first == "" || last == "" || itemNumber == "" || title == "" || vote == "" {
			continue
		}
		description := stringField(rec, "Vote Description")
		votes = append(votes, VoteRecord{
			SourceID:         sourceID,
			AgendaItemNumber: itemNumber,
			AgendaItemTitle:  title,
			MotionType:       stringField(rec, "Motion Type"),
			VoteDescription:  description,
			Result:           stringField(rec, "Result"),
			VoteDate:         parseTorontoDate(stringField(rec, "Date/Time")),
			CouncillorFirst:  first,
			CouncillorLast:   last,
			VoteDetail:       vote,
			Category:         classifyVote(title + " " + description),
		})
	}
	return votes, nil
}

func stringField(m map[string]any, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return strings.TrimSpace(s)
		}
		return strings.TrimSpace(fmt.Sprint(v))
	}
	return ""
}

func parseTorontoDate(value string) time.Time {
	value = strings.TrimSpace(value)
	withoutMeridiem := strings.TrimSuffix(strings.TrimSuffix(value, " AM"), " PM")
	location, _ := time.LoadLocation("America/Toronto")
	for _, candidate := range []string{value, withoutMeridiem} {
		for _, layout := range []string{"2006-01-02 15:04 PM", "2006-01-02 3:04 PM", "2006-01-02 15:04", "2006-01-02"} {
			if t, err := time.ParseInLocation(layout, candidate, location); err == nil {
				return t
			}
		}
	}
	return time.Time{}
}

func normalizeVote(vote string) string {
	switch strings.ToLower(strings.TrimSpace(vote)) {
	case "yes":
		return "Yes"
	case "no":
		return "No"
	case "absent":
		return "Absent"
	default:
		if strings.Contains(strings.ToLower(vote), "conflict") {
			return "Conflict"
		}
		return strings.TrimSpace(vote)
	}
}

func classifyVote(title string) string {
	t := strings.ToLower(title)
	switch {
	case contains(t, "housing", "rental", "affordable", "tenant"):
		return "Housing"
	case contains(t, "zoning", "rezoning", "development", "heritage"):
		return "Development"
	case contains(t, "transit", "transportation", "bike", "cycling", "traffic", "parking"):
		return "Transportation"
	case contains(t, "environment", "climate", "tree", "park", "green"):
		return "Environment"
	case contains(t, "budget", "finance", "tax", "fee", "grant"):
		return "Finance"
	case contains(t, "homelessness", "shelter", "social", "community", "food"):
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
		id := fmt.Sprintf("%s-%s-%s", v.AgendaItemNumber, v.SourceID, strings.ToLower(v.CouncillorLast))
		var voteDate *time.Time
		if !v.VoteDate.IsZero() {
			voteDate = &v.VoteDate
		}
		batch.Queue(`
			INSERT INTO toronto_council_votes (
				vote_id, source_id, agenda_item_number, agenda_item_title,
				motion_type, vote_description, result, vote_date,
				councillor_first, councillor_last, vote_detail, category, source_url
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			ON CONFLICT (vote_id) DO UPDATE SET
				agenda_item_title = EXCLUDED.agenda_item_title,
				motion_type       = EXCLUDED.motion_type,
				vote_description  = EXCLUDED.vote_description,
				result            = EXCLUDED.result,
				vote_date         = EXCLUDED.vote_date,
				vote_detail       = EXCLUDED.vote_detail,
				category          = EXCLUDED.category,
				source_url        = EXCLUDED.source_url`,
			id, v.SourceID, v.AgendaItemNumber, v.AgendaItemTitle,
			v.MotionType, v.VoteDescription, v.Result, voteDate,
			v.CouncillorFirst, v.CouncillorLast, v.VoteDetail, v.Category, sourceURL,
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
