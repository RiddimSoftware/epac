package usecase_test

import (
	"context"
	"testing"

	"epac/hansard-search/internal/domain"
	"epac/hansard-search/internal/usecase"
)

// stubManifestLoader implements usecase.ManifestLoader for tests.
type stubManifestLoader struct {
	manifest domain.Manifest
	err      error
}

func (s *stubManifestLoader) Load(_ context.Context) (domain.Manifest, error) {
	return s.manifest, s.err
}

// stubIndexDownloader implements usecase.IndexDownloader for tests.
type stubIndexDownloader struct {
	localPath string
	err       error
}

func (s *stubIndexDownloader) Download(_ context.Context, _, _ string) (string, error) {
	return s.localPath, s.err
}

func TestOpenSearchIndex_HappyPath(t *testing.T) {
	manifest := domain.Manifest{
		Version:      "1",
		SQLiteKey:    "hansard-search/v1/index.sqlite",
		SQLiteSHA256: "abc123",
	}
	loader := &stubManifestLoader{manifest: manifest}
	downloader := &stubIndexDownloader{localPath: "/tmp/index.sqlite"}

	uc := usecase.NewOpenSearchIndex(loader, downloader)
	result, err := uc.Execute(context.Background())
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.LocalPath != "/tmp/index.sqlite" {
		t.Errorf("want /tmp/index.sqlite, got %q", result.LocalPath)
	}
	if result.Manifest.SQLiteKey != manifest.SQLiteKey {
		t.Errorf("manifest not propagated")
	}
}

func TestOpenSearchIndex_ManifestNotFound(t *testing.T) {
	loader := &stubManifestLoader{err: usecase.ErrManifestNotFound}
	downloader := &stubIndexDownloader{}

	uc := usecase.NewOpenSearchIndex(loader, downloader)
	_, err := uc.Execute(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestOpenSearchIndex_ChecksumMismatch(t *testing.T) {
	loader := &stubManifestLoader{manifest: domain.Manifest{SQLiteKey: "key", SQLiteSHA256: "hash"}}
	downloader := &stubIndexDownloader{err: usecase.ErrChecksumMismatch}

	uc := usecase.NewOpenSearchIndex(loader, downloader)
	_, err := uc.Execute(context.Background())
	if err == nil {
		t.Fatal("expected error")
	}
}
