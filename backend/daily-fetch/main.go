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

type Intervention struct {
	Id      string
	Speaker string
	Content string
}

func main() {
	lambda.Start(HandleRequest)
}

const pipelineName = "hansard-daily-fetch"

func recordHealth(ctx context.Context, conn *pgx.Conn, count int, runErr error) {
	now := time.Now().UTC()
	var errMsg *string
	var successAt *time.Time
	if runErr == nil {
		successAt = &now
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
			record_count    = EXCLUDED.record_count
	`, pipelineName, now, successAt, errMsg, count)
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

	// In a real scenario, these could be environment variables or fetched from a DB config table.
	// Current Parliament and Session: 44-1
	parl := "44"
	sess := "1"
	sessionCode := parl + sess

	// 1. Find the last sitting number we have in the database
	var lastSitting int
	err = conn.QueryRow(ctx, "SELECT COALESCE(MAX(CAST(substring(filename FROM 'HAN([0-9]+)-E.XML') AS INTEGER)), 0) FROM speeches").Scan(&lastSitting)
	if err != nil {
		fmt.Printf("Error finding last sitting: %v. Starting from 0.\n", err)
		lastSitting = 0
	}

	nextSitting := lastSitting + 1
	sittingPadded := fmt.Sprintf("%03d", nextSitting)
	url := fmt.Sprintf("https://www.ourcommons.ca/Content/House/%s/Debates/%s/HAN%s-E.XML", sessionCode, sittingPadded, sittingPadded)
	filename := fmt.Sprintf("44-1-HAN%s-E.XML", sittingPadded)

	fmt.Printf("Attempting to download sitting %d from %s\n", nextSitting, url)

	// 2. Download the Hansard XML
	interventions, err := downloadAndParse(url)
	if err != nil {
		fetchErr := fmt.Errorf("failed to download or parse Hansard: %w", err)
		recordHealth(ctx, conn, 0, fetchErr)
		return fetchErr
	}

	if len(interventions) == 0 {
		fmt.Printf("No interventions found for sitting %d. It might not be available yet.\n", nextSitting)
		recordHealth(ctx, conn, 0, nil)
		return nil
	}

	// 3. Insert into database
	err = bulkInsertSpeeches(ctx, conn, filename, interventions)
	if err != nil {
		insertErr := fmt.Errorf("failed to insert speeches: %w", err)
		recordHealth(ctx, conn, 0, insertErr)
		return insertErr
	}

	recordHealth(ctx, conn, len(interventions), nil)
	fmt.Printf("Successfully loaded %d entries from sitting %d\n", len(interventions), nextSitting)
	return nil
}

func downloadAndParse(url string) ([]Intervention, error) {
	client := &http.Client{Timeout: 30 * time.Second}
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
		return nil, nil // Not found is not an error, just means it's not ready
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	return parseHansard(resp.Body)
}

func parseHansard(r io.Reader) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)
	var interventions []Intervention
	var current *Intervention
	var inParaText, inAffiliation int

	for {
		t, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, err
		}

		switch se := t.(type) {
		case xml.StartElement:
			if se.Name.Local == "Intervention" {
				current = &Intervention{}
				for _, attr := range se.Attr {
					if attr.Name.Local == "id" {
						current.Id = attr.Value
					}
				}
			} else if se.Name.Local == "Affiliation" {
				inAffiliation++
			} else if se.Name.Local == "ParaText" {
				inParaText++
			} else if inParaText > 0 {
				inParaText++
			}
		case xml.CharData:
			if current == nil {
				continue
			}
			if inAffiliation > 0 {
				current.Speaker += string(se)
			} else if inParaText > 0 {
				current.Content += string(se)
			}
		case xml.EndElement:
			if se.Name.Local == "Intervention" {
				current.Content = strings.TrimSpace(current.Content)
				interventions = append(interventions, *current)
				current = nil
			} else if se.Name.Local == "Affiliation" {
				inAffiliation--
			} else if se.Name.Local == "ParaText" {
				inParaText--
				if current != nil {
					current.Content += " "
				}
			} else if inParaText > 0 {
				inParaText--
			}
		}
	}
	return interventions, nil
}

func bulkInsertSpeeches(ctx context.Context, conn *pgx.Conn, filename string, interventions []Intervention) error {
	rows := [][]interface{}{}
	for _, inv := range interventions {
		rows = append(rows, []interface{}{
			inv.Id,
			filename,
			inv.Speaker,
			inv.Content,
		})
	}

	_, err := conn.CopyFrom(
		ctx,
		pgx.Identifier {"speeches"},
		[]string{"intervention_id", "filename", "speaker_name", "content"},
		pgx.CopyFromRows(rows),
	)
	return err
}
