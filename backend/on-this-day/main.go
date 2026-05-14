// on-this-day Lambda - GET /api/v1/on-this-day?date=YYYY-MM-DD&limit=5
//
// Returns prior-year Hansard moments from the same calendar day, ranked toward
// current MPs and speeches linked to bills or recorded votes.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

const (
	defaultLimit = 5
	maxLimit     = 20
)

type OnThisDayItem struct {
	ID             string  `json:"id"`
	Kind           string  `json:"kind"`
	Year           int     `json:"year"`
	Date           string  `json:"date"`
	Title          string  `json:"title"`
	Excerpt        string  `json:"excerpt"`
	SpeakerName    *string `json:"speaker_name,omitempty"`
	MemberID       *string `json:"member_id,omitempty"`
	SubjectTitle   *string `json:"subject_title,omitempty"`
	InterventionID *string `json:"intervention_id,omitempty"`
	SourceURL      *string `json:"source_url,omitempty"`
}

type OnThisDayResponse struct {
	Date  string          `json:"date"`
	Items []OnThisDayItem `json:"items"`
}

var dbConn *pgx.Conn

func getDBConn(ctx context.Context) (*pgx.Conn, error) {
	if dbConn != nil {
		if err := dbConn.Ping(ctx); err == nil {
			return dbConn, nil
		}
		dbConn.Close(ctx)
		dbConn = nil
	}
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return nil, fmt.Errorf("DATABASE_URL not set")
	}
	var err error
	dbConn, err = pgx.Connect(ctx, connStr)
	return dbConn, err
}

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	date, err := parseDate(req.QueryStringParameters["date"])
	if err != nil {
		return jsonError(http.StatusBadRequest, "date must be YYYY-MM-DD"), nil
	}
	limit := parseLimit(req.QueryStringParameters["limit"])

	conn, err := getDBConn(ctx)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	items, err := queryOnThisDay(ctx, conn, date, limit)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}
	if items == nil {
		items = []OnThisDayItem{}
	}

	body, err := json.Marshal(OnThisDayResponse{
		Date:  date.Format("2006-01-02"),
		Items: items,
	})
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
}

func parseDate(value string) (time.Time, error) {
	if value == "" {
		return time.Now().UTC(), nil
	}
	if len(value) != len("2006-01-02") {
		return time.Time{}, fmt.Errorf("invalid date")
	}
	date, err := time.Parse("2006-01-02", value)
	if err != nil {
		return time.Time{}, err
	}
	return date, nil
}

func parseLimit(value string) int {
	limit := defaultLimit
	if value != "" {
		if parsed, err := strconv.Atoi(value); err == nil && parsed > 0 {
			limit = parsed
		}
	}
	if limit > maxLimit {
		return maxLimit
	}
	return limit
}

func queryOnThisDay(ctx context.Context, conn *pgx.Conn, date time.Time, limit int) ([]OnThisDayItem, error) {
	rows, err := conn.Query(ctx, `
		SELECT
			s.intervention_id,
			EXTRACT(YEAR FROM s.sitting_date)::int AS year,
			s.sitting_date,
			COALESCE(s.speaker_name, ''),
			COALESCE(s.subject_title, ''),
			COALESCE(s.content, ''),
			s.member_id,
			s.source_url
		FROM speeches s
		LEFT JOIN members m ON m.person_id = s.member_id
		WHERE s.sitting_date IS NOT NULL
			AND EXTRACT(MONTH FROM s.sitting_date) = EXTRACT(MONTH FROM $1::date)
			AND EXTRACT(DAY FROM s.sitting_date) = EXTRACT(DAY FROM $1::date)
			AND s.sitting_date < $1::date
			AND COALESCE(s.content, '') <> ''
		ORDER BY
			CASE WHEN m.person_id IS NOT NULL AND (m.to_date IS NULL OR m.to_date >= CURRENT_DATE) THEN 1 ELSE 0 END DESC,
			COALESCE(cardinality(s.related_bill_ids), 0) DESC,
			COALESCE(cardinality(s.related_vote_ids), 0) DESC,
			s.sitting_date DESC,
			s.intervention_seq ASC NULLS LAST
		LIMIT $2`,
		date.Format("2006-01-02"), limit,
	)
	if err != nil && isOptionalRankingSchemaError(err) {
		rows, err = conn.Query(ctx, `
			SELECT
				s.intervention_id,
				EXTRACT(YEAR FROM s.sitting_date)::int AS year,
				s.sitting_date,
				COALESCE(s.speaker_name, ''),
				COALESCE(s.subject_title, ''),
				COALESCE(s.content, ''),
				s.member_id,
				s.source_url
			FROM speeches s
			WHERE s.sitting_date IS NOT NULL
				AND EXTRACT(MONTH FROM s.sitting_date) = EXTRACT(MONTH FROM $1::date)
				AND EXTRACT(DAY FROM s.sitting_date) = EXTRACT(DAY FROM $1::date)
				AND s.sitting_date < $1::date
				AND COALESCE(s.content, '') <> ''
			ORDER BY
				s.sitting_date DESC,
				s.intervention_seq ASC NULLS LAST
			LIMIT $2`,
			date.Format("2006-01-02"), limit,
		)
	}
	if err != nil {
		return nil, fmt.Errorf("on-this-day query error: %w", err)
	}
	defer rows.Close()

	items := make([]OnThisDayItem, 0)
	for rows.Next() {
		item, err := scanSpeechItem(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}
	return items, nil
}

func isOptionalRankingSchemaError(err error) bool {
	message := err.Error()
	return strings.Contains(message, "related_") || strings.Contains(message, `relation "members" does not exist`)
}

type speechRow interface {
	Scan(dest ...any) error
}

func scanSpeechItem(row speechRow) (OnThisDayItem, error) {
	var (
		id           string
		year         int
		date         time.Time
		speakerName  string
		subjectTitle string
		content      string
		memberID     *string
		sourceURL    *string
	)
	if err := row.Scan(&id, &year, &date, &speakerName, &subjectTitle, &content, &memberID, &sourceURL); err != nil {
		return OnThisDayItem{}, fmt.Errorf("scan speech item: %w", err)
	}
	title := subjectTitle
	if title == "" {
		title = "Hansard speech"
	}
	return OnThisDayItem{
		ID:             "speech:" + id,
		Kind:           "speech",
		Year:           year,
		Date:           date.Format("2006-01-02"),
		Title:          title,
		Excerpt:        oneLineExcerpt(content, 180),
		SpeakerName:    stringPtrIfNotEmpty(speakerName),
		MemberID:       memberID,
		SubjectTitle:   stringPtrIfNotEmpty(subjectTitle),
		InterventionID: stringPtrIfNotEmpty(id),
		SourceURL:      sourceURL,
	}, nil
}

func oneLineExcerpt(value string, maxRunes int) string {
	cleaned := strings.Join(strings.Fields(value), " ")
	if maxRunes <= 0 || utf8.RuneCountInString(cleaned) <= maxRunes {
		return cleaned
	}
	runes := []rune(cleaned)
	truncated := strings.TrimSpace(string(runes[:maxRunes]))
	if idx := strings.LastIndex(truncated, " "); idx > 0 {
		truncated = truncated[:idx]
	}
	return truncated + "..."
}

func stringPtrIfNotEmpty(value string) *string {
	if value == "" {
		return nil
	}
	return &value
}

func jsonError(status int, msg string) events.APIGatewayProxyResponse {
	body, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}
}

func main() {
	lambda.Start(observability.WrapAPIGateway("on-this-day", HandleRequest))
}
