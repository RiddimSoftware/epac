// Package usecase implements the SearchHansard application policy.
//
// It depends only on HansardRepository and MemberRepository ports; it must not
// import database driver, Lambda runtime, or cloud SDK packages.
package usecase

import (
	"context"
	"strings"
	"time"
)

type SearchResult struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Snippet     string  `json:"snippet"`
	SittingDate *string `json:"sitting_date,omitempty"`
	Subject     *string `json:"subject,omitempty"`
	MemberId    *string `json:"member_id,omitempty"`
}

type SearchResponse struct {
	Query        string         `json:"query"`
	LanguageHint string         `json:"language_hint"`
	Results      []SearchResult `json:"results"`
}

type SearchParams struct {
	Query    string
	UserID   string
	FromDate *time.Time
	ToDate   *time.Time
}

type RankingConfig struct {
	TextWeight        float64
	RecencyWeight     float64
	FollowWeight      float64
	RecencyHalfLife   float64
	LanguageHintBoost float64
	MyMPBoost         float64
	BillBoost         float64
	TopicBoost        float64
}

type SearchContext struct {
	MyMPMemberID      string
	TopicIDs          []string
	BillIDs           []string
	TopicKeywordHints []string
}

// HansardRepository is the outbound port for searching ingested Hansard
// speech records. Matches the catalog's `HansardRepository` port.
type HansardRepository interface {
	SearchSpeeches(ctx context.Context, params SearchParams, languageHint string, searchContext SearchContext, cfg RankingConfig) ([]SearchResult, error)
}

// MemberRepository is the outbound port for resolving member-linked search
// context such as the user's saved MP preference. Matches the catalog's
// `MemberRepository` port.
type MemberRepository interface {
	LoadSearchContext(ctx context.Context, userID string) (SearchContext, error)
}

type SearchHansard struct {
	hansardRepository HansardRepository
	memberRepository  MemberRepository
}

func New(hansardRepository HansardRepository, memberRepository MemberRepository) *SearchHansard {
	return &SearchHansard{
		hansardRepository: hansardRepository,
		memberRepository:  memberRepository,
	}
}

func (u *SearchHansard) Execute(ctx context.Context, params SearchParams, cfg RankingConfig) (SearchResponse, error) {
	languageHint := DetectQueryLanguage(params.Query)
	searchContext, err := u.memberRepository.LoadSearchContext(ctx, params.UserID)
	if err != nil {
		return SearchResponse{}, err
	}
	searchContext.TopicKeywordHints = FollowedTopicKeywords(searchContext.TopicIDs)

	results, err := u.hansardRepository.SearchSpeeches(ctx, params, languageHint, searchContext, cfg)
	if err != nil {
		return SearchResponse{}, err
	}
	if results == nil {
		results = []SearchResult{}
	}
	return SearchResponse{
		Query:        params.Query,
		LanguageHint: languageHint,
		Results:      results,
	}, nil
}

func DetectQueryLanguage(query string) string {
	lower := strings.ToLower(query)
	if strings.ContainsAny(lower, "àâçéèêëîïôùûüÿœ") {
		return "fr"
	}

	words := strings.FieldsFunc(lower, func(r rune) bool {
		return r < 'a' || r > 'z'
	})
	frenchMarkers := map[string]bool{
		"des": true, "les": true, "une": true, "avec": true, "pour": true,
		"aux": true, "sur": true, "dans": true, "budgetaire": true,
		"gouvernement": true, "logement": true, "sante": true,
	}
	for _, word := range words {
		if frenchMarkers[word] {
			return "fr"
		}
	}
	return "en"
}
