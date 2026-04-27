package main

import (
	"encoding/xml"
	"fmt"
	"io"
	"strings"
	"time"
)

// Intervention is one speech or procedural remark extracted from a Hansard XML file.
type Intervention struct {
	Id                   string
	SittingDate          time.Time
	ParliamentNum        int
	SessionNum           int
	MemberDbId           string // DbId attribute from PersonSpeaking/Affiliation
	SpeakerName          string // visible text of PersonSpeaking/Affiliation
	SubjectId            string
	SubjectTitle         string
	InterventionSequence int
	Content              string
	WordCount            int
}

// ParseHansardXML streams a Hansard XML reader and returns all interventions.
// Extracts sitting date, parliament/session numbers, and subject context from
// the document header before processing intervention content.
func ParseHansardXML(r io.Reader) ([]Intervention, error) {
	decoder := xml.NewDecoder(r)

	// ── Header metadata (populated from ExtractedItem elements) ────────────
	var yearStr, monthStr, dayStr, parliStr, sessStr string
	var sittingDate time.Time
	var parliamentNum, sessionNum int
	headerDone := false

	inExtractedItem := false
	extractedItemName := ""

	// ── Subject tracking ────────────────────────────────────────────────────
	var currentSubjectId, currentSubjectTitle string
	var subjectSequence int
	inSubjectTitle := false

	// ── Intervention tracking ────────────────────────────────────────────────
	var interventions []Intervention
	var current *Intervention

	// ── PersonSpeaking tracking ──────────────────────────────────────────────
	inPersonSpeaking := false
	inPersonAffil := false // only the Affiliation directly inside PersonSpeaking

	// ── Content tracking ────────────────────────────────────────────────────
	inContent := false
	paraTextDepth := 0 // > 0 means we're capturing speech text
	contentNested := 0 // depth of non-ParaText nested elements within ParaText

	// Finalize header once: parse date, parliament, session
	finalizeHeader := func() {
		if headerDone {
			return
		}
		headerDone = true
		if yearStr != "" && monthStr != "" && dayStr != "" {
			dateStr := fmt.Sprintf("%s-%02s-%02s", yearStr,
				zeroPad(monthStr), zeroPad(dayStr))
			t, err := time.Parse("2006-01-02", dateStr)
			if err == nil {
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
		// ── Start elements ────────────────────────────────────────────────
		case xml.StartElement:
			lname := se.Name.Local

			// Header: ExtractedItem
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

			// Subject context
			if lname == "SubjectOfBusiness" {
				finalizeHeader()
				currentSubjectId = ""
				currentSubjectTitle = ""
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

			// Intervention
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
				inPersonSpeaking = false
				inPersonAffil = false
				inContent = false
				paraTextDepth = 0
				contentNested = 0
				continue
			}

			if current == nil {
				continue
			}

			// PersonSpeaking
			if lname == "PersonSpeaking" {
				inPersonSpeaking = true
				continue
			}
			if inPersonSpeaking && lname == "Affiliation" {
				inPersonAffil = true
				for _, a := range se.Attr {
					if a.Name.Local == "DbId" && current.MemberDbId == "" {
						current.MemberDbId = a.Value
					}
				}
				continue
			}

			// Content
			if lname == "Content" {
				inContent = true
				continue
			}
			if inContent {
				if lname == "ParaText" {
					paraTextDepth++
				} else if paraTextDepth > 0 {
					// nested element inside ParaText (Affiliation, B, I, etc.)
					contentNested++
				}
			}

		// ── Character data ────────────────────────────────────────────────
		case xml.CharData:
			text := string(se)

			// Header values
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

			if current == nil {
				if inSubjectTitle {
					currentSubjectTitle += text
				}
				continue
			}

			if inSubjectTitle {
				currentSubjectTitle += text
				continue
			}

			// PersonSpeaking speaker name
			if inPersonAffil {
				current.SpeakerName += text
				continue
			}

			// Content text (inside ParaText, not inside nested Affiliation)
			if inContent && paraTextDepth > 0 && contentNested == 0 {
				current.Content += text
			}

		// ── End elements ──────────────────────────────────────────────────
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
				inPersonSpeaking = false
				inPersonAffil = false
				current.SpeakerName = strings.TrimSpace(current.SpeakerName)
				continue
			}
			if inPersonSpeaking && lname == "Affiliation" {
				inPersonAffil = false
				continue
			}

			if inContent {
				if lname == "ParaText" {
					if paraTextDepth > 0 {
						paraTextDepth--
					}
					if paraTextDepth == 0 {
						current.Content += " "
					}
				} else if paraTextDepth > 0 && lname != "Content" {
					if contentNested > 0 {
						contentNested--
					}
				}
				if lname == "Content" {
					inContent = false
					paraTextDepth = 0
					contentNested = 0
					current.Content = strings.TrimSpace(current.Content)
					current.WordCount = countWords(current.Content)
				}
				continue
			}

			if lname == "Intervention" {
				if current.Content != "" {
					interventions = append(interventions, *current)
				}
				current = nil
			}
		}
	}

	return interventions, nil
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
