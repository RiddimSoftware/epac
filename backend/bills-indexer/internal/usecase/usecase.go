package usecase

import (
	"context"
	"errors"
	"fmt"
	"path"
	"strings"
	"time"

	"epac/bills-indexer/internal/domain"
)

const (
	DefaultPrefix = "bills/v1"
	SQLiteName    = "index.sqlite"
	ManifestName  = "manifest.json"
)

var (
	ErrSourceRequired   = errors.New("bill source is required")
	ErrWriterRequired   = errors.New("sqlite writer is required")
	ErrUploaderRequired = errors.New("sqlite uploader is required")
	ErrManifestRequired = errors.New("manifest writer is required")
)

type BillSource interface {
	FetchBills(ctx context.Context, session domain.Session) (domain.Batch, error)
}

type SQLiteWriter interface {
	Write(ctx context.Context, dbPath string, batch domain.Batch) (domain.Stats, error)
}

type SQLiteUploader interface {
	Upload(ctx context.Context, localPath, key string) (sha256 string, sizeBytes int64, err error)
}

type ManifestWriter interface {
	Write(ctx context.Context, manifest domain.Manifest) error
}

type IngestBills struct {
	source   BillSource
	writer   SQLiteWriter
	uploader SQLiteUploader
	manifest ManifestWriter
	dbPath   string
	clock    func() time.Time
}

type Option func(*IngestBills)

func WithDatabasePath(path string) Option {
	return func(u *IngestBills) {
		if strings.TrimSpace(path) != "" {
			u.dbPath = strings.TrimSpace(path)
		}
	}
}

func WithClock(clock func() time.Time) Option {
	return func(u *IngestBills) {
		if clock != nil {
			u.clock = clock
		}
	}
}

type Input struct {
	Session domain.Session
	Prefix  string
}

type Output struct {
	Manifest domain.Manifest
	DBPath   string
}

func NewIngestBills(source BillSource, writer SQLiteWriter, uploader SQLiteUploader, manifest ManifestWriter, opts ...Option) (*IngestBills, error) {
	switch {
	case source == nil:
		return nil, ErrSourceRequired
	case writer == nil:
		return nil, ErrWriterRequired
	case uploader == nil:
		return nil, ErrUploaderRequired
	case manifest == nil:
		return nil, ErrManifestRequired
	}

	uc := &IngestBills{
		source:   source,
		writer:   writer,
		uploader: uploader,
		manifest: manifest,
		dbPath:   "/tmp/bills.db",
		clock:    func() time.Time { return time.Now().UTC() },
	}
	for _, opt := range opts {
		opt(uc)
	}
	return uc, nil
}

func (u *IngestBills) Execute(ctx context.Context, input Input) (Output, error) {
	if input.Session.ParliamentNumber <= 0 {
		return Output{}, fmt.Errorf("parliament number must be positive")
	}
	if input.Session.SessionNumber <= 0 {
		return Output{}, fmt.Errorf("session number must be positive")
	}

	batch, err := u.source.FetchBills(ctx, input.Session)
	if err != nil {
		return Output{}, fmt.Errorf("fetch bills: %w", err)
	}
	// Diff computation is application policy, not source-format work: the source
	// adapter fetches and parses version text into sections, then this use case
	// composes the clause-aware diffs over the parsed batch.
	for i := range batch.Bills {
		bill := &batch.Bills[i]
		bill.Diffs = ComputeBillVersionDiff(bill.Number, bill.Versions, bill.SourceURL)
	}
	stats, err := u.writer.Write(ctx, u.dbPath, batch)
	if err != nil {
		return Output{}, fmt.Errorf("write bills sqlite: %w", err)
	}
	if stats.BuiltAt.IsZero() {
		stats.BuiltAt = u.clock().UTC()
	}
	if stats.Parliament == 0 {
		stats.Parliament = input.Session.ParliamentNumber
	}
	if stats.Session == 0 {
		stats.Session = input.Session.SessionNumber
	}

	prefix := cleanPrefix(input.Prefix)
	sqliteKey := path.Join(prefix, SQLiteName)
	sha256, sizeBytes, err := u.uploader.Upload(ctx, u.dbPath, sqliteKey)
	if err != nil {
		return Output{}, fmt.Errorf("upload bills sqlite: %w", err)
	}
	manifest := domain.Manifest{
		Version:          domain.ManifestVersion,
		BuiltAt:          stats.BuiltAt.UTC().Format(time.RFC3339),
		ParliamentNumber: stats.Parliament,
		SessionNumber:    stats.Session,
		SQLiteKey:        sqliteKey,
		SQLiteSizeBytes:  sizeBytes,
		SQLiteSHA256:     sha256,
		TableCounts:      stats.TableCounts,
	}
	if err := u.manifest.Write(ctx, manifest); err != nil {
		return Output{}, fmt.Errorf("write bills manifest: %w", err)
	}

	return Output{Manifest: manifest, DBPath: u.dbPath}, nil
}

func cleanPrefix(prefix string) string {
	prefix = strings.Trim(strings.TrimSpace(prefix), "/")
	if prefix == "" || prefix == "." {
		return DefaultPrefix
	}
	return prefix
}
