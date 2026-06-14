package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"sort"
	"time"

	"epac/bills/internal/domain"
	"epac/bills/internal/usecase"
)

type Repository struct {
	db  *sql.DB
	now func() time.Time
}

type Option func(*Repository)

func WithNow(now func() time.Time) Option {
	return func(r *Repository) {
		if now != nil {
			r.now = now
		}
	}
}

func New(db *sql.DB, opts ...Option) *Repository {
	r := &Repository{
		db:  db,
		now: func() time.Time { return time.Now().UTC() },
	}
	for _, opt := range opts {
		opt(r)
	}
	return r
}

func (r *Repository) ListBills(ctx context.Context) ([]domain.Bill, error) {
	bills, err := r.queryBills(ctx, `
		SELECT
			id,
			number,
			title,
			sponsor_name,
			status,
			current_stage,
			introduced_on,
			source_url,
			bill_type,
			parliament,
			session,
			legis_info_url
		FROM bills
		ORDER BY rowid`)
	if err != nil {
		return nil, err
	}
	if err := r.attachStages(ctx, bills); err != nil {
		return nil, err
	}
	return bills, nil
}

func (r *Repository) GetBillDepth(ctx context.Context, id string) (domain.Bill, error) {
	bills, err := r.queryBills(ctx, `
		SELECT
			id,
			number,
			title,
			sponsor_name,
			status,
			current_stage,
			introduced_on,
			source_url,
			bill_type,
			parliament,
			session,
			legis_info_url
		FROM bills
		WHERE id = ?
		LIMIT 1`, id)
	if err != nil {
		return domain.Bill{}, err
	}
	if len(bills) == 0 {
		return domain.Bill{}, usecase.ErrBillNotFound
	}
	bill := bills[0]
	stages, err := r.billStages(ctx, bill.ID)
	if err != nil {
		return domain.Bill{}, err
	}
	versions, err := r.billVersions(ctx, bill.ID)
	if err != nil {
		return domain.Bill{}, err
	}
	amendments, err := r.billAmendments(ctx, bill.ID)
	if err != nil {
		return domain.Bill{}, err
	}
	bill.Stages = stages
	bill.Versions = versions
	bill.Amendments = amendments
	return bill, nil
}

func (r *Repository) GetBillCommitteeStage(ctx context.Context, id string) (*domain.BillCommitteeStage, error) {
	billID, err := r.lookupBillID(ctx, id)
	if err != nil {
		return nil, err
	}
	if ok, err := r.tableExists(ctx, "bill_committee_stages"); err != nil || !ok {
		return nil, err
	}

	var stageRow billCommitteeStageRow
	var studiedSince, studyCompletedAt sql.NullString
	err = r.db.QueryRowContext(ctx, `
		SELECT
			id,
			committee_acronym,
			committee_name,
			committee_chamber,
			committee_url,
			studied_since,
			study_completed_at
		FROM bill_committee_stages
		WHERE bill_id = ?
		ORDER BY
			CASE WHEN study_completed_at IS NULL THEN 0 ELSE 1 END,
			sort_order DESC,
			rowid DESC
		LIMIT 1`, billID).Scan(
		&stageRow.id,
		&stageRow.committeeAcronym,
		&stageRow.committeeName,
		&stageRow.committeeChamber,
		&stageRow.committeeURL,
		&studiedSince,
		&studyCompletedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("query bill committee stage sqlite artifact: %w", err)
	}

	meetings, err := r.billCommitteeMeetings(ctx, billID, stageRow.id)
	if err != nil {
		return nil, err
	}
	upcoming, past := r.splitCommitteeMeetings(meetings)

	return &domain.BillCommitteeStage{
		Committee: domain.ParliamentaryCommittee{
			Code:    stageRow.committeeAcronym,
			Name:    stageRow.committeeName,
			Chamber: stageRow.committeeChamber,
			URL:     stageRow.committeeURL,
		},
		StudiedSince:     stringPtr(studiedSince),
		StudyCompletedAt: stringPtr(studyCompletedAt),
		UpcomingMeetings: upcoming,
		PastMeetings:     past,
	}, nil
}

func (r *Repository) GetBillVersionDiff(ctx context.Context, id, fromVersionID, toVersionID string) (*domain.BillVersionDiff, error) {
	billID, err := r.lookupBillID(ctx, id)
	if err != nil {
		return nil, err
	}

	if ok, err := r.tableExists(ctx, "bill_versions"); err != nil || !ok {
		return nil, err
	}
	if ok, err := r.tableExists(ctx, "bill_diffs"); err != nil || !ok {
		return nil, err
	}
	if ok, err := r.tableExists(ctx, "bill_clause_diffs"); err != nil || !ok {
		return nil, err
	}

	fromVersion, ok, err := r.billVersionByID(ctx, billID, fromVersionID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, usecase.ErrVersionNotFound
	}

	toVersion, ok, err := r.billVersionByID(ctx, billID, toVersionID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, usecase.ErrVersionNotFound
	}

	var diffID string
	err = r.db.QueryRowContext(ctx, `
		SELECT id
		FROM bill_diffs
		WHERE bill_id = ? AND from_version_id = ? AND to_version_id = ?
		LIMIT 1`, billID, fromVersionID, toVersionID).Scan(&diffID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("query bill diff sqlite artifact: %w", err)
	}

	clauses, err := r.billClauseDiffs(ctx, billID, diffID)
	if err != nil {
		return nil, err
	}
	return &domain.BillVersionDiff{
		From:    fromVersion,
		To:      toVersion,
		Clauses: clauses,
	}, nil
}

func (r *Repository) queryBills(ctx context.Context, query string, args ...any) ([]domain.Bill, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query bills sqlite artifact: %w", err)
	}
	defer rows.Close()

	bills := make([]domain.Bill, 0)
	for rows.Next() {
		var bill domain.Bill
		var sponsorName, status, currentStage, sourceURL, billType, legisInfoURL sql.NullString
		var introducedOn sql.NullString
		var parliament sql.NullInt64
		var session sql.NullInt64
		if err := rows.Scan(
			&bill.ID,
			&bill.Number,
			&bill.Title,
			&sponsorName,
			&status,
			&currentStage,
			&introducedOn,
			&sourceURL,
			&billType,
			&parliament,
			&session,
			&legisInfoURL,
		); err != nil {
			return nil, fmt.Errorf("scan bills sqlite artifact: %w", err)
		}
		bill.SponsorName = stringValue(sponsorName)
		bill.Status = stringValue(status)
		bill.CurrentStage = stringValue(currentStage)
		bill.IntroducedOn = stringPtr(introducedOn)
		bill.SourceURL = stringValue(sourceURL)
		bill.BillType = stringValue(billType)
		bill.Parliament = intPtr(parliament)
		bill.Session = intPtr(session)
		bill.LegisInfoURL = stringValue(legisInfoURL)
		bills = append(bills, bill)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bills sqlite artifact: %w", err)
	}
	if bills == nil {
		bills = []domain.Bill{}
	}
	return bills, nil
}

func (r *Repository) lookupBillID(ctx context.Context, id string) (string, error) {
	var billID string
	err := r.db.QueryRowContext(ctx, `
		SELECT id
		FROM bills
		WHERE id = ? OR number = ?
		LIMIT 1`, id, id).Scan(&billID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", usecase.ErrBillNotFound
	}
	if err != nil {
		return "", fmt.Errorf("lookup bill sqlite artifact: %w", err)
	}
	return billID, nil
}

func (r *Repository) billCommitteeMeetings(ctx context.Context, billID, stageID string) ([]domain.BillCommitteeMeeting, error) {
	if ok, err := r.tableExists(ctx, "bill_committee_meetings"); err != nil || !ok {
		return []domain.BillCommitteeMeeting{}, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, meeting_number, meeting_date, witness_count, evidence_url
		FROM bill_committee_meetings
		WHERE bill_id = ? AND stage_id = ?
		ORDER BY sort_order, rowid`, billID, stageID)
	if err != nil {
		return nil, fmt.Errorf("query bill committee meetings sqlite artifact: %w", err)
	}
	defer rows.Close()

	meetings := make([]domain.BillCommitteeMeeting, 0)
	for rows.Next() {
		var meeting domain.BillCommitteeMeeting
		var date, evidenceURL sql.NullString
		var witnessCount sql.NullInt64
		if err := rows.Scan(&meeting.ID, &meeting.MeetingNumber, &date, &witnessCount, &evidenceURL); err != nil {
			return nil, fmt.Errorf("scan bill committee meetings sqlite artifact: %w", err)
		}
		meeting.Date = stringPtr(date)
		meeting.WitnessCount = intPtr(witnessCount)
		meeting.EvidenceURL = stringPtr(evidenceURL)
		meetings = append(meetings, meeting)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill committee meetings sqlite artifact: %w", err)
	}
	return meetings, nil
}

func (r *Repository) splitCommitteeMeetings(meetings []domain.BillCommitteeMeeting) ([]domain.BillCommitteeMeeting, []domain.BillCommitteeMeeting) {
	today := r.now().UTC().Format("2006-01-02")
	upcoming := make([]domain.BillCommitteeMeeting, 0)
	past := make([]domain.BillCommitteeMeeting, 0)
	for _, meeting := range meetings {
		if meeting.Date != nil && *meeting.Date >= today {
			upcoming = append(upcoming, meeting)
			continue
		}
		past = append(past, meeting)
	}
	sort.SliceStable(upcoming, func(i, j int) bool {
		return dateValue(upcoming[i].Date) < dateValue(upcoming[j].Date)
	})
	sort.SliceStable(past, func(i, j int) bool {
		return dateValue(past[i].Date) > dateValue(past[j].Date)
	})
	return upcoming, past
}

func dateValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

type billCommitteeStageRow struct {
	id               string
	committeeAcronym string
	committeeName    string
	committeeChamber string
	committeeURL     string
}

func (r *Repository) attachStages(ctx context.Context, bills []domain.Bill) error {
	if len(bills) == 0 {
		return nil
	}
	stages, err := r.allBillStages(ctx)
	if err != nil {
		return err
	}
	for i := range bills {
		bills[i].Stages = stages[bills[i].ID]
	}
	return nil
}

func (r *Repository) allBillStages(ctx context.Context) (map[string][]domain.BillStage, error) {
	if ok, err := r.tableExists(ctx, "bill_stages"); err != nil || !ok {
		return map[string][]domain.BillStage{}, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT bill_id, id, name, completed_date, is_completed
		FROM bill_stages
		ORDER BY bill_id, sort_order, rowid`)
	if err != nil {
		return nil, fmt.Errorf("query bill stages sqlite artifact: %w", err)
	}
	defer rows.Close()

	stages := make(map[string][]domain.BillStage)
	for rows.Next() {
		var billID string
		var stage domain.BillStage
		var completedDate sql.NullString
		var isCompleted int
		if err := rows.Scan(&billID, &stage.ID, &stage.Name, &completedDate, &isCompleted); err != nil {
			return nil, fmt.Errorf("scan bill stages sqlite artifact: %w", err)
		}
		stage.CompletedDate = stringPtr(completedDate)
		stage.IsCompleted = isCompleted != 0
		stages[billID] = append(stages[billID], stage)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill stages sqlite artifact: %w", err)
	}
	return stages, nil
}

func (r *Repository) billStages(ctx context.Context, billID string) ([]domain.BillStage, error) {
	if ok, err := r.tableExists(ctx, "bill_stages"); err != nil || !ok {
		return []domain.BillStage{}, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, name, completed_date, is_completed
		FROM bill_stages
		WHERE bill_id = ?
		ORDER BY sort_order, rowid`, billID)
	if err != nil {
		return nil, fmt.Errorf("query bill stages sqlite artifact: %w", err)
	}
	defer rows.Close()

	stages := make([]domain.BillStage, 0)
	for rows.Next() {
		var stage domain.BillStage
		var completedDate sql.NullString
		var isCompleted int
		if err := rows.Scan(&stage.ID, &stage.Name, &completedDate, &isCompleted); err != nil {
			return nil, fmt.Errorf("scan bill stages sqlite artifact: %w", err)
		}
		stage.CompletedDate = stringPtr(completedDate)
		stage.IsCompleted = isCompleted != 0
		stages = append(stages, stage)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill stages sqlite artifact: %w", err)
	}
	return stages, nil
}

// billVersions reads the version rows the bills-indexer writes. The producer's
// bill_versions table is the locked contract (see the seam test): per version
// it stores a stage name and a canonical viewer URL (html_url), so we read
// those with fixed SQL rather than probing for columns the indexer never
// writes. Label and Stage both carry the stage name; SourceURL is html_url.
func (r *Repository) billVersions(ctx context.Context, billID string) ([]domain.BillVersion, error) {
	if ok, err := r.tableExists(ctx, "bill_versions"); err != nil || !ok {
		return []domain.BillVersion{}, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, stage, html_url
		FROM bill_versions
		WHERE bill_id = ?
		ORDER BY sort_order, rowid`, billID)
	if err != nil {
		return nil, fmt.Errorf("query bill versions sqlite artifact: %w", err)
	}
	defer rows.Close()

	versions := make([]domain.BillVersion, 0)
	for rows.Next() {
		version, err := scanBillVersion(rows)
		if err != nil {
			return nil, err
		}
		versions = append(versions, version)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill versions sqlite artifact: %w", err)
	}
	return versions, nil
}

func (r *Repository) billVersionByID(ctx context.Context, billID, versionID string) (domain.BillVersion, bool, error) {
	if ok, err := r.tableExists(ctx, "bill_versions"); err != nil || !ok {
		return domain.BillVersion{}, false, err
	}
	version, err := scanBillVersion(r.db.QueryRowContext(ctx, `
		SELECT id, stage, html_url
		FROM bill_versions
		WHERE bill_id = ? AND id = ?
		LIMIT 1`, billID, versionID))
	if errors.Is(err, sql.ErrNoRows) {
		return domain.BillVersion{}, false, nil
	}
	if err != nil {
		return domain.BillVersion{}, false, err
	}
	return version, true, nil
}

// rowScanner is satisfied by both *sql.Rows and *sql.Row so scanBillVersion can
// serve list and single-row reads from the same fixed projection.
type rowScanner interface {
	Scan(dest ...any) error
}

// scanBillVersion maps the producer's (id, stage, html_url) projection to the
// served BillVersion. The indexer has no separate version label or title, so
// Label and Stage both carry the publication stage name; SourceURL is the
// indexer's html_url. These are the only version fields the producer writes.
func scanBillVersion(scanner rowScanner) (domain.BillVersion, error) {
	var id, stage, htmlURL sql.NullString
	if err := scanner.Scan(&id, &stage, &htmlURL); err != nil {
		return domain.BillVersion{}, fmt.Errorf("scan bill version sqlite artifact: %w", err)
	}
	return domain.BillVersion{
		ID:        stringValue(id),
		Label:     stringValue(stage),
		Stage:     stringValue(stage),
		SourceURL: stringValue(htmlURL),
	}, nil
}

func (r *Repository) billClauseDiffs(ctx context.Context, billID, diffID string) ([]domain.BillClauseDiff, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, label, change_type, from_text, to_text, hansard_anchor_url
		FROM bill_clause_diffs
		WHERE bill_id = ? AND diff_id = ?
		ORDER BY sort_order, rowid`, billID, diffID)
	if err != nil {
		return nil, fmt.Errorf("query bill clause diffs sqlite artifact: %w", err)
	}
	defer rows.Close()

	clauses := make([]domain.BillClauseDiff, 0)
	for rows.Next() {
		var clause domain.BillClauseDiff
		var id, label, changeType, fromText, toText, hansardAnchorURL sql.NullString
		if err := rows.Scan(&id, &label, &changeType, &fromText, &toText, &hansardAnchorURL); err != nil {
			return nil, fmt.Errorf("scan bill clause diffs sqlite artifact: %w", err)
		}
		clause.ID = stringValue(id)
		clause.Label = stringValue(label)
		clause.ChangeType = stringValue(changeType)
		clause.FromText = stringValue(fromText)
		clause.ToText = stringValue(toText)
		clause.HansardAnchorURL = stringPtr(hansardAnchorURL)
		clauses = append(clauses, clause)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill clause diffs sqlite artifact: %w", err)
	}
	return clauses, nil
}

// billAmendments reads the amendment rows the bills-indexer writes. The
// producer's bill_amendments table only carries an id and a source_url that map
// onto the served BillAmendment, so we read those with fixed SQL. The remaining
// served fields (number, title, status, stage, sponsor_name, proposed_on, text)
// have no producer column and are intentionally left empty — matching what
// production already returns. Trimming or enriching those served fields is a
// separate contract decision (out of scope for the version contract this seam
// locks); see the "Known limitation" section in
// docs/architecture/bills-artifact-contract-epac2304.md.
func (r *Repository) billAmendments(ctx context.Context, billID string) ([]domain.BillAmendment, error) {
	if ok, err := r.tableExists(ctx, "bill_amendments"); err != nil || !ok {
		return []domain.BillAmendment{}, err
	}
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, source_url
		FROM bill_amendments
		WHERE bill_id = ?
		ORDER BY rowid`, billID)
	if err != nil {
		return nil, fmt.Errorf("query bill amendments sqlite artifact: %w", err)
	}
	defer rows.Close()

	amendments := make([]domain.BillAmendment, 0)
	for rows.Next() {
		var amendment domain.BillAmendment
		var id, sourceURL sql.NullString
		if err := rows.Scan(&id, &sourceURL); err != nil {
			return nil, fmt.Errorf("scan bill amendments sqlite artifact: %w", err)
		}
		amendment.ID = stringValue(id)
		amendment.SourceURL = stringValue(sourceURL)
		amendments = append(amendments, amendment)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill amendments sqlite artifact: %w", err)
	}
	return amendments, nil
}

func (r *Repository) tableExists(ctx context.Context, table string) (bool, error) {
	var name string
	err := r.db.QueryRowContext(ctx, "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", table).Scan(&name)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("find sqlite table %s: %w", table, err)
	}
	return true, nil
}

func stringValue(value sql.NullString) string {
	if !value.Valid {
		return ""
	}
	return value.String
}

func stringPtr(value sql.NullString) *string {
	if !value.Valid {
		return nil
	}
	return &value.String
}

func intPtr(value sql.NullInt64) *int {
	if !value.Valid {
		return nil
	}
	converted := int(value.Int64)
	return &converted
}
