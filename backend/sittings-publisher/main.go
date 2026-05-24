// sittings-publisher emits S3-ready sitting index and per-date speech artifacts.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type Sitting struct {
	Date          string `json:"date"`
	ParliamentNum *int   `json:"parliament_num,omitempty"`
	SessionNum    *int   `json:"session_num,omitempty"`
	SittingNum    *int   `json:"sitting_num,omitempty"`
	SourceURL     string `json:"source_url"`
}

type SittingsResponse struct {
	Page     int       `json:"page"`
	PerPage  int       `json:"per_page"`
	Total    int       `json:"total"`
	Sittings []Sitting `json:"sittings"`
}

type Speech struct {
	ID           string  `json:"id"`
	SpeakerName  *string `json:"speaker_name,omitempty"`
	MemberID     *string `json:"member_id,omitempty"`
	SubjectTitle *string `json:"subject_title,omitempty"`
	Content      *string `json:"content,omitempty"`
	SourceURL    *string `json:"source_url,omitempty"`
}

type SpeechesResponse struct {
	Date     string   `json:"date"`
	Page     int      `json:"page"`
	PerPage  int      `json:"per_page"`
	Total    int      `json:"total"`
	Speeches []Speech `json:"speeches"`
}

var filenameRe = regexp.MustCompile(`^(\d+)-(\d+)-HAN([0-9]+)-[A-Z]\.XML$`)

func main() {
	output := flag.String("output", "../../build/artifacts/sittings", "artifact output directory")
	databaseURL := flag.String("database-url", os.Getenv("DATABASE_URL"), "Postgres connection string")
	flag.Parse()

	if strings.TrimSpace(*databaseURL) == "" {
		fmt.Fprintln(os.Stderr, "DATABASE_URL is required")
		os.Exit(1)
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, *databaseURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect database: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	sittings, err := readSittings(ctx, conn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read sittings: %v\n", err)
		os.Exit(1)
	}
	if err := writeArtifacts(ctx, conn, *output, sittings); err != nil {
		fmt.Fprintf(os.Stderr, "write artifacts: %v\n", err)
		os.Exit(1)
	}
	fmt.Fprintf(os.Stderr, "published %d sitting records\n", len(sittings))
}

func readSittings(ctx context.Context, conn *pgx.Conn) ([]Sitting, error) {
	rows, err := conn.Query(ctx, `
		SELECT
			sitting_date,
			MAX(parliament_num)::int,
			MAX(session_num)::int,
			MIN(filename),
			MIN(source_url)
		FROM speeches
		WHERE sitting_date IS NOT NULL
		GROUP BY sitting_date
		ORDER BY sitting_date DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	sittings := make([]Sitting, 0)
	for rows.Next() {
		var date time.Time
		var parliamentNum, sessionNum *int
		var filename, sourceURL *string
		if err := rows.Scan(&date, &parliamentNum, &sessionNum, &filename, &sourceURL); err != nil {
			return nil, err
		}
		sittingNum := sittingNumFromFilename(valueOrEmpty(filename))
		sittings = append(sittings, Sitting{
			Date:          date.Format("2006-01-02"),
			ParliamentNum: parliamentNum,
			SessionNum:    sessionNum,
			SittingNum:    sittingNum,
			SourceURL:     sourceURLForSitting(valueOrEmpty(sourceURL), valueOrEmpty(filename), parliamentNum, sessionNum),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return sittings, nil
}

func readSpeeches(ctx context.Context, conn *pgx.Conn, date string) ([]Speech, error) {
	rows, err := conn.Query(ctx, `
		SELECT intervention_id, speaker_name, member_id, subject_title, content, source_url
		FROM speeches
		WHERE sitting_date = $1::date
		ORDER BY intervention_seq ASC NULLS LAST, intervention_id ASC`, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	speeches := make([]Speech, 0)
	for rows.Next() {
		var speech Speech
		if err := rows.Scan(&speech.ID, &speech.SpeakerName, &speech.MemberID, &speech.SubjectTitle, &speech.Content, &speech.SourceURL); err != nil {
			return nil, err
		}
		speeches = append(speeches, speech)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return speeches, nil
}

func writeArtifacts(ctx context.Context, conn *pgx.Conn, output string, sittings []Sitting) error {
	all := SittingsResponse{
		Page:     1,
		PerPage:  len(sittings),
		Total:    len(sittings),
		Sittings: sittings,
	}
	if err := writeJSON(filepath.Join(output, "v1", "all.json"), all); err != nil {
		return err
	}
	for _, sitting := range sittings {
		speeches, err := readSpeeches(ctx, conn, sitting.Date)
		if err != nil {
			return err
		}
		resp := SpeechesResponse{
			Date:     sitting.Date,
			Page:     1,
			PerPage:  len(speeches),
			Total:    len(speeches),
			Speeches: speeches,
		}
		if err := writeJSON(filepath.Join(output, "v1", "by-date", sitting.Date+".json"), resp); err != nil {
			return err
		}
	}
	return nil
}

func sourceURLForSitting(sourceURL, filename string, parliamentNum, sessionNum *int) string {
	if strings.TrimSpace(sourceURL) != "" {
		return sourceURL
	}
	sittingNum := sittingNumFromFilename(filename)
	if parliamentNum == nil || sessionNum == nil || sittingNum == nil {
		return "https://www.ourcommons.ca/documentviewer/en"
	}
	return fmt.Sprintf("https://www.ourcommons.ca/documentviewer/en/%d-%d/house/sitting-%d/hansard", *parliamentNum, *sessionNum, *sittingNum)
}

func sittingNumFromFilename(filename string) *int {
	matches := filenameRe.FindStringSubmatch(strings.TrimSpace(filename))
	if len(matches) != 4 {
		return nil
	}
	parsed, err := strconv.Atoi(matches[3])
	if err != nil {
		return nil
	}
	return &parsed
}

func valueOrEmpty(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func writeJSON(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()
	enc := json.NewEncoder(f)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	return enc.Encode(value)
}
