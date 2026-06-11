package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"epac/bills-indexer/internal/adapter/legisinfo"
	s3adapter "epac/bills-indexer/internal/adapter/s3"
	sqliteadapter "epac/bills-indexer/internal/adapter/sqlite"
	"epac/bills-indexer/internal/domain"
	"epac/bills-indexer/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	defaultParliamentNumber = 45
	defaultSessionNumber    = 1
	defaultDBPath           = "/tmp/bills.db"
)

func main() {
	if err := run(context.Background()); err != nil {
		logJSON(map[string]any{
			"pipeline": "bills-indexer",
			"level":    "error",
			"event":    "ingest_failed",
			"error":    err.Error(),
		})
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	session, err := sessionFromEnv()
	if err != nil {
		return err
	}
	prefix := firstEnv("BILLS_INDEX_PREFIX", "EPAC_BILLS_INDEX_PREFIX")
	if strings.TrimSpace(prefix) == "" {
		prefix = usecase.DefaultPrefix
	}
	bucket := firstEnv("EPAC_ARTIFACT_BUCKET", "ARTIFACT_BUCKET")
	if strings.TrimSpace(bucket) == "" {
		return fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	httpClient := &http.Client{Timeout: 45 * time.Second}
	source := legisinfo.NewFetcher(
		legisinfo.WithHTTPClient(httpClient),
		legisinfo.WithBaseURL(firstEnv("LEGISINFO_BASE_URL", "PARL_BASE_URL")),
		legisinfo.WithMaxBills(envInt("MAX_BILLS", 0)),
	)
	writer := sqliteadapter.NewWriter()
	store := s3adapter.NewStore(awss3.NewFromConfig(awsCfg), bucket, prefix)
	uc, err := usecase.NewIngestBills(source, writer, store, store, usecase.WithDatabasePath(firstEnvDefault(defaultDBPath, "DB_PATH", "BILLS_DB_PATH")))
	if err != nil {
		return err
	}
	out, err := uc.Execute(ctx, usecase.Input{Session: session, Prefix: prefix})
	if err != nil {
		return err
	}
	logJSON(map[string]any{
		"pipeline":          "bills-indexer",
		"event":             "artifact_uploaded",
		"db_path":           out.DBPath,
		"sqlite_key":        out.Manifest.SQLiteKey,
		"sqlite_size_bytes": out.Manifest.SQLiteSizeBytes,
		"sqlite_sha256":     out.Manifest.SQLiteSHA256,
		"table_counts":      out.Manifest.TableCounts,
	})
	return nil
}

func sessionFromEnv() (domain.Session, error) {
	parliament, err := positiveIntFromEnv("PARLIAMENT_NUMBER", defaultParliamentNumber)
	if err != nil {
		return domain.Session{}, err
	}
	session, err := positiveIntFromEnv("SESSION_NUMBER", defaultSessionNumber)
	if err != nil {
		return domain.Session{}, err
	}
	return domain.Session{ParliamentNumber: parliament, SessionNumber: session}, nil
}

func positiveIntFromEnv(name string, fallback int) (int, error) {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback, nil
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%s must be a positive integer", name)
	}
	return value, nil
}

func envInt(name string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value < 0 {
		return fallback
	}
	return value
}

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

func firstEnvDefault(fallback string, names ...string) string {
	if value := firstEnv(names...); value != "" {
		return value
	}
	return fallback
}

func logJSON(payload map[string]any) {
	payload["timestamp"] = time.Now().UTC().Format(time.RFC3339)
	encoded, err := json.Marshal(payload)
	if err == nil {
		fmt.Fprintln(os.Stderr, string(encoded))
	}
}
