// Package sqlitefile implements IndexDownloader: downloads the SQLite index from S3,
// verifies its SHA-256 checksum, and validates the schema version.
package sqlitefile

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"

	"epac/hansard-search/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "modernc.org/sqlite" // pure-Go SQLite driver; no CGO required
)

const (
	localIndexPath        = "/tmp/index.sqlite"
	expectedSchemaVersion = "v1"
)

type s3Downloader interface {
	GetObject(ctx context.Context, params *s3.GetObjectInput, optFns ...func(*s3.Options)) (*s3.GetObjectOutput, error)
}

// IndexDownloader downloads and validates the hansard SQLite search index from S3.
type IndexDownloader struct {
	s3     s3Downloader
	bucket string
}

// NewIndexDownloaderFromEnv constructs an IndexDownloader from environment variables.
// Requires EPAC_ARTIFACT_BUCKET.
func NewIndexDownloaderFromEnv(ctx context.Context) (*IndexDownloader, error) {
	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewIndexDownloader(s3.NewFromConfig(cfg), bucket), nil
}

// NewIndexDownloader constructs an IndexDownloader from explicit dependencies (for testing).
func NewIndexDownloader(s3Client s3Downloader, bucket string) *IndexDownloader {
	return &IndexDownloader{s3: s3Client, bucket: bucket}
}

// Download fetches s3://bucket/sqliteKey to /tmp/index.sqlite using streaming I/O,
// verifies its SHA-256 checksum against expectedSHA256, opens it read-only, reads
// the meta.version row, and returns ErrSchemaMismatch if it does not equal "v1".
func (d *IndexDownloader) Download(ctx context.Context, sqliteKey, expectedSHA256 string) (string, error) {
	out, err := d.s3.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(d.bucket),
		Key:    aws.String(sqliteKey),
	})
	if err != nil {
		return "", fmt.Errorf("s3 get index %s/%s: %w", d.bucket, sqliteKey, err)
	}
	defer out.Body.Close()

	f, err := os.Create(localIndexPath)
	if err != nil {
		return "", fmt.Errorf("create local index file: %w", err)
	}
	defer f.Close()

	h := sha256.New()
	if _, err := io.Copy(io.MultiWriter(f, h), out.Body); err != nil {
		return "", fmt.Errorf("write index: %w", err)
	}
	if err := f.Close(); err != nil {
		return "", fmt.Errorf("flush index file: %w", err)
	}

	actual := hex.EncodeToString(h.Sum(nil))
	if !strings.EqualFold(actual, expectedSHA256) {
		return "", usecase.ErrChecksumMismatch
	}

	if err := verifySchemaVersion(localIndexPath); err != nil {
		return "", err
	}

	return localIndexPath, nil
}

func verifySchemaVersion(path string) error {
	dsn := fmt.Sprintf("file:%s?mode=ro&_pragma=query_only(1)", path)
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return fmt.Errorf("open index: %w", err)
	}
	defer db.Close()

	var version string
	err = db.QueryRow("SELECT value FROM meta WHERE key = 'version'").Scan(&version)
	if err != nil {
		return fmt.Errorf("read meta version: %w", err)
	}

	if version != expectedSchemaVersion {
		return usecase.ErrSchemaMismatch
	}
	return nil
}
