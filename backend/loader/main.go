package main

import (
	"context"
	"encoding/json"
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
	Id              string
	MemberId        string
	Speaker         string
	SubjectID       string
	SubjectTitle    string
	InterventionSeq int
	Content         string
	Language        string
	WordCount       int
	SittingDate     time.Time
	ParliamentNum   int
	SessionNum      int
	Filename        string
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

type PBOPublication struct {
	ID                  string  `json:"id"`
	Title               string  `json:"title"`
	PublicationDate     *string `json:"publication_date"`
	MethodologyCategory *string `json:"methodology_category"`
	SourceURL           string  `json:"source_url"`
	PDFURL              *string `json:"pdf_url"`
	SummaryText         *string `json:"summary_text"`
	ContentHash         string  `json:"content_hash"`
}

type OCLSubjectMatter struct {
	OCLCode int    `json:"ocl_code"`
	LabelEN string `json:"label_en"`
	LabelFR string `json:"label_fr"`
	Active  bool   `json:"active"`
}

func main() {
	membersPath := flag.String("members", "../../data/members/all.xml", "path to members all.xml")
	speechesDir := flag.String("speeches", "../../data/hansard", "directory containing Hansard XML files")
	pboPath := flag.String("pbo", "", "path to PBO publications JSON file")
	lobbyingPath := flag.String("lobbying", "", "path to OCL subject-matter JSON file")
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

	if passedFlags["pbo"] {
		fmt.Printf("Loading PBO publications from %s...\n", *pboPath)
		if n, err := loadPBO(ctx, conn, *pboPath); err != nil {
			fmt.Printf("Error loading PBO publications: %v\n", err)
			recordHealth(ctx, conn, "pbo-publications", 0, err)
		} else {
			recordHealth(ctx, conn, "pbo-publications", n, nil)
		}
	}

	if passedFlags["lobbying"] {
		fmt.Printf("Loading OCL subject matters from %s...\n", *lobbyingPath)
		if n, err := loadLobbyistSubjectMatters(ctx, conn, *lobbyingPath); err != nil {
			fmt.Printf("Error loading OCL subject matters: %v\n", err)
			recordHealth(ctx, conn, "lobbyist-subject-matters", 0, err)
		} else {
			recordHealth(ctx, conn, "lobbyist-subject-matters", n, nil)
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
		parliamentNum   int
		sessionNum      int
		sittingDate     time.Time
		inExtractedItem bool
		currentItemName string
	)

	// Subject-level state
	var (
		inSubjectTitle   bool
		currentSubjectID string
		currentSubject   string
		subjectSeq       int
	)

	// Intervention-level state
	var current *Intervention
	currentFloorLanguage := "und"

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
				currentSubjectID = ""
				currentSubject = ""
				subjectSeq = 0
				for _, a := range se.Attr {
					if a.Name.Local == "id" {
						currentSubjectID = a.Value
					}
				}

			case "SubjectOfBusinessTitle":
				inSubjectTitle = true

			case "Intervention":
				current = &Intervention{
					SubjectID:       currentSubjectID,
					SubjectTitle:    currentSubject,
					InterventionSeq: subjectSeq,
					Language:        currentFloorLanguage,
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

			case "FloorLanguage":
				if language := floorLanguage(se); language != "" {
					currentFloorLanguage = language
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
					if current != nil {
						current.Language = mergeLanguage(current.Language, currentFloorLanguage)
					}
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
					current.Language = normalizeLanguage(current.Language)
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

func floorLanguage(se xml.StartElement) string {
	for _, attr := range se.Attr {
		if attr.Name.Local == "language" {
			return normalizeLanguage(attr.Value)
		}
	}
	return ""
}

func normalizeLanguage(language string) string {
	switch strings.ToLower(strings.TrimSpace(language)) {
	case "en", "eng", "english":
		return "en"
	case "fr", "fra", "fre", "french":
		return "fr"
	case "mixed":
		return "mixed"
	default:
		return "und"
	}
}

func mergeLanguage(existing, next string) string {
	existing = normalizeLanguage(existing)
	next = normalizeLanguage(next)
	if existing == "und" {
		return next
	}
	if next == "und" || existing == next {
		return existing
	}
	return "mixed"
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
				subject_id, subject_title, intervention_seq, word_count, language
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			ON CONFLICT (intervention_id) DO UPDATE SET
				speaker_name     = EXCLUDED.speaker_name,
				content          = EXCLUDED.content,
				sitting_date     = EXCLUDED.sitting_date,
				parliament_num   = EXCLUDED.parliament_num,
				session_num      = EXCLUDED.session_num,
				member_id        = EXCLUDED.member_id,
				subject_id       = EXCLUDED.subject_id,
				subject_title    = EXCLUDED.subject_title,
				intervention_seq = EXCLUDED.intervention_seq,
				word_count       = EXCLUDED.word_count,
				language         = EXCLUDED.language`,
			inv.Id, inv.Filename, inv.Speaker, inv.Content,
			date, parlNum, sessNum, memberId,
			inv.SubjectID, inv.SubjectTitle, inv.InterventionSeq, inv.WordCount, normalizeLanguage(inv.Language),
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

func loadPBO(ctx context.Context, conn *pgx.Conn, filename string) (int, error) {
	f, err := os.Open(filename)
	if err != nil {
		return 0, err
	}
	defer f.Close()

	var publications []PBOPublication
	if err := json.NewDecoder(f).Decode(&publications); err != nil {
		return 0, err
	}

	batch := &pgx.Batch{}
	for _, pub := range publications {
		batch.Queue(`
            INSERT INTO pbo_publications
                (id, title, publication_date, methodology_category,
                 source_url, pdf_url, summary_text, content_hash, ingested_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
            ON CONFLICT (source_url) DO UPDATE SET
                title                = EXCLUDED.title,
                publication_date     = EXCLUDED.publication_date,
                methodology_category = EXCLUDED.methodology_category,
                pdf_url              = EXCLUDED.pdf_url,
                summary_text         = EXCLUDED.summary_text,
                content_hash         = EXCLUDED.content_hash,
                ingested_at          = NOW()
            WHERE pbo_publications.content_hash <> EXCLUDED.content_hash
               OR pbo_publications.pdf_url IS DISTINCT FROM EXCLUDED.pdf_url
               OR pbo_publications.summary_text IS DISTINCT FROM EXCLUDED.summary_text
               OR pbo_publications.methodology_category IS DISTINCT FROM EXCLUDED.methodology_category
        `, pub.ID, pub.Title, pub.PublicationDate, pub.MethodologyCategory, pub.SourceURL, pub.PDFURL, pub.SummaryText, pub.ContentHash)
	}

	br := conn.SendBatch(ctx, batch)
	defer br.Close()

	inserted := 0
	for i := 0; i < len(publications); i++ {
		if _, err := br.Exec(); err != nil {
			return inserted, fmt.Errorf("upsert %d: %w", i, err)
		}
		inserted++
	}
	fmt.Printf("  Successfully upserted %d PBO publications\n", inserted)
	return inserted, nil
}

func loadLobbyistSubjectMatters(ctx context.Context, conn *pgx.Conn, filename string) (int, error) {
	f, err := os.Open(filename)
	if err != nil {
		return 0, err
	}
	defer f.Close()

	var subjects []OCLSubjectMatter
	if err := json.NewDecoder(f).Decode(&subjects); err != nil {
		return 0, err
	}

	batch := &pgx.Batch{}
	for _, s := range subjects {
		batch.Queue(`
            INSERT INTO lobbyist_subject_matter_codes
                (ocl_code, label_en, label_fr, active, ingested_at)
            VALUES ($1, $2, $3, $4, NOW())
            ON CONFLICT (ocl_code) DO UPDATE SET
                label_en    = EXCLUDED.label_en,
                label_fr    = EXCLUDED.label_fr,
                active      = EXCLUDED.active,
                ingested_at = NOW()
            WHERE lobbyist_subject_matter_codes.label_en <> EXCLUDED.label_en
               OR lobbyist_subject_matter_codes.label_fr <> EXCLUDED.label_fr
               OR lobbyist_subject_matter_codes.active   <> EXCLUDED.active
        `, s.OCLCode, s.LabelEN, s.LabelFR, s.Active)
	}

	br := conn.SendBatch(ctx, batch)
	defer br.Close()

	inserted := 0
	for i := 0; i < len(subjects); i++ {
		if _, err := br.Exec(); err != nil {
			return inserted, fmt.Errorf("upsert ocl_code %d: %w", subjects[i].OCLCode, err)
		}
		inserted++
	}
	fmt.Printf("  Successfully upserted %d OCL subject matters\n", inserted)
	return inserted, nil
}

func recordHealth(ctx context.Context, conn *pgx.Conn, name string, count int, runErr error) {
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
	`, name, now, successAt, errMsg, recordCount)
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
			subject_id       TEXT,
			subject_title    TEXT,
			intervention_seq INT,
			word_count       INT,
			language         TEXT NOT NULL DEFAULT 'en',
			search_vector_en TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('en', 'mixed', 'und')
						THEN to_tsvector('english', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED,
			search_vector_fr TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('fr', 'mixed', 'und')
						THEN to_tsvector('french', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED
		);

        CREATE TABLE IF NOT EXISTS pbo_publications (
            id                    TEXT PRIMARY KEY,
            title                 TEXT NOT NULL,
            publication_date      DATE,
            methodology_category  TEXT,
            source_url            TEXT NOT NULL UNIQUE,
            pdf_url               TEXT,
            summary_text          TEXT,
            content_hash          TEXT NOT NULL,
            ingested_at           TIMESTAMPTZ NOT NULL DEFAULT now()
        );

        CREATE TABLE IF NOT EXISTS lobbyist_subject_matter_codes (
            ocl_code     INTEGER PRIMARY KEY,
            label_en     TEXT NOT NULL,
            label_fr     TEXT NOT NULL,
            active       BOOLEAN NOT NULL DEFAULT TRUE,
            ingested_at  TIMESTAMPTZ NOT NULL DEFAULT now()
        );

		ALTER TABLE speeches
			ADD COLUMN IF NOT EXISTS subject_id TEXT,
			ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en',
			ADD COLUMN IF NOT EXISTS search_vector_en TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('en', 'mixed', 'und')
						THEN to_tsvector('english', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED,
			ADD COLUMN IF NOT EXISTS search_vector_fr TSVECTOR GENERATED ALWAYS AS (
				CASE
					WHEN language IN ('fr', 'mixed', 'und')
						THEN to_tsvector('french', COALESCE(content, ''))
					ELSE NULL
				END
			) STORED;

		ALTER TABLE speeches
			DROP CONSTRAINT IF EXISTS speeches_language_check,
			ADD CONSTRAINT speeches_language_check
				CHECK (language IN ('en', 'fr', 'mixed', 'und'));

		CREATE INDEX IF NOT EXISTS speeches_member_date_idx
			ON speeches(member_id, sitting_date DESC);

		CREATE INDEX IF NOT EXISTS speeches_fts_idx
			ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));

		CREATE INDEX IF NOT EXISTS speeches_fts_en_idx
			ON speeches USING gin(search_vector_en)
			WHERE search_vector_en IS NOT NULL;

		CREATE INDEX IF NOT EXISTS speeches_fts_fr_idx
			ON speeches USING gin(search_vector_fr)
			WHERE search_vector_fr IS NOT NULL;

		CREATE INDEX IF NOT EXISTS speeches_subject_idx
			ON speeches(subject_title);

		CREATE INDEX IF NOT EXISTS speeches_subject_id_idx
			ON speeches(subject_id);

        CREATE INDEX IF NOT EXISTS idx_pbo_pub_date ON pbo_publications(publication_date DESC);
        CREATE INDEX IF NOT EXISTS idx_pbo_category ON pbo_publications(methodology_category);

        CREATE INDEX IF NOT EXISTS idx_lobbyist_subject_matter_codes_active
            ON lobbyist_subject_matter_codes(active);
	`)
	return err
}
