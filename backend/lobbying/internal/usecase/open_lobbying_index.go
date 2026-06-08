package usecase

import (
	"context"
	"errors"

	"epac/lobbying/domain"
)

var (
	ErrManifestNotFound = errors.New("lobbying index manifest not found")
	ErrChecksumMismatch = errors.New("lobbying index checksum mismatch")
	ErrSchemaMismatch   = errors.New("lobbying index schema version mismatch")
)

type ManifestLoader interface {
	Load(ctx context.Context) (domain.LobbyingIndexManifest, error)
}

type IndexDownloader interface {
	Download(ctx context.Context, sqliteKey, expectedSHA256 string) (localPath string, err error)
}

type LobbyingIndex struct {
	Manifest  domain.LobbyingIndexManifest
	LocalPath string
}

type OpenLobbyingIndex struct {
	manifests  ManifestLoader
	downloader IndexDownloader
}

func NewOpenLobbyingIndex(manifests ManifestLoader, downloader IndexDownloader) *OpenLobbyingIndex {
	return &OpenLobbyingIndex{manifests: manifests, downloader: downloader}
}

func (u *OpenLobbyingIndex) Execute(ctx context.Context) (LobbyingIndex, error) {
	manifest, err := u.manifests.Load(ctx)
	if err != nil {
		return LobbyingIndex{}, err
	}
	if manifest.Version != domain.LobbyingIndexManifestVersion {
		return LobbyingIndex{}, ErrSchemaMismatch
	}

	localPath, err := u.downloader.Download(ctx, manifest.SQLiteKey, manifest.SQLiteSHA256)
	if err != nil {
		return LobbyingIndex{}, err
	}

	return LobbyingIndex{Manifest: manifest, LocalPath: localPath}, nil
}
