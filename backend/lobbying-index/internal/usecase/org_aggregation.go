package usecase

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"epac/lobbying-index/internal/domain"
)

var (
	ErrOrgAggregatorRequired    = errors.New("org aggregator is required")
	ErrLegisInfoSourceRequired  = errors.New("legisinfo source is required")
	ErrBillContextWriterRequired = errors.New("bill context writer is required")
)

// OrgAggregator builds derived organization tables from raw OCL tables in the build-time SQLite.
type OrgAggregator interface {
	AggregateOrganizationTables(ctx context.Context, databasePath string) error
}

// LegisInfoSource fetches bill metadata from the parl.ca/legisinfo JSON API.
type LegisInfoSource interface {
	FetchBills(ctx context.Context, parliament, session int) ([]domain.LegisInfoBill, error)
}

// BillContextWriter saves bill context tables to the build-time SQLite.
type BillContextWriter interface {
	SaveBillContextTables(ctx context.Context, databasePath string, bills []domain.LegisInfoBill, topicMap []domain.TopicMapping) error
}

// BuildOrganizationTables aggregates raw OCL tables into lobbyist_organizations and supporting tables.
type BuildOrganizationTables struct {
	aggregator   OrgAggregator
	databasePath string
}

// BuildOrganizationTablesResult records how many rows were written.
type BuildOrganizationTablesResult struct {
	DatabasePath string
}

func NewBuildOrganizationTables(aggregator OrgAggregator, databasePath string) (*BuildOrganizationTables, error) {
	if aggregator == nil {
		return nil, ErrOrgAggregatorRequired
	}
	path := strings.TrimSpace(databasePath)
	if path == "" {
		path = DefaultDatabasePath
	}
	return &BuildOrganizationTables{aggregator: aggregator, databasePath: path}, nil
}

func (u *BuildOrganizationTables) Execute(ctx context.Context) (BuildOrganizationTablesResult, error) {
	if err := u.aggregator.AggregateOrganizationTables(ctx, u.databasePath); err != nil {
		return BuildOrganizationTablesResult{}, fmt.Errorf("aggregate organization tables: %w", err)
	}
	return BuildOrganizationTablesResult{DatabasePath: u.databasePath}, nil
}

// BuildBillContextTables fetches legisinfo bills and builds legisinfo_bill_subject_tags
// and legisinfo_bill_readings in the build-time SQLite.
type BuildBillContextTables struct {
	source       LegisInfoSource
	writer       BillContextWriter
	topicMap     []domain.TopicMapping
	databasePath string
	parliament   int
	session      int
}

// BuildBillContextTablesResult records how many rows were written.
type BuildBillContextTablesResult struct {
	DatabasePath string
	BillCount    int
}

func NewBuildBillContextTables(
	source LegisInfoSource,
	writer BillContextWriter,
	topicMap []domain.TopicMapping,
	databasePath string,
	parliament, session int,
) (*BuildBillContextTables, error) {
	if source == nil {
		return nil, ErrLegisInfoSourceRequired
	}
	if writer == nil {
		return nil, ErrBillContextWriterRequired
	}
	path := strings.TrimSpace(databasePath)
	if path == "" {
		path = DefaultDatabasePath
	}
	return &BuildBillContextTables{
		source:       source,
		writer:       writer,
		topicMap:     topicMap,
		databasePath: path,
		parliament:   parliament,
		session:      session,
	}, nil
}

func (u *BuildBillContextTables) Execute(ctx context.Context) (BuildBillContextTablesResult, error) {
	bills, err := u.source.FetchBills(ctx, u.parliament, u.session)
	if err != nil {
		return BuildBillContextTablesResult{}, fmt.Errorf("fetch legisinfo bills: %w", err)
	}
	if err := u.writer.SaveBillContextTables(ctx, u.databasePath, bills, u.topicMap); err != nil {
		return BuildBillContextTablesResult{}, fmt.Errorf("save bill context tables: %w", err)
	}
	return BuildBillContextTablesResult{
		DatabasePath: u.databasePath,
		BillCount:    len(bills),
	}, nil
}
