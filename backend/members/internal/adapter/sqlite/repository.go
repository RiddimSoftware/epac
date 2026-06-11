package sqlite

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"epac/members/internal/domain"
	"epac/members/internal/usecase"
)

type Repository struct {
	db *sql.DB
}

func New(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) ListMembers(ctx context.Context) ([]domain.Member, error) {
	return r.queryMembers(ctx, `
		SELECT id, name, riding, province, party, source_url
		FROM members
		ORDER BY rowid`)
}

func (r *Repository) GetMemberProfile(ctx context.Context, id string) (domain.Member, error) {
	members, err := r.queryMembers(ctx, `
		SELECT id, name, riding, province, party, source_url
		FROM members
		WHERE id = ?
		LIMIT 1`, id)
	if err != nil {
		return domain.Member{}, err
	}
	if len(members) == 0 {
		return domain.Member{}, usecase.ErrMemberNotFound
	}
	member := members[0]
	attendance, err := r.attendance(ctx, member.ID)
	if err != nil {
		return domain.Member{}, err
	}
	member.Attendance = attendance
	return member, nil
}

func (r *Repository) queryMembers(ctx context.Context, query string, args ...any) ([]domain.Member, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query members sqlite artifact: %w", err)
	}
	defer rows.Close()

	members := make([]domain.Member, 0)
	for rows.Next() {
		var member domain.Member
		var riding, province, party, sourceURL sql.NullString
		if err := rows.Scan(&member.ID, &member.Name, &riding, &province, &party, &sourceURL); err != nil {
			return nil, fmt.Errorf("scan members sqlite artifact: %w", err)
		}
		member.Riding = stringValue(riding)
		member.Province = stringValue(province)
		member.Party = stringValue(party)
		member.SourceURL = stringValue(sourceURL)
		members = append(members, member)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate members sqlite artifact: %w", err)
	}
	if members == nil {
		members = []domain.Member{}
	}
	return members, nil
}

func (r *Repository) attendance(ctx context.Context, memberID string) ([]domain.AttendanceRecord, error) {
	table, columns, ok, err := r.attendanceTable(ctx)
	if err != nil || !ok {
		return []domain.AttendanceRecord{}, err
	}
	memberIDColumn := firstColumn(columns, "member_id", "person_id")
	if memberIDColumn == "" {
		return []domain.AttendanceRecord{}, nil
	}
	query := fmt.Sprintf(`
		SELECT %s, %s, %s, %s, %s, %s
		FROM %s
		WHERE %s = ?
		ORDER BY %s`,
		columnExpr(columns, "sitting_date", "date"),
		columnExpr(columns, "status", "attendance_status"),
		columnExpr(columns, "present", "is_present"),
		columnExpr(columns, "source_url", "url"),
		columnExpr(columns, "parliament", "parliament_num", "parliament_number"),
		columnExpr(columns, "session", "session_num", "session_number"),
		table,
		memberIDColumn,
		orderExpr(columns),
	)
	rows, err := r.db.QueryContext(ctx, query, memberID)
	if err != nil {
		return nil, fmt.Errorf("query member attendance sqlite artifact: %w", err)
	}
	defer rows.Close()

	records := make([]domain.AttendanceRecord, 0)
	for rows.Next() {
		var record domain.AttendanceRecord
		var sittingDate, status, sourceURL sql.NullString
		var present, parliament, session sql.NullInt64
		if err := rows.Scan(&sittingDate, &status, &present, &sourceURL, &parliament, &session); err != nil {
			return nil, fmt.Errorf("scan member attendance sqlite artifact: %w", err)
		}
		record.SittingDate = stringValue(sittingDate)
		record.Status = stringValue(status)
		record.Present = boolPtr(present)
		record.SourceURL = stringValue(sourceURL)
		record.Parliament = intPtr(parliament)
		record.Session = intPtr(session)
		records = append(records, record)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate member attendance sqlite artifact: %w", err)
	}
	return records, nil
}

func (r *Repository) attendanceTable(ctx context.Context) (string, map[string]bool, bool, error) {
	for _, table := range []string{"mp_attendance", "member_attendance"} {
		columns, ok, err := r.tableColumns(ctx, table)
		if err != nil {
			return "", nil, false, err
		}
		if ok {
			return table, columns, true, nil
		}
	}
	return "", nil, false, nil
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

func (r *Repository) tableColumns(ctx context.Context, table string) (map[string]bool, bool, error) {
	if ok, err := r.tableExists(ctx, table); err != nil || !ok {
		return nil, false, err
	}
	rows, err := r.db.QueryContext(ctx, "PRAGMA table_info("+table+")")
	if err != nil {
		return nil, false, fmt.Errorf("read sqlite table info %s: %w", table, err)
	}
	defer rows.Close()

	columns := map[string]bool{}
	for rows.Next() {
		var cid int
		var name, columnType string
		var notNull, pk int
		var defaultValue any
		if err := rows.Scan(&cid, &name, &columnType, &notNull, &defaultValue, &pk); err != nil {
			return nil, false, fmt.Errorf("scan sqlite table info %s: %w", table, err)
		}
		columns[name] = true
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("iterate sqlite table info %s: %w", table, err)
	}
	return columns, true, nil
}

func columnExpr(columns map[string]bool, candidates ...string) string {
	for _, candidate := range candidates {
		if columns[candidate] {
			return candidate
		}
	}
	return "NULL"
}

func firstColumn(columns map[string]bool, candidates ...string) string {
	for _, candidate := range candidates {
		if columns[candidate] {
			return candidate
		}
	}
	return ""
}

func orderExpr(columns map[string]bool) string {
	if columns["sitting_date"] {
		return "sitting_date DESC, rowid"
	}
	if columns["date"] {
		return "date DESC, rowid"
	}
	if columns["sort_order"] {
		return "sort_order, rowid"
	}
	return "rowid"
}

func stringValue(value sql.NullString) string {
	if !value.Valid {
		return ""
	}
	return value.String
}

func boolPtr(value sql.NullInt64) *bool {
	if !value.Valid {
		return nil
	}
	converted := value.Int64 != 0
	return &converted
}

func intPtr(value sql.NullInt64) *int {
	if !value.Valid {
		return nil
	}
	converted := int(value.Int64)
	return &converted
}
