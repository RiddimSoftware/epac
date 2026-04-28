// hansard-backfill downloads, archives, parses, and upserts House of Commons
// Hansard XML files across multiple parliamentary sessions.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"encoding/xml"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

const (
	defaultBaseURL   = "https://www.ourcommons.ca/Content/House"
	defaultUserAgent = "epac-hansard-backfill/1.0 (Civic Engagement Tool; contact: sunny)"
	pipelineName     = "hansard-backfill"
)

type Session struct {
	Parliament    int
	SessionNumber int
}

type SittingRef struct {
	Session
	Sitting int
}

type SourceMetadata struct {
	URL          string    `json:"url"`
	RawXMLPath   string    `json:"raw_xml_path"`
	ETag         string    `json:"etag,omitempty"`
	LastModified string    `json:"last_modified,omitempty"`
	FetchedAt    time.Time `json:"fetched_at"`
}

type Intervention struct {
	Id                 string
	MemberId           string
	Speaker            string
	SpeakerParty       string
	SpeechTime         string
	OrderTitle         string
	SubjectTitle       string
	SubjectQualifier   string
	InterventionSeq    int
	Content            string
	WordCount          int
	SittingDate        time.Time
	ParliamentNum      int
	SessionNum         int
	Filename           string
	Language           string
	SourceURL          string
	RawXMLPath         string
	SourceETag         string
	SourceLastModified string
	RelatedBillIDs     []string
	RelatedVoteIDs     []string
	ParagraphIDs       []string
}

type Config struct {
	Sessions        []Session
	StartDate       time.Time
	EndDate         time.Time
	ArchiveDir      string
	BaseURL         string
	UserAgent       string
	Force           bool
	DryRun          bool
	MaxSittings     int
	StopAfterMisses int
	Delay           time.Duration
}

type Summary struct {
	SittingsSeen          int `json:"sittings_seen"`
	SittingsArchived      int `json:"sittings_archived"`
	SittingsParsed        int `json:"sittings_parsed"`
	SittingsSkipped       int `json:"sittings_skipped"`
	SittingsMissing       int `json:"sittings_missing"`
	InterventionsExpected int `json:"interventions_expected"`
	InterventionsRead     int `json:"interventions_read"`
	InterventionsKept     int `json:"interventions_kept"`
	SpeechesUpserted      int `json:"speeches_upserted"`
}

func main() {
	cfg, err := configFromFlags(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "configuration error: %v\n", err)
		os.Exit(2)
	}

	ctx := context.Background()
	var conn *pgx.Conn
	if !cfg.DryRun {
		connStr := os.Getenv("DATABASE_URL")
		if connStr == "" {
			fmt.Fprintln(os.Stderr, "DATABASE_URL environment variable is not set")
			os.Exit(2)
		}
		conn, err = pgx.Connect(ctx, connStr)
		if err != nil {
			fmt.Fprintf(os.Stderr, "unable to connect to database: %v\n", err)
			os.Exit(1)
		}
		defer conn.Close(ctx)
		if err := ensureSchema(ctx, conn); err != nil {
			fmt.Fprintf(os.Stderr, "schema error: %v\n", err)
			os.Exit(1)
		}
	}

	summary, err := RunBackfill(ctx, conn, http.DefaultClient, cfg)
	if conn != nil {
		recordHealth(ctx, conn, summary.SpeechesUpserted, err)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "backfill error: %v\n", err)
		os.Exit(1)
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(summary)
}

func configFromFlags(args []string) (Config, error) {
	fs := flag.NewFlagSet("hansard-backfill", flag.ContinueOnError)
	sessionList := fs.String("sessions", "43-2,44-1,45-1", "comma-separated parliament-session list")
	startDate := fs.String("start-date", time.Now().UTC().AddDate(-5, 0, 0).Format("2006-01-02"), "inclusive YYYY-MM-DD sitting date")
	endDate := fs.String("end-date", time.Now().UTC().Format("2006-01-02"), "inclusive YYYY-MM-DD sitting date")
	archiveDir := fs.String("archive-dir", "../../data/hansard/raw", "directory for archived XML")
	baseURL := fs.String("base-url", defaultBaseURL, "base URL for House content XML")
	force := fs.Bool("force", false, "re-download archived XML files")
	dryRun := fs.Bool("dry-run", false, "download and parse without writing to the database")
	maxSittings := fs.Int("max-sittings", 1000, "maximum sitting number to probe per session")
	stopAfterMisses := fs.Int("stop-after-misses", 10, "stop a session after this many consecutive missing sittings")
	delayMS := fs.Int("delay-ms", 50, "delay between network requests")
	if err := fs.Parse(args); err != nil {
		return Config{}, err
	}

	sessions, err := parseSessions(*sessionList)
	if err != nil {
		return Config{}, err
	}
	start, err := parseDateFlag(*startDate)
	if err != nil {
		return Config{}, fmt.Errorf("start-date: %w", err)
	}
	end, err := parseDateFlag(*endDate)
	if err != nil {
		return Config{}, fmt.Errorf("end-date: %w", err)
	}
	if start.After(end) {
		return Config{}, errors.New("start-date must be on or before end-date")
	}
	if *maxSittings < 1 {
		return Config{}, errors.New("max-sittings must be positive")
	}
	if *stopAfterMisses < 1 {
		return Config{}, errors.New("stop-after-misses must be positive")
	}

	return Config{
		Sessions:        sessions,
		StartDate:       start,
		EndDate:         end,
		ArchiveDir:      *archiveDir,
		BaseURL:         strings.TrimRight(*baseURL, "/"),
		UserAgent:       defaultUserAgent,
		Force:           *force,
		DryRun:          *dryRun,
		MaxSittings:     *maxSittings,
		StopAfterMisses: *stopAfterMisses,
		Delay:           time.Duration(*delayMS) * time.Millisecond,
	}, nil
}

func RunBackfill(ctx context.Context, conn *pgx.Conn, client *http.Client, cfg Config) (Summary, error) {
	if cfg.UserAgent == "" {
		cfg.UserAgent = defaultUserAgent
	}
	if cfg.BaseURL == "" {
		cfg.BaseURL = defaultBaseURL
	}
	var summary Summary

	for _, session := range cfg.Sessions {
		consecutiveMissing := 0
		for sitting := 1; sitting <= cfg.MaxSittings; sitting++ {
			ref := SittingRef{Session: session, Sitting: sitting}
			summary.SittingsSeen++

			body, meta, downloaded, missing, err := fetchOrReadArchive(ctx, client, cfg, ref)
			if err != nil {
				return summary, err
			}
			if missing {
				summary.SittingsMissing++
				consecutiveMissing++
				if consecutiveMissing >= cfg.StopAfterMisses {
					break
				}
				continue
			}
			consecutiveMissing = 0
			if downloaded {
				summary.SittingsArchived++
			}

			expected, err := countStartElements(bytes.NewReader(body), "Intervention")
			if err != nil {
				return summary, fmt.Errorf("count interventions %s: %w", ref.Filename(), err)
			}
			summary.InterventionsExpected += expected

			interventions, err := parseHansard(bytes.NewReader(body), ref.Filename(), meta)
			if err != nil {
				return summary, fmt.Errorf("parse %s: %w", ref.Filename(), err)
			}
			if len(interventions) != expected {
				return summary, fmt.Errorf("parse %s: intervention row count mismatch: parsed %d, expected %d", ref.Filename(), len(interventions), expected)
			}
			if len(interventions) == 0 {
				summary.SittingsSkipped++
				continue
			}
			summary.SittingsParsed++
			summary.InterventionsRead += len(interventions)

			kept := filterByDate(interventions, cfg.StartDate, cfg.EndDate)
			if len(kept) == 0 {
				summary.SittingsSkipped++
				continue
			}
			summary.InterventionsKept += len(kept)

			if !cfg.DryRun {
				n, err := upsertSpeeches(ctx, conn, kept)
				if err != nil {
					return summary, fmt.Errorf("upsert %s: %w", ref.Filename(), err)
				}
				summary.SpeechesUpserted += n
			}
			if cfg.Delay > 0 {
				select {
				case <-ctx.Done():
					return summary, ctx.Err()
				case <-time.After(cfg.Delay):
				}
			}
		}
	}

	return summary, nil
}

func parseSessions(raw string) ([]Session, error) {
	parts := strings.Split(raw, ",")
	sessions := make([]Session, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		bits := strings.Split(part, "-")
		if len(bits) != 2 {
			return nil, fmt.Errorf("invalid session %q, expected N-N", part)
		}
		parl, err := strconv.Atoi(bits[0])
		if err != nil {
			return nil, fmt.Errorf("invalid parliament in %q", part)
		}
		sess, err := strconv.Atoi(bits[1])
		if err != nil {
			return nil, fmt.Errorf("invalid session in %q", part)
		}
		sessions = append(sessions, Session{Parliament: parl, SessionNumber: sess})
	}
	if len(sessions) == 0 {
		return nil, errors.New("at least one session is required")
	}
	return sessions, nil
}

func parseDateFlag(s string) (time.Time, error) {
	t, err := time.Parse("2006-01-02", strings.TrimSpace(s))
	if err != nil {
		return time.Time{}, err
	}
	return t, nil
}

func (r SittingRef) SessionCode() string {
	return fmt.Sprintf("%d%d", r.Parliament, r.SessionNumber)
}

func (r SittingRef) SittingPadded() string {
	return fmt.Sprintf("%03d", r.Sitting)
}

func (r SittingRef) Filename() string {
	return fmt.Sprintf("%d-%d-HAN%s-E.XML", r.Parliament, r.SessionNumber, r.SittingPadded())
}

func (r SittingRef) URL(baseURL string) string {
	return fmt.Sprintf("%s/%s/Debates/%s/HAN%s-E.XML", strings.TrimRight(baseURL, "/"), r.SessionCode(), r.SittingPadded(), r.SittingPadded())
}

func archivePath(archiveDir string, ref SittingRef) string {
	return filepath.Join(archiveDir, fmt.Sprintf("%d-%d", ref.Parliament, ref.SessionNumber), ref.Filename())
}

func fetchOrReadArchive(ctx context.Context, client *http.Client, cfg Config, ref SittingRef) ([]byte, SourceMetadata, bool, bool, error) {
	path := archivePath(cfg.ArchiveDir, ref)
	url := ref.URL(cfg.BaseURL)
	if !cfg.Force {
		if body, err := os.ReadFile(path); err == nil {
			meta := readMetadata(path)
			if meta.URL == "" {
				meta.URL = url
			}
			meta.RawXMLPath = path
			return body, meta, false, false, nil
		} else if !errors.Is(err, os.ErrNotExist) {
			return nil, SourceMetadata{}, false, false, err
		}
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, SourceMetadata{}, false, false, err
	}
	req.Header.Set("User-Agent", cfg.UserAgent)
	resp, err := client.Do(req)
	if err != nil {
		return nil, SourceMetadata{}, false, false, err
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusNotFound {
		return nil, SourceMetadata{}, false, true, nil
	}
	if resp.StatusCode != http.StatusOK {
		return nil, SourceMetadata{}, false, false, fmt.Errorf("%s returned status %d", url, resp.StatusCode)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, SourceMetadata{}, false, false, err
	}
	if !looksLikeXML(resp.Header.Get("Content-Type"), body) {
		return nil, SourceMetadata{}, false, false, fmt.Errorf("%s did not return Hansard XML", url)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, SourceMetadata{}, false, false, err
	}
	if err := os.WriteFile(path, body, 0o644); err != nil {
		return nil, SourceMetadata{}, false, false, err
	}

	meta := SourceMetadata{
		URL:          url,
		RawXMLPath:   path,
		ETag:         resp.Header.Get("ETag"),
		LastModified: resp.Header.Get("Last-Modified"),
		FetchedAt:    time.Now().UTC(),
	}
	_ = writeMetadata(path, meta)
	return body, meta, true, false, nil
}

func looksLikeXML(contentType string, body []byte) bool {
	ct := strings.ToLower(contentType)
	if strings.Contains(ct, "xml") {
		return true
	}
	return bytes.Contains(bytes.TrimSpace(body[:min(len(body), 128)]), []byte("<?xml"))
}

func readMetadata(path string) SourceMetadata {
	var meta SourceMetadata
	b, err := os.ReadFile(path + ".json")
	if err != nil {
		return meta
	}
	_ = json.Unmarshal(b, &meta)
	return meta
}

func writeMetadata(path string, meta SourceMetadata) error {
	b, err := json.MarshalIndent(meta, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path+".json", b, 0o644)
}

func parseHansard(r io.Reader, filename string, meta SourceMetadata) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)
	var interventions []Intervention

	var (
		parliamentNum   int
		sessionNum      int
		sittingDate     time.Time
		docLanguage     = "und"
		inExtractedItem bool
		currentItemName string
	)
	var (
		currentOrderTitle string
		inOrderTitle      bool
		currentSubject    string
		currentQualifier  string
		currentTimestamp  string
		subjectSeq        int
		inSubjectTitle    bool
		inQualifier       bool
		currentLanguage   string
	)
	var current *Intervention
	var (
		inPersonSpeaking int
		inContentEl      int
		captureAffPS     bool
		inParaText       int
	)

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
			case "Hansard":
				if lang := attrValue(se, "lang"); lang != "" {
					docLanguage = normalizeLanguage(lang)
					currentLanguage = docLanguage
				}
			case "ExtractedItem":
				inExtractedItem = true
				currentItemName = attrValue(se, "Name")
			case "OrderOfBusiness":
				currentOrderTitle = ""
			case "OrderOfBusinessTitle":
				inOrderTitle = true
			case "SubjectOfBusiness":
				currentSubject = ""
				currentQualifier = ""
				subjectSeq = 0
			case "SubjectOfBusinessTitle":
				inSubjectTitle = true
			case "SubjectOfBusinessQualifier":
				inQualifier = true
			case "FloorLanguage":
				if lang := attrValue(se, "language"); lang != "" {
					currentLanguage = normalizeLanguage(lang)
					if current != nil && current.Language == "" {
						current.Language = currentLanguage
					}
				}
			case "Timestamp":
				if timestamp := timestampFromAttrs(se); timestamp != "" {
					currentTimestamp = timestamp
					if current != nil && current.SpeechTime == "" {
						current.SpeechTime = timestamp
					}
				}
			case "Intervention":
				lang := currentLanguage
				if lang == "" {
					lang = docLanguage
				}
				current = &Intervention{
					Id:                 attrValue(se, "id"),
					SpeechTime:         currentTimestamp,
					OrderTitle:         currentOrderTitle,
					SubjectTitle:       currentSubject,
					SubjectQualifier:   currentQualifier,
					InterventionSeq:    subjectSeq,
					SittingDate:        sittingDate,
					ParliamentNum:      parliamentNum,
					SessionNum:         sessionNum,
					Filename:           filename,
					Language:           lang,
					SourceURL:          meta.URL,
					RawXMLPath:         meta.RawXMLPath,
					SourceETag:         meta.ETag,
					SourceLastModified: meta.LastModified,
				}
				subjectSeq++
			case "PersonSpeaking":
				inPersonSpeaking++
			case "Content":
				inContentEl++
			case "Affiliation":
				if inPersonSpeaking > 0 && inContentEl == 0 && !captureAffPS {
					captureAffPS = true
					if current != nil && current.MemberId == "" {
						current.MemberId = attrValue(se, "DbId")
					}
				}
			case "ParaText":
				if inContentEl > 0 {
					inParaText++
					if current != nil {
						current.ParagraphIDs = appendUnique(current.ParagraphIDs, attrValue(se, "id"))
					}
				}
			case "Document":
				if current != nil {
					docID := attrValue(se, "DbId")
					switch attrValue(se, "Type") {
					case "3", "4":
						current.RelatedBillIDs = appendUnique(current.RelatedBillIDs, docID)
					case "6", "7":
						current.RelatedVoteIDs = appendUnique(current.RelatedVoteIDs, docID)
					}
				}
			case "RecordedDivision", "Vote", "Division":
				if current != nil {
					current.RelatedVoteIDs = appendUnique(current.RelatedVoteIDs, firstNonEmpty(attrValue(se, "DbId"), attrValue(se, "id")))
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
			case inOrderTitle:
				currentOrderTitle += text
			case inSubjectTitle && current == nil:
				currentSubject += text
			case inQualifier && current == nil:
				currentQualifier += text
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
			case "OrderOfBusinessTitle":
				inOrderTitle = false
				currentOrderTitle = normalizeWhitespace(currentOrderTitle)
			case "SubjectOfBusinessTitle":
				inSubjectTitle = false
				currentSubject = normalizeWhitespace(currentSubject)
			case "SubjectOfBusinessQualifier":
				inQualifier = false
				currentQualifier = normalizeWhitespace(currentQualifier)
			case "Intervention":
				if current != nil {
					current.Content = normalizeWhitespace(current.Content)
					current.WordCount = wordCount(current.Content)
					current.Speaker = normalizeWhitespace(current.Speaker)
					current.SpeakerParty = extractPartyFromAffiliation(current.Speaker)
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

func attrValue(se xml.StartElement, name string) string {
	for _, a := range se.Attr {
		if a.Name.Local == name {
			return a.Value
		}
	}
	return ""
}

func timestampFromAttrs(se xml.StartElement) string {
	hour, err := strconv.Atoi(attrValue(se, "Hr"))
	if err != nil {
		return ""
	}
	minute, err := strconv.Atoi(attrValue(se, "Mn"))
	if err != nil {
		return ""
	}
	if hour < 0 || hour > 23 || minute < 0 || minute > 59 {
		return ""
	}
	return fmt.Sprintf("%02d:%02d", hour, minute)
}

func extractPartyFromAffiliation(s string) string {
	s = strings.TrimSpace(s)
	close := strings.LastIndex(s, ")")
	if close == -1 {
		return ""
	}
	open := strings.LastIndex(s[:close], "(")
	if open == -1 || close == -1 || open >= close {
		return ""
	}
	parts := strings.Split(s[open+1:close], ",")
	if len(parts) < 2 {
		return ""
	}
	return normalizeWhitespace(parts[len(parts)-1])
}

func normalizeLanguage(s string) string {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "en", "eng", "english":
		return "en"
	case "fr", "fra", "fre", "french":
		return "fr"
	case "":
		return "und"
	default:
		return strings.ToLower(strings.TrimSpace(s))
	}
}

func normalizeWhitespace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

func appendUnique(values []string, value string) []string {
	value = strings.TrimSpace(value)
	if value == "" || value == "0" {
		return values
	}
	for _, existing := range values {
		if existing == value {
			return values
		}
	}
	return append(values, value)
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func filterByDate(interventions []Intervention, start, end time.Time) []Intervention {
	kept := make([]Intervention, 0, len(interventions))
	for _, inv := range interventions {
		if inv.SittingDate.IsZero() {
			kept = append(kept, inv)
			continue
		}
		if inv.SittingDate.Before(start) || inv.SittingDate.After(end) {
			continue
		}
		kept = append(kept, inv)
	}
	return kept
}

func parseHansardDate(s string) time.Time {
	dayPrefix := regexp.MustCompile(`^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday),\s+`)
	cleaned := dayPrefix.ReplaceAllString(strings.TrimSpace(s), "")
	t, err := time.Parse("January 2, 2006", cleaned)
	if err != nil {
		return time.Time{}
	}
	return t
}

func wordCount(s string) int {
	return len(strings.Fields(s))
}

func countStartElements(r io.Reader, localName string) (int, error) {
	decoder := xml.NewDecoder(r)
	count := 0
	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			return count, nil
		}
		if err != nil {
			return count, err
		}
		if se, ok := tok.(xml.StartElement); ok && se.Name.Local == localName {
			count++
		}
	}
}

func upsertSpeeches(ctx context.Context, conn *pgx.Conn, interventions []Intervention) (int, error) {
	if conn == nil {
		return 0, errors.New("database connection is nil")
	}
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
				subject_title, intervention_seq, word_count,
				order_title, subject_qualifier, source_url, raw_xml_path,
				source_etag, source_last_modified, language,
				related_bill_ids, related_vote_ids, paragraph_ids,
				speaker_party, speech_time
			) VALUES (
				$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
				$12, $13, $14, $15, $16, $17, $18, $19, $20, $21,
				$22, $23
			)
			ON CONFLICT (intervention_id) DO UPDATE SET
				filename             = EXCLUDED.filename,
				speaker_name         = EXCLUDED.speaker_name,
				content              = EXCLUDED.content,
				sitting_date         = EXCLUDED.sitting_date,
				parliament_num       = EXCLUDED.parliament_num,
				session_num          = EXCLUDED.session_num,
				member_id            = EXCLUDED.member_id,
				subject_title        = EXCLUDED.subject_title,
				intervention_seq     = EXCLUDED.intervention_seq,
				word_count           = EXCLUDED.word_count,
				order_title          = EXCLUDED.order_title,
				subject_qualifier    = EXCLUDED.subject_qualifier,
				source_url           = EXCLUDED.source_url,
				raw_xml_path         = EXCLUDED.raw_xml_path,
				source_etag          = EXCLUDED.source_etag,
				source_last_modified = EXCLUDED.source_last_modified,
				language             = EXCLUDED.language,
				related_bill_ids     = EXCLUDED.related_bill_ids,
				related_vote_ids     = EXCLUDED.related_vote_ids,
				paragraph_ids        = EXCLUDED.paragraph_ids,
				speaker_party        = EXCLUDED.speaker_party,
				speech_time          = EXCLUDED.speech_time`,
			inv.Id, inv.Filename, inv.Speaker, inv.Content,
			date, parlNum, sessNum, memberId,
			inv.SubjectTitle, inv.InterventionSeq, inv.WordCount,
			inv.OrderTitle, inv.SubjectQualifier, inv.SourceURL, inv.RawXMLPath,
			inv.SourceETag, inv.SourceLastModified, inv.Language,
			inv.RelatedBillIDs, inv.RelatedVoteIDs, inv.ParagraphIDs,
			inv.SpeakerParty, inv.SpeechTime,
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

func ensureSchema(ctx context.Context, conn *pgx.Conn) error {
	_, err := conn.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS pipeline_health (
			name                    TEXT PRIMARY KEY,
			last_run_at             TIMESTAMPTZ,
			last_success_at         TIMESTAMPTZ,
			last_error              TEXT,
			record_count            INTEGER,
			expected_interval_hours INTEGER NOT NULL DEFAULT 24
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

		ALTER TABLE speeches
		  ADD COLUMN IF NOT EXISTS order_title          TEXT,
		  ADD COLUMN IF NOT EXISTS subject_qualifier    TEXT,
		  ADD COLUMN IF NOT EXISTS source_url           TEXT,
		  ADD COLUMN IF NOT EXISTS raw_xml_path         TEXT,
		  ADD COLUMN IF NOT EXISTS source_etag          TEXT,
		  ADD COLUMN IF NOT EXISTS source_last_modified TEXT,
		  ADD COLUMN IF NOT EXISTS language             TEXT DEFAULT 'en',
		  ADD COLUMN IF NOT EXISTS related_bill_ids     TEXT[] DEFAULT '{}',
		  ADD COLUMN IF NOT EXISTS related_vote_ids     TEXT[] DEFAULT '{}',
		  ADD COLUMN IF NOT EXISTS paragraph_ids        TEXT[] DEFAULT '{}',
		  ADD COLUMN IF NOT EXISTS speaker_party        TEXT,
		  ADD COLUMN IF NOT EXISTS speech_time          TEXT,
		  ADD COLUMN IF NOT EXISTS search_vector        TSVECTOR;

		CREATE INDEX IF NOT EXISTS speeches_member_date_idx
			ON speeches(member_id, sitting_date DESC);
		CREATE INDEX IF NOT EXISTS speeches_fts_idx
			ON speeches USING gin(to_tsvector('english', COALESCE(content, '')));
		CREATE INDEX IF NOT EXISTS speeches_subject_idx
			ON speeches(subject_title);
		CREATE INDEX IF NOT EXISTS speeches_related_bill_ids_idx
			ON speeches USING gin(related_bill_ids);
	`)
	return err
}

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
		VALUES ($1, $2, $3, $4, $5, 168)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at     = EXCLUDED.last_run_at,
			last_success_at = COALESCE(EXCLUDED.last_success_at, pipeline_health.last_success_at),
			last_error      = EXCLUDED.last_error,
			record_count    = COALESCE(EXCLUDED.record_count, pipeline_health.record_count)
	`, pipelineName, now, successAt, errMsg, recordCount)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func sortedStrings(values []string) []string {
	out := append([]string(nil), values...)
	sort.Strings(out)
	return out
}
