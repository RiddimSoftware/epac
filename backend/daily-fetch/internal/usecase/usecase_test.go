package usecase

import (
	"context"
	"errors"
	"testing"
	"time"
)

type fixedClock time.Time

func (c fixedClock) Now() time.Time {
	return time.Time(c)
}

type memoryHansardRepository struct {
	last     int
	upserted int
	health   int
	runErr   error
}

func (r *memoryHansardRepository) LastSitting(ctx context.Context, parliamentNum, sessionNum int) (int, error) {
	return r.last, nil
}

func (r *memoryHansardRepository) UpsertSpeeches(ctx context.Context, interventions []Intervention) (int, error) {
	r.upserted = len(interventions)
	return len(interventions), nil
}

func (r *memoryHansardRepository) RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time) {
	r.health = count
	r.runErr = runErr
}

func TestNextBuildsHansardLocation(t *testing.T) {
	next, err := New(&memoryHansardRepository{last: 42}, fixedClock(time.Now())).Next(context.Background())
	if err != nil {
		t.Fatalf("Next() error = %v", err)
	}
	if next.Sitting != 43 {
		t.Fatalf("Sitting = %d, want 43", next.Sitting)
	}
	if next.Filename != "44-1-HAN043-E.XML" {
		t.Fatalf("Filename = %q, want 44-1-HAN043-E.XML", next.Filename)
	}
}

func TestExecuteRecordsHealthForEmptyInput(t *testing.T) {
	repo := &memoryHansardRepository{}
	count, err := New(repo, fixedClock(time.Now())).Execute(context.Background(), nil)
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}
	if count != 0 || repo.health != 0 {
		t.Fatalf("count=%d health=%d, want 0/0", count, repo.health)
	}
}

func TestRecordHealthStoresError(t *testing.T) {
	repo := &memoryHansardRepository{}
	runErr := errors.New("fetch failed")
	New(repo, fixedClock(time.Now())).RecordHealth(context.Background(), 0, runErr)
	if !errors.Is(repo.runErr, runErr) {
		t.Fatalf("runErr = %v, want %v", repo.runErr, runErr)
	}
}
