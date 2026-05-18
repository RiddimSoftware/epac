package main

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"daily-fetch/internal/adapter/postgres"
	"daily-fetch/internal/usecase"
	"epac/observability"

	"github.com/aws/aws-lambda-go/lambda"
)

type Intervention = usecase.Intervention

type systemClock struct{}

func (systemClock) Now() time.Time {
	return time.Now()
}

func main() {
	lambda.Start(observability.WrapNoEvent("daily-fetch", HandleRequest))
}

func HandleRequest(ctx context.Context) error {
	conn, err := postgres.Connect(ctx)
	if err != nil {
		return fmt.Errorf("unable to connect to database: %w", err)
	}
	defer conn.Close(ctx)

	repo := postgres.NewHansardRepository(conn)
	ingest := usecase.New(repo, systemClock{})
	next, err := ingest.Next(ctx)
	if err != nil {
		return err
	}

	fmt.Printf("Attempting to download sitting %d from %s\n", next.Sitting, next.URL)

	httpClient := &http.Client{Timeout: 30 * time.Second}
	interventions, err := downloadAndParse(httpClient, next.URL, next.Filename)
	if err != nil {
		fetchErr := fmt.Errorf("failed to download or parse Hansard: %w", err)
		ingest.RecordHealth(ctx, 0, fetchErr)
		return fetchErr
	}

	if len(interventions) == 0 {
		fmt.Printf("No interventions found for sitting %d. Not available yet.\n", next.Sitting)
		ingest.RecordHealth(ctx, 0, nil)
		return nil
	}

	n, err := ingest.Execute(ctx, interventions)
	if err != nil {
		insertErr := fmt.Errorf("failed to upsert speeches: %w", err)
		return insertErr
	}

	fmt.Printf("Successfully upserted %d entries from sitting %d\n", n, next.Sitting)
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
		inSubjectTitle   bool
		currentSubjectID string
		currentSubject   string
		subjectSeq       int
	)

	var current *Intervention
	currentFloorLanguage := "und"

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
	return usecase.NormalizeLanguage(language)
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
