// Package artifacts adapts the static on-this-day S3 artifact to the
// application use case's HansardRepository port.
package artifacts

import (
	"context"
	"encoding/json"
	"time"

	"epac/on-this-day/internal/usecase"
	sharedartifacts "epac/shared/artifacts"
)

const allArtifactKey = "on-this-day/v1/all.json"

type allResponse struct {
	Items []usecase.OnThisDayItem `json:"items"`
}

type HansardRepository struct {
	store sharedartifacts.Store
}

func NewHansardRepository(store sharedartifacts.Store) *HansardRepository {
	return &HansardRepository{store: store}
}

func (r *HansardRepository) OnThisDay(ctx context.Context, date time.Time, limit int) ([]usecase.OnThisDayItem, error) {
	data, err := r.store.Get(ctx, allArtifactKey)
	if err != nil {
		return nil, err
	}
	var all allResponse
	if err := json.Unmarshal(data, &all); err != nil {
		return nil, err
	}
	items := make([]usecase.OnThisDayItem, 0, limit)
	for _, item := range all.Items {
		itemDate, err := time.Parse("2006-01-02", item.Date)
		if err != nil {
			continue
		}
		if itemDate.Month() != date.Month() || itemDate.Day() != date.Day() {
			continue
		}
		if !itemDate.Before(date) {
			continue
		}
		items = append(items, item)
		if len(items) == limit {
			break
		}
	}
	return items, nil
}
