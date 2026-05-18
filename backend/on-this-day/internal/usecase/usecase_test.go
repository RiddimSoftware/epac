package usecase

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fakeRepo struct {
	items []OnThisDayItem
	err   error
}

func (r *fakeRepo) OnThisDay(ctx context.Context, date time.Time, limit int) ([]OnThisDayItem, error) {
	return r.items, r.err
}

func TestExecute_NilItemsBecomesEmptySlice(t *testing.T) {
	uc := New(&fakeRepo{items: nil})
	items, err := uc.Execute(context.Background(), time.Now(), 5)
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if items == nil {
		t.Fatal("items must be non-nil (empty slice, not nil)")
	}
	if len(items) != 0 {
		t.Fatalf("len(items) = %d, want 0", len(items))
	}
}

func TestExecute_PropagatesError(t *testing.T) {
	want := errors.New("boom")
	uc := New(&fakeRepo{err: want})
	if _, err := uc.Execute(context.Background(), time.Now(), 5); !errors.Is(err, want) {
		t.Fatalf("err = %v, want %v", err, want)
	}
}
