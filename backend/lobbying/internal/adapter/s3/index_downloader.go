package s3

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strings"

	"epac/lobbying/domain"
	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "modernc.org/sqlite"
)

const localIndexPath = "/tmp/index.sqlite"

type IndexDownloader struct {
	s3     getter
	bucket string
}

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

func NewIndexDownloader(s3Client getter, bucket string) *IndexDownloader {
	return &IndexDownloader{s3: s3Client, bucket: bucket}
}

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

	h := sha256.New()
	if _, err := io.Copy(io.MultiWriter(f, h), out.Body); err != nil {
		_ = f.Close()
		return "", fmt.Errorf("write index: %w", err)
	}
	if err := f.Close(); err != nil {
		return "", fmt.Errorf("flush index file: %w", err)
	}

	if !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), expectedSHA256) {
		return "", usecase.ErrChecksumMismatch
	}
	if err := verifySchemaVersion(localIndexPath); err != nil {
		return "", err
	}
	return localIndexPath, nil
}

func verifySchemaVersion(path string) error {
	db, err := sql.Open("sqlite", fmt.Sprintf("file:%s?mode=ro&_pragma=query_only(1)", path))
	if err != nil {
		return fmt.Errorf("open index: %w", err)
	}
	defer db.Close()

	var version string
	err = db.QueryRow("SELECT value FROM meta WHERE key = 'version'").Scan(&version)
	if err != nil {
		return fmt.Errorf("read meta version: %w", err)
	}
	if version != domain.LobbyingIndexManifestVersion {
		return usecase.ErrSchemaMismatch
	}
	return nil
}
