package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"epac/members-indexer/internal/domain"

	_ "modernc.org/sqlite"
)

type Clock interface {
	Now() time.Time
}

type SystemClock struct{}

func (SystemClock) Now() time.Time { return time.Now().UTC() }

type Writer struct {
	clock  Clock
	logger func(map[string]any)
}

type Option func(*Writer)

func WithClock(clock Clock) Option {
	return func(w *Writer) {
		if clock != nil {
			w.clock = clock
		}
	}
}

func WithLogger(logger func(map[string]any)) Option {
	return func(w *Writer) {
		w.logger = logger
	}
}

func NewWriter(opts ...Option) *Writer {
	w := &Writer{clock: SystemClock{}}
	for _, opt := range opts {
		opt(w)
	}
	return w
}

func (w *Writer) Write(ctx context.Context, dbPath string, batch domain.Batch) (domain.Stats, error) {
	if strings.TrimSpace(dbPath) == "" {
		return domain.Stats{}, fmt.Errorf("database path is required")
	}
	if err := removeSQLiteFiles(dbPath); err != nil {
		return domain.Stats{}, err
	}
	if err := os.MkdirAll(filepath.Dir(dbPath), 0o755); err != nil {
		return domain.Stats{}, fmt.Errorf("create sqlite directory: %w", err)
	}
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return domain.Stats{}, fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()
	if _, err := db.ExecContext(ctx, "PRAGMA foreign_keys=ON"); err != nil {
		return domain.Stats{}, fmt.Errorf("enable foreign keys: %w", err)
	}
	if _, err := db.ExecContext(ctx, schemaSQL); err != nil {
		return domain.Stats{}, fmt.Errorf("create schema: %w", err)
	}

	if w.logger != nil {
		w.logger(map[string]any{
			"pipeline": "members-indexer",
			"event":    "write_started",
			"count":    len(batch.Members),
		})
	}

	stats := domain.Stats{BuiltAt: w.clock.Now().UTC(), TableCounts: map[string]int{}}
	if err := insertBatch(ctx, db, batch, &stats); err != nil {
		return domain.Stats{}, err
	}
	tableCounts, err := countTables(ctx, db)
	if err != nil {
		return domain.Stats{}, err
	}
	stats.TableCounts = tableCounts
	if err := writeMeta(ctx, db, stats); err != nil {
		return domain.Stats{}, err
	}
	if err := selfCheck(ctx, db, stats); err != nil {
		return domain.Stats{}, err
	}

	if w.logger != nil {
		w.logger(map[string]any{
			"pipeline": "members-indexer",
			"event":    "write_completed",
		})
	}

	return stats, nil
}

const schemaSQL = `
DROP TABLE IF EXISTS pmb_sponsorships;
DROP TABLE IF EXISTS attendance_records;
DROP TABLE IF EXISTS member_biographies;
DROP TABLE IF EXISTS members;
DROP TABLE IF EXISTS meta;

CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE members (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    honorific TEXT NOT NULL DEFAULT '',
    first_name TEXT NOT NULL DEFAULT '',
    last_name TEXT NOT NULL DEFAULT '',
    riding TEXT NOT NULL DEFAULT '',
    province TEXT NOT NULL DEFAULT '',
    party TEXT NOT NULL DEFAULT '',
    from_date TEXT,
    to_date TEXT,
    source_url TEXT NOT NULL DEFAULT '',
    profile_url TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_members_party ON members(party);
CREATE INDEX idx_members_province ON members(province);
CREATE TABLE member_biographies (
    member_id TEXT PRIMARY KEY REFERENCES members(id) ON DELETE CASCADE,
    summary TEXT NOT NULL DEFAULT '',
    preferred_language TEXT NOT NULL DEFAULT '',
    photo_url TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT ''
);
CREATE TABLE attendance_records (
    member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    vote_number TEXT NOT NULL DEFAULT '',
    subject TEXT NOT NULL DEFAULT '',
    ballot TEXT NOT NULL DEFAULT '',
    result TEXT NOT NULL DEFAULT '',
    vote_date TEXT NOT NULL DEFAULT '',
    source_url TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (member_id, id)
);
CREATE INDEX idx_attendance_member_vote ON attendance_records(member_id, vote_number);
CREATE TABLE pmb_sponsorships (
    member_id TEXT NOT NULL REFERENCES members(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    bill_number TEXT NOT NULL DEFAULT '',
    title TEXT NOT NULL DEFAULT '',
    relationship TEXT NOT NULL DEFAULT '',
    legis_info_url TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (member_id, id)
);
CREATE INDEX idx_pmb_sponsorships_bill ON pmb_sponsorships(bill_number);
`

func insertBatch(ctx context.Context, db *sql.DB, batch domain.Batch, stats *domain.Stats) error {
	ordered := append([]domain.Member(nil), batch.Members...)
	sort.SliceStable(ordered, func(i, j int) bool {
		return ordered[i].Name < ordered[j].Name
	})
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()
	for _, member := range ordered {
		if strings.TrimSpace(member.ID) == "" || strings.TrimSpace(member.Name) == "" {
			continue
		}
		if _, err := tx.ExecContext(ctx, `
INSERT INTO members (
    id, name, honorific, first_name, last_name, riding, province, party,
    from_date, to_date, source_url, profile_url
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			member.ID,
			member.Name,
			member.Honorific,
			member.FirstName,
			member.LastName,
			member.Riding,
			member.Province,
			member.Party,
			emptyToNil(member.FromDate),
			emptyToNil(member.ToDate),
			member.SourceURL,
			member.ProfileURL,
		); err != nil {
			return fmt.Errorf("insert member %s: %w", member.ID, err)
		}
		stats.MemberCount++
		if err := insertChildren(ctx, tx, member, stats); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}

func insertChildren(ctx context.Context, tx *sql.Tx, member domain.Member, stats *domain.Stats) error {
	bio := member.Biography
	if bio.MemberID == "" {
		bio.MemberID = member.ID
	}
	if bio.SourceURL != "" || bio.Summary != "" || bio.PhotoURL != "" {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO member_biographies (
    member_id, summary, preferred_language, photo_url, source_url
) VALUES (?, ?, ?, ?, ?)`,
			bio.MemberID, bio.Summary, bio.PreferredLanguage, bio.PhotoURL, bio.SourceURL); err != nil {
			return fmt.Errorf("insert biography %s: %w", member.ID, err)
		}
		stats.BiographyCount++
	}
	for _, attendance := range member.Attendance {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO attendance_records (
    member_id, id, vote_number, subject, ballot, result, vote_date, source_url
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			member.ID, attendance.ID, attendance.VoteNumber, attendance.Subject, attendance.Ballot, attendance.Result,
			attendance.VoteDate, attendance.SourceURL); err != nil {
			return fmt.Errorf("insert attendance %s/%s: %w", member.ID, attendance.ID, err)
		}
		stats.AttendanceCount++
	}
	for _, sponsorship := range member.PMBSponsorships {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO pmb_sponsorships (
    member_id, id, bill_number, title, relationship, legis_info_url
) VALUES (?, ?, ?, ?, ?, ?)`,
			member.ID, sponsorship.ID, sponsorship.BillNumber, sponsorship.Title, sponsorship.Relationship, sponsorship.LegisInfoURL); err != nil {
			return fmt.Errorf("insert PMB sponsorship %s/%s: %w", member.ID, sponsorship.ID, err)
		}
		stats.SponsorshipCount++
	}
	return nil
}

func writeMeta(ctx context.Context, db *sql.DB, stats domain.Stats) error {
	values := map[string]string{
		"version":           domain.ManifestVersion,
		"built_at":          stats.BuiltAt.UTC().Format(time.RFC3339),
		"member_count":      fmt.Sprintf("%d", stats.MemberCount),
		"biography_count":   fmt.Sprintf("%d", stats.BiographyCount),
		"attendance_count":  fmt.Sprintf("%d", stats.AttendanceCount),
		"sponsorship_count": fmt.Sprintf("%d", stats.SponsorshipCount),
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin meta transaction: %w", err)
	}
	defer tx.Rollback()
	for key, value := range values {
		if _, err := tx.ExecContext(ctx, "INSERT INTO meta (key, value) VALUES (?, ?)", key, value); err != nil {
			return fmt.Errorf("insert meta %s: %w", key, err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit meta transaction: %w", err)
	}
	return nil
}

func countTables(ctx context.Context, db *sql.DB) (map[string]int, error) {
	names := []string{"members", "member_biographies", "attendance_records", "pmb_sponsorships"}
	counts := make(map[string]int, len(names))
	for _, name := range names {
		var count int
		if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+name).Scan(&count); err != nil {
			return nil, fmt.Errorf("count %s: %w", name, err)
		}
		counts[name] = count
	}
	return counts, nil
}

func selfCheck(ctx context.Context, db *sql.DB, stats domain.Stats) error {
	var memberCount int
	if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM members").Scan(&memberCount); err != nil {
		return fmt.Errorf("count members: %w", err)
	}
	if memberCount != stats.MemberCount {
		return fmt.Errorf("members count %d does not match stats %d", memberCount, stats.MemberCount)
	}
	return nil
}

func emptyToNil(value string) any {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return value
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
