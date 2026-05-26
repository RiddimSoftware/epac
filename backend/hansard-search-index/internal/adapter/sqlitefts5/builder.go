package sqlitefts5

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"epac/hansard-search-index/internal/domain"

	_ "modernc.org/sqlite"
)

const DefaultPath = "/tmp/index.sqlite"

type Clock interface {
	Now() time.Time
}

type SystemClock struct{}

func (SystemClock) Now() time.Time { return time.Now().UTC() }

// Logger is a minimal interface for structured warning output.
type Logger interface {
	Warn(event string, fields map[string]any)
}

type discardLogger struct{}

func (discardLogger) Warn(string, map[string]any) {}

type Builder struct {
	path   string
	clock  Clock
	logger Logger
}

func NewBuilder(path string, clock Clock, logger Logger) *Builder {
	if strings.TrimSpace(path) == "" {
		path = DefaultPath
	}
	if clock == nil {
		clock = SystemClock{}
	}
	if logger == nil {
		logger = discardLogger{}
	}
	return &Builder{path: path, clock: clock, logger: logger}
}

func (b *Builder) Build(ctx context.Context, interventions []domain.Intervention) (string, domain.Stats, error) {
	if err := removeSQLiteFiles(b.path); err != nil {
		return "", domain.Stats{}, err
	}
	if err := os.MkdirAll(filepath.Dir(b.path), 0o755); err != nil {
		return "", domain.Stats{}, fmt.Errorf("create sqlite dir: %w", err)
	}

	db, err := sql.Open("sqlite", b.path)
	if err != nil {
		return "", domain.Stats{}, fmt.Errorf("open sqlite: %w", err)
	}
	defer func() {
		if db != nil {
			_ = db.Close()
		}
	}()
	if _, err := db.ExecContext(ctx, "PRAGMA foreign_keys=ON"); err != nil {
		return "", domain.Stats{}, fmt.Errorf("enable foreign keys: %w", err)
	}
	if err := createSchema(ctx, db); err != nil {
		return "", domain.Stats{}, err
	}

	stats, err := b.insertCorpus(ctx, db, interventions)
	if err != nil {
		return "", domain.Stats{}, err
	}
	if err := writeMeta(ctx, db, stats); err != nil {
		return "", domain.Stats{}, err
	}
	if err := selfCheck(ctx, db, stats.MessageCount, interventions); err != nil {
		return "", domain.Stats{}, err
	}
	if err := db.Close(); err != nil {
		return "", domain.Stats{}, fmt.Errorf("close sqlite: %w", err)
	}
	db = nil
	if _, err := SHA256File(b.path); err != nil {
		return "", domain.Stats{}, err
	}
	return b.path, stats, nil
}

func createSchema(ctx context.Context, db *sql.DB) error {
	_, err := db.ExecContext(ctx, schemaSQL)
	if err != nil {
		return fmt.Errorf("create schema: %w", err)
	}
	return nil
}

const schemaSQL = `
DROP TRIGGER IF EXISTS messages_ai;
DROP TRIGGER IF EXISTS messages_ad;
DROP TRIGGER IF EXISTS messages_au;
DROP TABLE IF EXISTS messages_fts;
DROP TABLE IF EXISTS messages;
DROP TABLE IF EXISTS interventions;
DROP TABLE IF EXISTS meta;

CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE interventions (
    rowid INTEGER PRIMARY KEY,
    parliament_number INTEGER NOT NULL,
    session_number INTEGER NOT NULL,
    sitting_date TEXT NOT NULL,
    intervention_id TEXT NOT NULL UNIQUE,
    speaker_name TEXT NOT NULL,
    party_abbreviation TEXT NOT NULL DEFAULT '',
    riding_name TEXT NOT NULL DEFAULT '',
    topic TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_interventions_sitting_date ON interventions(sitting_date);
CREATE TABLE messages (
    rowid INTEGER PRIMARY KEY,
    intervention_rowid INTEGER NOT NULL REFERENCES interventions(rowid),
    message_id TEXT NOT NULL UNIQUE,
    position INTEGER NOT NULL,
    content TEXT NOT NULL
);
CREATE VIRTUAL TABLE messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='rowid',
    tokenize='porter unicode61 remove_diacritics 1'
);
CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (new.rowid, new.content);
END;
CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.rowid, old.content);
END;
CREATE TRIGGER messages_au AFTER UPDATE ON messages BEGIN
    INSERT INTO messages_fts(messages_fts, rowid, content) VALUES('delete', old.rowid, old.content);
    INSERT INTO messages_fts(rowid, content) VALUES (new.rowid, new.content);
END;
`

func (b *Builder) insertCorpus(ctx context.Context, db *sql.DB, interventions []domain.Intervention) (domain.Stats, error) {
	stats := domain.Stats{BuiltAt: b.clock.Now().UTC()}
	if len(interventions) == 0 {
		return stats, nil
	}

	ordered := append([]domain.Intervention(nil), interventions...)
	sort.SliceStable(ordered, func(i, j int) bool {
		return sittingKey(ordered[i]) < sittingKey(ordered[j])
	})
	stats.ParliamentNumber = ordered[0].ParliamentNumber
	stats.SessionNumber = ordered[0].SessionNumber

	seen := make(map[string]struct{}, len(ordered))
	write := 0
	for _, iv := range ordered {
		id := strings.TrimSpace(iv.InterventionID)
		if id == "" {
			ordered[write] = iv
			write++
			continue
		}
		if _, dup := seen[id]; dup {
			b.logger.Warn("duplicate_intervention_id", map[string]any{"intervention_id": id})
			continue
		}
		seen[id] = struct{}{}
		ordered[write] = iv
		write++
	}
	ordered = ordered[:write]

	for start := 0; start < len(ordered); {
		end := start + 1
		key := sittingKey(ordered[start])
		for end < len(ordered) && sittingKey(ordered[end]) == key {
			end++
		}
		if err := insertSitting(ctx, db, ordered[start:end], &stats); err != nil {
			return domain.Stats{}, err
		}
		stats.SittingCount++
		start = end
	}
	return stats, nil
}

func insertSitting(ctx context.Context, db *sql.DB, interventions []domain.Intervention, stats *domain.Stats) error {
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin sitting transaction: %w", err)
	}
	defer tx.Rollback()

	for _, intervention := range interventions {
		if strings.TrimSpace(intervention.InterventionID) == "" {
			continue
		}
		res, err := tx.ExecContext(ctx, `
INSERT INTO interventions (
    parliament_number, session_number, sitting_date, intervention_id,
    speaker_name, party_abbreviation, riding_name, topic
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			intervention.ParliamentNumber,
			intervention.SessionNumber,
			formatDate(intervention.SittingDate),
			strings.TrimSpace(intervention.InterventionID),
			speakerName(intervention),
			strings.TrimSpace(intervention.PartyAbbreviation),
			strings.TrimSpace(intervention.RidingName),
			strings.TrimSpace(intervention.Topic),
		)
		if err != nil {
			return fmt.Errorf("insert intervention %q: %w", intervention.InterventionID, err)
		}
		interventionRowID, err := res.LastInsertId()
		if err != nil {
			return fmt.Errorf("read intervention rowid: %w", err)
		}
		stats.InterventionCount++

		for _, message := range intervention.Messages {
			if strings.TrimSpace(message.MessageID) == "" || strings.TrimSpace(message.Text) == "" {
				continue
			}
			if _, err := tx.ExecContext(ctx, `
INSERT INTO messages (intervention_rowid, message_id, position, content)
VALUES (?, ?, ?, ?)`,
				interventionRowID,
				strings.TrimSpace(message.MessageID),
				message.Position,
				strings.TrimSpace(message.Text),
			); err != nil {
				return fmt.Errorf("insert message %q: %w", message.MessageID, err)
			}
			stats.MessageCount++
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit sitting transaction: %w", err)
	}
	return nil
}

func writeMeta(ctx context.Context, db *sql.DB, stats domain.Stats) error {
	values := map[string]string{
		"version":            domain.ManifestVersion,
		"built_at":           stats.BuiltAt.UTC().Format(time.RFC3339),
		"parliament_number":  fmt.Sprintf("%d", stats.ParliamentNumber),
		"session_number":     fmt.Sprintf("%d", stats.SessionNumber),
		"sitting_count":      fmt.Sprintf("%d", stats.SittingCount),
		"intervention_count": fmt.Sprintf("%d", stats.InterventionCount),
		"message_count":      fmt.Sprintf("%d", stats.MessageCount),
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin meta transaction: %w", err)
	}
	defer tx.Rollback()
	for key, value := range values {
		if _, err := tx.ExecContext(ctx, "INSERT INTO meta (key, value) VALUES (?, ?)", key, value); err != nil {
			return fmt.Errorf("insert meta %q: %w", key, err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit meta transaction: %w", err)
	}
	return nil
}

func selfCheck(ctx context.Context, db *sql.DB, messageCount int, interventions []domain.Intervention) error {
	var ftsCount int
	if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM messages_fts").Scan(&ftsCount); err != nil {
		return fmt.Errorf("count messages_fts: %w", err)
	}
	if ftsCount != messageCount {
		return fmt.Errorf("messages_fts count %d does not match message_count %d", ftsCount, messageCount)
	}
	if messageCount == 0 {
		return nil
	}
	term := sampleTerm(interventions)
	if term == "" {
		return nil
	}
	var matchCount int
	if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM messages_fts WHERE messages_fts MATCH ?", term).Scan(&matchCount); err != nil {
		return fmt.Errorf("sample FTS match: %w", err)
	}
	if matchCount == 0 {
		return fmt.Errorf("sample FTS match for %q returned no rows", term)
	}
	return nil
}

func SHA256File(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", fmt.Errorf("open %s for sha256: %w", path, err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}

func sampleTerm(interventions []domain.Intervention) string {
	for _, intervention := range interventions {
		for _, message := range intervention.Messages {
			for _, field := range strings.Fields(message.Text) {
				cleaned := sampleTermPattern.FindString(strings.ToLower(field))
				if len(cleaned) >= 4 {
					return cleaned
				}
			}
		}
	}
	return ""
}

var sampleTermPattern = regexp.MustCompile(`[[:alnum:]]+`)

func sittingKey(intervention domain.Intervention) string {
	return fmt.Sprintf("%04d-%02d-%s", intervention.ParliamentNumber, intervention.SessionNumber, formatDate(intervention.SittingDate))
}

func formatDate(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format("2006-01-02")
}

func speakerName(intervention domain.Intervention) string {
	name := strings.TrimSpace(strings.Join([]string{intervention.SpeakerFirstName, intervention.SpeakerLastName}, " "))
	if name == "" {
		return "Unknown"
	}
	return name
}

func removeSQLiteFiles(path string) error {
	for _, suffix := range []string{"", "-wal", "-shm"} {
		err := os.Remove(path + suffix)
		if err == nil || os.IsNotExist(err) {
			continue
		}
		return fmt.Errorf("remove existing sqlite file %s: %w", path+suffix, err)
	}
	return nil
}
