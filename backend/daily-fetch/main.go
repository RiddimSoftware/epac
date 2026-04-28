package main

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"epac/observability"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

type Intervention struct {
	Id              string
	MemberId        string
	Speaker         string
	SubjectTitle    string
	InterventionSeq int
	Content         string
	WordCount       int
	SittingDate     time.Time
	ParliamentNum   int
	SessionNum      int
	Filename        string
}

func main() {
	lambda.Start(observability.WrapNoEvent("daily-fetch", HandleRequest))
}

const pipelineName = "hansard-daily-fetch"

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

	// Current Parliament and Session
	parl := "44"
	sess := "1"
	sessionCode := parl + sess

	// Derive the last sitting number from the filename column.
	// WHERE filters to parliament 44 session 1 when those columns are populated;
	// rows from before the schema migration have NULL values and are excluded by
	// the IS NOT DISTINCT FROM guard. COALESCE returns 0 for an empty table.
	var lastSitting int
	err = conn.QueryRow(ctx, `
		SELECT COALESCE(MAX(CAST(substring(filename FROM 'HAN([0-9]+)-E.XML') AS INTEGER)), 0)
		FROM speeches
		WHERE (parliament_num IS NULL OR (parliament_num = 44 AND session_num = 1))`,
	).Scan(&lastSitting)
	if err != nil {
		lastSitting = 0
	}

	nextSitting := lastSitting + 1
	sittingPadded := fmt.Sprintf("%03d", nextSitting)
	url := fmt.Sprintf("https://www.ourcommons.ca/Content/House/%s/Debates/%s/HAN%s-E.XML", sessionCode, sittingPadded, sittingPadded)
	filename := fmt.Sprintf("44-1-HAN%s-E.XML", sittingPadded)

	fmt.Printf("Attempting to download sitting %d from %s\n", nextSitting, url)

	httpClient := &http.Client{Timeout: 30 * time.Second}
	interventions, err := downloadAndParse(httpClient, url, filename)
	if err != nil {
		fetchErr := fmt.Errorf("failed to download or parse Hansard: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}

	if len(interventions) == 0 {
		fmt.Printf("No interventions found for sitting %d. Not available yet.\n", nextSitting)
		recordHealth(ctx, conn, 0, nil)
		return nil
	}

	n, err := upsertSpeeches(ctx, conn, interventions)
	if err != nil {
		insertErr := fmt.Errorf("failed to upsert speeches: %w", err)
		recordHealth(ctx, conn, 0, insertErr)
		return insertErr
	}

	recordHealth(ctx, conn, n, nil)
	fmt.Printf("Successfully upserted %d entries from sitting %d\n", n, nextSitting)
	return nil
}

func downloadAndParse(client *http.Client, url, filename string) ([]Intervention, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "HansardDownloader/1.0 (Civic Engagement Tool; contact: sunny)")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	return parseHansard(resp.Body, filename)
}

// parseHansard extracts every <Intervention> from a Hansard XML stream.
// Member ID comes from the DbId attribute on <Affiliation> inside <PersonSpeaking>.
// Subject title, sitting date, parliament, and session come from the XML metadata.
func parseHansard(r io.Reader, filename string) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)
	var interventions []Intervention

	var (
		parliamentNum   int
		sessionNum      int
		sittingDate     time.Time
		inExtractedItem bool
		currentItemName string
	)

	var (
		inSubjectTitle bool
		currentSubject string
		subjectSeq     int
	)

	var current *Intervention

	var (
		inPersonSpeaking int
		inContentEl      int
		captureAffPS     bool
	)

	var inParaText int

	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		switch se := tok.(type) {
		case xml.StartElement:
			switch se.Name.Local {
			case "ExtractedItem":
				inExtractedItem = true
				currentItemName = ""
				for _, a := range se.Attr {
					if a.Name.Local == "Name" {
						currentItemName = a.Value
					}
				}
			case "SubjectOfBusiness":
				currentSubject = ""
				subjectSeq = 0
			case "SubjectOfBusinessTitle":
				inSubjectTitle = true
			case "Intervention":
				current = &Intervention{
					SubjectTitle:    currentSubject,
					InterventionSeq: subjectSeq,
					SittingDate:     sittingDate,
					ParliamentNum:   parliamentNum,
					SessionNum:      sessionNum,
					Filename:        filename,
				}
				subjectSeq++
				for _, a := range se.Attr {
					if a.Name.Local == "id" {
						current.Id = a.Value
					}
				}
			case "PersonSpeaking":
				inPersonSpeaking++
			case "Content":
				inContentEl++
			case "Affiliation":
				if inPersonSpeaking > 0 && inContentEl == 0 && !captureAffPS {
					captureAffPS = true
					if current != nil && current.MemberId == "" {
						for _, a := range se.Attr {
							if a.Name.Local == "DbId" {
								current.MemberId = a.Value
							}
						}
					}
				}
			case "ParaText":
				if inContentEl > 0 {
					inParaText++
				}
			}

		case xml.CharData:
			text := string(se)
			switch {
			case inExtractedItem:
				switch currentItemName {
				case "ParliamentNumber":
					parliamentNum, _ = strconv.Atoi(strings.TrimSpace(text))
				case "SessionNumber":
					sessionNum, _ = strconv.Atoi(strings.TrimSpace(text))
				case "Date":
					sittingDate = parseHansardDate(strings.TrimSpace(text))
				}
			case inSubjectTitle && current == nil:
				currentSubject += text
			case current != nil && captureAffPS:
				current.Speaker += text
			case current != nil && inParaText > 0:
				current.Content += text
			}

		case xml.EndElement:
			switch se.Name.Local {
			case "ExtractedItem":
				inExtractedItem = false
				currentItemName = ""
			case "SubjectOfBusinessTitle":
				inSubjectTitle = false
				currentSubject = strings.TrimSpace(currentSubject)
			case "Intervention":
				if current != nil {
					current.Content = strings.TrimSpace(current.Content)
					current.WordCount = wordCount(current.Content)
					current.Speaker = strings.TrimSpace(current.Speaker)
					interventions = append(interventions, *current)
					current = nil
				}
			case "PersonSpeaking":
				if inPersonSpeaking > 0 {
					inPersonSpeaking--
				}
			case "Affiliation":
				captureAffPS = false
			case "Content":
				if inContentEl > 0 {
					inContentEl--
				}
			case "ParaText":
				if inParaText > 0 {
					inParaText--
					if current != nil {
						current.Content += " "
					}
				}
			}
		}
	}
	return interventions, nil
}

func parseHansardDate(s string) time.Time {
	dayPrefixes := []string{
		"Monday, ", "Tuesday, ", "Wednesday, ", "Thursday, ",
		"Friday, ", "Saturday, ", "Sunday, ",
	}
	cleaned := s
	for _, p := range dayPrefixes {
		cleaned = strings.TrimPrefix(cleaned, p)
	}
	t, err := time.Parse("January 2, 2006", cleaned)
	if err != nil {
		return time.Time{}
	}
	return t
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

func upsertSpeeches(ctx context.Context, conn *pgx.Conn, interventions []Intervention) (int, error) {
	batch := &pgx.Batch{}
	valid := 0
	for _, inv := range interventions {
		if inv.Id == "" || inv.Content == "" {
			continue
		}
		var memberId *string
		if inv.MemberId != "" {
			memberId = &inv.MemberId
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
				subject_title, intervention_seq, word_count
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
			ON CONFLICT (intervention_id) DO UPDATE SET
				speaker_name     = EXCLUDED.speaker_name,
				content          = EXCLUDED.content,
				sitting_date     = EXCLUDED.sitting_date,
				parliament_num   = EXCLUDED.parliament_num,
				session_num      = EXCLUDED.session_num,
				member_id        = EXCLUDED.member_id,
				subject_title    = EXCLUDED.subject_title,
				intervention_seq = EXCLUDED.intervention_seq,
				word_count       = EXCLUDED.word_count`,
			inv.Id, inv.Filename, inv.Speaker, inv.Content,
			date, parlNum, sessNum, memberId,
			inv.SubjectTitle, inv.InterventionSeq, inv.WordCount,
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
