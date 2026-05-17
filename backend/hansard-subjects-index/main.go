package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"epac/hansard-subjects-index/application"
	"epac/hansard-subjects-index/repository"
	"github.com/jackc/pgx/v5"
)

const (
	defaultOutputDir    = "artifacts"
	defaultArtifactPath = "hansard-subjects/v1/all.json"
	defaultMaxGzipBytes = 2 * 1024 * 1024
	pipelineTimeout     = 60 * time.Second
)

type config struct {
	outputDir       string
	fromDate        *time.Time
	toDate          *time.Time
	parliamentCount int
	maxGzipBytes    int
}

type artifactMetadata struct {
	Path         string `json:"path"`
	SHA256       string `json:"sha256"`
	Bytes        int    `json:"bytes"`
	GzipBytes    int    `json:"gzip_bytes"`
	SubjectCount int    `json:"subject_count"`
}

type runSummary struct {
	Artifacts []artifactMetadata      `json:"artifacts"`
	Window    application.IndexWindow `json:"window"`
}

func main() {
	cfg, err := configFromArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintf(os.Stderr, "configuration error: %v\n", err)
		os.Exit(2)
	}

	if err := run(cfg); err != nil {
		fmt.Fprintf(os.Stderr, "hansard subjects index error: %v\n", err)
		os.Exit(1)
	}
}

func configFromArgs(args []string) (config, error) {
	fs := flag.NewFlagSet("hansard-subjects-index", flag.ContinueOnError)
	outputDir := fs.String("output-dir", defaultOutputDir, "directory where artifact files are written")
	fromDate := fs.String("from-date", "", "inclusive YYYY-MM-DD sitting date lower bound")
	toDate := fs.String("to-date", "", "inclusive YYYY-MM-DD sitting date upper bound")
	parliamentCount := fs.Int("parliament-count", application.DefaultParliamentCount, "current parliament plus this many-1 previous parliaments")
	maxGzipBytes := fs.Int("max-gzip-bytes", defaultMaxGzipBytes, "maximum gzipped JSON bytes before pagination")
	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	if *parliamentCount < 1 {
		return config{}, errors.New("parliament-count must be positive")
	}
	if *maxGzipBytes < 1 {
		return config{}, errors.New("max-gzip-bytes must be positive")
	}

	from, err := parseOptionalDate(*fromDate)
	if err != nil {
		return config{}, fmt.Errorf("from-date: %w", err)
	}
	to, err := parseOptionalDate(*toDate)
	if err != nil {
		return config{}, fmt.Errorf("to-date: %w", err)
	}
	if from != nil && to != nil && from.After(*to) {
		return config{}, errors.New("from-date must be on or before to-date")
	}

	return config{
		outputDir:       *outputDir,
		fromDate:        from,
		toDate:          to,
		parliamentCount: *parliamentCount,
		maxGzipBytes:    *maxGzipBytes,
	}, nil
}

func run(cfg config) error {
	connStr := os.Getenv("DATABASE_URL")
	if connStr == "" {
		return errors.New("DATABASE_URL environment variable is not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), pipelineTimeout)
	defer cancel()

	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		return fmt.Errorf("connect database: %w", err)
	}
	defer conn.Close(ctx)

	repo := repository.NewPostgresSubjectsRepository(conn)
	useCase, err := application.NewBuildHansardSubjectsIndex(repo, application.SystemClock{})
	if err != nil {
		return err
	}

	index, err := useCase.Execute(ctx, application.BuildInput{
		From:            cfg.fromDate,
		To:              cfg.toDate,
		ParliamentCount: cfg.parliamentCount,
	})
	if err != nil {
		return err
	}

	artifacts, err := writeArtifacts(cfg.outputDir, index, cfg.maxGzipBytes)
	if err != nil {
		return err
	}

	summary := runSummary{Artifacts: artifacts, Window: index.Window}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	return enc.Encode(summary)
}

func writeArtifacts(outputDir string, index application.Index, maxGzipBytes int) ([]artifactMetadata, error) {
	meta, raw, err := marshalArtifact(defaultArtifactPath, index)
	if err != nil {
		return nil, err
	}
	if meta.GzipBytes <= maxGzipBytes {
		if err := writeArtifactFiles(outputDir, meta, raw); err != nil {
			return nil, err
		}
		return []artifactMetadata{meta}, nil
	}
	return writePaginatedArtifacts(outputDir, index, maxGzipBytes)
}

func writePaginatedArtifacts(outputDir string, index application.Index, maxGzipBytes int) ([]artifactMetadata, error) {
	var artifacts []artifactMetadata
	pageStart := 0
	pageNumber := 1
	for pageStart < len(index.Subjects) {
		pageEnd := pageStart + 1
		var pageMeta artifactMetadata
		var pageRaw []byte
		for pageEnd <= len(index.Subjects) {
			page := index
			page.Subjects = index.Subjects[pageStart:pageEnd]
			path := fmt.Sprintf("hansard-subjects/v1/all-%03d.json", pageNumber)
			meta, raw, err := marshalArtifact(path, page)
			if err != nil {
				return nil, err
			}
			if meta.GzipBytes > maxGzipBytes && pageEnd == pageStart+1 {
				return nil, fmt.Errorf("single subject page exceeds %d gzipped bytes", maxGzipBytes)
			}
			if meta.GzipBytes > maxGzipBytes {
				break
			}
			pageMeta = meta
			pageRaw = raw
			pageEnd++
		}
		if err := writeArtifactFiles(outputDir, pageMeta, pageRaw); err != nil {
			return nil, err
		}
		artifacts = append(artifacts, pageMeta)
		pageStart += pageMeta.SubjectCount
		pageNumber++
	}

	indexMeta := struct {
		SchemaVersion int                     `json:"schema_version"`
		GeneratedAt   string                  `json:"generated_at"`
		Window        application.IndexWindow `json:"window"`
		Pages         []artifactMetadata      `json:"pages"`
	}{
		SchemaVersion: application.SchemaVersion,
		GeneratedAt:   index.GeneratedAt,
		Window:        index.Window,
		Pages:         artifacts,
	}
	raw, err := marshalCompact(indexMeta)
	if err != nil {
		return nil, err
	}
	meta := metadataFor("hansard-subjects/v1/subjects-index.json", raw, len(index.Subjects))
	if err := writeArtifactFiles(outputDir, meta, raw); err != nil {
		return nil, err
	}
	return append(artifacts, meta), nil
}

func marshalArtifact(path string, index application.Index) (artifactMetadata, []byte, error) {
	raw, err := marshalCompact(index)
	if err != nil {
		return artifactMetadata{}, nil, err
	}
	return metadataFor(path, raw, len(index.Subjects)), raw, nil
}

func marshalCompact(v any) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(v); err != nil {
		return nil, err
	}
	return bytes.TrimSpace(buf.Bytes()), nil
}

func metadataFor(path string, raw []byte, subjectCount int) artifactMetadata {
	sum := sha256.Sum256(raw)
	return artifactMetadata{
		Path:         path,
		SHA256:       hex.EncodeToString(sum[:]),
		Bytes:        len(raw),
		GzipBytes:    gzipSize(raw),
		SubjectCount: subjectCount,
	}
}

func writeArtifactFiles(outputDir string, meta artifactMetadata, raw []byte) error {
	path := filepath.Join(outputDir, filepath.FromSlash(meta.Path))
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		return err
	}

	metaRaw, err := marshalCompact(meta)
	if err != nil {
		return err
	}
	return os.WriteFile(path+".metadata.json", metaRaw, 0o644)
}

func gzipSize(raw []byte) int {
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	_, _ = w.Write(raw)
	_ = w.Close()
	return buf.Len()
}

func parseOptionalDate(value string) (*time.Time, error) {
	if value == "" {
		return nil, nil
	}
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		return nil, err
	}
	return &parsed, nil
}
