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
	query, err := r.memberSelect(ctx, "", "ORDER BY rowid")
	if err != nil {
		return nil, err
	}
	return r.queryMembers(ctx, query)
}

func (r *Repository) GetMemberProfile(ctx context.Context, id string) (domain.Member, error) {
	query, err := r.memberSelect(ctx, "WHERE id = ?", "LIMIT 1")
	if err != nil {
		return domain.Member{}, err
	}
	members, err := r.queryMembers(ctx, query, id)
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
	biography, err := r.biography(ctx, member.ID)
	if err != nil {
		return domain.Member{}, err
	}
	member.Biography = biography
	sponsorships, err := r.pmbSponsorships(ctx, member.ID)
	if err != nil {
		return domain.Member{}, err
	}
	member.PMBSponsorships = sponsorships
	return member, nil
}

func (r *Repository) memberSelect(ctx context.Context, whereClause, orderClause string) (string, error) {
	columns, ok, err := r.tableColumns(ctx, "members")
	if err != nil {
		return "", err
	}
	if !ok {
		return "", usecase.ErrMemberNotFound
	}
	return fmt.Sprintf(`
		SELECT %s, %s, %s, %s, %s, %s, %s, %s, %s
		FROM members
		%s
		%s`,
		columnExpr(columns, "id"),
		columnExpr(columns, "name"),
		columnExpr(columns, "riding"),
		columnExpr(columns, "province"),
		columnExpr(columns, "party"),
		columnExpr(columns, "source_url", "url"),
		columnExpr(columns, "profile_url"),
		columnExpr(columns, "from_date"),
		columnExpr(columns, "to_date"),
		whereClause,
		orderClause,
	), nil
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
		var riding, province, party, sourceURL, profileURL, fromDate, toDate sql.NullString
		if err := rows.Scan(
			&member.ID,
			&member.Name,
			&riding,
			&province,
			&party,
			&sourceURL,
			&profileURL,
			&fromDate,
			&toDate,
		); err != nil {
			return nil, fmt.Errorf("scan members sqlite artifact: %w", err)
		}
		member.Riding = stringValue(riding)
		member.Province = stringValue(province)
		member.Party = stringValue(party)
		member.SourceURL = stringValue(sourceURL)
		member.ProfileURL = stringValue(profileURL)
		member.FromDate = stringValue(fromDate)
		member.ToDate = stringValue(toDate)
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

func (r *Repository) biography(ctx context.Context, memberID string) (*domain.Biography, error) {
	columns, ok, err := r.tableColumns(ctx, "member_biographies")
	if err != nil || !ok {
		return nil, err
	}
	memberIDColumn := firstColumn(columns, "member_id", "person_id")
	if memberIDColumn == "" {
		return nil, nil
	}
	query := fmt.Sprintf(`
		SELECT %s, %s, %s, %s
		FROM member_biographies
		WHERE %s = ?
		LIMIT 1`,
		columnExpr(columns, "summary"),
		columnExpr(columns, "preferred_language"),
		columnExpr(columns, "photo_url"),
		columnExpr(columns, "source_url", "url"),
		memberIDColumn,
	)
	var summary, preferredLanguage, photoURL, sourceURL sql.NullString
	err = r.db.QueryRowContext(ctx, query, memberID).Scan(&summary, &preferredLanguage, &photoURL, &sourceURL)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("query member biography sqlite artifact: %w", err)
	}
	return &domain.Biography{
		Summary:           stringValue(summary),
		PreferredLanguage: stringValue(preferredLanguage),
		PhotoURL:          stringValue(photoURL),
		SourceURL:         stringValue(sourceURL),
	}, nil
}

func (r *Repository) pmbSponsorships(ctx context.Context, memberID string) ([]domain.PMBSponsorship, error) {
	columns, ok, err := r.tableColumns(ctx, "pmb_sponsorships")
	if err != nil || !ok {
		return []domain.PMBSponsorship{}, err
	}
	memberIDColumn := firstColumn(columns, "member_id", "person_id")
	if memberIDColumn == "" {
		return []domain.PMBSponsorship{}, nil
	}
	query := fmt.Sprintf(`
		SELECT %s, %s, %s, %s, %s
		FROM pmb_sponsorships
		WHERE %s = ?
		ORDER BY %s`,
		columnExpr(columns, "id"),
		columnExpr(columns, "bill_number", "number"),
		columnExpr(columns, "title"),
		columnExpr(columns, "relationship"),
		columnExpr(columns, "legis_info_url", "legisinfo_url", "url"),
		memberIDColumn,
		orderExpr(columns),
	)
	rows, err := r.db.QueryContext(ctx, query, memberID)
	if err != nil {
		return nil, fmt.Errorf("query PMB sponsorship sqlite artifact: %w", err)
	}
	defer rows.Close()

	sponsorships := make([]domain.PMBSponsorship, 0)
	for rows.Next() {
		var sponsorship domain.PMBSponsorship
		var id, billNumber, title, relationship, legisInfoURL sql.NullString
		if err := rows.Scan(&id, &billNumber, &title, &relationship, &legisInfoURL); err != nil {
			return nil, fmt.Errorf("scan PMB sponsorship sqlite artifact: %w", err)
		}
		sponsorship.ID = stringValue(id)
		sponsorship.BillNumber = stringValue(billNumber)
		sponsorship.Title = stringValue(title)
		sponsorship.Relationship = stringValue(relationship)
		sponsorship.LegisInfoURL = stringValue(legisInfoURL)
		sponsorships = append(sponsorships, sponsorship)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate PMB sponsorship sqlite artifact: %w", err)
	}
	return sponsorships, nil
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
