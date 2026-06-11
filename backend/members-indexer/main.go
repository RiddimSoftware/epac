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

	"epac/members-indexer/internal/adapter/ourcommons"
	s3adapter "epac/members-indexer/internal/adapter/s3"
	sqliteadapter "epac/members-indexer/internal/adapter/sqlite"
	"epac/members-indexer/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

const defaultDBPath = "/tmp/members.db"

func main() {
	if err := run(context.Background()); err != nil {
		logJSON(map[string]any{
			"pipeline": "members-indexer",
			"level":    "error",
			"event":    "ingest_failed",
			"error":    err.Error(),
		})
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	prefix := firstEnv("MEMBERS_INDEX_PREFIX", "EPAC_MEMBERS_INDEX_PREFIX")
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

	logJSON(map[string]any{
		"pipeline": "members-indexer",
		"event":    "ingest_started",
		"prefix":   prefix,
		"bucket":   bucket,
	})

	logger := func(payload map[string]any) { logJSON(payload) }

	source := ourcommons.NewFetcher(
		ourcommons.WithHTTPClient(&http.Client{Timeout: 45 * time.Second}),
		ourcommons.WithBaseURL(firstEnv("OURCOMMONS_BASE_URL")),
		ourcommons.WithMaxMembers(envInt("MAX_MEMBERS", 0)),
		ourcommons.WithFullVotes(envBool("MEMBERS_INDEX_FETCH_FULL_VOTES", false)),
		ourcommons.WithLogger(logger),
	)
	writer := sqliteadapter.NewWriter(sqliteadapter.WithLogger(logger))
	store := s3adapter.NewStore(awss3.NewFromConfig(awsCfg), bucket, prefix, s3adapter.WithLogger(logger))
	uc, err := usecase.NewIngestMembers(source, writer, store, store, usecase.WithDatabasePath(firstEnvDefault(defaultDBPath, "DB_PATH", "MEMBERS_DB_PATH")))
	if err != nil {
		return err
	}
	out, err := uc.Execute(ctx, usecase.Input{Prefix: prefix})
	if err != nil {
		return err
	}
	logJSON(map[string]any{
		"pipeline":          "members-indexer",
		"event":             "artifact_uploaded",
		"db_path":           out.DBPath,
		"sqlite_key":        out.Manifest.SQLiteKey,
		"sqlite_size_bytes": out.Manifest.SQLiteSizeBytes,
		"sqlite_sha256":     out.Manifest.SQLiteSHA256,
		"table_counts":      out.Manifest.TableCounts,
	})
	return nil
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

func envBool(name string, fallback bool) bool {
	raw := strings.TrimSpace(os.Getenv(name))
	if raw == "" {
		return fallback
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
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
