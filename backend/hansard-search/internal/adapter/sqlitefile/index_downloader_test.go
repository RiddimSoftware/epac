package sqlitefile

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"epac/hansard-search/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "modernc.org/sqlite"
)

type mockS3Downloader struct {
	body []byte
	err  error
}

func (m *mockS3Downloader) GetObject(_ context.Context, _ *s3.GetObjectInput, _ ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	if m.err != nil {
		return nil, m.err
	}
	return &s3.GetObjectOutput{Body: io.NopCloser(bytes.NewReader(m.body))}, nil
}

// createTestDB creates a temporary SQLite DB with the meta table containing the given version.
func createTestDB(t *testing.T, version string) (path string, content []byte) {
	t.Helper()
	path = filepath.Join(t.TempDir(), "test.sqlite")
	db, err := sql.Open("sqlite", "file:"+path)
	if err != nil {
		t.Fatalf("open test db: %v", err)
	}
	defer db.Close()

	if _, err := db.ExecContext(context.Background(), "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)"); err != nil {
		t.Fatalf("create meta table: %v", err)
	}
	if _, err := db.ExecContext(context.Background(), "INSERT INTO meta (key, value) VALUES ('version', ?)", version); err != nil {
		t.Fatalf("insert version: %v", err)
	}
	db.Close()

	content, err = io.ReadAll(mustOpen(t, path))
	if err != nil {
		t.Fatalf("read test db: %v", err)
	}
	return path, content
}

func mustOpen(t *testing.T, path string) io.ReadCloser {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open %s: %v", path, err)
	}
	return f
}

func sha256hex(data []byte) string {
	h := sha256.Sum256(data)
	return hex.EncodeToString(h[:])
}

func TestIndexDownloader_HappyPath(t *testing.T) {
	_, content := createTestDB(t, "v1")

	expectedHash := sha256hex(content)
	mock := &mockS3Downloader{body: content}

	// Override localIndexPath to write to a temp location.
	// The downloader writes to /tmp/index.sqlite; in tests we accept this.
	d := &IndexDownloader{s3: mock, bucket: "test-bucket"}
	got, err := d.Download(context.Background(), "some/key", expectedHash)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != localIndexPath {
		t.Errorf("want %q, got %q", localIndexPath, got)
	}
}

func TestIndexDownloader_ChecksumMismatch(t *testing.T) {
	_, content := createTestDB(t, "v1")

	mock := &mockS3Downloader{body: content}
	d := &IndexDownloader{s3: mock, bucket: "test-bucket"}

	_, err := d.Download(context.Background(), "some/key", "deadbeef")
	if !errors.Is(err, usecase.ErrChecksumMismatch) {
		t.Errorf("want ErrChecksumMismatch, got %v", err)
	}
}

func TestIndexDownloader_SchemaMismatch(t *testing.T) {
	_, content := createTestDB(t, "v99")

	expectedHash := sha256hex(content)
	mock := &mockS3Downloader{body: content}
	d := &IndexDownloader{s3: mock, bucket: "test-bucket"}

	_, err := d.Download(context.Background(), "some/key", expectedHash)
	if !errors.Is(err, usecase.ErrSchemaMismatch) {
		t.Errorf("want ErrSchemaMismatch, got %v", err)
	}
}
