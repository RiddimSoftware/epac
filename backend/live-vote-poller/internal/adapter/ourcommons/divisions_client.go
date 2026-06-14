package ourcommons

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"epac/live-vote-poller/internal/usecase"
)

type DivisionsClient struct {
	URL    string
	Client *http.Client
}

func (c *DivisionsClient) FetchDivisions(ctx context.Context) ([]usecase.Division, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", c.URL, nil)
	if err != nil {
		return nil, err
	}

	resp, err := c.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("parliament API returned %d", resp.StatusCode)
	}

	var data struct {
		Divisions []usecase.Division `json:"divisions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&data); err != nil {
		return nil, fmt.Errorf("decode parliament response: %w", err)
	}

	return data.Divisions, nil
}
