package main

import (
	"context"
	"encoding/xml"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Member matches the members XML format from Parliament.ca.
type Member struct {
	PersonId     string  `xml:"PersonId"`
	Honorific    string  `xml:"PersonShortHonorific"`
	FirstName    string  `xml:"PersonOfficialFirstName"`
	LastName     string  `xml:"PersonOfficialLastName"`
	Constituency string  `xml:"ConstituencyName"`
	Province     string  `xml:"ConstituencyProvinceTerritoryName"`
	Caucus       string  `xml:"CaucusShortName"`
	FromDate     string  `xml:"FromDateTime"`
	ToDate       *string `xml:"ToDateTime"`
}

type MemberArray struct {
	Members []Member `xml:"MemberOfParliament"`
}

func main() {
	membersPath := flag.String("members", "../../data/members/all.xml", "path to the members all.xml file")
	speechesDir := flag.String("speeches", "../../data/hansard", "directory containing Hansard XML files")
	flag.Parse()

	passedFlags := make(map[string]bool)
	flag.Visit(func(f *flag.Flag) {
		passedFlags[f.Name] = true
	})

	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		fmt.Println("Error: DATABASE_URL environment variable is not set")
		return
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		fmt.Printf("Unable to connect to database: %v\n", err)
		return
	}
	defer conn.Close(ctx)

	if err := ensureSchema(ctx, conn); err != nil {
		fmt.Printf("Error ensuring schema: %v\n", err)
		return
	}

	if passedFlags["members"] {
		fmt.Printf("Loading members from %s...\n", *membersPath)
		if err := loadMembers(ctx, conn, *membersPath); err != nil {
			fmt.Printf("Error loading members: %v\n", err)
		}
	}

	if passedFlags["speeches"] {
		files, err := filepath.Glob(filepath.Join(*speechesDir, "*.XML"))
		if err != nil {
			fmt.Printf("Error globbing files: %v\n", err)
			return
		}

		total := 0
		for _, file := range files {
			// Skip pre-44th Parliament files (filenames like 44-1-HAN001-E.XML)
			base := filepath.Base(file)
			parts := strings.Split(base, "-")
			if len(parts) > 0 {
				parl, err := strconv.Atoi(parts[0])
				if err == nil && parl < 40 {
					continue
				}
			}

			fmt.Printf("Loading speeches from %s...\n", base)
			f, err := os.Open(file)
			if err != nil {
				fmt.Printf("  Error opening %s: %v\n", base, err)
				continue
			}
			interventions, err := ParseHansardXML(f)
			f.Close()
			if err != nil {
				fmt.Printf("  Error parsing %s: %v\n", base, err)
				continue
			}

			n, err := bulkInsertSpeeches(ctx, conn, base, interventions)
			if err != nil {
				fmt.Printf("  Error inserting %s: %v\n", base, err)
			} else {
				fmt.Printf("  Loaded %d interventions\n", n)
				total += n
			}
		}
		fmt.Printf("Total interventions loaded: %d\n", total)
	}
}

func loadMembers(ctx context.Context, conn *pgx.Conn, filename string) error {
	f, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer f.Close()

	var memberArray MemberArray
	if err := xml.NewDecoder(f).Decode(&memberArray); err != nil {
		return err
	}

	rows := make([][]interface{}, 0, len(memberArray.Members))
	for _, m := range memberArray.Members {
		fromDate, _ := time.Parse("2006-01-02T15:04:05", m.FromDate)
		var toDate interface{}
		if m.ToDate != nil && *m.ToDate != "" {
			if t, err := time.Parse("2006-01-02T15:04:05", *m.ToDate); err == nil {
				toDate = t
			}
		}
		rows = append(rows, []interface{}{
			m.PersonId, m.Honorific, m.FirstName, m.LastName,
			m.Constituency, m.Province, m.Caucus, fromDate, toDate,
		})
	}

	_, err = conn.CopyFrom(
		ctx,
		pgx.Identifier{"members"},
		[]string{"person_id", "honorific", "first_name", "last_name",
			"constituency", "province", "caucus", "from_date", "to_date"},
		pgx.CopyFromRows(rows),
	)
	if err == nil {
		fmt.Printf("  Loaded %d members\n", len(memberArray.Members))
	}
	return err
}

// bulkInsertSpeeches upserts interventions using ON CONFLICT DO NOTHING so
// re-running the loader on the same file is safe.
func bulkInsertSpeeches(ctx context.Context, conn *pgx.Conn, filename string, interventions []Intervention) (int, error) {
	if len(interventions) == 0 {
		return 0, nil
	}

	// Use a batch of individual upserts rather than COPY so we can use
	// ON CONFLICT DO NOTHING for idempotency.
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

func ensureSchema(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS members (
			person_id     TEXT PRIMARY KEY,
			honorific     TEXT,
			first_name    TEXT,
			last_name     TEXT,
			constituency  TEXT,
			province      TEXT,
			caucus        TEXT,
			from_date     TIMESTAMP,
			to_date       TIMESTAMP
		);

		CREATE TABLE IF NOT EXISTS speeches (
			intervention_id       TEXT PRIMARY KEY,
			filename              TEXT,
			speaker_name          TEXT,
			content               TEXT,
			sitting_date          DATE,
			parliament_num        INT,
			session_num           INT,
			member_id             TEXT,
			subject_id            TEXT,
			subject_title         TEXT,
			intervention_sequence INT,
			word_count            INT
		);
	`)
	return err
}
