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
	Id               string
	MemberId         string
	Speaker          string
	SubjectTitle     string
	InterventionSeq  int
	Content          string
	WordCount        int
	SittingDate      time.Time
	ParliamentNum    int
	SessionNum       int
	Filename         string
}

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
	membersPath := flag.String("members", "../../data/members/all.xml", "path to members all.xml")
	speechesDir := flag.String("speeches", "../../data/hansard", "directory containing Hansard XML files")
	flag.Parse()

	passedFlags := make(map[string]bool)
	flag.Visit(func(f *flag.Flag) { passedFlags[f.Name] = true })

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

		for _, file := range files {
			base := filepath.Base(file)
			parts := strings.Split(base, "-")
			if len(parts) > 0 {
				if parl, err := strconv.Atoi(parts[0]); err == nil && parl < 40 {
					continue
				}
			}

			fmt.Printf("Loading speeches from %s...\n", file)
			interventions, err := parseHansardFile(file)
			if err != nil {
				fmt.Printf("  Error parsing %s: %v\n", file, err)
				continue
			}

			n, err := upsertSpeeches(ctx, conn, interventions)
			if err != nil {
				fmt.Printf("  Error inserting %s: %v\n", file, err)
			} else {
				fmt.Printf("  Successfully upserted %d entries\n", n)
			}
		}
	}
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

func parseHansardFile(filename string) ([]Intervention, error) {
	f, err := os.Open(filename)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parseHansard(f, filepath.Base(filename))
}

// parseHansard extracts every <Intervention> from a Hansard XML file.
// It captures: member ID (Affiliation DbId in PersonSpeaking), subject title,
// intervention sequence within subject, content, word count, sitting date,
// parliament number, and session number.
func parseHansard(r io.Reader, filename string) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)
	var interventions []Intervention

	// Document-level metadata from <ExtractedInformation>
	var (
		parliamentNum      int
		sessionNum         int
		sittingDate        time.Time
		inExtractedItem    bool
		currentItemName    string
	)

	// Subject-level state
	var (
		inSubjectTitle   bool
		currentSubject   string
		subjectSeq       int
	)

	// Intervention-level state
	var current *Intervention

	// Speaker context: Affiliation inside <PersonSpeaking>
	var (
		inPersonSpeaking int
		inContentEl      int
		captureAffPS     bool // true while inside the first Affiliation in PersonSpeaking
	)

	// Content context
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
				// Only capture the first Affiliation in PersonSpeaking (not in Content)
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

// parseHansardDate parses the date string from <ExtractedItem Name="Date">.
// Format: "Monday, November 22, 2021" or "November 22, 2021".
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

func upsertSpeeches(ctx context.Context, conn *pgx.Conn, interventions []Intervention) (int, error) {
	batch := &pgx.Batch{}
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
	}

	br := conn.SendBatch(ctx, batch)
	defer br.Close()

	inserted := 0
	for _, inv := range interventions {
		if inv.Id == "" || inv.Content == "" {
			continue
		}
		if _, err := br.Exec(); err != nil {
			return inserted, fmt.Errorf("upsert %s: %w", inv.Id, err)
		}
		inserted++
	}
	return inserted, nil
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
		[]string{"person_id", "honorific", "first_name", "last_name", "constituency", "province", "caucus", "from_date", "to_date"},
		pgx.CopyFromRows(rows),
	)
	if err == nil {
		fmt.Printf("  Successfully loaded %d members\n", len(memberArray.Members))
	}
	return err
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
			intervention_id  TEXT PRIMARY KEY,
			filename         TEXT,
			speaker_name     TEXT,
			content          TEXT,
			sitting_date     DATE,
			parliament_num   INT,
			session_num      INT,
			member_id        TEXT,
			subject_title    TEXT,
			intervention_seq INT,
			word_count       INT
		);

		CREATE INDEX IF NOT EXISTS speeches_member_date_idx
			ON speeches(member_id, sitting_date DESC);

		CREATE INDEX IF NOT EXISTS speeches_fts_idx
			ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));

		CREATE INDEX IF NOT EXISTS speeches_subject_idx
			ON speeches(subject_title);
	`)
	return err
}
