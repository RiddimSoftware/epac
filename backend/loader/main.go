package main

import (
	"context"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

type Intervention struct {
	Id      string
	Speaker string
	Content string
}

type Member struct {
	PersonId     string    `xml:"PersonId"`
	Honorific    string    `xml:"PersonShortHonorific"`
	FirstName    string    `xml:"PersonOfficialFirstName"`
	LastName     string    `xml:"PersonOfficialLastName"`
	Constituency string    `xml:"ConstituencyName"`
	Province     string    `xml:"ConstituencyProvinceTerritoryName"`
	Caucus       string    `xml:"CaucusShortName"`
	FromDate     string    `xml:"FromDateTime"`
	ToDate       *string   `xml:"ToDateTime"`
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

	// Ensure schema exists
	err = ensureSchema(ctx, conn)
	if err != nil {
		fmt.Printf("Error ensuring schema: %v\n", err)
		return
	}

	// 1. Load Members
	if passedFlags["members"] {
		fmt.Printf("Loading members from %s...\n", *membersPath)
		err = loadMembers(ctx, conn, *membersPath)
		if err != nil {
			fmt.Printf("Error loading members: %v\n", err)
		}
	}

	// 2. Load Speeches
	if passedFlags["speeches"] {
		files, err := filepath.Glob(filepath.Join(*speechesDir, "*.XML"))
		if err != nil {
			fmt.Printf("Error globbing files: %v\n", err)
			return
		}

		for _, file := range files {
			base := filepath.Base(file)
			parts := strings.Split(base, "-")
			if len(parts) > 0 {
				parliament, err := strconv.Atoi(parts[0])
				if err == nil && parliament < 40 {
					continue
				}
			}

			fmt.Printf("Loading speeches from %s...\n", file)
			interventions, err := parseHansardFile(file)
			if err != nil {
				fmt.Printf("  Error parsing %s: %v\n", file, err)
				continue
			}

			err = bulkInsertSpeeches(ctx, conn, file, interventions)
			if err != nil {
				fmt.Printf("  Error inserting %s: %v\n", file, err)
			} else {
				fmt.Printf("  Successfully loaded %d entries\n", len(interventions))
			}
		}
	}
}

func loadMembers(ctx context.Context, conn *pgx.Conn, filename string) error {
	f, err := os.Open(filename)
	if err != nil {
		return err
	}
	defer f.Close()

	var memberArray MemberArray
	decoder := xml.NewDecoder(f)
	if err := decoder.Decode(&memberArray); err != nil {
		return err
	}

	rows := [][]interface{}{}
	for _, m := range memberArray.Members {
		// Clean up dates
		fromDate, _ := time.Parse("2006-01-02T15:04:05", m.FromDate)
		var toDate interface{}
		if m.ToDate != nil && *m.ToDate != "" {
			t, err := time.Parse("2006-01-02T15:04:05", *m.ToDate)
			if err == nil {
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
		[]string{"person_id", "honorific", "first_name", "last_name", "constituency", "province", "caucus", "from_date", "to_date"},
		pgx.CopyFromRows(rows),
	)
	if err == nil {
		fmt.Printf("  Successfully loaded %d members\n", len(memberArray.Members))
	}
	return err
}

func parseHansardFile(filename string) ([]Intervention, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	decoder := xml.NewDecoder(f)
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
				inParaText++ // Treat nested tags as part of the text
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
			filepath.Base(filename),
			inv.Speaker,
			inv.Content,
		})
	}

	_, err := conn.CopyFrom(
		ctx,
		pgx.Identifier{"speeches"},
		[]string{"intervention_id", "filename", "speaker_name", "content"},
		pgx.CopyFromRows(rows),
	)
	return err
}

func ensureSchema(ctx context.Context, conn *pgx.Conn) error {
	schema := `
	CREATE TABLE IF NOT EXISTS members (
		person_id TEXT PRIMARY KEY,
		honorific TEXT,
		first_name TEXT,
		last_name TEXT,
		constituency TEXT,
		province TEXT,
		caucus TEXT,
		from_date TIMESTAMP,
		to_date TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS speeches (
		intervention_id TEXT PRIMARY KEY,
		filename TEXT,
		speaker_name TEXT,
		content TEXT
	);
	`
	_, err := conn.Exec(ctx, schema)
	return err
}
