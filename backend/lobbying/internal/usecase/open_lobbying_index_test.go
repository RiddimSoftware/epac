package usecase

import (
	"context"
	"errors"
	"testing"

	"epac/lobbying/domain"
)

type fakeManifestLoader struct {
	manifest domain.LobbyingIndexManifest
	err      error
}

func (f fakeManifestLoader) Load(context.Context) (domain.LobbyingIndexManifest, error) {
	if f.err != nil {
		return domain.LobbyingIndexManifest{}, f.err
	}
	return f.manifest, nil
}

type fakeIndexDownloader struct {
	path string
	err  error
}

func (f fakeIndexDownloader) Download(context.Context, string, string) (string, error) {
	return f.path, f.err
}

func TestOpenLobbyingIndexRejectsManifestVersionMismatch(t *testing.T) {
	opener := NewOpenLobbyingIndex(
		fakeManifestLoader{manifest: domain.LobbyingIndexManifest{Version: "v2"}},
		fakeIndexDownloader{path: "/tmp/index.sqlite"},
	)

	if _, err := opener.Execute(context.Background()); !errors.Is(err, ErrSchemaMismatch) {
		t.Fatalf("err = %v, want schema mismatch", err)
	}
}

func TestOpenLobbyingIndexReturnsDownloadedPath(t *testing.T) {
	manifest := domain.LobbyingIndexManifest{
		Version:      domain.LobbyingIndexManifestVersion,
		SQLiteKey:    "lobbying-index/v1/index.sqlite",
		SQLiteSHA256: "abc",
	}
	opener := NewOpenLobbyingIndex(fakeManifestLoader{manifest: manifest}, fakeIndexDownloader{path: "/tmp/index.sqlite"})

	index, err := opener.Execute(context.Background())
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if index.Manifest.SQLiteKey != manifest.SQLiteKey || index.LocalPath != "/tmp/index.sqlite" {
		t.Fatalf("index = %#v", index)
	}
}
