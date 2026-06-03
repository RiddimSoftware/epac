// Package usecase implements the LoadLobbyingByTopic application policy.
//
// It depends only on ports for OCL topic mapping and lobbying records. Lambda,
// SQLite, S3, and JSON-file details stay in adapters.
package usecase

import (
	"context"
	"errors"
	"strings"
)

const (
	DefaultPerPage         = 50
	MaxPerPage             = 200
	LowConfidenceThreshold = 0.80
	Citation               = "Source: Office of the Commissioner of Lobbying (OCL)"
	SourceURL              = "https://lobbycanada.gc.ca/en/open-data/"
)

var ErrInvalidPagination = errors.New("invalid pagination")

type EpacTopicSlug string

type OCLTopicMapping struct {
	OCLCode       string
	EpacTopicSlug string
	Confidence    float64
}

type Pagination struct {
	Page    int
	PerPage int
}

type LobbyingByTopicRecord struct {
	Kind               string  `json:"kind"`
	OCLID              string  `json:"ocl_id"`
	OCLCode            string  `json:"ocl_code"`
	EpacTopicSlug      string  `json:"epac_topic_slug"`
	MappingConfidence  float64 `json:"mapping_confidence"`
	SubjectMatter      string  `json:"subject_matter"`
	SubjectDescription string  `json:"subject_description,omitempty"`
	OrganizationName   string  `json:"organization_name,omitempty"`
	RegistrantName     string  `json:"registrant_name,omitempty"`
	RegistrantType     string  `json:"registrant_type,omitempty"`
	CommunicationDate  string  `json:"communication_date,omitempty"`
	PostedDate         string  `json:"posted_date,omitempty"`
	EffectiveDate      string  `json:"effective_date,omitempty"`
	EndDate            string  `json:"end_date,omitempty"`
	Citation           string  `json:"citation"`
	SourceURL          string  `json:"source_url"`
}

type LobbyingByTopicResult struct {
	TopicSlug string                  `json:"topic_slug"`
	Page      int                     `json:"page"`
	PerPage   int                     `json:"per_page"`
	Total     int                     `json:"total"`
	Citation  string                  `json:"citation"`
	SourceURL string                  `json:"source_url"`
	Rows      []LobbyingByTopicRecord `json:"rows"`
}

type LobbyingByTopicPage struct {
	Total int
	Rows  []LobbyingByTopicRecord
}

type LobbyingSubjectsRepository interface {
	ListByOCLCodes(ctx context.Context, mappings []OCLTopicMapping, pagination Pagination) (LobbyingByTopicPage, error)
}

type OCLSubjectsSource interface {
	CodesForTopic(slug string) ([]OCLTopicMapping, bool)
}

type LowConfidenceLogger interface {
	WarnLowConfidenceMapping(ctx context.Context, mapping OCLTopicMapping)
}

type NoopLowConfidenceLogger struct{}

func (NoopLowConfidenceLogger) WarnLowConfidenceMapping(context.Context, OCLTopicMapping) {}

type LoadLobbyingByTopic struct {
	repo   LobbyingSubjectsRepository
	source OCLSubjectsSource
	logger LowConfidenceLogger
}

func New(repo LobbyingSubjectsRepository, source OCLSubjectsSource, logger LowConfidenceLogger) LoadLobbyingByTopic {
	if logger == nil {
		logger = NoopLowConfidenceLogger{}
	}
	return LoadLobbyingByTopic{repo: repo, source: source, logger: logger}
}

func NewPagination(page, perPage int) (Pagination, error) {
	if page < 1 || perPage < 1 {
		return Pagination{}, ErrInvalidPagination
	}
	if perPage > MaxPerPage {
		perPage = MaxPerPage
	}
	return Pagination{Page: page, PerPage: perPage}, nil
}

func (u LoadLobbyingByTopic) Execute(ctx context.Context, slug string, pagination Pagination) (LobbyingByTopicResult, error) {
	normalizedSlug := NormalizeTopicSlug(slug)
	result := emptyResult(normalizedSlug, pagination)

	mappings, ok := u.source.CodesForTopic(normalizedSlug)
	if !ok || len(mappings) == 0 {
		return result, nil
	}

	for _, mapping := range mappings {
		if mapping.Confidence < LowConfidenceThreshold {
			u.logger.WarnLowConfidenceMapping(ctx, mapping)
		}
	}

	page, err := u.repo.ListByOCLCodes(ctx, mappings, pagination)
	if err != nil {
		return LobbyingByTopicResult{}, err
	}

	mappingByCode := make(map[string]OCLTopicMapping, len(mappings))
	for _, mapping := range mappings {
		mappingByCode[mapping.OCLCode] = mapping
	}

	rows := page.Rows
	if rows == nil {
		rows = []LobbyingByTopicRecord{}
	}
	for i := range rows {
		mapping := mappingByCode[rows[i].OCLCode]
		rows[i].EpacTopicSlug = normalizedSlug
		if rows[i].MappingConfidence == 0 {
			rows[i].MappingConfidence = mapping.Confidence
		}
		if rows[i].Citation == "" {
			rows[i].Citation = Citation
		}
		if rows[i].SourceURL == "" {
			rows[i].SourceURL = SourceURL
		}
	}

	result.Total = page.Total
	result.Rows = rows
	return result, nil
}

func NormalizeTopicSlug(slug string) string {
	return strings.ToLower(strings.TrimSpace(slug))
}

func emptyResult(slug string, pagination Pagination) LobbyingByTopicResult {
	return LobbyingByTopicResult{
		TopicSlug: slug,
		Page:      pagination.Page,
		PerPage:   pagination.PerPage,
		Total:     0,
		Citation:  Citation,
		SourceURL: SourceURL,
		Rows:      []LobbyingByTopicRecord{},
	}
}
