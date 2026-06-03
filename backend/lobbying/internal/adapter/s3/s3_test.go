package s3

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"testing"

	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/service/s3"
	s3types "github.com/aws/aws-sdk-go-v2/service/s3/types"
	_ "modernc.org/sqlite"
)

type fakeS3 struct {
	body []byte
	err  error
}

func (f fakeS3) GetObject(context.Context, *s3.GetObjectInput, ...func(*s3.Options)) (*s3.GetObjectOutput, error) {
	if f.err != nil {
		return nil, f.err
	}
	return &s3.GetObjectOutput{Body: io.NopCloser(bytes.NewReader(f.body))}, nil
}

func TestManifestLoaderMapsNoSuchKey(t *testing.T) {
	loader := NewManifestLoader(fakeS3{err: &s3types.NoSuchKey{}}, "bucket", "prefix/manifest.json")

	if _, err := loader.Load(context.Background()); !errors.Is(err, usecase.ErrManifestNotFound) {
		t.Fatalf("err = %v, want manifest not found", err)
	}
}

func TestManifestLoaderParsesManifest(t *testing.T) {
	loader := NewManifestLoader(fakeS3{body: []byte(`{"version":"v1","sqlite_key":"lobbying/index.sqlite","sqlite_sha256":"abc"}`)}, "bucket", "prefix/manifest.json")

	manifest, err := loader.Load(context.Background())
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if manifest.Version != "v1" || manifest.SQLiteKey != "lobbying/index.sqlite" || manifest.SQLiteSHA256 != "abc" {
		t.Fatalf("manifest = %#v", manifest)
	}
}

func TestIndexDownloaderVerifiesChecksumAndSchema(t *testing.T) {
	indexBytes := sqliteIndexBytes(t, "v1")
	sum := sha256.Sum256(indexBytes)
	downloader := NewIndexDownloader(fakeS3{body: indexBytes}, "bucket")

	path, err := downloader.Download(context.Background(), "lobbying/index.sqlite", hex.EncodeToString(sum[:]))
	if err != nil {
		t.Fatalf("Download: %v", err)
	}
	if path != localIndexPath {
		t.Fatalf("path = %q, want %q", path, localIndexPath)
	}
}

func TestIndexDownloaderMapsChecksumMismatch(t *testing.T) {
	downloader := NewIndexDownloader(fakeS3{body: sqliteIndexBytes(t, "v1")}, "bucket")

	if _, err := downloader.Download(context.Background(), "lobbying/index.sqlite", "bad"); !errors.Is(err, usecase.ErrChecksumMismatch) {
		t.Fatalf("err = %v, want checksum mismatch", err)
	}
}

func TestIndexDownloaderMapsSchemaMismatch(t *testing.T) {
	indexBytes := sqliteIndexBytes(t, "v2")
	sum := sha256.Sum256(indexBytes)
	downloader := NewIndexDownloader(fakeS3{body: indexBytes}, "bucket")

	if _, err := downloader.Download(context.Background(), "lobbying/index.sqlite", hex.EncodeToString(sum[:])); !errors.Is(err, usecase.ErrSchemaMismatch) {
		t.Fatalf("err = %v, want schema mismatch", err)
	}
}

func sqliteIndexBytes(t *testing.T, version string) []byte {
	t.Helper()
	path := t.TempDir() + "/index.sqlite"
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL); INSERT INTO meta VALUES ('version', ?);`, version); err != nil {
		t.Fatalf("create index: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite: %v", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read index: %v", err)
	}
	return data
}
