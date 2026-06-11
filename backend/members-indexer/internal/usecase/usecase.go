package usecase

import (
	"context"
	"errors"
	"fmt"
	"path"
	"strings"
	"time"

	"epac/members-indexer/internal/domain"
)

const (
	DefaultPrefix = "members/v1"
	SQLiteName    = "index.sqlite"
)

var (
	ErrSourceRequired   = errors.New("members source is required")
	ErrWriterRequired   = errors.New("sqlite writer is required")
	ErrUploaderRequired = errors.New("sqlite uploader is required")
	ErrManifestRequired = errors.New("manifest writer is required")
)

type MembersSource interface {
	FetchMembers(ctx context.Context) (domain.Batch, error)
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

type IngestMembers struct {
	source   MembersSource
	writer   SQLiteWriter
	uploader SQLiteUploader
	manifest ManifestWriter
	dbPath   string
	clock    func() time.Time
}

type Option func(*IngestMembers)

func WithDatabasePath(path string) Option {
	return func(u *IngestMembers) {
		if strings.TrimSpace(path) != "" {
			u.dbPath = strings.TrimSpace(path)
		}
	}
}

func WithClock(clock func() time.Time) Option {
	return func(u *IngestMembers) {
		if clock != nil {
			u.clock = clock
		}
	}
}

type Input struct {
	Prefix string
}

type Output struct {
	Manifest domain.Manifest
	DBPath   string
}

func NewIngestMembers(source MembersSource, writer SQLiteWriter, uploader SQLiteUploader, manifest ManifestWriter, opts ...Option) (*IngestMembers, error) {
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
	uc := &IngestMembers{
		source:   source,
		writer:   writer,
		uploader: uploader,
		manifest: manifest,
		dbPath:   "/tmp/members.db",
		clock:    func() time.Time { return time.Now().UTC() },
	}
	for _, opt := range opts {
		opt(uc)
	}
	return uc, nil
}

func (u *IngestMembers) Execute(ctx context.Context, input Input) (Output, error) {
	batch, err := u.source.FetchMembers(ctx)
	if err != nil {
		return Output{}, fmt.Errorf("fetch members: %w", err)
	}
	stats, err := u.writer.Write(ctx, u.dbPath, batch)
	if err != nil {
		return Output{}, fmt.Errorf("write members sqlite: %w", err)
	}
	if stats.BuiltAt.IsZero() {
		stats.BuiltAt = u.clock().UTC()
	}
	prefix := cleanPrefix(input.Prefix)
	sqliteKey := path.Join(prefix, SQLiteName)
	sha256, sizeBytes, err := u.uploader.Upload(ctx, u.dbPath, sqliteKey)
	if err != nil {
		return Output{}, fmt.Errorf("upload members sqlite: %w", err)
	}
	manifest := domain.Manifest{
		Version:         domain.ManifestVersion,
		BuiltAt:         stats.BuiltAt.UTC().Format(time.RFC3339),
		SQLiteKey:       sqliteKey,
		SQLiteSizeBytes: sizeBytes,
		SQLiteSHA256:    sha256,
		TableCounts:     stats.TableCounts,
	}
	if err := u.manifest.Write(ctx, manifest); err != nil {
		return Output{}, fmt.Errorf("write members manifest: %w", err)
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
