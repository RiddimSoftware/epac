package usecase_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"epac/lobbying-index/internal/domain"
	"epac/lobbying-index/internal/usecase"
)

type fakeCabinetSource struct {
	snapshot domain.CabinetSnapshot
	err      error
}

func (f *fakeCabinetSource) FetchCabinet(context.Context) (domain.CabinetSnapshot, error) {
	return f.snapshot, f.err
}

type fakeMinisterTableWriter struct {
	result   usecase.PreBakeMinisterCommunicationsResult
	err      error
	path     string
	snapshot domain.CabinetSnapshot
}

func (f *fakeMinisterTableWriter) SaveMinisterTables(_ context.Context, path string, snapshot domain.CabinetSnapshot) (usecase.PreBakeMinisterCommunicationsResult, error) {
	f.path = path
	f.snapshot = snapshot
	return f.result, f.err
}

func TestNewPreBakeMinisterCommunicationsRequiresDependencies(t *testing.T) {
	if _, err := usecase.NewPreBakeMinisterCommunications(nil, &fakeMinisterTableWriter{}, "", 45); !errors.Is(err, usecase.ErrCabinetSourceRequired) {
		t.Fatalf("err = %v, want %v", err, usecase.ErrCabinetSourceRequired)
	}
	if _, err := usecase.NewPreBakeMinisterCommunications(&fakeCabinetSource{}, nil, "", 45); !errors.Is(err, usecase.ErrMinisterTableWriterRequired) {
		t.Fatalf("err = %v, want %v", err, usecase.ErrMinisterTableWriterRequired)
	}
}

func TestPreBakeMinisterCommunicationsExecute(t *testing.T) {
	startDate := time.Date(2025, 5, 21, 0, 0, 0, 0, time.UTC)
	source := &fakeCabinetSource{snapshot: domain.CabinetSnapshot{
		PortfolioPeriods: []domain.CabinetPortfolioPeriod{{
			MinisterName:  "Mark Carney",
			FirstName:     "Mark",
			LastName:      "Carney",
			PortfolioName: "Prime Minister of Canada",
			StartDate:     &startDate,
			SourceURL:     "https://www.pm.gc.ca/en/cabinet",
		}},
		MandateTopics: []domain.CabinetMandateTopic{{
			EpacTopicSlug: "housing",
			Confidence:    0.85,
			SourceURL:     "https://www.pm.gc.ca/en/mandate-letters/2025/05/21/mandate-letter",
		}},
	}}
	writer := &fakeMinisterTableWriter{result: usecase.PreBakeMinisterCommunicationsResult{
		PortfolioRows:     1,
		MandateRows:       1,
		CommunicationRows: 2,
	}}

	uc, err := usecase.NewPreBakeMinisterCommunications(source, writer, "/tmp/ministers.sqlite", 45)
	if err != nil {
		t.Fatalf("NewPreBakeMinisterCommunications: %v", err)
	}

	result, err := uc.Execute(context.Background())
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if got, want := writer.path, "/tmp/ministers.sqlite"; got != want {
		t.Fatalf("writer path = %q, want %q", got, want)
	}
	if got, want := writer.snapshot.PortfolioPeriods[0].ParliamentNumber, 45; got != want {
		t.Fatalf("parliament number = %d, want %d", got, want)
	}
	if got, want := result.DatabasePath, "/tmp/ministers.sqlite"; got != want {
		t.Fatalf("database path = %q, want %q", got, want)
	}
	if got, want := result.MinistersProcessed, 1; got != want {
		t.Fatalf("ministers processed = %d, want %d", got, want)
	}
}

func TestPreBakeMinisterCommunicationsExecutePropagatesErrors(t *testing.T) {
	sourceErr := errors.New("cabinet unavailable")
	uc, err := usecase.NewPreBakeMinisterCommunications(&fakeCabinetSource{err: sourceErr}, &fakeMinisterTableWriter{}, "", 45)
	if err != nil {
		t.Fatalf("NewPreBakeMinisterCommunications: %v", err)
	}
	if _, err := uc.Execute(context.Background()); !errors.Is(err, sourceErr) {
		t.Fatalf("err = %v, want %v", err, sourceErr)
	}

	writerErr := errors.New("sqlite write failed")
	uc, err = usecase.NewPreBakeMinisterCommunications(&fakeCabinetSource{}, &fakeMinisterTableWriter{err: writerErr}, "", 45)
	if err != nil {
		t.Fatalf("NewPreBakeMinisterCommunications: %v", err)
	}
	if _, err := uc.Execute(context.Background()); !errors.Is(err, writerErr) {
		t.Fatalf("err = %v, want %v", err, writerErr)
	}
}
