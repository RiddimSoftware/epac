// Package usecase implements the IngestHansard application policy.
//
// It depends only on HansardRepository and Clock ports; it must not import
// framework packages.
package usecase

import (
	"context"
	"fmt"
	"strings"
	"time"
)

const (
	ParliamentNum = 44
	SessionNum    = 1
)

type Intervention struct {
	Id              string
	MemberId        string
	Speaker         string
	SubjectID       string
	SubjectTitle    string
	InterventionSeq int
	Content         string
	Language        string
	WordCount       int
	SittingDate     time.Time
	ParliamentNum   int
	SessionNum      int
	Filename        string
}

type NextHansard struct {
	Sitting  int
	URL      string
	Filename string
}

// HansardRepository is the outbound port for reading the latest ingested
// sitting and storing parsed Hansard records. Matches the catalog's
// `HansardRepository` port.
type HansardRepository interface {
	LastSitting(ctx context.Context, parliamentNum, sessionNum int) (int, error)
	UpsertSpeeches(ctx context.Context, interventions []Intervention) (int, error)
	RecordHealth(ctx context.Context, count int, runErr error, recordedAt time.Time)
}

// Clock is the outbound port for current timestamps. Matches the catalog's
// `Clock` port.
type Clock interface {
	Now() time.Time
}

type IngestHansard struct {
	repo  HansardRepository
	clock Clock
}

func New(repo HansardRepository, clock Clock) *IngestHansard {
	return &IngestHansard{repo: repo, clock: clock}
}

func (u *IngestHansard) Next(ctx context.Context) (NextHansard, error) {
	lastSitting, err := u.repo.LastSitting(ctx, ParliamentNum, SessionNum)
	if err != nil {
		lastSitting = 0
	}
	nextSitting := lastSitting + 1
	sittingPadded := fmt.Sprintf("%03d", nextSitting)
	sessionCode := fmt.Sprintf("%d%d", ParliamentNum, SessionNum)
	return NextHansard{
		Sitting:  nextSitting,
		URL:      fmt.Sprintf("https://www.ourcommons.ca/Content/House/%s/Debates/%s/HAN%s-E.XML", sessionCode, sittingPadded, sittingPadded),
		Filename: fmt.Sprintf("%d-%d-HAN%s-E.XML", ParliamentNum, SessionNum, sittingPadded),
	}, nil
}

func (u *IngestHansard) Execute(ctx context.Context, interventions []Intervention) (int, error) {
	if len(interventions) == 0 {
		u.repo.RecordHealth(ctx, 0, nil, u.clock.Now().UTC())
		return 0, nil
	}
	count, err := u.repo.UpsertSpeeches(ctx, interventions)
	if err != nil {
		u.repo.RecordHealth(ctx, 0, err, u.clock.Now().UTC())
		return count, err
	}
	u.repo.RecordHealth(ctx, count, nil, u.clock.Now().UTC())
	return count, nil
}

func (u *IngestHansard) RecordHealth(ctx context.Context, count int, runErr error) {
	u.repo.RecordHealth(ctx, count, runErr, u.clock.Now().UTC())
}

func NormalizeLanguage(language string) string {
	switch strings.ToLower(strings.TrimSpace(language)) {
	case "en", "eng", "english":
		return "en"
	case "fr", "fra", "fre", "french":
		return "fr"
	case "mixed":
		return "mixed"
	default:
		return "und"
	}
}
