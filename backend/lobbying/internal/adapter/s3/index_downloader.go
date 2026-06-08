package s3

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
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
	if err := verifySchema(ctx, localIndexPath); err != nil {
		return "", err
	}
	return localIndexPath, nil
}

var requiredIndexTables = []string{
	"legisinfo_bill_readings",
	"legisinfo_bill_subject_tags",
	"lobbyist_communications",
	"lobbyist_organizations",
	"lobbyist_registrations",
	"lobbyist_subject_matters",
	"minister_communications",
	"minister_mandate_topic_mappings",
	"minister_portfolio_periods",
	"mp_lobbying_subject_breakdowns",
	"mp_lobbying_summaries",
	"mp_lobbying_timeline_entries",
	"ocl_subject_matter_types",
}

func verifySchema(ctx context.Context, path string) error {
	db, err := sql.Open("sqlite", fmt.Sprintf("file:%s?mode=ro&_pragma=query_only(1)", path))
	if err != nil {
		return fmt.Errorf("open index: %w", err)
	}
	defer db.Close()

	if err := verifyRequiredTables(ctx, db); err != nil {
		return err
	}

	version, ok, err := readMetaVersion(ctx, db)
	if err != nil {
		return err
	}
	if ok && version != domain.LobbyingIndexManifestVersion {
		return usecase.ErrSchemaMismatch
	}
	return nil
}

func verifyRequiredTables(ctx context.Context, db *sql.DB) error {
	rows, err := db.QueryContext(ctx, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
	if err != nil {
		return fmt.Errorf("list index tables: %w", err)
	}
	defer rows.Close()

	present := map[string]bool{}
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
	for _, table := range requiredIndexTables {
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

func readMetaVersion(ctx context.Context, db *sql.DB) (string, bool, error) {
	var metaTable string
	if err := db.QueryRowContext(ctx, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'meta'").Scan(&metaTable); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", false, nil
		}
		return "", false, fmt.Errorf("find meta table: %w", err)
	}

	var version string
	if err := db.QueryRowContext(ctx, "SELECT value FROM meta WHERE key = 'version'").Scan(&version); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", true, usecase.ErrSchemaMismatch
		}
		return "", true, fmt.Errorf("read meta version: %w", err)
	}
	return version, true, nil
}
