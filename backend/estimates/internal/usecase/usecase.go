// Package usecase implements the application policy for the estimates Lambda:
// reading Main Estimates rows for the API and persisting parsed CSV rows for
// the daily ingest job. It depends only on the EstimatesRepository port and
// must not import database driver, Lambda runtime, or cloud SDK packages.
package usecase

import (
	"context"
	"errors"
	"fmt"
)

type Estimate struct {
	FiscalYear       string  `json:"fiscal_year"`
	OrganizationID   int     `json:"organization_id"`
	OrganizationName string  `json:"organization_name"`
	VoteNumber       int     `json:"vote_number"`
	VoteDescription  string  `json:"vote_description"`
	Authorities      float64 `json:"authorities"`
	Source           string  `json:"source"`
}

type EstimatesResponse struct {
	Estimates []Estimate `json:"estimates"`
}

type OrgRecord struct {
	ID         int
	Name       string
	LegalTitle string
	Abbr       string
	DeptID     string
	Status     string
}

// EstimatesFilter is the search shape accepted by FetchEstimates.
// At least one of OrgID or FiscalYear must be non-nil.
type EstimatesFilter struct {
	All        bool
	OrgID      *int
	FiscalYear *string
}

// ErrInvalidFilter is returned when no filter criteria are supplied.
var ErrInvalidFilter = errors.New("missing org_id or fiscal_year")

// EstimatesReader is the outbound port for fetching federal Main Estimates.
type EstimatesReader interface {
	FetchEstimates(ctx context.Context, filter EstimatesFilter) ([]Estimate, error)
}

// EstimatesWriter is the outbound port for persisting federal Main Estimates
// and organization metadata.
type EstimatesWriter interface {
	UpsertOrganization(ctx context.Context, org OrgRecord) error
	UpsertEstimate(ctx context.Context, est Estimate) error
	RecordHealth(ctx context.Context, count int, runErr error)
}

// GetEstimates implements the read-side application policy.
type GetEstimates struct {
	repo EstimatesReader
}

func NewGet(repo EstimatesReader) *GetEstimates {
	return &GetEstimates{repo: repo}
}

func (u *GetEstimates) Execute(ctx context.Context, filter EstimatesFilter) ([]Estimate, error) {
	if !filter.All && filter.OrgID == nil && filter.FiscalYear == nil {
		return nil, ErrInvalidFilter
	}
	return u.repo.FetchEstimates(ctx, filter)
}

// IngestEstimates implements the daily-ingest application policy: persist the
// parsed CSV rows (organizations first so estimates can resolve names to IDs)
// and record pipeline health on completion.
type IngestEstimates struct {
	repo EstimatesWriter
}

func NewIngest(repo EstimatesWriter) *IngestEstimates {
	return &IngestEstimates{repo: repo}
}

type IngestInput struct {
	Organizations []OrgRecord
	Estimates     []Estimate
}

func (u *IngestEstimates) Execute(ctx context.Context, in IngestInput) (int, error) {
	for _, org := range in.Organizations {
		if err := u.repo.UpsertOrganization(ctx, org); err != nil {
			fmt.Printf("Warning: failed to insert organization %d: %v\n", org.ID, err)
		}
	}
	inserted := 0
	for _, est := range in.Estimates {
		if err := u.repo.UpsertEstimate(ctx, est); err != nil {
			fmt.Printf("Warning: failed to insert estimate: %v\n", err)
		} else {
			inserted++
		}
	}
	u.repo.RecordHealth(ctx, inserted, nil)
	return inserted, nil
}
