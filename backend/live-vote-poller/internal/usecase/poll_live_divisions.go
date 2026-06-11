package usecase

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

type Division map[string]any

type DivisionsFetching interface {
	FetchDivisions(ctx context.Context) ([]Division, error)
}

type ArtifactRepository interface {
	Exists(ctx context.Context, key string) (bool, error)
	Write(ctx context.Context, key string, payload []byte) error
}

type PushDispatching interface {
	Dispatch(ctx context.Context, payload []byte) error
}

type Clock interface {
	Now() time.Time
}

type PollLiveDivisions struct {
	Fetcher    DivisionsFetching
	Repository ArtifactRepository
	Dispatcher PushDispatching
	Clock      Clock
}

func (u *PollLiveDivisions) Execute(ctx context.Context) error {
	if !isSittingHours(u.Clock.Now()) {
		return nil
	}

	divisions, err := u.Fetcher.FetchDivisions(ctx)
	if err != nil {
		return fmt.Errorf("fetch parliament divisions: %w", err)
	}

	for _, div := range divisions {
		status, _ := div["status"].(string)
		if status != "concluded" {
			continue
		}

		divID, _ := div["division_id"].(float64)
		parl, _ := div["parliament"].(float64)
		sess, _ := div["session"].(float64)

		if divID == 0 || parl == 0 || sess == 0 {
			// Skip malformed division
			continue
		}

		if err := u.processConcludedDivision(ctx, div, int(parl), int(sess), int(divID)); err != nil {
			return fmt.Errorf("process division %d: %w", int(divID), err)
		}
	}

	return nil
}

func isSittingHours(now time.Time) bool {
	loc, err := time.LoadLocation("America/Toronto")
	if err != nil {
		return true // fail open if tzdata is missing
	}
	t := now.In(loc)
	offset := t.Hour()*60 + t.Minute()

	switch t.Weekday() {
	case time.Monday:
		return offset >= 10*60+30 && offset <= 19*60
	case time.Tuesday, time.Wednesday, time.Thursday:
		return offset >= 9*60+30 && offset <= 19*60
	case time.Friday:
		return offset >= 9*60+30 && offset <= 15*60
	default:
		return false
	}
}

func (u *PollLiveDivisions) processConcludedDivision(ctx context.Context, div Division, parl, sess, divID int) error {
	key := fmt.Sprintf("votes/live/%d-%d-%d.json", parl, sess, divID)

	exists, err := u.Repository.Exists(ctx, key)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}

	payload, err := json.Marshal(div)
	if err != nil {
		return err
	}
	if err := u.Repository.Write(ctx, key, payload); err != nil {
		return err
	}

	if err := u.Dispatcher.Dispatch(ctx, payload); err != nil {
		return err
	}

	return nil
}
