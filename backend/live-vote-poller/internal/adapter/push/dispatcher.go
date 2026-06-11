package push

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
)

type Dispatcher struct {
	URL    string
	Client *http.Client
}

func (d *Dispatcher) Dispatch(ctx context.Context, payload []byte) error {
	if d.URL == "" {
		return nil
	}

	req, err := http.NewRequestWithContext(ctx, "POST", d.URL, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	res, err := d.Client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusAccepted && res.StatusCode != http.StatusOK {
		return fmt.Errorf("dispatcher returned %d", res.StatusCode)
	}

	return nil
}
