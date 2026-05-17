// Package usecase implements the ViewMemberSpeechFeed application policy.
//
// This package depends only on a HansardRepository port; it must not import
// framework packages (pgx, aws-lambda-go, aws-sdk-go-v2). The Lambda handler
// in main.go wires a concrete postgres adapter to satisfy the port.
package usecase

import (
	"context"
	"math"
)

const (
	DefaultPerPage = 20
	MaxPerPage     = 100
)

type SpeechEntry struct {
	InterventionId string  `json:"id"`
	SittingDate    *string `json:"sitting_date,omitempty"`
	ParliamentNum  *int    `json:"parliament_num,omitempty"`
	SessionNum     *int    `json:"session_num,omitempty"`
	SubjectTitle   *string `json:"subject_title,omitempty"`
	Preview        string  `json:"preview"`
	WordCount      *int    `json:"word_count,omitempty"`
	Filename       string  `json:"filename"`
}

type MemberStats struct {
	TotalSpeeches int    `json:"total_speeches"`
	AvgWordCount  int    `json:"avg_word_count"`
	TopTopic      string `json:"top_topic"`
}

type MemberSpeechesResponse struct {
	MemberId string        `json:"member_id"`
	Page     int           `json:"page"`
	PerPage  int           `json:"per_page"`
	Total    int           `json:"total"`
	Pages    int           `json:"pages"`
	Stats    MemberStats   `json:"stats"`
	Speeches []SpeechEntry `json:"speeches"`
}

// HansardRepository is the outbound port for loading speech records ingested
// from Hansard XML. Matches the catalog's `HansardRepository` port.
type HansardRepository interface {
	CountMemberSpeeches(ctx context.Context, memberId, topic string) (int, error)
	FetchMemberSpeeches(ctx context.Context, memberId string, page, perPage int, topic string) ([]SpeechEntry, error)
	MemberStats(ctx context.Context, memberId string) (MemberStats, error)
}

type ViewMemberSpeechFeed struct {
	repo HansardRepository
}

func New(repo HansardRepository) *ViewMemberSpeechFeed {
	return &ViewMemberSpeechFeed{repo: repo}
}

func (u *ViewMemberSpeechFeed) Execute(ctx context.Context, memberId string, page, perPage int, topic string) (MemberSpeechesResponse, error) {
	total, err := u.repo.CountMemberSpeeches(ctx, memberId, topic)
	if err != nil {
		return MemberSpeechesResponse{}, err
	}
	speeches, err := u.repo.FetchMemberSpeeches(ctx, memberId, page, perPage, topic)
	if err != nil {
		return MemberSpeechesResponse{}, err
	}
	stats, err := u.repo.MemberStats(ctx, memberId)
	if err != nil {
		return MemberSpeechesResponse{}, err
	}
	return MemberSpeechesResponse{
		MemberId: memberId,
		Page:     page,
		PerPage:  perPage,
		Total:    total,
		Pages:    int(math.Ceil(float64(total) / float64(perPage))),
		Stats:    stats,
		Speeches: speeches,
	}, nil
}
