package usecase_test

import (
	"context"
	"errors"
	"testing"

	"epac/lobbying-index/internal/domain"
	"epac/lobbying-index/internal/usecase"
)

// --- fakes ---

type fakeOrgAggregator struct {
	err error
}

func (f *fakeOrgAggregator) AggregateOrganizationTables(_ context.Context, _ string) error {
	return f.err
}

type fakeLegisInfoSource struct {
	bills []domain.LegisInfoBill
	err   error
}

func (f *fakeLegisInfoSource) FetchBills(_ context.Context, _, _ int) ([]domain.LegisInfoBill, error) {
	return f.bills, f.err
}

type fakeBillContextWriter struct {
	err error
}

func (f *fakeBillContextWriter) SaveBillContextTables(_ context.Context, _ string, _ []domain.LegisInfoBill, _ []domain.TopicMapping) error {
	return f.err
}

// --- BuildOrganizationTables tests ---

func TestNewBuildOrganizationTables_NilAggregator(t *testing.T) {
	_, err := usecase.NewBuildOrganizationTables(nil, "/tmp/test.sqlite")
	if !errors.Is(err, usecase.ErrOrgAggregatorRequired) {
		t.Fatalf("expected ErrOrgAggregatorRequired, got %v", err)
	}
}

func TestBuildOrganizationTables_Execute_Success(t *testing.T) {
	agg := &fakeOrgAggregator{}
	uc, err := usecase.NewBuildOrganizationTables(agg, "/tmp/test.sqlite")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	result, err := uc.Execute(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.DatabasePath != "/tmp/test.sqlite" {
		t.Errorf("expected /tmp/test.sqlite, got %s", result.DatabasePath)
	}
}

func TestBuildOrganizationTables_Execute_AggregatorError(t *testing.T) {
	agg := &fakeOrgAggregator{err: errors.New("db error")}
	uc, _ := usecase.NewBuildOrganizationTables(agg, "/tmp/test.sqlite")
	_, err := uc.Execute(context.Background())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

// --- BuildBillContextTables tests ---

func TestNewBuildBillContextTables_NilSource(t *testing.T) {
	writer := &fakeBillContextWriter{}
	_, err := usecase.NewBuildBillContextTables(nil, writer, nil, "/tmp/test.sqlite", 45, 1)
	if !errors.Is(err, usecase.ErrLegisInfoSourceRequired) {
		t.Fatalf("expected ErrLegisInfoSourceRequired, got %v", err)
	}
}

func TestNewBuildBillContextTables_NilWriter(t *testing.T) {
	source := &fakeLegisInfoSource{}
	_, err := usecase.NewBuildBillContextTables(source, nil, nil, "/tmp/test.sqlite", 45, 1)
	if !errors.Is(err, usecase.ErrBillContextWriterRequired) {
		t.Fatalf("expected ErrBillContextWriterRequired, got %v", err)
	}
}

func TestBuildBillContextTables_Execute_Success(t *testing.T) {
	bills := []domain.LegisInfoBill{
		{Number: "C-1", Parliament: 45, Session: 1, LongTitleEn: "An Act respecting health"},
		{Number: "C-2", Parliament: 45, Session: 1, LongTitleEn: "An Act respecting railways"},
	}
	source := &fakeLegisInfoSource{bills: bills}
	writer := &fakeBillContextWriter{}
	uc, err := usecase.NewBuildBillContextTables(source, writer, nil, "/tmp/test.sqlite", 45, 1)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	result, err := uc.Execute(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.BillCount != 2 {
		t.Errorf("expected 2 bills, got %d", result.BillCount)
	}
}

func TestBuildBillContextTables_Execute_FetchError(t *testing.T) {
	source := &fakeLegisInfoSource{err: errors.New("network error")}
	writer := &fakeBillContextWriter{}
	uc, _ := usecase.NewBuildBillContextTables(source, writer, nil, "/tmp/test.sqlite", 45, 1)
	_, err := uc.Execute(context.Background())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestBuildBillContextTables_Execute_WriterError(t *testing.T) {
	source := &fakeLegisInfoSource{bills: []domain.LegisInfoBill{{Number: "C-1"}}}
	writer := &fakeBillContextWriter{err: errors.New("write error")}
	uc, _ := usecase.NewBuildBillContextTables(source, writer, nil, "/tmp/test.sqlite", 45, 1)
	_, err := uc.Execute(context.Background())
	if err == nil {
		t.Fatal("expected error, got nil")
	}
}

func TestBuildOrganizationTables_DefaultDatabasePath(t *testing.T) {
	agg := &fakeOrgAggregator{}
	uc, err := usecase.NewBuildOrganizationTables(agg, "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	result, err := uc.Execute(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.DatabasePath != usecase.DefaultDatabasePath {
		t.Errorf("expected default path %s, got %s", usecase.DefaultDatabasePath, result.DatabasePath)
	}
}
