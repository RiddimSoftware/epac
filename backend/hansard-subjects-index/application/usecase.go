package application

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"
)

const (
	SchemaVersion          = 1
	DefaultParliamentCount = 3
)

var ErrRepositoryRequired = errors.New("subjects repository is required")

type HansardSubject struct {
	SubjectID    string
	SubjectTitle string
	HansardDate  time.Time
}

type Window struct {
	From             time.Time
	To               time.Time
	ParliamentCutoff *int
}

type SubjectsRepository interface {
	DefaultWindow(ctx context.Context, to time.Time, parliamentCount int) (Window, error)
	ListSubjects(ctx context.Context, window Window) ([]HansardSubject, error)
}

type Clock interface {
	Now() time.Time
}

type SystemClock struct{}

func (SystemClock) Now() time.Time { return time.Now().UTC() }

type BuildHansardSubjectsIndex struct {
	repo  SubjectsRepository
	clock Clock
}

func NewBuildHansardSubjectsIndex(repo SubjectsRepository, clock Clock) (*BuildHansardSubjectsIndex, error) {
	if repo == nil {
		return nil, ErrRepositoryRequired
	}
	if clock == nil {
		clock = SystemClock{}
	}
	return &BuildHansardSubjectsIndex{repo: repo, clock: clock}, nil
}

type BuildInput struct {
	From             *time.Time
	To               *time.Time
	ParliamentCount  int
	ParliamentCutoff *int
}

type Index struct {
	SchemaVersion int            `json:"schema_version"`
	GeneratedAt   string         `json:"generated_at"`
	Window        IndexWindow    `json:"window"`
	Subjects      []IndexSubject `json:"subjects"`
}

type IndexWindow struct {
	From string `json:"from"`
	To   string `json:"to"`
}

type IndexSubject struct {
	SubjectID    string `json:"subject_id"`
	SubjectTitle string `json:"subject_title"`
	HansardDate  string `json:"hansard_date"`
}

func (u *BuildHansardSubjectsIndex) Execute(ctx context.Context, input BuildInput) (Index, error) {
	window, err := u.resolveWindow(ctx, input)
	if err != nil {
		return Index{}, err
	}

	subjects, err := u.repo.ListSubjects(ctx, window)
	if err != nil {
		return Index{}, err
	}
	subjects = dedupeAndSort(subjects)

	indexSubjects := make([]IndexSubject, 0, len(subjects))
	for _, subject := range subjects {
		indexSubjects = append(indexSubjects, IndexSubject{
			SubjectID:    strings.TrimSpace(subject.SubjectID),
			SubjectTitle: strings.TrimSpace(subject.SubjectTitle),
			HansardDate:  formatDate(subject.HansardDate),
		})
	}

	return Index{
		SchemaVersion: SchemaVersion,
		GeneratedAt:   u.clock.Now().UTC().Format(time.RFC3339),
		Window: IndexWindow{
			From: formatDate(window.From),
			To:   formatDate(window.To),
		},
		Subjects: indexSubjects,
	}, nil
}

func (u *BuildHansardSubjectsIndex) resolveWindow(ctx context.Context, input BuildInput) (Window, error) {
	to := dateOnly(u.clock.Now().UTC())
	if input.To != nil {
		to = dateOnly(*input.To)
	}

	if input.From != nil {
		return Window{
			From:             dateOnly(*input.From),
			To:               to,
			ParliamentCutoff: input.ParliamentCutoff,
		}, nil
	}

	parliamentCount := input.ParliamentCount
	if parliamentCount == 0 {
		parliamentCount = DefaultParliamentCount
	}
	return u.repo.DefaultWindow(ctx, to, parliamentCount)
}

func dedupeAndSort(subjects []HansardSubject) []HansardSubject {
	byID := make(map[string]HansardSubject, len(subjects))
	for _, subject := range subjects {
		subject.SubjectID = strings.TrimSpace(subject.SubjectID)
		subject.SubjectTitle = strings.TrimSpace(subject.SubjectTitle)
		if subject.SubjectID == "" || subject.SubjectTitle == "" || subject.HansardDate.IsZero() {
			continue
		}
		existing, ok := byID[subject.SubjectID]
		if !ok || subject.HansardDate.After(existing.HansardDate) {
			byID[subject.SubjectID] = subject
			continue
		}
		if subject.HansardDate.Equal(existing.HansardDate) && subject.SubjectTitle < existing.SubjectTitle {
			byID[subject.SubjectID] = subject
		}
	}

	out := make([]HansardSubject, 0, len(byID))
	for _, subject := range byID {
		out = append(out, subject)
	}
	sort.Slice(out, func(i, j int) bool {
		if !sameDate(out[i].HansardDate, out[j].HansardDate) {
			return out[i].HansardDate.After(out[j].HansardDate)
		}
		return out[i].SubjectID < out[j].SubjectID
	})
	return out
}

func dateOnly(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

func formatDate(t time.Time) string {
	return dateOnly(t).Format("2006-01-02")
}

func sameDate(a, b time.Time) bool {
	return formatDate(a) == formatDate(b)
}
