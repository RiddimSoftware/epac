// Package usecase implements the BuildIndex application policy.
//
// It owns the orchestration and port interfaces for fetching current-session
// Hansard XML, parsing source interventions, building a SQLite FTS index, and
// publishing the resulting artifact contract.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"path"
	"strings"
	"time"

	"epac/hansard-search-index/internal/domain"
)

const (
	DefaultPrefix = "hansard-search/v1"
	SQLiteName    = "index.sqlite"
	ManifestName  = "manifest.json"
)

var (
	ErrSittingNotFound  = errors.New("hansard sitting not found")
	ErrSourceRequired   = errors.New("hansard XML source is required")
	ErrParserRequired   = errors.New("hansard parser is required")
	ErrBuilderRequired  = errors.New("index builder is required")
	ErrUploaderRequired = errors.New("index uploader is required")
	ErrManifestRequired = errors.New("manifest writer is required")
)

type HansardXMLSource interface {
	FetchSitting(ctx context.Context, parliament, session, sitting int) ([]byte, error)
}

type HansardParser interface {
	Parse(xml []byte) ([]domain.Intervention, error)
}

type IndexBuilder interface {
	Build(ctx context.Context, interventions []domain.Intervention) (path string, stats domain.Stats, err error)
}

type IndexUploader interface {
	Upload(ctx context.Context, localPath, s3Key string) (sha256 string, sizeBytes int64, err error)
}

type ManifestWriter interface {
	Write(ctx context.Context, manifest domain.Manifest) error
}

type BuildIndex struct {
	source   HansardXMLSource
	parser   HansardParser
	builder  IndexBuilder
	uploader IndexUploader
	writer   ManifestWriter
}

type Input struct {
	Session domain.Session
	Prefix  string
}

type Output struct {
	Manifest domain.Manifest
}

func NewBuildIndex(source HansardXMLSource, parser HansardParser, builder IndexBuilder, uploader IndexUploader, writer ManifestWriter) (*BuildIndex, error) {
	switch {
	case source == nil:
		return nil, ErrSourceRequired
	case parser == nil:
		return nil, ErrParserRequired
	case builder == nil:
		return nil, ErrBuilderRequired
	case uploader == nil:
		return nil, ErrUploaderRequired
	case writer == nil:
		return nil, ErrManifestRequired
	default:
		return &BuildIndex{
			source:   source,
			parser:   parser,
			builder:  builder,
			uploader: uploader,
			writer:   writer,
		}, nil
	}
}

func (u *BuildIndex) Execute(ctx context.Context, input Input) (Output, error) {
	if input.Session.ParliamentNumber <= 0 {
		return Output{}, fmt.Errorf("parliament number must be positive")
	}
	if input.Session.SessionNumber <= 0 {
		return Output{}, fmt.Errorf("session number must be positive")
	}

	var all []domain.Intervention
	parseFailures := 0
	downloadedSittings := 0
	for sitting := 1; ; sitting++ {
		body, err := u.source.FetchSitting(ctx, input.Session.ParliamentNumber, input.Session.SessionNumber, sitting)
		if errors.Is(err, ErrSittingNotFound) {
			break
		}
		if err != nil {
			return Output{}, fmt.Errorf("fetch sitting %03d: %w", sitting, err)
		}
		downloadedSittings++

		interventions, err := u.parser.Parse(body)
		if err != nil {
			parseFailures++
			continue
		}
		all = append(all, interventions...)
	}
	if downloadedSittings > 0 && parseFailures == downloadedSittings {
		return Output{}, fmt.Errorf("all %d downloaded sittings failed to parse", downloadedSittings)
	}

	localPath, stats, err := u.builder.Build(ctx, all)
	if err != nil {
		return Output{}, fmt.Errorf("build sqlite index: %w", err)
	}
	if stats.ParliamentNumber == 0 {
		stats.ParliamentNumber = input.Session.ParliamentNumber
	}
	if stats.SessionNumber == 0 {
		stats.SessionNumber = input.Session.SessionNumber
	}
	if stats.BuiltAt.IsZero() {
		stats.BuiltAt = time.Now().UTC()
	}

	prefix := cleanPrefix(input.Prefix)
	sqliteKey := path.Join(prefix, SQLiteName)
	sha256, sizeBytes, err := u.uploader.Upload(ctx, localPath, sqliteKey)
	if err != nil {
		return Output{}, fmt.Errorf("upload sqlite index: %w", err)
	}

	manifest := domain.Manifest{
		Version:           domain.ManifestVersion,
		BuiltAt:           stats.BuiltAt.UTC().Format(time.RFC3339),
		ParliamentNumber:  stats.ParliamentNumber,
		SessionNumber:     stats.SessionNumber,
		SittingCount:      stats.SittingCount,
		InterventionCount: stats.InterventionCount,
		MessageCount:      stats.MessageCount,
		SQLiteKey:         sqliteKey,
		SQLiteSizeBytes:   sizeBytes,
		SQLiteSHA256:      sha256,
	}
	if err := u.writer.Write(ctx, manifest); err != nil {
		return Output{}, fmt.Errorf("write manifest: %w", err)
	}

	return Output{Manifest: manifest}, nil
}

func cleanPrefix(prefix string) string {
	prefix = strings.Trim(strings.TrimSpace(prefix), "/")
	if prefix == "" || prefix == "." {
		return DefaultPrefix
	}
	return prefix
}
