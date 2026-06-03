// Package usecase implements application policy for the lobbying index builder.
package usecase

import (
	"database/sql"
	"errors"
	"fmt"
)

var (
	ErrDatabaseRequired   = errors.New("database is required")
	ErrAggregatorRequired = errors.New("MP lobbying aggregator is required")
)

// MPLobbyingAggregator builds precomputed MP lobbying read tables in the
// builder's already-open SQLite database.
type MPLobbyingAggregator interface {
	BuildMPLobbyingTables(db *sql.DB) error
}

// BuildMPLobbyingTables runs the MP lobbying aggregation pipeline.
func BuildMPLobbyingTables(db *sql.DB, aggregator MPLobbyingAggregator) error {
	if db == nil {
		return ErrDatabaseRequired
	}
	if aggregator == nil {
		return ErrAggregatorRequired
	}
	if err := aggregator.BuildMPLobbyingTables(db); err != nil {
		return fmt.Errorf("build MP lobbying tables: %w", err)
	}
	return nil
}
