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

	"epac/bills-indexer/internal/domain"

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
			"pipeline": "bills-indexer",
			"event":    "write_started",
			"count":    len(batch.Bills),
		})
	}

	stats := domain.Stats{BuiltAt: w.clock.Now().UTC(), TableCounts: map[string]int{}}
	if err := w.insertBatch(ctx, db, batch, &stats); err != nil {
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
			"pipeline": "bills-indexer",
			"event":    "write_completed",
		})
	}

	return stats, nil
}

const schemaSQL = `
DROP TABLE IF EXISTS bill_clause_diffs;
DROP TABLE IF EXISTS pbo_costings;
DROP TABLE IF EXISTS bill_amendments;
DROP TABLE IF EXISTS bill_diffs;
DROP TABLE IF EXISTS bill_versions;
DROP TABLE IF EXISTS bill_committee_meetings;
DROP TABLE IF EXISTS bill_committee_stages;
DROP TABLE IF EXISTS bill_events;
DROP TABLE IF EXISTS bill_related_links;
DROP TABLE IF EXISTS bill_stages;
DROP TABLE IF EXISTS bills;
DROP TABLE IF EXISTS meta;

CREATE TABLE meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE bills (
    id TEXT PRIMARY KEY,
    number TEXT NOT NULL,
    title TEXT NOT NULL,
    short_title TEXT NOT NULL DEFAULT '',
    sponsor_id TEXT NOT NULL DEFAULT '',
    sponsor_name TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT '',
    current_stage TEXT NOT NULL DEFAULT '',
    introduced_on TEXT,
    source_url TEXT NOT NULL DEFAULT '',
    bill_type TEXT NOT NULL DEFAULT '',
    parliament INTEGER,
    session INTEGER,
    legis_info_url TEXT NOT NULL DEFAULT '',
    raw_json TEXT NOT NULL DEFAULT ''
);
CREATE INDEX idx_bills_number ON bills(number);
CREATE INDEX idx_bills_parliament_session ON bills(parliament, session);
CREATE TABLE bill_stages (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    chamber TEXT NOT NULL DEFAULT '',
    state TEXT NOT NULL DEFAULT '',
    completed_date TEXT,
    is_completed INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bill_id, id, chamber)
);
CREATE TABLE bill_events (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    stage_id TEXT NOT NULL DEFAULT '',
    stage_name TEXT NOT NULL DEFAULT '',
    name TEXT NOT NULL DEFAULT '',
    chamber TEXT NOT NULL DEFAULT '',
    event_date TEXT,
    meeting_number TEXT NOT NULL DEFAULT '',
    amendment_count INTEGER NOT NULL DEFAULT 0,
    amendment_note_id TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (bill_id, id)
);
CREATE INDEX idx_bill_events_bill_stage ON bill_events(bill_id, stage_id);
CREATE TABLE bill_committee_stages (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    stage_id TEXT NOT NULL DEFAULT '',
    stage_name TEXT NOT NULL DEFAULT '',
    chamber TEXT NOT NULL DEFAULT '',
    state TEXT NOT NULL DEFAULT '',
    committee_id TEXT NOT NULL DEFAULT '',
    committee_acronym TEXT NOT NULL DEFAULT '',
    committee_name TEXT NOT NULL DEFAULT '',
    committee_chamber TEXT NOT NULL DEFAULT '',
    committee_url TEXT NOT NULL DEFAULT '',
    studied_since TEXT,
    study_completed_at TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bill_id, id)
);
CREATE INDEX idx_bill_committee_stages_bill ON bill_committee_stages(bill_id, sort_order);
CREATE TABLE bill_committee_meetings (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    stage_id TEXT NOT NULL,
    id TEXT NOT NULL,
    meeting_number INTEGER NOT NULL DEFAULT 0,
    meeting_date TEXT,
    evidence_url TEXT,
    witness_count INTEGER,
    sort_order INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (bill_id, stage_id, id)
);
CREATE INDEX idx_bill_committee_meetings_stage ON bill_committee_meetings(bill_id, stage_id, sort_order);
CREATE TABLE bill_versions (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    publication_id TEXT NOT NULL DEFAULT '',
    stage TEXT NOT NULL DEFAULT '',
    stage_slug TEXT NOT NULL DEFAULT '',
    html_url TEXT NOT NULL DEFAULT '',
    xml_url TEXT NOT NULL DEFAULT '',
    pdf_url TEXT NOT NULL DEFAULT '',
    published_date TEXT,
    source TEXT NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 0,
    text_hash TEXT,
    text_source_url TEXT,
    PRIMARY KEY (bill_id, id)
);
CREATE TABLE bill_diffs (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    from_version_id TEXT NOT NULL,
    to_version_id TEXT NOT NULL,
    source_url TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (bill_id, id)
);
CREATE TABLE bill_clause_diffs (
    bill_id TEXT NOT NULL,
    diff_id TEXT NOT NULL,
    id TEXT NOT NULL,
    label TEXT,
    change_type TEXT NOT NULL,
    from_text TEXT,
    to_text TEXT,
    hansard_anchor_url TEXT,
    sort_order INTEGER NOT NULL,
    PRIMARY KEY (bill_id, diff_id, id),
    FOREIGN KEY (bill_id, diff_id) REFERENCES bill_diffs(bill_id, id) ON DELETE CASCADE
);
CREATE TABLE bill_amendments (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    event_id TEXT NOT NULL DEFAULT '',
    stage_name TEXT NOT NULL DEFAULT '',
    amendment_note_id TEXT NOT NULL DEFAULT '',
    amendment_count INTEGER NOT NULL DEFAULT 0,
    source_url TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (bill_id, id)
);
CREATE TABLE pbo_costings (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    url TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    published TEXT,
    PRIMARY KEY (bill_id, id)
);
CREATE TABLE bill_related_links (
    bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    url TEXT NOT NULL DEFAULT '',
    type TEXT NOT NULL DEFAULT '',
    source TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (bill_id, id)
);
`

func (w *Writer) insertBatch(ctx context.Context, db *sql.DB, batch domain.Batch, stats *domain.Stats) error {
	ordered := append([]domain.Bill(nil), batch.Bills...)
	sort.SliceStable(ordered, func(i, j int) bool {
		if ordered[i].Parliament != ordered[j].Parliament {
			return ordered[i].Parliament < ordered[j].Parliament
		}
		if ordered[i].Session != ordered[j].Session {
			return ordered[i].Session < ordered[j].Session
		}
		return ordered[i].Number < ordered[j].Number
	})
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	for _, bill := range ordered {
		if strings.TrimSpace(bill.ID) == "" || strings.TrimSpace(bill.Number) == "" {
			continue
		}
		if stats.Parliament == 0 {
			stats.Parliament = bill.Parliament
		}
		if stats.Session == 0 {
			stats.Session = bill.Session
		}
		if _, err := tx.ExecContext(ctx, `
INSERT INTO bills (
    id, number, title, short_title, sponsor_id, sponsor_name, status,
    current_stage, introduced_on, source_url, bill_type, parliament, session,
    legis_info_url, raw_json
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			bill.ID,
			bill.Number,
			bill.Title,
			bill.ShortTitle,
			bill.SponsorID,
			bill.SponsorName,
			bill.Status,
			bill.CurrentStage,
			emptyToNil(bill.IntroducedOn),
			bill.SourceURL,
			bill.BillType,
			zeroToNil(bill.Parliament),
			zeroToNil(bill.Session),
			bill.LegisInfoURL,
			bill.RawJSON,
		); err != nil {
			return fmt.Errorf("insert bill %s: %w", bill.Number, err)
		}
		stats.BillCount++
		if err := insertChildren(ctx, tx, bill, stats); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit transaction: %w", err)
	}
	return nil
}

func insertChildren(ctx context.Context, tx *sql.Tx, bill domain.Bill, stats *domain.Stats) error {
	for _, stage := range bill.Stages {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_stages (
    bill_id, id, name, chamber, state, completed_date, is_completed, sort_order
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			bill.ID, stage.ID, stage.Name, stage.Chamber, stage.State, emptyToNil(stage.CompletedDate), boolInt(stage.IsCompleted), stage.SortOrder); err != nil {
			return fmt.Errorf("insert bill stage %s/%s: %w", bill.Number, stage.ID, err)
		}
		stats.StageCount++
	}
	for _, event := range bill.Events {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_events (
    bill_id, id, stage_id, stage_name, name, chamber, event_date, meeting_number,
    amendment_count, amendment_note_id
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			bill.ID, event.ID, event.StageID, event.StageName, event.Name, event.Chamber, emptyToNil(event.EventDate),
			event.MeetingNumber, event.AmendmentCount, event.AmendmentNoteID); err != nil {
			return fmt.Errorf("insert bill event %s/%s: %w", bill.Number, event.ID, err)
		}
		stats.EventCount++
	}
	for _, stage := range bill.CommitteeStages {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_committee_stages (
    bill_id, id, stage_id, stage_name, chamber, state, committee_id,
    committee_acronym, committee_name, committee_chamber, committee_url,
    studied_since, study_completed_at, sort_order
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			bill.ID,
			stage.ID,
			stage.StageID,
			stage.StageName,
			stage.Chamber,
			stage.State,
			stage.CommitteeID,
			stage.CommitteeAcronym,
			stage.CommitteeName,
			stage.CommitteeChamber,
			stage.CommitteeURL,
			emptyToNil(stage.StudiedSince),
			emptyToNil(stage.StudyCompletedAt),
			stage.SortOrder,
		); err != nil {
			return fmt.Errorf("insert bill committee stage %s/%s: %w", bill.Number, stage.ID, err)
		}
		stats.CommitteeStageCount++
		for _, meeting := range stage.Meetings {
			if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_committee_meetings (
    bill_id, stage_id, id, meeting_number, meeting_date, evidence_url, witness_count, sort_order
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
				bill.ID,
				stage.ID,
				meeting.ID,
				meeting.MeetingNumber,
				emptyToNil(meeting.Date),
				emptyToNil(meeting.EvidenceURL),
				intPtrValue(meeting.WitnessCount),
				meeting.SortOrder,
			); err != nil {
				return fmt.Errorf("insert bill committee meeting %s/%s: %w", bill.Number, meeting.ID, err)
			}
			stats.CommitteeMeetingCount++
		}
	}
	for _, version := range bill.Versions {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_versions (
    bill_id, id, publication_id, stage, stage_slug, html_url, xml_url, pdf_url,
    published_date, source, sort_order, text_hash, text_source_url
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			bill.ID, version.ID, version.PublicationID, version.Stage, version.StageSlug, version.HTMLURL, version.XMLURL,
			version.PDFURL, emptyToNil(version.PublishedDate), version.Source, version.SortOrder,
			emptyToNil(derefString(version.TextHash)), emptyToNil(derefString(version.TextSourceURL))); err != nil {
			return fmt.Errorf("insert bill version %s/%s: %w", bill.Number, version.ID, err)
		}
		stats.VersionCount++
	}
	for _, diff := range bill.Diffs {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_diffs (bill_id, id, from_version_id, to_version_id, source_url)
VALUES (?, ?, ?, ?, ?)`,
			bill.ID, diff.ID, diff.FromVersionID, diff.ToVersionID, diff.SourceURL); err != nil {
			return fmt.Errorf("insert bill diff %s/%s: %w", bill.Number, diff.ID, err)
		}
		stats.DiffCount++

		for idx, clause := range diff.Clauses {
			if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_clause_diffs (
    bill_id, diff_id, id, label, change_type, from_text, to_text, hansard_anchor_url, sort_order
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				bill.ID, diff.ID, clause.ID, emptyToNil(clause.Label), clause.ChangeType,
				emptyToNil(clause.FromText), emptyToNil(clause.ToText), clause.HansardAnchorURL, idx+1); err != nil {
				return fmt.Errorf("insert bill clause diff %s/%s/%s: %w", bill.Number, diff.ID, clause.ID, err)
			}
		}
	}
	for _, amendment := range bill.Amendments {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_amendments (
    bill_id, id, event_id, stage_name, amendment_note_id, amendment_count, source_url
) VALUES (?, ?, ?, ?, ?, ?, ?)`,
			bill.ID, amendment.ID, amendment.EventID, amendment.StageName, amendment.AmendmentNoteID, amendment.AmendmentCount, amendment.SourceURL); err != nil {
			return fmt.Errorf("insert bill amendment %s/%s: %w", bill.Number, amendment.ID, err)
		}
		stats.AmendmentCount++
	}
	for _, costing := range bill.PBOCostings {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO pbo_costings (bill_id, id, title, url, source, published)
VALUES (?, ?, ?, ?, ?, ?)`,
			bill.ID, costing.ID, costing.Title, costing.URL, costing.Source, emptyToNil(costing.Published)); err != nil {
			return fmt.Errorf("insert PBO costing %s/%s: %w", bill.Number, costing.ID, err)
		}
		stats.PBOCostingCount++
	}
	for _, link := range bill.RelatedLinks {
		if _, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO bill_related_links (bill_id, id, title, url, type, source)
VALUES (?, ?, ?, ?, ?, ?)`,
			bill.ID, link.ID, link.Title, link.URL, link.Type, link.Source); err != nil {
			return fmt.Errorf("insert related link %s/%s: %w", bill.Number, link.ID, err)
		}
		stats.RelatedLinkCount++
	}
	return nil
}

func writeMeta(ctx context.Context, db *sql.DB, stats domain.Stats) error {
	values := map[string]string{
		"version":           domain.ManifestVersion,
		"built_at":          stats.BuiltAt.UTC().Format(time.RFC3339),
		"parliament_number": fmt.Sprintf("%d", stats.Parliament),
		"session_number":    fmt.Sprintf("%d", stats.Session),
		"bill_count":        fmt.Sprintf("%d", stats.BillCount),
		"version_count":     fmt.Sprintf("%d", stats.VersionCount),
		"amendment_count":   fmt.Sprintf("%d", stats.AmendmentCount),
		"pbo_costing_count": fmt.Sprintf("%d", stats.PBOCostingCount),
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
	names := []string{
		"bills",
		"bill_stages",
		"bill_events",
		"bill_committee_stages",
		"bill_committee_meetings",
		"bill_versions",
		"bill_diffs",
		"bill_clause_diffs",
		"bill_amendments",
		"pbo_costings",
		"bill_related_links",
	}
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
	var billCount int
	if err := db.QueryRowContext(ctx, "SELECT COUNT(*) FROM bills").Scan(&billCount); err != nil {
		return fmt.Errorf("count bills: %w", err)
	}
	if billCount != stats.BillCount {
		return fmt.Errorf("bills count %d does not match stats %d", billCount, stats.BillCount)
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

func zeroToNil(value int) any {
	if value == 0 {
		return nil
	}
	return value
}

func boolInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func intPtrValue(value *int) any {
	if value == nil {
		return nil
	}
	return *value
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

func derefString(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
