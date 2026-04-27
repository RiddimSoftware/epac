package main

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	"github.com/jackc/pgx/v5"
)

// Intervention mirrors the struct in backend/loader/speeches.go.
// Duplicated here to keep each Lambda self-contained without shared module dependencies.
type Intervention struct {
	Id                   string
	SittingDate          time.Time
	ParliamentNum        int
	SessionNum           int
	MemberDbId           string
	SpeakerName          string
	SubjectId            string
	SubjectTitle         string
	InterventionSequence int
	Content              string
	WordCount            int
}

func main() {
	lambda.Start(HandleRequest)
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

	parl := "44"
	sess := "1"
	sessionCode := parl + sess

	var lastSitting int
	err = conn.QueryRow(ctx,
		"SELECT COALESCE(MAX(CAST(substring(filename FROM 'HAN([0-9]+)-E.XML') AS INTEGER)), 0) FROM speeches",
	).Scan(&lastSitting)
	if err != nil {
		fmt.Printf("Error finding last sitting: %v. Starting from 0.\n", err)
		lastSitting = 0
	}

	nextSitting := lastSitting + 1
	sittingPadded := fmt.Sprintf("%03d", nextSitting)
	url := fmt.Sprintf("https://www.ourcommons.ca/Content/House/%s/Debates/%s/HAN%s-E.XML",
		sessionCode, sittingPadded, sittingPadded)
	filename := fmt.Sprintf("44-1-HAN%s-E.XML", sittingPadded)

	fmt.Printf("Attempting to download sitting %d from %s\n", nextSitting, url)

	interventions, err := downloadAndParse(url)
	if err != nil {
		fetchErr := fmt.Errorf("failed to download or parse Hansard: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}

	if len(interventions) == 0 {
		fmt.Printf("No interventions found for sitting %d — not available yet.\n", nextSitting)
		recordHealth(ctx, conn, 0, nil)
		return nil
	}

	n, err := bulkInsertSpeeches(ctx, conn, filename, interventions)
	if err != nil {
		insertErr := fmt.Errorf("failed to insert speeches: %w", err)
		recordHealth(ctx, conn, 0, insertErr)
		return insertErr
	}

	recordHealth(ctx, conn, n, nil)
	fmt.Printf("Successfully loaded %d interventions from sitting %d\n", n, nextSitting)
	return nil
}

func downloadAndParse(url string) ([]Intervention, error) {
	client := &http.Client{Timeout: 30 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "epac/1.0 (civic engagement tool; contact: sunny@riddimsoftware.com)")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected HTTP status: %d", resp.StatusCode)
	}

	return parseHansard(resp.Body)
}

// parseHansard is the rich streaming parser. It is a copy of the logic in
// backend/loader/speeches.go — kept in sync manually.
func parseHansard(r io.Reader) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)

	var yearStr, monthStr, dayStr, parliStr, sessStr string
	var sittingDate time.Time
	var parliamentNum, sessionNum int
	headerDone := false

	inExtractedItem := false
	extractedItemName := ""

	var currentSubjectId, currentSubjectTitle string
	var subjectSequence int
	inSubjectTitle := false

	var interventions []Intervention
	var current *Intervention

	inPersonSpeaking := false
	inPersonAffil := false
	inContent := false
	paraTextDepth := 0
	contentNested := 0

	finalizeHeader := func() {
		if headerDone {
			return
		}
		headerDone = true
		if yearStr != "" && monthStr != "" && dayStr != "" {
			dateStr := fmt.Sprintf("%s-%s-%s", yearStr, zeroPad(monthStr), zeroPad(dayStr))
			if t, err := time.Parse("2006-01-02", dateStr); err == nil {
				sittingDate = t
			}
		}
		fmt.Sscanf(parliStr, "%d", &parliamentNum)
		fmt.Sscanf(sessStr, "%d", &sessionNum)
	}

	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("xml decode error: %w", err)
		}

		switch se := tok.(type) {
		case xml.StartElement:
			lname := se.Name.Local
			if lname == "ExtractedItem" {
				inExtractedItem = true
				extractedItemName = ""
				for _, a := range se.Attr {
					if a.Name.Local == "Name" {
						extractedItemName = a.Value
					}
				}
				continue
			}
			if lname == "SubjectOfBusiness" {
				finalizeHeader()
				currentSubjectId, currentSubjectTitle = "", ""
				subjectSequence = 0
				for _, a := range se.Attr {
					if a.Name.Local == "id" {
						currentSubjectId = a.Value
					}
				}
				continue
			}
			if lname == "SubjectOfBusinessTitle" {
				inSubjectTitle = true
				continue
			}
			if lname == "Intervention" {
				finalizeHeader()
				subjectSequence++
				current = &Intervention{
					SittingDate:          sittingDate,
					ParliamentNum:        parliamentNum,
					SessionNum:           sessionNum,
					SubjectId:            currentSubjectId,
					SubjectTitle:         strings.TrimSpace(currentSubjectTitle),
					InterventionSequence: subjectSequence,
				}
				for _, a := range se.Attr {
					if a.Name.Local == "id" {
						current.Id = a.Value
					}
				}
				inPersonSpeaking, inPersonAffil, inContent = false, false, false
				paraTextDepth, contentNested = 0, 0
				continue
			}
			if current == nil {
				continue
			}
			if lname == "PersonSpeaking" {
				inPersonSpeaking = true
			} else if inPersonSpeaking && lname == "Affiliation" {
				inPersonAffil = true
				for _, a := range se.Attr {
					if a.Name.Local == "DbId" && current.MemberDbId == "" {
						current.MemberDbId = a.Value
					}
				}
			} else if lname == "Content" {
				inContent = true
			} else if inContent {
				if lname == "ParaText" {
					paraTextDepth++
				} else if paraTextDepth > 0 {
					contentNested++
				}
			}

		case xml.CharData:
			text := string(se)
			if inExtractedItem {
				v := strings.TrimSpace(text)
				switch extractedItemName {
				case "MetaDateNumYear":
					yearStr = v
				case "MetaDateNumMonth":
					monthStr = v
				case "MetaDateNumDay":
					dayStr = v
				case "ParliamentNumber":
					parliStr = v
				case "SessionNumber":
					sessStr = v
				}
			}
			if inSubjectTitle {
				currentSubjectTitle += text
			}
			if current == nil {
				continue
			}
			if inPersonAffil {
				current.SpeakerName += text
			} else if inContent && paraTextDepth > 0 && contentNested == 0 {
				current.Content += text
			}

		case xml.EndElement:
			lname := se.Name.Local
			if lname == "ExtractedItem" {
				inExtractedItem = false
				extractedItemName = ""
				continue
			}
			if lname == "SubjectOfBusinessTitle" {
				inSubjectTitle = false
				currentSubjectTitle = strings.TrimSpace(currentSubjectTitle)
				continue
			}
			if current == nil {
				continue
			}
			if lname == "PersonSpeaking" {
				inPersonSpeaking, inPersonAffil = false, false
				current.SpeakerName = strings.TrimSpace(current.SpeakerName)
			} else if inPersonSpeaking && lname == "Affiliation" {
				inPersonAffil = false
			} else if inContent {
				switch lname {
				case "ParaText":
					if paraTextDepth > 0 {
						paraTextDepth--
					}
					if paraTextDepth == 0 {
						current.Content += " "
					}
				case "Content":
					inContent = false
					paraTextDepth, contentNested = 0, 0
					current.Content = strings.TrimSpace(current.Content)
					current.WordCount = countWords(current.Content)
				default:
					if paraTextDepth > 0 && contentNested > 0 {
						contentNested--
					}
				}
			} else if lname == "Intervention" && current != nil {
				if current.Content != "" {
					interventions = append(interventions, *current)
				}
				current = nil
			}
		}
	}
	return interventions, nil
}

func bulkInsertSpeeches(ctx context.Context, conn *pgx.Conn, filename string, interventions []Intervention) (int, error) {
	if len(interventions) == 0 {
		return 0, nil
	}
	batch := &pgx.Batch{}
	for _, inv := range interventions {
		var sittingDate interface{}
		if !inv.SittingDate.IsZero() {
			sittingDate = inv.SittingDate
		}
		var memberDbId interface{}
		if inv.MemberDbId != "" {
			memberDbId = inv.MemberDbId
		}
		batch.Queue(
			`INSERT INTO speeches
			    (intervention_id, filename, speaker_name, content,
			     sitting_date, parliament_num, session_num,
			     member_id, subject_id, subject_title,
			     intervention_sequence, word_count)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
			 ON CONFLICT (intervention_id) DO NOTHING`,
			inv.Id, filename, inv.SpeakerName, inv.Content,
			sittingDate, nullableInt(inv.ParliamentNum), nullableInt(inv.SessionNum),
			memberDbId, nullableStr(inv.SubjectId), nullableStr(inv.SubjectTitle),
			nullableInt(inv.InterventionSequence), nullableInt(inv.WordCount),
		)
	}
	results := conn.SendBatch(ctx, batch)
	defer results.Close()

	inserted := 0
	for range interventions {
		tag, err := results.Exec()
		if err != nil {
			return inserted, err
		}
		inserted += int(tag.RowsAffected())
	}
	return inserted, results.Close()
}

func countWords(s string) int {
	return len(strings.Fields(s))
}

func zeroPad(s string) string {
	s = strings.TrimSpace(s)
	if len(s) == 1 {
		return "0" + s
	}
	return s
}

func nullableInt(v int) interface{} {
	if v == 0 {
		return nil
	}
	return v
}

func nullableStr(v string) interface{} {
	if v == "" {
		return nil
	}
	return v
}
