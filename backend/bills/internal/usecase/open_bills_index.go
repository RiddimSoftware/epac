package usecase

import (
	"context"
	"errors"

	"epac/bills/internal/domain"
)

var (
	ErrManifestNotFound = errors.New("bills index manifest not found")
	ErrChecksumMismatch = errors.New("bills index checksum mismatch")
	ErrSchemaMismatch   = errors.New("bills index schema version mismatch")
	ErrBillNotFound     = errors.New("bill not found")
	ErrDiffMissingFrom  = errors.New("missing required from version id")
	ErrDiffMissingTo    = errors.New("missing required to version id")
	ErrVersionNotFound  = errors.New("version not found")
)

type ManifestLoader interface {
	Load(ctx context.Context) (domain.Manifest, error)
}

type IndexDownloader interface {
	Download(ctx context.Context, sqliteKey, expectedSHA256 string) (localPath string, err error)
}

type BillsIndex struct {
	Manifest  domain.Manifest
	LocalPath string
}

type OpenBillsIndex struct {
	manifests  ManifestLoader
	downloader IndexDownloader
}

func NewOpenBillsIndex(manifests ManifestLoader, downloader IndexDownloader) *OpenBillsIndex {
	return &OpenBillsIndex{manifests: manifests, downloader: downloader}
}

func (u *OpenBillsIndex) Execute(ctx context.Context) (BillsIndex, error) {
	manifest, err := u.manifests.Load(ctx)
	if err != nil {
		return BillsIndex{}, err
	}
	if manifest.Version != domain.ManifestVersion || manifest.SQLiteKey == "" {
		return BillsIndex{}, ErrSchemaMismatch
	}

	localPath, err := u.downloader.Download(ctx, manifest.SQLiteKey, manifest.SQLiteSHA256)
	if err != nil {
		return BillsIndex{}, err
	}
	return BillsIndex{Manifest: manifest, LocalPath: localPath}, nil
}
