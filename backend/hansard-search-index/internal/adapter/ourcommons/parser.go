package ourcommons

import (
	"bytes"
	"encoding/xml"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"time"

	"epac/hansard-search-index/internal/domain"
)

type Parser struct {
	logger      Logger
	unknownSeen map[string]bool
}

func NewParser(logger Logger) *Parser {
	return &Parser{
		logger:      defaultLogger(logger),
		unknownSeen: map[string]bool{},
	}
}

func (p *Parser) Parse(body []byte) ([]domain.Intervention, error) {
	decoder := xml.NewDecoder(bytes.NewReader(body))
	var interventions []domain.Intervention

	var parliamentNumber int
	var sessionNumber int
	var sittingDate time.Time
	var inExtractedItem bool
	var currentItemName string

	var currentSubject string
	var inSubjectTitle bool
	var current *interventionBuilder
	var inPersonSpeaking int
	var inContent int
	var captureSpeaker bool
	var inParaText int

	for {
		tok, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			p.warn("malformed_xml", map[string]any{"error": err.Error()})
			return nil, fmt.Errorf("decode XML: %w", err)
		}

		switch se := tok.(type) {
		case xml.StartElement:
			p.noteUnknown(se)
			switch se.Name.Local {
			case "ExtractedItem":
				inExtractedItem = true
				currentItemName = attrValue(se, "Name")
			case "SubjectOfBusiness":
				currentSubject = ""
			case "SubjectOfBusinessTitle":
				inSubjectTitle = true
			case "Intervention":
				current = &interventionBuilder{
					Intervention: domain.Intervention{
						ParliamentNumber: parliamentNumber,
						SessionNumber:    sessionNumber,
						SittingDate:      sittingDate,
						InterventionID:   strings.TrimSpace(attrValue(se, "id")),
						Topic:            strings.TrimSpace(currentSubject),
					},
				}
			case "PersonSpeaking":
				inPersonSpeaking++
			case "Content":
				inContent++
			case "Affiliation":
				if current != nil && inPersonSpeaking > 0 && inContent == 0 {
					captureSpeaker = true
				}
			case "ParaText":
				if current != nil && inContent > 0 {
					inParaText++
					id := strings.TrimSpace(attrValue(se, "id"))
					if id == "" {
						p.warn("malformed_para_text", map[string]any{
							"intervention_id": current.InterventionID,
							"reason":          "missing id",
						})
						continue
					}
					current.startMessage(id)
				}
			}
		case xml.CharData:
			text := string(se)
			switch {
			case inExtractedItem:
				switch currentItemName {
				case "ParliamentNumber":
					parliamentNumber, _ = strconv.Atoi(strings.TrimSpace(text))
				case "SessionNumber":
					sessionNumber, _ = strconv.Atoi(strings.TrimSpace(text))
				case "Date":
					sittingDate = parseHansardDate(strings.TrimSpace(text))
				}
			case inSubjectTitle && current == nil:
				currentSubject += text
			case current != nil && captureSpeaker:
				current.speaker += text
			case current != nil && inParaText > 0:
				current.writeMessageText(text)
			}
		case xml.EndElement:
			switch se.Name.Local {
			case "ExtractedItem":
				inExtractedItem = false
				currentItemName = ""
			case "SubjectOfBusinessTitle":
				inSubjectTitle = false
				currentSubject = normalizeWhitespace(currentSubject)
			case "Intervention":
				if current != nil {
					intervention, ok := current.finish(p.logger)
					if ok {
						interventions = append(interventions, intervention)
					}
					current = nil
				}
			case "PersonSpeaking":
				if inPersonSpeaking > 0 {
					inPersonSpeaking--
				}
			case "Affiliation":
				captureSpeaker = false
			case "Content":
				if inContent > 0 {
					inContent--
				}
			case "ParaText":
				if current != nil && inParaText > 0 {
					inParaText--
					current.endMessage()
				}
			}
		}
	}
	return interventions, nil
}

type interventionBuilder struct {
	domain.Intervention
	speaker        string
	currentMessage *domain.Message
}

func (b *interventionBuilder) startMessage(id string) {
	b.currentMessage = &domain.Message{
		MessageID: id,
		Position:  len(b.Messages) + 1,
	}
}

func (b *interventionBuilder) writeMessageText(text string) {
	if b.currentMessage != nil {
		b.currentMessage.Text += text
	}
}

func (b *interventionBuilder) endMessage() {
	if b.currentMessage == nil {
		return
	}
	b.currentMessage.Text = normalizeWhitespace(b.currentMessage.Text)
	if b.currentMessage.Text != "" {
		b.Messages = append(b.Messages, *b.currentMessage)
	}
	b.currentMessage = nil
}

func (b *interventionBuilder) finish(logger Logger) (domain.Intervention, bool) {
	if b.InterventionID == "" {
		logger.Warn("malformed_intervention", map[string]any{"reason": "missing id"})
		return domain.Intervention{}, false
	}
	speaker := parseSpeaker(b.speaker)
	b.SpeakerFirstName = speaker.firstName
	b.SpeakerLastName = speaker.lastName
	b.PartyAbbreviation = speaker.partyAbbreviation
	b.RidingName = speaker.ridingName
	return b.Intervention, true
}

type parsedSpeaker struct {
	firstName         string
	lastName          string
	partyAbbreviation string
	ridingName        string
}

func parseSpeaker(text string) parsedSpeaker {
	text = strings.TrimSpace(strings.ReplaceAll(text, "Mme ", "Mme. "))
	name := strings.TrimSpace(text)
	details := ""
	if open := strings.Index(text, "("); open >= 0 {
		name = strings.TrimSpace(text[:open])
		if close := strings.LastIndex(text, ")"); close > open {
			details = strings.TrimSpace(text[open+1 : close])
		}
	}
	party := partyFromDetails(details)
	riding := ridingFromDetails(details)
	if party == "" && riding == "" && details != "" {
		name = details
	}
	first, last := speakerNameParts(name)
	return parsedSpeaker{
		firstName:         first,
		lastName:          last,
		partyAbbreviation: party,
		ridingName:        riding,
	}
}

func partyFromDetails(details string) string {
	comma := strings.LastIndex(details, ",")
	if comma == -1 {
		return ""
	}
	return strings.TrimSuffix(strings.TrimSpace(details[comma+1:]), ".")
}

func ridingFromDetails(details string) string {
	comma := strings.LastIndex(details, ",")
	if comma == -1 {
		return ""
	}
	ridingOrRole := strings.TrimSpace(details[:comma])
	if roleComma := strings.LastIndex(ridingOrRole, ","); roleComma >= 0 {
		return strings.TrimSpace(ridingOrRole[roleComma+1:])
	}
	if strings.Contains(ridingOrRole, "(") {
		return ""
	}
	return ridingOrRole
}

func speakerNameParts(name string) (string, string) {
	parts := strings.Fields(name)
	cleaned := make([]string, 0, len(parts))
	for _, part := range parts {
		if !speakerTitleWords[part] {
			cleaned = append(cleaned, part)
		}
	}
	if len(cleaned) == 0 {
		return "", ""
	}
	if len(cleaned) == 1 {
		return "", cleaned[0]
	}
	return strings.Join(cleaned[:len(cleaned)-1], " "), cleaned[len(cleaned)-1]
}

var speakerTitleWords = map[string]bool{
	"Hon.": true, "Rt.": true, "Mr.": true, "Ms.": true, "Mrs.": true,
	"Mme.": true, "Mme": true, "M.": true, "L'hon.": true, "L'hon": true,
	"Dr.": true, "The": true, "Hon": true, "Rt": true, "Right": true,
}

func attrValue(se xml.StartElement, name string) string {
	for _, attr := range se.Attr {
		if attr.Name.Local == name {
			return attr.Value
		}
	}
	return ""
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

func normalizeWhitespace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

func (p *Parser) noteUnknown(se xml.StartElement) {
	if knownElements[se.Name.Local] || p.unknownSeen[se.Name.Local] {
		return
	}
	p.unknownSeen[se.Name.Local] = true
	p.warn("unknown_element", map[string]any{"element": se.Name.Local})
}

func (p *Parser) warn(event string, fields map[string]any) {
	p.logger.Warn(event, fields)
}

var knownElements = map[string]bool{
	"Affiliation": true, "CatchLine": true, "Content": true, "DocumentTitle": true,
	"ExtractedInformation": true, "ExtractedItem": true, "FloorLanguage": true,
	"Hansard": true, "HansardBody": true, "Intervention": true, "Intro": true,
	"I": true, "OrderOfBusiness": true, "OrderOfBusinessTitle": true, "ParaText": true,
	"PersonSpeaking": true, "Prayer": true, "ProceduralText": true, "Quote": true,
	"QuotePara": true, "StartPageNumber": true, "SubjectOfBusiness": true,
	"SubjectOfBusinessContent": true, "SubjectOfBusinessQualifier": true,
	"SubjectOfBusinessTitle": true, "Sup": true, "Timestamp": true,
}
