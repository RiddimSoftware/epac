// Package artifacts adapts static estimates artifacts to the read-side use case.
package artifacts

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"epac/estimates/internal/usecase"
	sharedartifacts "epac/shared/artifacts"
)

const allArtifactKey = "estimates/v1/all.json"

type EstimatesRepository struct {
	store sharedartifacts.Store
}

func NewEstimatesRepository(store sharedartifacts.Store) *EstimatesRepository {
	return &EstimatesRepository{store: store}
}

func (r *EstimatesRepository) FetchEstimates(ctx context.Context, filter usecase.EstimatesFilter) ([]usecase.Estimate, error) {
	resp, err := r.readResponse(ctx, artifactKey(filter))
	if err != nil {
		return nil, err
	}
	estimates := resp.Estimates
	if filter.FiscalYear != nil {
		estimates = filterFiscalYear(estimates, *filter.FiscalYear)
	}
	if estimates == nil {
		estimates = []usecase.Estimate{}
	}
	return estimates, nil
}

func (r *EstimatesRepository) readResponse(ctx context.Context, key string) (usecase.EstimatesResponse, error) {
	data, err := r.store.Get(ctx, key)
	if err != nil {
		return usecase.EstimatesResponse{}, err
	}
	var resp usecase.EstimatesResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return usecase.EstimatesResponse{}, err
	}
	return resp, nil
}

func artifactKey(filter usecase.EstimatesFilter) string {
	if filter.OrgID != nil {
		return fmt.Sprintf("estimates/v1/by-org/%s.json", strconv.Itoa(*filter.OrgID))
	}
	return allArtifactKey
}

func filterFiscalYear(estimates []usecase.Estimate, fiscalYear string) []usecase.Estimate {
	filtered := make([]usecase.Estimate, 0, len(estimates))
	for _, estimate := range estimates {
		if estimate.FiscalYear == fiscalYear {
			filtered = append(filtered, estimate)
		}
	}
	return filtered
}
