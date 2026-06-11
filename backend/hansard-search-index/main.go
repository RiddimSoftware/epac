// hansard-search-index Lambda builds the SQLite FTS5 Hansard search artifact.
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

	ourcommonsadapter "epac/hansard-search-index/internal/adapter/ourcommons"
	s3adapter "epac/hansard-search-index/internal/adapter/s3"
	"epac/hansard-search-index/internal/adapter/sqlitefts5"
	"epac/hansard-search-index/internal/domain"
	"epac/hansard-search-index/internal/usecase"

	"github.com/aws/aws-sdk-go-v2/config"
	awss3 "github.com/aws/aws-sdk-go-v2/service/s3"
)

const (
	DefaultParliamentNumber = 45
	DefaultSessionNumber    = 1
)

func HandleRequest(ctx context.Context) error {
	session, err := sessionFromEnv()
	if err != nil {
		return err
	}
	bucket := strings.TrimSpace(os.Getenv("EPAC_ARTIFACT_BUCKET"))
	if bucket == "" {
		return fmt.Errorf("EPAC_ARTIFACT_BUCKET is required")
	}
	prefix := firstEnv("EPAC_HANSARD_SEARCH_PREFIX")
	if prefix == "" {
		prefix = usecase.DefaultPrefix
	}

	logger := ourcommonsadapter.NewJSONLogger(os.Stdout)
	source := ourcommonsadapter.NewSource(
		ourcommonsadapter.WithHTTPClient(&http.Client{Timeout: 30 * time.Second}),
		ourcommonsadapter.WithLogger(logger),
	)
	parser := ourcommonsadapter.NewParser(logger)
	builder := sqlitefts5.NewBuilder(sqlitefts5.DefaultPath, sqlitefts5.SystemClock{}, logger)

	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	store := s3adapter.NewStore(awss3.NewFromConfig(awsCfg), bucket, prefix)

	buildIndex, err := usecase.NewBuildIndex(source, parser, builder, store, store)
	if err != nil {
		return err
	}
	out, err := buildIndex.Execute(ctx, usecase.Input{Session: session, Prefix: prefix})
	if err != nil {
		return err
	}
	logSummary(out.Manifest)
	return nil
}

func sessionFromEnv() (domain.Session, error) {
	parliament, err := positiveIntFromEnv("PARLIAMENT_NUMBER", DefaultParliamentNumber)
	if err != nil {
		return domain.Session{}, err
	}
	session, err := positiveIntFromEnv("SESSION_NUMBER", DefaultSessionNumber)
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

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

func logSummary(manifest domain.Manifest) {
	record := map[string]any{
		"timestamp":          time.Now().UTC().Format(time.RFC3339),
		"level":              "info",
		"pipeline":           "hansard-search-index",
		"event":              "index_built",
		"sqlite_key":         manifest.SQLiteKey,
		"sqlite_size_bytes":  manifest.SQLiteSizeBytes,
		"sqlite_sha256":      manifest.SQLiteSHA256,
		"sitting_count":      manifest.SittingCount,
		"intervention_count": manifest.InterventionCount,
		"message_count":      manifest.MessageCount,
	}
	data, err := json.Marshal(record)
	if err != nil {
		return
	}
	fmt.Println(string(data))
}

func main() {
	if err := HandleRequest(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
