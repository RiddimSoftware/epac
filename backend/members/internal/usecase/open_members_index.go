package usecase

import (
	"context"
	"errors"

	"epac/members/internal/domain"
)

var (
	ErrManifestNotFound = errors.New("members index manifest not found")
	ErrChecksumMismatch = errors.New("members index checksum mismatch")
	ErrSchemaMismatch   = errors.New("members index schema version mismatch")
	ErrMemberNotFound   = errors.New("member not found")
)

type ManifestLoader interface {
	Load(ctx context.Context) (domain.Manifest, error)
}

type IndexDownloader interface {
	Download(ctx context.Context, sqliteKey, expectedSHA256 string) (localPath string, err error)
}

type MembersIndex struct {
	Manifest  domain.Manifest
	LocalPath string
}

type OpenMembersIndex struct {
	manifests  ManifestLoader
	downloader IndexDownloader
}

func NewOpenMembersIndex(manifests ManifestLoader, downloader IndexDownloader) *OpenMembersIndex {
	return &OpenMembersIndex{manifests: manifests, downloader: downloader}
}

func (u *OpenMembersIndex) Execute(ctx context.Context) (MembersIndex, error) {
	manifest, err := u.manifests.Load(ctx)
	if err != nil {
		return MembersIndex{}, err
	}
	if manifest.Version != domain.ManifestVersion || manifest.SQLiteKey == "" {
		return MembersIndex{}, ErrSchemaMismatch
	}

	localPath, err := u.downloader.Download(ctx, manifest.SQLiteKey, manifest.SQLiteSHA256)
	if err != nil {
		return MembersIndex{}, err
	}
	return MembersIndex{Manifest: manifest, LocalPath: localPath}, nil
}
