// Package usecase implements the OpenSearchIndex application policy.
//
// This package MUST NOT import aws-sdk-go-v2 or modernc.org/sqlite.
// External I/O dependencies are accessed only through the port interfaces below.
package usecase

import (
	"context"
	"errors"

	"epac/hansard-search/internal/domain"
)

var (
	ErrManifestNotFound = errors.New("hansard search manifest not found")
	ErrChecksumMismatch = errors.New("index checksum mismatch")
	ErrSchemaMismatch   = errors.New("index schema version mismatch")
)

// ManifestLoader is the outbound port for reading the index manifest from storage.
type ManifestLoader interface {
	Load(ctx context.Context) (domain.Manifest, error)
}

// IndexDownloader is the outbound port for fetching, verifying, and validating the SQLite index.
type IndexDownloader interface {
	// Download fetches s3://bucket/sqliteKey to /tmp/index.sqlite, verifies the
	// SHA-256 checksum, checks the schema version, and returns the local path.
	Download(ctx context.Context, sqliteKey, expectedSHA256 string) (localPath string, err error)
}

// SearchIndex holds a verified, downloaded SQLite index ready for query use cases.
// D2 will extend this with an open *sql.DB connection.
type SearchIndex struct {
	Manifest  domain.Manifest
	LocalPath string
}

// OpenSearchIndex reads the manifest, downloads the SQLite index, verifies it,
// and returns a SearchIndex for query use cases to consume.
type OpenSearchIndex struct {
	manifests  ManifestLoader
	downloader IndexDownloader
}

func NewOpenSearchIndex(manifests ManifestLoader, downloader IndexDownloader) *OpenSearchIndex {
	return &OpenSearchIndex{manifests: manifests, downloader: downloader}
}

func (u *OpenSearchIndex) Execute(ctx context.Context) (SearchIndex, error) {
	manifest, err := u.manifests.Load(ctx)
	if err != nil {
		return SearchIndex{}, err
	}

	localPath, err := u.downloader.Download(ctx, manifest.SQLiteKey, manifest.SQLiteSHA256)
	if err != nil {
		return SearchIndex{}, err
	}

	return SearchIndex{
		Manifest:  manifest,
		LocalPath: localPath,
	}, nil
}
