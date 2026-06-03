// Package usecase implements OCL raw-data ingestion for the lobbying-index builder.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"epac/lobbying-index/internal/domain"
)

const (
	DefaultDatabasePath = "/tmp/ocl-index.sqlite"
)

var (
	ErrOCLSourceRequired           = errors.New("OCL source is required")
	ErrMembersSourceRequired       = errors.New("members source is required")
	ErrSubjectMatterSourceRequired = errors.New("subject-matter source is required")
	ErrWriterRequired              = errors.New("raw table writer is required")
)

// OCLSource reads and normalizes both OCL communications and registration CSVs.
type OCLSource interface {
	FetchOCLData(context.Context) (domain.OCLIngestionBatch, error)
}

// MembersSource reads members metadata from authoritative member sources.
type MembersSource interface {
	FetchMembers(context.Context) ([]domain.Member, error)
}

// SubjectMatterSource reads the subject matter controlled vocabulary.
type SubjectMatterSource interface {
	FetchSubjectMatters(context.Context) ([]domain.OCLSubjectMatterType, error)
}

// RawTableWriter stores normalized rows in build-time SQLite tables.
type RawTableWriter interface {
	Write(context.Context, string, domain.OCLIngestionBatch, []domain.Member, []domain.OCLSubjectMatterType) error
}

// IngestOCLData is the application policy for building the raw OCL tables.
type IngestOCLData struct {
	oclSource           OCLSource
	membersSource       MembersSource
	subjectMatterSource SubjectMatterSource
	writer              RawTableWriter
	databasePath        string
}

// IngestOCLDataResult returns row counts for logging and verification.
type IngestOCLDataResult struct {
	DatabasePath                   string
	CommunicationPrimaryRows       int
	CommunicationDPOHRows          int
	CommunicationSubjectMatterRows int
	RegistrationPrimaryRows        int
	RegistrationSubjectMatterRows  int
	RegistrationInHouseRows        int
	RegistrationConsultantRows     int
	MemberRows                     int
	SubjectMatterTypeRows          int
}

// IngestOCLDataOption customizes use-case dependencies.
type IngestOCLDataOption func(*IngestOCLData)

func WithDatabasePath(path string) IngestOCLDataOption {
	return func(useCase *IngestOCLData) {
		if strings.TrimSpace(path) != "" {
			useCase.databasePath = strings.TrimSpace(path)
		}
	}
}

func NewIngestOCLData(
	oclSource OCLSource,
	membersSource MembersSource,
	subjectMatterSource SubjectMatterSource,
	writer RawTableWriter,
	options ...IngestOCLDataOption,
) (*IngestOCLData, error) {
	if oclSource == nil {
		return nil, ErrOCLSourceRequired
	}
	if membersSource == nil {
		return nil, ErrMembersSourceRequired
	}
	if subjectMatterSource == nil {
		return nil, ErrSubjectMatterSourceRequired
	}
	if writer == nil {
		return nil, ErrWriterRequired
	}

	useCase := &IngestOCLData{
		oclSource:           oclSource,
		membersSource:       membersSource,
		subjectMatterSource: subjectMatterSource,
		writer:              writer,
		databasePath:        DefaultDatabasePath,
	}

	for _, option := range options {
		option(useCase)
	}

	return useCase, nil
}

func (u *IngestOCLData) Execute(ctx context.Context) (IngestOCLDataResult, error) {
	batch, err := u.oclSource.FetchOCLData(ctx)
	if err != nil {
		return IngestOCLDataResult{}, fmt.Errorf("fetch OCL data: %w", err)
	}

	members, err := u.membersSource.FetchMembers(ctx)
	if err != nil {
		return IngestOCLDataResult{}, fmt.Errorf("fetch members: %w", err)
	}

	subjectMatters, err := u.subjectMatterSource.FetchSubjectMatters(ctx)
	if err != nil {
		return IngestOCLDataResult{}, fmt.Errorf("fetch subject matters: %w", err)
	}

	if err := u.writer.Write(ctx, u.databasePath, batch, members, subjectMatters); err != nil {
		return IngestOCLDataResult{}, fmt.Errorf("write raw tables: %w", err)
	}

	return IngestOCLDataResult{
		DatabasePath:                   u.databasePath,
		CommunicationPrimaryRows:       len(batch.CommunicationsPrimary),
		CommunicationDPOHRows:          len(batch.CommunicationsDPOHs),
		CommunicationSubjectMatterRows: len(batch.CommunicationsSubjectMatters),
		RegistrationPrimaryRows:        len(batch.RegistrationPrimary),
		RegistrationSubjectMatterRows:  len(batch.RegistrationSubjectMatters),
		RegistrationInHouseRows:        len(batch.RegistrationInHouseLobbyists),
		RegistrationConsultantRows:     len(batch.RegistrationConsultantLobbyists),
		MemberRows:                     len(members),
		SubjectMatterTypeRows:          len(subjectMatters),
	}, nil
}
