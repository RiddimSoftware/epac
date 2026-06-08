package sqlite

import (
	"context"
	"database/sql"
	"testing"

	"epac/lobbying-index/internal/domain"

	_ "modernc.org/sqlite"
)

func TestWriterCreatesSchemaMetadata(t *testing.T) {
	dbPath := t.TempDir() + "/index.sqlite"

	if err := NewWriter().Write(context.Background(), dbPath, domain.OCLIngestionBatch{}, nil, nil); err != nil {
		t.Fatalf("Write: %v", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	var version string
	if err := db.QueryRow("SELECT value FROM meta WHERE key = 'version'").Scan(&version); err != nil {
		t.Fatalf("query schema metadata: %v", err)
	}
	if version != domain.ManifestVersion {
		t.Fatalf("version = %q, want %q", version, domain.ManifestVersion)
	}
}
