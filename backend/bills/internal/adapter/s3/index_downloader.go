package s3

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"epac/bills/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	_ "modernc.org/sqlite"
)

const localBillsIndexPath = "/tmp/bills.db"

type IndexDownloader struct {
	s3        getter
	bucket    string
	localPath string
}

type LocalIndexDownloader struct {
	rootDir   string
	localPath string
}

func NewIndexDownloaderFromEnv(ctx context.Context) (usecase.IndexDownloader, error) {
	if dir := strings.TrimSpace(os.Getenv("EPAC_ARTIFACTS_DIR")); dir != "" {
		return NewLocalIndexDownloader(dir, localBillsIndexPath), nil
	}

	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return nil, fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("load AWS config: %w", err)
	}
	return NewIndexDownloader(s3.NewFromConfig(cfg), bucket, localBillsIndexPath), nil
}

func NewIndexDownloader(s3Client getter, bucket, localPath string) *IndexDownloader {
	return &IndexDownloader{s3: s3Client, bucket: bucket, localPath: localPath}
}

func NewLocalIndexDownloader(rootDir, localPath string) *LocalIndexDownloader {
	return &LocalIndexDownloader{rootDir: rootDir, localPath: localPath}
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
	return writeAndVerify(ctx, out.Body, d.localPath, expectedSHA256)
}

func (d *LocalIndexDownloader) Download(ctx context.Context, sqliteKey, expectedSHA256 string) (string, error) {
	path := filepath.Join(d.rootDir, filepath.FromSlash(sqliteKey))
	if samePath(path, d.localPath) {
		return verifyLocalFile(ctx, path, expectedSHA256)
	}

	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open local index %s: %w", path, err)
	}
	defer file.Close()
	return writeAndVerify(ctx, file, d.localPath, expectedSHA256)
}

func samePath(a, b string) bool {
	absA, errA := filepath.Abs(a)
	absB, errB := filepath.Abs(b)
	return errA == nil && errB == nil && absA == absB
}

func verifyLocalFile(ctx context.Context, path, expectedSHA256 string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open local index %s: %w", path, err)
	}
	defer file.Close()

	h := sha256.New()
	if _, err := io.Copy(h, file); err != nil {
		return "", fmt.Errorf("read index: %w", err)
	}
	if expectedSHA256 != "" && !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), expectedSHA256) {
		return "", usecase.ErrChecksumMismatch
	}
	if err := verifySchema(ctx, path); err != nil {
		return "", err
	}
	return path, nil
}

func writeAndVerify(ctx context.Context, body io.Reader, localPath, expectedSHA256 string) (string, error) {
	file, err := os.Create(localPath)
	if err != nil {
		return "", fmt.Errorf("create local index file: %w", err)
	}

	h := sha256.New()
	if _, err := io.Copy(io.MultiWriter(file, h), body); err != nil {
		_ = file.Close()
		return "", fmt.Errorf("write index: %w", err)
	}
	if err := file.Close(); err != nil {
		return "", fmt.Errorf("flush index file: %w", err)
	}

	if expectedSHA256 != "" && !strings.EqualFold(hex.EncodeToString(h.Sum(nil)), expectedSHA256) {
		return "", usecase.ErrChecksumMismatch
	}
	if err := verifySchema(ctx, localPath); err != nil {
		return "", err
	}
	return localPath, nil
}

func verifySchema(ctx context.Context, path string) error {
	db, err := sql.Open("sqlite", fmt.Sprintf("file:%s?mode=ro&_pragma=query_only(1)", path))
	if err != nil {
		return fmt.Errorf("open index: %w", err)
	}
	defer db.Close()

	present := map[string]bool{}
	rows, err := db.QueryContext(ctx, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
	if err != nil {
		return fmt.Errorf("list index tables: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return fmt.Errorf("scan index table: %w", err)
		}
		present[name] = true
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("iterate index tables: %w", err)
	}

	missing := []string{}
	for _, table := range []string{"bills"} {
		if !present[table] {
			missing = append(missing, table)
		}
	}
	if len(missing) > 0 {
		sort.Strings(missing)
		return fmt.Errorf("%w: missing tables %s", usecase.ErrSchemaMismatch, strings.Join(missing, ", "))
	}
	return nil
}
