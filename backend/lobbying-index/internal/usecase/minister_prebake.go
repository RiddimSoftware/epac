// Package usecase implements application policy for the lobbying index builder.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"epac/lobbying-index/internal/domain"
)

var (
	ErrCabinetSourceRequired       = errors.New("cabinet source is required")
	ErrMinisterTableWriterRequired = errors.New("minister table writer is required")
)

// CabinetSource scrapes pm.gc.ca Cabinet and mandate-letter pages into typed rows.
type CabinetSource interface {
	FetchCabinet(ctx context.Context) (domain.CabinetSnapshot, error)
}

// MinisterTableWriter resolves member IDs and writes minister prebake tables.
type MinisterTableWriter interface {
	SaveMinisterTables(ctx context.Context, databasePath string, snapshot domain.CabinetSnapshot) (PreBakeMinisterCommunicationsResult, error)
}

// PreBakeMinisterCommunicationsResult records the minister builder output.
type PreBakeMinisterCommunicationsResult struct {
	DatabasePath                   string
	MinistersProcessed             int
	PortfolioRows                  int
	MandateRows                    int
	CommunicationRows              int
	MemberResolutionMissCount      int
	MinistersWithoutCommunications int
	UnresolvedMinisters            []string
}

// PreBakeMinisterCommunications fetches current Cabinet data and writes the
// minister-specific SQLite tables used by the lobbying serving stack.
type PreBakeMinisterCommunications struct {
	source       CabinetSource
	writer       MinisterTableWriter
	databasePath string
	parliament   int
}

func NewPreBakeMinisterCommunications(
	source CabinetSource,
	writer MinisterTableWriter,
	databasePath string,
	parliament int,
) (*PreBakeMinisterCommunications, error) {
	if source == nil {
		return nil, ErrCabinetSourceRequired
	}
	if writer == nil {
		return nil, ErrMinisterTableWriterRequired
	}
	path := strings.TrimSpace(databasePath)
	if path == "" {
		path = DefaultDatabasePath
	}
	if parliament <= 0 {
		parliament = 45
	}
	return &PreBakeMinisterCommunications{
		source:       source,
		writer:       writer,
		databasePath: path,
		parliament:   parliament,
	}, nil
}

func (u *PreBakeMinisterCommunications) Execute(ctx context.Context) (PreBakeMinisterCommunicationsResult, error) {
	snapshot, err := u.source.FetchCabinet(ctx)
	if err != nil {
		return PreBakeMinisterCommunicationsResult{}, fmt.Errorf("fetch cabinet data: %w", err)
	}
	for i := range snapshot.PortfolioPeriods {
		if snapshot.PortfolioPeriods[i].ParliamentNumber == 0 {
			snapshot.PortfolioPeriods[i].ParliamentNumber = u.parliament
		}
	}

	result, err := u.writer.SaveMinisterTables(ctx, u.databasePath, snapshot)
	if err != nil {
		return PreBakeMinisterCommunicationsResult{}, fmt.Errorf("save minister tables: %w", err)
	}
	result.DatabasePath = u.databasePath
	if result.MinistersProcessed == 0 {
		result.MinistersProcessed = len(snapshot.PortfolioPeriods)
	}
	return result, nil
}
