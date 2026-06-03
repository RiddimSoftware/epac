package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"sort"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
	"epac/lobbying-index/internal/usecase"
)

const defaultMandateSourceURL = "https://www.pm.gc.ca/en/mandate-letters"

type resolvedMinisterPeriod struct {
	MemberID         string
	MinisterName     string
	FirstName        string
	LastName         string
	PortfolioName    string
	StartDate        *time.Time
	EndDate          *time.Time
	TenureStartDate  *time.Time
	TenureEndDate    *time.Time
	ParliamentNumber int
	SourceURL        string
	MinisterKey      string
}

type memberRecord struct {
	PersonID string
	FullName string
	FromDate string
	ToDate   string
}

func (a *Aggregator) SaveMinisterTables(ctx context.Context, databasePath string, snapshot domain.CabinetSnapshot) (usecase.PreBakeMinisterCommunicationsResult, error) {
	if databasePath == "" {
		databasePath = DefaultDatabasePath
	}

	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, fmt.Errorf("begin minister prebake tx: %w", err)
	}
	defer tx.Rollback()

	if err := createMinisterSchema(ctx, tx); err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, err
	}

	memberIndex, err := loadMemberIndex(ctx, tx)
	if err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, err
	}

	periods, unresolved := resolveMinisterPeriods(snapshot.PortfolioPeriods, memberIndex)
	if err := insertMinisterPortfolioPeriods(ctx, tx, periods); err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, err
	}

	mandateRows, err := insertMinisterMandateMappings(ctx, tx, periods, snapshot.MandateTopics)
	if err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, err
	}

	communicationRows, zeroCommunicationCount, err := insertMinisterCommunications(ctx, tx, periods)
	if err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, err
	}

	if err := tx.Commit(); err != nil {
		return usecase.PreBakeMinisterCommunicationsResult{}, fmt.Errorf("commit minister prebake tx: %w", err)
	}

	sort.Strings(unresolved)
	return usecase.PreBakeMinisterCommunicationsResult{
		DatabasePath:                   databasePath,
		MinistersProcessed:             countUniqueMinisters(periods),
		PortfolioRows:                  len(periods),
		MandateRows:                    mandateRows,
		CommunicationRows:              communicationRows,
		MemberResolutionMissCount:      len(unresolved),
		MinistersWithoutCommunications: zeroCommunicationCount,
		UnresolvedMinisters:            unresolved,
	}, nil
}

func createMinisterSchema(ctx context.Context, tx *sql.Tx) error {
	if _, err := tx.ExecContext(ctx, ministerSchemaSQL); err != nil {
		return fmt.Errorf("create minister prebake schema: %w", err)
	}
	return nil
}

func loadMemberIndex(ctx context.Context, tx *sql.Tx) (map[string]memberRecord, error) {
	rows, err := tx.QueryContext(ctx, `
SELECT
    COALESCE(person_id, ''),
    COALESCE(first_name, ''),
    COALESCE(last_name, ''),
    COALESCE(CAST(from_date AS TEXT), ''),
    COALESCE(CAST(to_date AS TEXT), '')
FROM members`)
	if err != nil {
		return nil, fmt.Errorf("query members for minister resolution: %w", err)
	}
	defer rows.Close()

	index := map[string]memberRecord{}
	for rows.Next() {
		var personID, firstName, lastName, fromDate, toDate string
		if err := rows.Scan(&personID, &firstName, &lastName, &fromDate, &toDate); err != nil {
			return nil, fmt.Errorf("scan member for minister resolution: %w", err)
		}
		key := normalizePersonName(strings.TrimSpace(firstName) + " " + strings.TrimSpace(lastName))
		if key == "" || strings.TrimSpace(personID) == "" {
			continue
		}
		candidate := memberRecord{
			PersonID: personID,
			FullName: key,
			FromDate: fromDate,
			ToDate:   toDate,
		}
		existing, ok := index[key]
		if !ok || preferMemberCandidate(candidate, existing) {
			index[key] = candidate
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate members for minister resolution: %w", err)
	}
	return index, nil
}

func preferMemberCandidate(left, right memberRecord) bool {
	leftCurrent := strings.TrimSpace(left.ToDate) == ""
	rightCurrent := strings.TrimSpace(right.ToDate) == ""
	if leftCurrent != rightCurrent {
		return leftCurrent
	}
	if left.FromDate != right.FromDate {
		return left.FromDate > right.FromDate
	}
	return left.PersonID < right.PersonID
}

func resolveMinisterPeriods(periods []domain.CabinetPortfolioPeriod, memberIndex map[string]memberRecord) ([]resolvedMinisterPeriod, []string) {
	resolved := make([]resolvedMinisterPeriod, 0, len(periods))
	unresolvedSet := map[string]struct{}{}
	groupIndices := map[string][]int{}

	for _, period := range periods {
		key := normalizePersonName(period.FirstName + " " + period.LastName)
		memberID := ""
		if candidate, ok := memberIndex[key]; ok {
			memberID = candidate.PersonID
		} else if strings.TrimSpace(period.MinisterName) != "" {
			unresolvedSet[period.MinisterName] = struct{}{}
		}

		ministerKey := memberKey(memberID, period.MinisterName)
		resolved = append(resolved, resolvedMinisterPeriod{
			MemberID:         memberID,
			MinisterName:     strings.TrimSpace(period.MinisterName),
			FirstName:        strings.TrimSpace(period.FirstName),
			LastName:         strings.TrimSpace(period.LastName),
			PortfolioName:    strings.TrimSpace(period.PortfolioName),
			StartDate:        dateOnlyPtr(period.StartDate),
			EndDate:          dateOnlyPtr(period.EndDate),
			ParliamentNumber: period.ParliamentNumber,
			SourceURL:        fallback(period.SourceURL, "https://www.pm.gc.ca/en/cabinet"),
			MinisterKey:      ministerKey,
		})
		groupIndices[ministerKey] = append(groupIndices[ministerKey], len(resolved)-1)
	}

	for _, indices := range groupIndices {
		startDate, endDate := computeTenureWindow(resolved, indices)
		for _, index := range indices {
			resolved[index].TenureStartDate = startDate
			resolved[index].TenureEndDate = endDate
		}
	}

	unresolved := make([]string, 0, len(unresolvedSet))
	for name := range unresolvedSet {
		unresolved = append(unresolved, name)
	}
	return resolved, unresolved
}

func computeTenureWindow(periods []resolvedMinisterPeriod, indices []int) (*time.Time, *time.Time) {
	var tenureStart *time.Time
	var tenureEnd *time.Time
	hasOpenEnd := false

	for _, index := range indices {
		period := periods[index]
		if period.StartDate != nil && (tenureStart == nil || period.StartDate.Before(*tenureStart)) {
			value := *period.StartDate
			tenureStart = &value
		}
		if period.EndDate == nil {
			hasOpenEnd = true
			continue
		}
		if tenureEnd == nil || tenureEnd.Before(*period.EndDate) {
			value := *period.EndDate
			tenureEnd = &value
		}
	}
	if hasOpenEnd {
		tenureEnd = nil
	}
	return tenureStart, tenureEnd
}

func insertMinisterPortfolioPeriods(ctx context.Context, tx *sql.Tx, periods []resolvedMinisterPeriod) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO minister_portfolio_periods (
    member_id,
    minister_name,
    first_name,
    last_name,
    portfolio_name,
    start_date,
    end_date,
    tenure_start_date,
    tenure_end_date,
    parliament_number,
    source_url
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
	if err != nil {
		return fmt.Errorf("prepare minister portfolio periods insert: %w", err)
	}
	defer stmt.Close()

	for _, period := range periods {
		if _, err := stmt.ExecContext(ctx,
			period.MemberID,
			period.MinisterName,
			nullableString(period.FirstName),
			nullableString(period.LastName),
			period.PortfolioName,
			dateParam(period.StartDate),
			dateParam(period.EndDate),
			dateParam(period.TenureStartDate),
			dateParam(period.TenureEndDate),
			period.ParliamentNumber,
			period.SourceURL,
		); err != nil {
			return fmt.Errorf("insert minister portfolio period for %s: %w", period.MinisterName, err)
		}
	}
	return nil
}

func insertMinisterMandateMappings(ctx context.Context, tx *sql.Tx, periods []resolvedMinisterPeriod, topics []domain.CabinetMandateTopic) (int, error) {
	if len(periods) == 0 || len(topics) == 0 {
		return 0, nil
	}
	stmt, err := tx.PrepareContext(ctx, `
INSERT INTO minister_mandate_topic_mappings (
    member_id,
    portfolio_name,
    epac_topic_slug,
    confidence,
    source_url
) VALUES (?, ?, ?, ?, ?)`)
	if err != nil {
		return 0, fmt.Errorf("prepare minister mandate mapping insert: %w", err)
	}
	defer stmt.Close()

	count := 0
	for _, period := range periods {
		for _, topic := range topics {
			if strings.TrimSpace(topic.EpacTopicSlug) == "" {
				continue
			}
			if _, err := stmt.ExecContext(ctx,
				period.MemberID,
				period.PortfolioName,
				strings.TrimSpace(topic.EpacTopicSlug),
				topic.Confidence,
				fallback(topic.SourceURL, defaultMandateSourceURL),
			); err != nil {
				return 0, fmt.Errorf("insert minister mandate mapping for %s: %w", period.MinisterName, err)
			}
			count++
		}
	}
	return count, nil
}

func insertMinisterCommunications(ctx context.Context, tx *sql.Tx, periods []resolvedMinisterPeriod) (int, int, error) {
	query, err := tx.PrepareContext(ctx, ministerCommunicationsQuery)
	if err != nil {
		return 0, 0, fmt.Errorf("prepare minister communications query: %w", err)
	}
	defer query.Close()

	insertStmt, err := tx.PrepareContext(ctx, `
INSERT INTO minister_communications (
    member_id,
    comlog_id,
    organization_name,
    registrant_name,
    registrant_type,
    communication_date,
    subject_matter_codes,
    source_url
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
	if err != nil {
		return 0, 0, fmt.Errorf("prepare minister communications insert: %w", err)
	}
	defer insertStmt.Close()

	countsByMinister := map[string]int{}
	seen := map[string]struct{}{}
	totalRows := 0

	for _, period := range periods {
		startDate := ""
		if period.StartDate != nil {
			startDate = formatDate(*period.StartDate)
		}
		endDate := ""
		if period.EndDate != nil {
			endDate = formatDate(*period.EndDate)
		}
		rows, err := query.QueryContext(ctx,
			strings.ToLower(strings.TrimSpace(period.LastName)),
			firstNamePrefix(period.FirstName),
			firstNamePrefix(period.FirstName),
			startDate,
			startDate,
			endDate,
			endDate,
		)
		if err != nil {
			return 0, 0, fmt.Errorf("query minister communications for %s: %w", period.MinisterName, err)
		}

		for rows.Next() {
			var (
				comlogID          string
				organizationName  string
				registrantName    string
				registrantType    string
				communicationDate string
				subjectCodes      string
			)
			if err := rows.Scan(
				&comlogID,
				&organizationName,
				&registrantName,
				&registrantType,
				&communicationDate,
				&subjectCodes,
			); err != nil {
				rows.Close()
				return 0, 0, fmt.Errorf("scan minister communication for %s: %w", period.MinisterName, err)
			}

			seenKey := period.MinisterKey + "\x00" + comlogID
			if _, ok := seen[seenKey]; ok {
				continue
			}
			seen[seenKey] = struct{}{}

			if subjectCodes == "" {
				subjectCodes = "[]"
			}
			if _, err := insertStmt.ExecContext(ctx,
				period.MemberID,
				comlogID,
				organizationName,
				registrantName,
				registrantType,
				communicationDate,
				subjectCodes,
				DefaultSourceURL,
			); err != nil {
				rows.Close()
				return 0, 0, fmt.Errorf("insert minister communication for %s: %w", period.MinisterName, err)
			}
			countsByMinister[period.MinisterKey]++
			totalRows++
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return 0, 0, fmt.Errorf("iterate minister communications for %s: %w", period.MinisterName, err)
		}
		rows.Close()
		if _, ok := countsByMinister[period.MinisterKey]; !ok {
			countsByMinister[period.MinisterKey] = 0
		}
	}

	zeroCommunicationCount := 0
	for _, count := range countsByMinister {
		if count == 0 {
			zeroCommunicationCount++
		}
	}
	return totalRows, zeroCommunicationCount, nil
}

func countUniqueMinisters(periods []resolvedMinisterPeriod) int {
	seen := map[string]struct{}{}
	for _, period := range periods {
		seen[period.MinisterKey] = struct{}{}
	}
	return len(seen)
}

func memberKey(memberID, ministerName string) string {
	if strings.TrimSpace(memberID) != "" {
		return strings.TrimSpace(memberID)
	}
	return normalizePersonName(ministerName)
}

func firstNamePrefix(firstName string) string {
	parts := strings.Fields(strings.TrimSpace(firstName))
	if len(parts) == 0 {
		return ""
	}
	normalized := normalizePersonName(parts[0])
	normalizedParts := strings.Fields(normalized)
	if len(normalizedParts) == 0 {
		return ""
	}
	return normalizedParts[0]
}

func normalizePersonName(name string) string {
	replacer := strings.NewReplacer(
		".", " ",
		",", " ",
		"'", " ",
		"’", " ",
		"-", " ",
	)
	normalized := strings.ToLower(replacer.Replace(strings.TrimSpace(name)))
	return strings.Join(strings.Fields(normalized), " ")
}

func nullableString(value string) any {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return value
}

func fallback(value, fallbackValue string) string {
	value = strings.TrimSpace(value)
	if value == "" {
		return fallbackValue
	}
	return value
}

const ministerSchemaSQL = `
DROP TABLE IF EXISTS minister_communications;
DROP TABLE IF EXISTS minister_mandate_topic_mappings;
DROP TABLE IF EXISTS minister_portfolio_periods;

CREATE TABLE minister_portfolio_periods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id TEXT NOT NULL,
    minister_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    portfolio_name TEXT NOT NULL,
    start_date TEXT,
    end_date TEXT,
    tenure_start_date TEXT,
    tenure_end_date TEXT,
    parliament_number INTEGER,
    source_url TEXT NOT NULL DEFAULT 'https://www.pm.gc.ca/en/cabinet',
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX minister_portfolio_periods_member_idx
    ON minister_portfolio_periods (member_id, start_date);
CREATE INDEX minister_portfolio_periods_parliament_portfolio_idx
    ON minister_portfolio_periods (parliament_number, LOWER(portfolio_name));

CREATE TABLE minister_mandate_topic_mappings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id TEXT NOT NULL,
    portfolio_name TEXT,
    epac_topic_slug TEXT NOT NULL,
    confidence REAL NOT NULL,
    source_url TEXT NOT NULL DEFAULT 'https://www.pm.gc.ca/en/mandate-letters',
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE UNIQUE INDEX minister_mandate_topic_mappings_unique_idx
    ON minister_mandate_topic_mappings (member_id, COALESCE(portfolio_name, ''), epac_topic_slug);
CREATE INDEX minister_mandate_topic_mappings_member_idx
    ON minister_mandate_topic_mappings (member_id, confidence DESC);

CREATE TABLE minister_communications (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id TEXT NOT NULL,
    comlog_id TEXT NOT NULL,
    organization_name TEXT,
    registrant_name TEXT,
    registrant_type TEXT,
    communication_date TEXT,
    subject_matter_codes TEXT NOT NULL DEFAULT '[]',
    source_url TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);
CREATE INDEX minister_communications_member_date_idx
    ON minister_communications (member_id, communication_date DESC, comlog_id);
`

const ministerCommunicationsQuery = `
WITH matched_dpohs AS (
    SELECT DISTINCT CAST(comlog_id AS TEXT) AS source_id
    FROM ocl_communication_dpohs
    WHERE lower(trim(COALESCE(dpoh_last_nm_tcpd, ''))) = ?
      AND (? = '' OR lower(trim(COALESCE(dpoh_first_nm_prenom_tcpd, ''))) LIKE '%' || ? || '%')
      AND lower(COALESCE(NULLIF(institution, 'null'), '')) LIKE '%house of commons%'
)
SELECT
    CAST(cp.comlog_id AS TEXT),
    COALESCE(NULLIF(cp.en_client_org_corp_nm_an, 'null'), NULLIF(cp.fr_client_org_corp_nm, 'null'), ''),
    trim(trim(COALESCE(cp.rgstrnt_1st_nm_prenom_dclrnt, '')) || ' ' || trim(COALESCE(cp.rgstrnt_last_nm_dclrnt, ''))),
    CASE COALESCE(cp.reg_type_enr, '')
        WHEN '1' THEN 'Consultant'
        WHEN '2' THEN 'In-house (corporation)'
        WHEN '3' THEN 'In-house (organization)'
        ELSE COALESCE(cp.reg_type_enr, '')
    END,
    COALESCE(date(NULLIF(CAST(cp.comm_date AS TEXT), 'null')), ''),
    COALESCE((
        SELECT json_group_array(code)
        FROM (
            SELECT DISTINCT csm.subject_code_objet AS code
            FROM ocl_communication_subject_matters csm
            WHERE CAST(csm.comlog_id AS TEXT) = CAST(cp.comlog_id AS TEXT)
              AND NULLIF(trim(csm.subject_code_objet), '') IS NOT NULL
            ORDER BY code
        )
    ), '[]')
FROM matched_dpohs md
JOIN ocl_communication_primary cp ON CAST(cp.comlog_id AS TEXT) = md.source_id
WHERE (? = '' OR date(NULLIF(CAST(cp.comm_date AS TEXT), 'null')) >= date(?))
  AND (? = '' OR date(NULLIF(CAST(cp.comm_date AS TEXT), 'null')) <= date(?))
ORDER BY date(NULLIF(CAST(cp.comm_date AS TEXT), 'null')) DESC, CAST(cp.comlog_id AS TEXT)
`
