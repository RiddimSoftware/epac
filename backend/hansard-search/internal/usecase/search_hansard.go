package usecase

import (
	"context"
	"errors"
	"strings"
	"unicode"
)

var (
	ErrInvalidQuery       = errors.New("invalid hansard search query")
	ErrInvalidPagination  = errors.New("invalid hansard search pagination")
	ErrInvalidQuerySyntax = errors.New("invalid hansard search query syntax")
)

type SearchQuery struct {
	Query   string // FTS5 MATCH expression
	Speaker string // optional case-insensitive substring filter
	Topic   string // optional case-insensitive substring filter
}

type Pagination struct {
	Page    int // 1-indexed
	PerPage int // 1..100
}

type SearchHit struct {
	ParliamentNumber  int
	SessionNumber     int
	SittingDate       string
	InterventionID    string
	MessageID         string
	SpeakerName       string
	PartyAbbreviation string
	RidingName        string
	Topic             string
	Snippet           string
	Score             float64
}

type SearchResults struct {
	Total int
	Hits  []SearchHit
}

type HansardSearchRepository interface {
	Search(ctx context.Context, q SearchQuery, p Pagination) (SearchResults, error)
}

type SearchHansard struct {
	Repo HansardSearchRepository
}

func (s SearchHansard) Execute(ctx context.Context, q SearchQuery, p Pagination) (SearchResults, error) {
	q.Query = strings.TrimSpace(stripControlCharacters(q.Query))
	if q.Query == "" {
		return SearchResults{}, ErrInvalidQuery
	}

	if p.Page < 1 || p.PerPage < 1 || p.PerPage > 100 {
		return SearchResults{}, ErrInvalidPagination
	}

	q.Speaker = strings.TrimSpace(q.Speaker)
	q.Topic = strings.TrimSpace(q.Topic)

	return s.Repo.Search(ctx, q, p)
}

func stripControlCharacters(value string) string {
	return strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, value)
}
