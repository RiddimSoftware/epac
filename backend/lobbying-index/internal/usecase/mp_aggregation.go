// Package usecase implements application policy for the lobbying index builder.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

var ErrAggregatorRequired = errors.New("MP lobbying aggregator is required")

// MPLobbyingAggregator builds precomputed MP lobbying read tables in the
// build-time SQLite database at the given path. Implementations own the
// SQLite handle, including connection lifecycle and SQLite-specific pragmas.
type MPLobbyingAggregator interface {
	BuildMPLobbyingTables(ctx context.Context, databasePath string) error
}

// BuildMPLobbyingTables is the application policy for building the MP
// lobbying read tables from raw OCL tables.
type BuildMPLobbyingTables struct {
	aggregator   MPLobbyingAggregator
	databasePath string
}

// BuildMPLobbyingTablesResult records the use-case output.
type BuildMPLobbyingTablesResult struct {
	DatabasePath string
}

// BuildMPLobbyingTablesOption customizes use-case dependencies.
type BuildMPLobbyingTablesOption func(*BuildMPLobbyingTables)

// NewBuildMPLobbyingTables constructs a BuildMPLobbyingTables use case.
func NewBuildMPLobbyingTables(
	aggregator MPLobbyingAggregator,
	databasePath string,
	options ...BuildMPLobbyingTablesOption,
) (*BuildMPLobbyingTables, error) {
	if aggregator == nil {
		return nil, ErrAggregatorRequired
	}
	path := strings.TrimSpace(databasePath)
	if path == "" {
		path = DefaultDatabasePath
	}
	useCase := &BuildMPLobbyingTables{
		aggregator:   aggregator,
		databasePath: path,
	}
	for _, option := range options {
		option(useCase)
	}
	return useCase, nil
}

// Execute runs the MP lobbying aggregation pipeline against the configured
// database path.
func (u *BuildMPLobbyingTables) Execute(ctx context.Context) (BuildMPLobbyingTablesResult, error) {
	if err := u.aggregator.BuildMPLobbyingTables(ctx, u.databasePath); err != nil {
		return BuildMPLobbyingTablesResult{}, fmt.Errorf("build MP lobbying tables: %w", err)
	}
	return BuildMPLobbyingTablesResult{DatabasePath: u.databasePath}, nil
}
