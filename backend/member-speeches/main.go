// member-speeches Lambda — GET /api/v1/members/{id}/speeches
//
// Path parameter: id (member_id / Affiliation DbId from Hansard XML)
// Query parameters:
//   - page     int  (default 1)
//   - per_page int  (default 20, max 100)
//   - topic    string (ILIKE filter on subject_title)
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type SpeechEntry struct {
	InterventionId string  `json:"id"`
	SittingDate    *string `json:"sitting_date,omitempty"`
	ParliamentNum  *int    `json:"parliament_num,omitempty"`
	SessionNum     *int    `json:"session_num,omitempty"`
	SubjectTitle   *string `json:"subject_title,omitempty"`
	Preview        string  `json:"preview"`
	WordCount      *int    `json:"word_count,omitempty"`
	Filename       string  `json:"filename"`
}

type MemberStats struct {
	TotalSpeeches int    `json:"total_speeches"`
	AvgWordCount  int    `json:"avg_word_count"`
	TopTopic      string `json:"top_topic"`
}

type MemberSpeechesResponse struct {
	MemberId string        `json:"member_id"`
	Page     int           `json:"page"`
	PerPage  int           `json:"per_page"`
	Total    int           `json:"total"`
	Pages    int           `json:"pages"`
	Stats    MemberStats   `json:"stats"`
	Speeches []SpeechEntry `json:"speeches"`
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
	memberId := req.PathParameters["id"]
	if memberId == "" {
		return jsonError(http.StatusBadRequest, "missing member id"), nil
	}

	page := 1
	if p := req.QueryStringParameters["page"]; p != "" {
		if n, err := strconv.Atoi(p); err == nil && n > 0 {
			page = n
		}
	}

	perPage := 20
	if pp := req.QueryStringParameters["per_page"]; pp != "" {
		if n, err := strconv.Atoi(pp); err == nil && n > 0 && n <= 100 {
			perPage = n
		}
	}

	topic := strings.TrimSpace(req.QueryStringParameters["topic"])

	conn, err := getDBConn(ctx)
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	// Count total matching speeches
	var total int
	if topic != "" {
		err = conn.QueryRow(ctx,
			`SELECT COUNT(*) FROM speeches WHERE member_id = $1 AND subject_title ILIKE $2`,
			memberId, "%"+topic+"%",
		).Scan(&total)
	} else {
		err = conn.QueryRow(ctx,
			`SELECT COUNT(*) FROM speeches WHERE member_id = $1`,
			memberId,
		).Scan(&total)
	}
	if err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	offset := (page - 1) * perPage

	// Fetch paginated speeches
	var rows pgx.Rows
	if topic != "" {
		rows, err = conn.Query(ctx, `
			SELECT intervention_id, sitting_date, parliament_num, session_num,
			       subject_title, content, word_count, filename
			FROM speeches
			WHERE member_id = $1 AND subject_title ILIKE $2
			ORDER BY sitting_date DESC NULLS LAST, intervention_seq ASC
			LIMIT $3 OFFSET $4`,
			memberId, "%"+topic+"%", perPage, offset,
		)
	} else {
		rows, err = conn.Query(ctx, `
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
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}
	defer rows.Close()

	speeches := make([]SpeechEntry, 0)
	for rows.Next() {
		var (
			id           string
			date         *time.Time
			parlNum      *int
			sessNum      *int
			subjectTitle *string
			content      string
			wordCount    *int
			filename     string
		)
		if err := rows.Scan(&id, &date, &parlNum, &sessNum, &subjectTitle, &content, &wordCount, &filename); err != nil {
			return jsonError(http.StatusInternalServerError, err.Error()), nil
		}

		entry := SpeechEntry{
			InterventionId: id,
			ParliamentNum:  parlNum,
			SessionNum:     sessNum,
			SubjectTitle:   subjectTitle,
			WordCount:      wordCount,
			Filename:       filename,
		}
		if date != nil {
			s := date.Format("2006-01-02")
			entry.SittingDate = &s
		}
		// Preview: first 150 runes of content
		runes := []rune(content)
		if len(runes) > 150 {
			entry.Preview = string(runes[:150])
		} else {
			entry.Preview = content
		}
		speeches = append(speeches, entry)
	}
	if err := rows.Err(); err != nil {
		return jsonError(http.StatusInternalServerError, err.Error()), nil
	}

	// Stats: total speeches, avg word count, top topic
	stats := MemberStats{}
	conn.QueryRow(ctx, `
		SELECT
			COUNT(*),
			COALESCE(AVG(word_count)::int, 0)
		FROM speeches
		WHERE member_id = $1`, memberId,
	).Scan(&stats.TotalSpeeches, &stats.AvgWordCount)

	conn.QueryRow(ctx, `
		SELECT COALESCE(subject_title, '')
		FROM speeches
		WHERE member_id = $1 AND subject_title IS NOT NULL AND subject_title != ''
		GROUP BY subject_title
		ORDER BY COUNT(*) DESC
		LIMIT 1`, memberId,
	).Scan(&stats.TopTopic)

	pages := int(math.Ceil(float64(total) / float64(perPage)))

	resp := MemberSpeechesResponse{
		MemberId: memberId,
		Page:     page,
		PerPage:  perPage,
		Total:    total,
		Pages:    pages,
		Stats:    stats,
		Speeches: speeches,
	}

	body, err := json.Marshal(resp)
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}

	return events.APIGatewayProxyResponse{
		StatusCode: http.StatusOK,
		Headers:    map[string]string{"Content-Type": "application/json"},
		Body:       string(body),
	}, nil
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
	lambda.Start(observability.WrapAPIGateway("member-speeches", HandleRequest))
}
