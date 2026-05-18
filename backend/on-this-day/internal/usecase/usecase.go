// Package usecase implements the BrowseOnThisDay application policy.
//
// The package depends only on a HansardRepository port; it must not
// import database driver, Lambda runtime, or cloud SDK packages.
package usecase

import (
	"context"
	"time"
)

const (
	DefaultLimit = 5
	MaxLimit     = 20
)

type OnThisDayItem struct {
	ID             string  `json:"id"`
	Kind           string  `json:"kind"`
	Year           int     `json:"year"`
	Date           string  `json:"date"`
	Title          string  `json:"title"`
	Excerpt        string  `json:"excerpt"`
	SpeakerName    *string `json:"speaker_name,omitempty"`
	MemberID       *string `json:"member_id,omitempty"`
	SubjectTitle   *string `json:"subject_title,omitempty"`
	InterventionID *string `json:"intervention_id,omitempty"`
	SourceURL      *string `json:"source_url,omitempty"`
}

type OnThisDayResponse struct {
	Date  string          `json:"date"`
	Items []OnThisDayItem `json:"items"`
}

// HansardRepository loads prior-year Hansard speeches keyed by calendar
// day. Matches the catalog's `HansardRepository` port.
type HansardRepository interface {
	OnThisDay(ctx context.Context, date time.Time, limit int) ([]OnThisDayItem, error)
}

type BrowseOnThisDay struct {
	repo HansardRepository
}

func New(repo HansardRepository) *BrowseOnThisDay {
	return &BrowseOnThisDay{repo: repo}
}

func (u *BrowseOnThisDay) Execute(ctx context.Context, date time.Time, limit int) ([]OnThisDayItem, error) {
	items, err := u.repo.OnThisDay(ctx, date, limit)
	if err != nil {
		return nil, err
	}
	if items == nil {
		items = []OnThisDayItem{}
	}
	return items, nil
}
