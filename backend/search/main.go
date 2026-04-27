package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// ── Response types ────────────────────────────────────────────────────────────

type SpeechResult struct {
	InterventionId       string `json:"intervention_id"`
	SittingDate          string `json:"sitting_date,omitempty"`
	ParliamentNum        *int   `json:"parliament_num,omitempty"`
	SessionNum           *int   `json:"session_num,omitempty"`
	SpeakerName          string `json:"speaker_name,omitempty"`
	MemberId             string `json:"member_id,omitempty"`
	SubjectTitle         string `json:"subject_title,omitempty"`
	SubjectId            string `json:"subject_id,omitempty"`
	InterventionSequence *int   `json:"intervention_sequence,omitempty"`
	WordCount            *int   `json:"word_count,omitempty"`
	Preview              string `json:"preview"` // first 150 chars of content
	Snippet              string `json:"snippet,omitempty"` // FTS-highlighted snippet (search only)
}

type SearchResponse struct {
	Query   string         `json:"query"`
	Page    int            `json:"page"`
	PerPage int            `json:"per_page"`
	Total   int            `json:"total,omitempty"`
	Results []SpeechResult `json:"results"`
}

type MemberSpeechesResponse struct {
	MemberId string         `json:"member_id"`
	Page     int            `json:"page"`
	PerPage  int            `json:"per_page"`
	Total    int            `json:"total"`
	Speeches []SpeechResult `json:"speeches"`
}

// ── Database connection ───────────────────────────────────────────────────────

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
	if err != nil {
		return nil, fmt.Errorf("unable to connect to database: %w", err)
	}
	return dbConn, nil
}

// ── Queries ───────────────────────────────────────────────────────────────────

var memberPathRE = regexp.MustCompile(`^/api/v1/members/([^/]+)/speeches$`)

// searchSpeeches performs GIN full-text search with headline snippets.
func searchSpeeches(ctx context.Context, conn *pgx.Conn, query string, page, perPage int) ([]SpeechResult, error) {
	offset := (page - 1) * perPage
	rows, err := conn.Query(ctx, `
		SELECT
			intervention_id,
			COALESCE(sitting_date::TEXT, '')    AS sitting_date,
			parliament_num,
			session_num,
			COALESCE(speaker_name, '')          AS speaker_name,
			COALESCE(member_id, '')             AS member_id,
			COALESCE(subject_title, '')         AS subject_title,
			COALESCE(subject_id, '')            AS subject_id,
			intervention_sequence,
			word_count,
			LEFT(content, 150)                  AS preview,
			ts_headline('english', content,
				plainto_tsquery('english', $1),
				'MaxFragments=1,MaxWords=25,MinWords=10'
			)                                   AS snippet
		FROM speeches
		WHERE to_tsvector('english', COALESCE(content, '')) @@ plainto_tsquery('english', $1)
		ORDER BY sitting_date DESC NULLS LAST
		LIMIT $2 OFFSET $3
	`, query, perPage, offset)
	if err != nil {
		return nil, fmt.Errorf("search query error: %w", err)
	}
	defer rows.Close()
	return scanSpeechRows(rows)
}

// memberSpeeches returns paginated speeches for a specific member, most recent first.
func memberSpeeches(ctx context.Context, conn *pgx.Conn, memberId string, page, perPage int) ([]SpeechResult, int, error) {
	offset := (page - 1) * perPage

	var total int
	err := conn.QueryRow(ctx,
		`SELECT COUNT(*) FROM speeches WHERE member_id = $1`,
		memberId,
	).Scan(&total)
	if err != nil {
		return nil, 0, fmt.Errorf("count query error: %w", err)
	}

	rows, err := conn.Query(ctx, `
		SELECT
			intervention_id,
			COALESCE(sitting_date::TEXT, '')    AS sitting_date,
			parliament_num,
			session_num,
			COALESCE(speaker_name, '')          AS speaker_name,
			COALESCE(member_id, '')             AS member_id,
			COALESCE(subject_title, '')         AS subject_title,
			COALESCE(subject_id, '')            AS subject_id,
			intervention_sequence,
			word_count,
			LEFT(content, 150)                  AS preview,
			''                                  AS snippet
		FROM speeches
		WHERE member_id = $1
		ORDER BY sitting_date DESC NULLS LAST, intervention_sequence ASC
		LIMIT $2 OFFSET $3
	`, memberId, perPage, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("member speeches query error: %w", err)
	}
	defer rows.Close()

	results, err := scanSpeechRows(rows)
	return results, total, err
}

func scanSpeechRows(rows pgx.Rows) ([]SpeechResult, error) {
	var results []SpeechResult
	for rows.Next() {
		var r SpeechResult
		var parliNum, sessNum, sequence, wordCount *int
		if err := rows.Scan(
			&r.InterventionId, &r.SittingDate,
			&parliNum, &sessNum,
			&r.SpeakerName, &r.MemberId,
			&r.SubjectTitle, &r.SubjectId,
			&sequence, &wordCount,
			&r.Preview, &r.Snippet,
		); err != nil {
			return nil, fmt.Errorf("scan error: %w", err)
		}
		r.ParliamentNum = parliNum
		r.SessionNum = sessNum
		r.InterventionSequence = sequence
		r.WordCount = wordCount
		results = append(results, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows error: %w", err)
	}
	return results, nil
}

// ── Lambda handler ────────────────────────────────────────────────────────────

func HandleRequest(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	path := req.Path
	params := req.QueryStringParameters

	conn, err := getDBConn(ctx)
	if err != nil {
		return errResponse(http.StatusInternalServerError, err.Error()), nil
	}

	page := intParam(params, "page", 1)
	perPage := intParam(params, "per_page", 20)
	if perPage > 50 {
		perPage = 50
	}

	// Route: GET /api/v1/members/{id}/speeches
	if m := memberPathRE.FindStringSubmatch(path); m != nil {
		memberId := m[1]
		speeches, total, err := memberSpeeches(ctx, conn, memberId, page, perPage)
		if err != nil {
			return errResponse(http.StatusInternalServerError, err.Error()), nil
		}
		if speeches == nil {
			speeches = []SpeechResult{}
		}
		return jsonResponse(MemberSpeechesResponse{
			MemberId: memberId,
			Page:     page,
			PerPage:  perPage,
			Total:    total,
			Speeches: speeches,
		}), nil
	}

	// Route: GET /api/v1/speeches/search?q=... or legacy ?query=...
	q := params["q"]
	if q == "" {
		q = params["query"]
	}
	if strings.HasPrefix(path, "/api/v1/speeches/search") || q != "" {
		if q == "" {
			return errResponse(http.StatusBadRequest, "missing 'q' parameter"), nil
		}
		results, err := searchSpeeches(ctx, conn, q, page, perPage)
		if err != nil {
			return errResponse(http.StatusInternalServerError, err.Error()), nil
		}
		if results == nil {
			results = []SpeechResult{}
		}
		return jsonResponse(SearchResponse{
			Query:   q,
			Page:    page,
			PerPage: perPage,
			Results: results,
		}), nil
	}

	return errResponse(http.StatusNotFound, "not found"), nil
}

func main() {
	lambda.Start(HandleRequest)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func jsonResponse(body interface{}) events.APIGatewayProxyResponse {
	b, _ := json.Marshal(body)
	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(b),
	}
}

func errResponse(status int, msg string) events.APIGatewayProxyResponse {
	b, _ := json.Marshal(map[string]string{"error": msg})
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(b),
	}
}

func intParam(params map[string]string, key string, defaultVal int) int {
	if v, ok := params[key]; ok {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			return n
		}
	}
	return defaultVal
}
