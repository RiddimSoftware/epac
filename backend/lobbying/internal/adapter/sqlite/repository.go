// Package sqlite implements lobbying serving repositories backed by the
// verified lobbying-index SQLite artifact.
package sqlite

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"time"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	"epac/lobbying/internal/usecase"
)

type Repository struct {
	db *sql.DB
}

var ErrReadOnlyArtifact = errors.New("lobbying SQLite artifact is read-only")

const registrationReportsURL = "https://www.lobbycanada.gc.ca/app/secure/ocl/lrs/do/rgstrnCmmnctnRprts?lang=eng&regId="

func New(db *sql.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) SaveLobbyistOrganizations(context.Context, []domain.LobbyistOrganization) error {
	return ErrReadOnlyArtifact
}

func (r *Repository) ListByOCLCodes(ctx context.Context, mappings []usecase.OCLTopicMapping, pagination usecase.Pagination) (usecase.LobbyingByTopicPage, error) {
	if len(mappings) == 0 {
		return usecase.LobbyingByTopicPage{Rows: []usecase.LobbyingByTopicRecord{}}, nil
	}

	codes := normalizedCodes(mappings)
	if len(codes) == 0 {
		return usecase.LobbyingByTopicPage{Rows: []usecase.LobbyingByTopicRecord{}}, nil
	}
	confidenceByCode := map[string]float64{}
	for _, mapping := range mappings {
		confidenceByCode[usecase.NormalizeOCLCode(mapping.OCLCode)] = mapping.Confidence
	}

	args := make([]any, 0, len(codes)+2)
	placeholders := make([]string, 0, len(codes))
	for _, code := range codes {
		placeholders = append(placeholders, "?")
		args = append(args, code)
	}
	args = append(args, pagination.PerPage, (pagination.Page-1)*pagination.PerPage)

	rows, err := r.db.QueryContext(ctx, fmt.Sprintf(`
WITH matched AS (
	SELECT
		lsm.source_type,
		lsm.source_id,
		lsm.ocl_code,
		COALESCE(NULLIF(smt.smt_en_desc, ''), lsm.ocl_code) AS subject_matter,
		COALESCE(NULLIF(smt.smt_en_desc, ''), lsm.ocl_code) AS subject_description,
		COALESCE(lc.organization_name, lr.organization_name, '') AS organization_name,
		COALESCE(lc.registrant_name, '') AS registrant_name,
		CASE COALESCE(lc.registrant_type, lr.registrant_type, '')
			WHEN '1' THEN 'Consultant'
			WHEN '2' THEN 'In-house (corporation)'
			WHEN '3' THEN 'In-house (organization)'
			ELSE COALESCE(lc.registrant_type, lr.registrant_type, '')
		END AS registrant_type,
		COALESCE(DATE(lc.communication_date), '') AS communication_date,
		'' AS posted_date,
		COALESCE(DATE(lr.effective_date), '') AS effective_date,
		COALESCE(DATE(lr.end_date), '') AS end_date,
		COALESCE(lc.source_url, lr.source_url, ?) AS source_url,
		COALESCE(DATE(lc.communication_date), DATE(lr.effective_date), DATE(lr.end_date), '') AS sort_date,
		ROW_NUMBER() OVER (
			PARTITION BY lsm.source_type, lsm.source_id, lsm.ocl_code
			ORDER BY COALESCE(NULLIF(smt.smt_en_desc, ''), lsm.ocl_code)
		) AS duplicate_rank
	FROM lobbyist_subject_matters lsm
	LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = lsm.ocl_code
	LEFT JOIN lobbyist_communications lc
		ON lsm.source_type = 'communication' AND lc.comlog_id = lsm.source_id
	LEFT JOIN lobbyist_registrations lr
		ON lsm.source_type = 'registration' AND lr.reg_id = lsm.source_id
	WHERE lsm.source_type IN ('communication', 'registration')
	  AND lsm.ocl_code IN (%s)
),
deduped AS (
	SELECT * FROM matched WHERE duplicate_rank = 1
)
SELECT
	COUNT(*) OVER() AS total,
	source_type,
	source_id,
	ocl_code,
	subject_matter,
	subject_description,
	organization_name,
	registrant_name,
	registrant_type,
	communication_date,
	posted_date,
	effective_date,
	end_date,
	source_url
FROM deduped
ORDER BY sort_date DESC, source_type, source_id, ocl_code
LIMIT ? OFFSET ?`, strings.Join(placeholders, ",")), append([]any{usecase.SourceURL}, args...)...)
	if err != nil {
		return usecase.LobbyingByTopicPage{}, fmt.Errorf("query lobbying by topic: %w", err)
	}
	defer rows.Close()

	page := usecase.LobbyingByTopicPage{Rows: []usecase.LobbyingByTopicRecord{}}
	for rows.Next() {
		var record usecase.LobbyingByTopicRecord
		if err := rows.Scan(
			&page.Total,
			&record.Kind,
			&record.OCLID,
			&record.OCLCode,
			&record.SubjectMatter,
			&record.SubjectDescription,
			&record.OrganizationName,
			&record.RegistrantName,
			&record.RegistrantType,
			&record.CommunicationDate,
			&record.PostedDate,
			&record.EffectiveDate,
			&record.EndDate,
			&record.SourceURL,
		); err != nil {
			return usecase.LobbyingByTopicPage{}, fmt.Errorf("scan lobbying row: %w", err)
		}
		record.OCLCode = usecase.NormalizeOCLCode(record.OCLCode)
		record.MappingConfidence = confidenceByCode[record.OCLCode]
		record.Citation = usecase.Citation
		page.Rows = append(page.Rows, record)
	}
	if err := rows.Err(); err != nil {
		return usecase.LobbyingByTopicPage{}, fmt.Errorf("iterate lobbying rows: %w", err)
	}
	return page, nil
}

func (r *Repository) LoadBillSubjectContext(ctx context.Context, legisInfoID string) (usecase.BillSubjectContext, error) {
	legisInfoID = strings.TrimSpace(legisInfoID)
	if legisInfoID == "" {
		return usecase.BillSubjectContext{SubjectTags: []string{}}, nil
	}

	tags, err := r.listStrings(ctx, `
SELECT DISTINCT TRIM(subject_tag)
FROM legisinfo_bill_subject_tags
WHERE legisinfo_id = ? AND confidence >= ?
  AND NULLIF(TRIM(subject_tag), '') IS NOT NULL
ORDER BY TRIM(subject_tag)`, legisInfoID, usecase.LowConfidenceThreshold)
	if err != nil {
		return usecase.BillSubjectContext{}, fmt.Errorf("query bill subject tags: %w", err)
	}
	slugs, err := r.listStrings(ctx, `
SELECT DISTINCT TRIM(epac_topic_slug)
FROM legisinfo_bill_subject_tags
WHERE legisinfo_id = ? AND confidence >= ?
  AND NULLIF(TRIM(COALESCE(epac_topic_slug, '')), '') IS NOT NULL
ORDER BY TRIM(epac_topic_slug)`, legisInfoID, usecase.LowConfidenceThreshold)
	if err != nil {
		return usecase.BillSubjectContext{}, fmt.Errorf("query bill topic slugs: %w", err)
	}

	var latest sql.NullString
	if err := r.db.QueryRowContext(ctx, `
SELECT COALESCE(MAX(DATE(reading_date)), '')
FROM legisinfo_bill_readings
WHERE legisinfo_id = ?`, legisInfoID).Scan(&latest); err != nil {
		return usecase.BillSubjectContext{}, fmt.Errorf("query bill reading: %w", err)
	}
	return usecase.BillSubjectContext{
		LegisInfoID:           legisInfoID,
		SubjectTags:           tags,
		TopicSlugs:            slugs,
		MostRecentReadingDate: latest.String,
	}, nil
}

func (r *Repository) ListBillLobbyingCommunications(ctx context.Context, mappings []usecase.OCLTopicMapping, window usecase.DateWindow) ([]usecase.BillLobbyingCommunication, error) {
	codes := normalizedCodes(mappings)
	if len(codes) == 0 {
		return []usecase.BillLobbyingCommunication{}, nil
	}
	placeholders, args := placeholdersFor(codes)
	args = append(args, window.StartDate, window.EndDate)
	rows, err := r.db.QueryContext(ctx, fmt.Sprintf(`
WITH matched AS (
	SELECT
		lc.comlog_id,
		COALESCE(lc.organization_name, '') AS organization_name,
		COALESCE(NULLIF(smt.smt_en_desc, ''), lsm.ocl_code) AS subject_matter,
		lsm.ocl_code,
		COALESCE(DATE(lc.communication_date), '') AS communication_date,
		ROW_NUMBER() OVER (
			PARTITION BY lc.comlog_id, lsm.ocl_code
			ORDER BY COALESCE(NULLIF(smt.smt_en_desc, ''), lsm.ocl_code)
		) AS duplicate_rank
	FROM lobbyist_subject_matters lsm
	JOIN lobbyist_communications lc
		ON lsm.source_type = 'communication' AND lc.comlog_id = lsm.source_id
	LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = lsm.ocl_code
	WHERE lsm.ocl_code IN (%s)
	  AND DATE(lc.communication_date) >= DATE(?)
	  AND DATE(lc.communication_date) <= DATE(?)
)
SELECT comlog_id, organization_name, subject_matter, ocl_code, communication_date
FROM matched
WHERE duplicate_rank = 1
ORDER BY communication_date DESC, comlog_id, ocl_code`, placeholders), args...)
	if err != nil {
		return nil, fmt.Errorf("query bill lobbying communications: %w", err)
	}
	defer rows.Close()

	communications := []usecase.BillLobbyingCommunication{}
	for rows.Next() {
		var communication usecase.BillLobbyingCommunication
		if err := rows.Scan(&communication.ID, &communication.OrganizationName, &communication.SubjectMatter, &communication.OCLCode, &communication.CommunicationDate); err != nil {
			return nil, fmt.Errorf("scan bill lobbying communication: %w", err)
		}
		communication.OCLCode = usecase.NormalizeOCLCode(communication.OCLCode)
		communications = append(communications, communication)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate bill lobbying communications: %w", err)
	}
	return communications, nil
}

func (r *Repository) LoadMinisterProfile(ctx context.Context, memberID string) (usecase.MinisterProfile, error) {
	rows, err := r.db.QueryContext(ctx, ministerProfilesSQL+`
WHERE member_id = ?
ORDER BY start_date IS NOT NULL, start_date, portfolio_name`, strings.TrimSpace(memberID))
	if err != nil {
		return usecase.MinisterProfile{}, fmt.Errorf("query minister profile: %w", err)
	}
	defer rows.Close()
	profiles, err := scanMinisterProfiles(rows)
	if err != nil {
		return usecase.MinisterProfile{}, err
	}
	if len(profiles) == 0 {
		return usecase.MinisterProfile{}, usecase.ErrMinisterNotFound
	}
	return profiles[0], nil
}

func (r *Repository) ListCabinetMinisters(ctx context.Context, filter usecase.CabinetMinisterFilter) ([]usecase.MinisterProfile, error) {
	rows, err := r.db.QueryContext(ctx, ministerProfilesSQL+`
WHERE (? = 0 OR parliament_number = ?)
  AND (? = '' OR LOWER(portfolio_name) LIKE '%' || LOWER(?) || '%')
ORDER BY minister_name, start_date IS NOT NULL, start_date, portfolio_name`,
		filter.Parliament, filter.Parliament, strings.TrimSpace(filter.Portfolio), strings.TrimSpace(filter.Portfolio))
	if err != nil {
		return nil, fmt.Errorf("query cabinet ministers: %w", err)
	}
	defer rows.Close()
	return scanMinisterProfiles(rows)
}

func (r *Repository) ListMandatePolicyAreas(ctx context.Context, memberID string) ([]usecase.MandatePolicyArea, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT epac_topic_slug, confidence
FROM minister_mandate_topic_mappings
WHERE member_id = ?
ORDER BY confidence DESC, epac_topic_slug`, strings.TrimSpace(memberID))
	if err != nil {
		return nil, fmt.Errorf("query minister mandate policy areas: %w", err)
	}
	defer rows.Close()
	areas := []usecase.MandatePolicyArea{}
	for rows.Next() {
		var area usecase.MandatePolicyArea
		if err := rows.Scan(&area.EpacTopicSlug, &area.Confidence); err != nil {
			return nil, fmt.Errorf("scan minister mandate policy area: %w", err)
		}
		areas = append(areas, area)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate minister mandate policy areas: %w", err)
	}
	return areas, nil
}

func (r *Repository) ListMinisterCommunications(ctx context.Context, filter usecase.MinisterCommunicationsFilter) ([]usecase.MinisterLobbyingCommunication, error) {
	memberID := strings.TrimSpace(filter.MemberID)
	if memberID == "" {
		return []usecase.MinisterLobbyingCommunication{}, nil
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT
	comlog_id,
	COALESCE(organization_name, ''),
	COALESCE(registrant_name, ''),
	CASE COALESCE(registrant_type, '')
		WHEN '1' THEN 'Consultant'
		WHEN '2' THEN 'In-house (corporation)'
		WHEN '3' THEN 'In-house (organization)'
		ELSE COALESCE(registrant_type, '')
	END,
	COALESCE(DATE(communication_date), ''),
	subject_matter_codes,
	COALESCE(source_url, ?)
FROM minister_communications
WHERE member_id = ?
  AND (? = '' OR DATE(communication_date) >= DATE(?))
  AND (? = '' OR DATE(communication_date) <= DATE(?))
ORDER BY communication_date DESC, comlog_id`,
		usecase.SourceURL, memberID, strings.TrimSpace(filter.StartDate), strings.TrimSpace(filter.StartDate), strings.TrimSpace(filter.EndDate), strings.TrimSpace(filter.EndDate))
	if err != nil {
		return nil, fmt.Errorf("query minister lobbying communications: %w", err)
	}
	defer rows.Close()

	communications := []usecase.MinisterLobbyingCommunication{}
	for rows.Next() {
		var communication usecase.MinisterLobbyingCommunication
		var codesJSON []byte
		if err := rows.Scan(
			&communication.ID,
			&communication.OrganizationName,
			&communication.RegistrantName,
			&communication.RegistrantType,
			&communication.CommunicationDate,
			&codesJSON,
			&communication.SourceURL,
		); err != nil {
			return nil, fmt.Errorf("scan minister lobbying communication: %w", err)
		}
		communication.OCLCodes = decodeStringArray(codesJSON)
		communication.SubjectMatters = r.subjectMatterLabels(ctx, communication.OCLCodes)
		communication.Citation = usecase.Citation
		communications = append(communications, communication)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate minister lobbying communications: %w", err)
	}
	return communications, nil
}

func (r *Repository) RecordPortfolioBoundaryGap(context.Context, usecase.PortfolioBoundaryGap) error {
	return nil
}

func (r *Repository) BrowseLobbyistOrganizations(ctx context.Context, input application.BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	direction := "DESC"
	if strings.EqualFold(strings.TrimSpace(input.SortDirection), "asc") {
		direction = "ASC"
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT organization_id, COALESCE(ocl_organization_id, ''), name, type, COALESCE(sector, ''),
	registered_lobbyists, active_subject_matters,
	communication_volume_current_parliament, communication_volume_prior_parliament,
	top_dpohs, registration_status, registrations, recent_communications,
	subject_matters, updated_at
FROM lobbyist_organizations
WHERE (? = '' OR LOWER(name) LIKE '%' || LOWER(?) || '%' OR LOWER(organization_id) LIKE '%' || LOWER(?) || '%')
  AND (? = '' OR LOWER(COALESCE(sector, '')) = LOWER(?))
ORDER BY communication_volume_current_parliament `+direction+`, name ASC
LIMIT ? OFFSET ?`,
		strings.TrimSpace(input.Search), strings.TrimSpace(input.Search), strings.TrimSpace(input.Search),
		strings.TrimSpace(input.Sector), strings.TrimSpace(input.Sector), limit, max(input.Offset, 0))
	if err != nil {
		return nil, fmt.Errorf("browse lobbyist organizations: %w", err)
	}
	defer rows.Close()

	organizations := []domain.LobbyistOrganization{}
	for rows.Next() {
		organization, err := scanOrganization(rows)
		if err != nil {
			return nil, err
		}
		organizations = append(organizations, organization)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate lobbyist organizations: %w", err)
	}
	return organizations, nil
}

func (r *Repository) LoadLobbyistOrganization(ctx context.Context, organizationID string) (domain.LobbyistOrganization, error) {
	row := r.db.QueryRowContext(ctx, `
SELECT organization_id, COALESCE(ocl_organization_id, ''), name, type, COALESCE(sector, ''),
	registered_lobbyists, active_subject_matters,
	communication_volume_current_parliament, communication_volume_prior_parliament,
	top_dpohs, registration_status, registrations, recent_communications,
	subject_matters, updated_at
FROM lobbyist_organizations
WHERE organization_id = ?`, organizationID)
	return scanOrganization(row)
}

func (r *Repository) LoadMPLobbyingSummary(ctx context.Context, input application.LoadMPLobbyingSummaryInput) (domain.MPLobbyingSummary, bool, error) {
	rows, err := r.db.QueryContext(ctx, `
SELECT member_id, parliament, quarter_start, "window", total_communication_count,
	unique_organizations_count, COALESCE(most_frequent_subject_matter, ''), top_organizations,
	current_parliament_communication_count, previous_parliament_communication_count,
	party_average_communications, national_average_communications, updated_at
FROM mp_lobbying_summaries
WHERE member_id = ? AND parliament = ? AND "window" = ?
ORDER BY quarter_start DESC
LIMIT 1`, input.MemberID, input.Parliament, string(input.Window))
	if err != nil {
		return domain.MPLobbyingSummary{}, false, fmt.Errorf("load MP lobbying summary: %w", err)
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return domain.MPLobbyingSummary{}, false, fmt.Errorf("load MP lobbying summary: %w", err)
		}
		return domain.MPLobbyingSummary{}, false, nil
	}
	summary, err := scanMPLobbyingSummary(rows)
	if err != nil {
		return domain.MPLobbyingSummary{}, false, err
	}
	return summary, true, nil
}

func (r *Repository) ListMPLobbyingTimeline(ctx context.Context, input application.ListMPLobbyingTimelineInput) (domain.LobbyingTimelinePage, error) {
	if input.Page < 1 {
		input.Page = 1
	}
	if input.PerPage <= 0 {
		input.PerPage = application.MPLobbyingTimelinePerPage
	}
	fromDate := ""
	if input.FromDate != nil {
		fromDate = input.FromDate.Format("2006-01-02")
	}
	page := domain.LobbyingTimelinePage{Rows: []domain.LobbyingTimelineEntry{}}
	if err := r.db.QueryRowContext(ctx, `
SELECT COUNT(*)
FROM mp_lobbying_timeline_entries
WHERE member_id = ? AND parliament = ?
  AND (? = '' OR DATE(communication_date) >= DATE(?))`, input.MemberID, input.Parliament, fromDate, fromDate).Scan(&page.Total); err != nil {
		return domain.LobbyingTimelinePage{}, fmt.Errorf("count MP lobbying timeline: %w", err)
	}
	if page.Total == 0 {
		return page, nil
	}
	rows, err := r.db.QueryContext(ctx, `
SELECT communication_id, COALESCE(DATE(communication_date), ''), organization_name,
	COALESCE(organization_sector, ''), subject_matter, communication_type,
	COALESCE(bill_number, ''), COALESCE(bill_title, ''), COALESCE(bill_url, ''),
	bill_mapping_confidence, COALESCE(source_url, ?)
FROM mp_lobbying_timeline_entries
WHERE member_id = ? AND parliament = ?
  AND (? = '' OR DATE(communication_date) >= DATE(?))
ORDER BY communication_date DESC, communication_id DESC, subject_matter ASC
LIMIT ? OFFSET ?`,
		domain.OCLSourceURL, input.MemberID, input.Parliament, fromDate, fromDate, input.PerPage, (input.Page-1)*input.PerPage)
	if err != nil {
		return domain.LobbyingTimelinePage{}, fmt.Errorf("query MP lobbying timeline: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var entry domain.LobbyingTimelineEntry
		var billNumber, billTitle, billURL string
		var billConfidence sql.NullFloat64
		if err := rows.Scan(
			&entry.CommunicationID,
			&entry.Date,
			&entry.OrganizationName,
			&entry.OrganizationSector,
			&entry.SubjectMatter,
			&entry.CommunicationType,
			&billNumber,
			&billTitle,
			&billURL,
			&billConfidence,
			&entry.SourceURL,
		); err != nil {
			return domain.LobbyingTimelinePage{}, fmt.Errorf("scan MP lobbying timeline row: %w", err)
		}
		entry.Citation = domain.OCLCitation
		if strings.TrimSpace(billURL) != "" {
			entry.Bill = &domain.BillCrossReference{
				BillNumber: strings.TrimSpace(billNumber),
				BillTitle:  strings.TrimSpace(billTitle),
				URL:        strings.TrimSpace(billURL),
				Confidence: billConfidence.Float64,
			}
		}
		page.Rows = append(page.Rows, entry)
	}
	if err := rows.Err(); err != nil {
		return domain.LobbyingTimelinePage{}, fmt.Errorf("iterate MP lobbying timeline rows: %w", err)
	}
	return page, nil
}

func (r *Repository) ListMPLobbyingSubjectDistribution(ctx context.Context, input application.ListMPLobbyingSubjectDistributionInput) ([]domain.LobbyingSubjectDistribution, error) {
	rows, err := r.db.QueryContext(ctx, `
WITH latest AS (
	SELECT quarter_start
	FROM mp_lobbying_summaries
	WHERE member_id = ? AND parliament = ? AND "window" = ?
	ORDER BY quarter_start DESC
	LIMIT 1
)
SELECT subject_matter, communication_count
FROM mp_lobbying_subject_breakdowns
JOIN latest USING (quarter_start)
WHERE member_id = ? AND parliament = ? AND "window" = ?
ORDER BY communication_count DESC, subject_matter ASC`,
		input.MemberID, input.Parliament, string(input.Window), input.MemberID, input.Parliament, string(input.Window))
	if err != nil {
		return nil, fmt.Errorf("query MP lobbying subject distribution: %w", err)
	}
	defer rows.Close()
	distribution := []domain.LobbyingSubjectDistribution{}
	for rows.Next() {
		var row domain.LobbyingSubjectDistribution
		if err := rows.Scan(&row.SubjectMatter, &row.CommunicationCount); err != nil {
			return nil, fmt.Errorf("scan MP lobbying subject distribution: %w", err)
		}
		distribution = append(distribution, row)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate MP lobbying subject distribution: %w", err)
	}
	return distribution, nil
}

func (r *Repository) RefreshMPLobbyingTimelineEntries(context.Context, application.RefreshMPLobbyingTimelineInput) error {
	return ErrReadOnlyArtifact
}

func (r *Repository) RefreshMPLobbyingSummaries(context.Context, application.RefreshMPLobbyingSummariesInput) error {
	return ErrReadOnlyArtifact
}

func (r *Repository) listStrings(ctx context.Context, query string, args ...any) ([]string, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	values := []string{}
	for rows.Next() {
		var value string
		if err := rows.Scan(&value); err != nil {
			return nil, err
		}
		if strings.TrimSpace(value) != "" {
			values = append(values, strings.TrimSpace(value))
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return values, nil
}

func (r *Repository) subjectMatterLabels(ctx context.Context, codes []string) []string {
	codes = normalizedStrings(codes)
	if len(codes) == 0 {
		return []string{}
	}
	placeholders, args := placeholdersFor(codes)
	rows, err := r.db.QueryContext(ctx, fmt.Sprintf(`
SELECT subject_code_objet, COALESCE(NULLIF(smt_en_desc, ''), subject_code_objet)
FROM ocl_subject_matter_types
WHERE subject_code_objet IN (%s)`, placeholders), args...)
	if err != nil {
		return codes
	}
	defer rows.Close()
	labelsByCode := map[string]string{}
	for rows.Next() {
		var code, label string
		if err := rows.Scan(&code, &label); err == nil {
			labelsByCode[usecase.NormalizeOCLCode(code)] = label
		}
	}
	labels := []string{}
	for _, code := range codes {
		label := strings.TrimSpace(labelsByCode[code])
		if label == "" {
			label = code
		}
		labels = append(labels, label)
	}
	return labels
}

const ministerProfilesSQL = `
SELECT
	member_id,
	minister_name,
	COALESCE(first_name, ''),
	COALESCE(last_name, ''),
	portfolio_name,
	COALESCE(DATE(start_date), ''),
	COALESCE(DATE(end_date), ''),
	COALESCE(DATE(tenure_start_date), ''),
	COALESCE(DATE(tenure_end_date), ''),
	COALESCE(parliament_number, 0)
FROM minister_portfolio_periods
`

func scanMinisterProfiles(rows *sql.Rows) ([]usecase.MinisterProfile, error) {
	byMemberID := map[string]*usecase.MinisterProfile{}
	order := []string{}
	for rows.Next() {
		var memberID, ministerName, firstName, lastName, portfolioName, startDate, endDate, tenureStartDate, tenureEndDate string
		var parliamentNumber int
		if err := rows.Scan(&memberID, &ministerName, &firstName, &lastName, &portfolioName, &startDate, &endDate, &tenureStartDate, &tenureEndDate, &parliamentNumber); err != nil {
			return nil, fmt.Errorf("scan minister profile: %w", err)
		}
		profile := byMemberID[memberID]
		if profile == nil {
			profile = &usecase.MinisterProfile{
				MemberID:        memberID,
				MinisterName:    ministerName,
				FirstName:       firstName,
				LastName:        lastName,
				TenureStartDate: tenureStartDate,
				TenureEndDate:   tenureEndDate,
			}
			byMemberID[memberID] = profile
			order = append(order, memberID)
		}
		profile.PortfolioPeriods = append(profile.PortfolioPeriods, usecase.MinisterPortfolioPeriod{
			PortfolioName: portfolioName,
			StartDate:     startDate,
			EndDate:       endDate,
		})
		if parliamentNumber > 0 && !containsInt(profile.ParliamentNumbers, parliamentNumber) {
			profile.ParliamentNumbers = append(profile.ParliamentNumbers, parliamentNumber)
		}
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate minister profiles: %w", err)
	}
	profiles := make([]usecase.MinisterProfile, 0, len(order))
	for _, memberID := range order {
		profile := *byMemberID[memberID]
		fillTenureFromPeriods(&profile)
		sort.Ints(profile.ParliamentNumbers)
		profiles = append(profiles, profile)
	}
	return profiles, nil
}

func scanOrganization(row interface{ Scan(dest ...any) error }) (domain.LobbyistOrganization, error) {
	var organization domain.LobbyistOrganization
	var organizationType, registrationStatus string
	var activeSubjectCount int
	var lobbyistsJSON, topDPOHsJSON, registrationsJSON, communicationsJSON, subjectMattersJSON []byte
	var updatedAt string
	if err := row.Scan(
		&organization.ID,
		&organization.OCLOrganizationID,
		&organization.Name,
		&organizationType,
		&organization.Sector,
		&lobbyistsJSON,
		&activeSubjectCount,
		&organization.CommunicationVolume.CurrentParliament,
		&organization.CommunicationVolume.PriorParliament,
		&topDPOHsJSON,
		&registrationStatus,
		&registrationsJSON,
		&communicationsJSON,
		&subjectMattersJSON,
		&updatedAt,
	); err != nil {
		return domain.LobbyistOrganization{}, fmt.Errorf("scan lobbyist organization: %w", err)
	}
	organization.Type = domain.OrganizationType(organizationType)
	organization.RegistrationStatus = domain.RegistrationStatus(registrationStatus)
	if organization.RegistrationStatus == "" {
		organization.RegistrationStatus = domain.RegistrationStatusExpired
	}
	_ = json.Unmarshal(lobbyistsJSON, &organization.RegisteredLobbyists)
	_ = json.Unmarshal(topDPOHsJSON, &organization.TopDPOHsContacted)
	organization.Registrations = decodeRegistrations(registrationsJSON)
	organization.RecentCommunications = decodeOrganizationCommunications(communicationsJSON)
	organization.SubjectMatters = decodeOrganizationSubjectMatters(subjectMattersJSON)
	organization.ActiveSubjectMatters = activeSubjectMatterNames(organization.SubjectMatters, activeSubjectCount)
	if parsed, err := time.Parse(time.RFC3339, updatedAt); err == nil {
		organization.UpdatedAt = parsed
	}
	return organization, nil
}

func scanMPLobbyingSummary(row interface{ Scan(dest ...any) error }) (domain.MPLobbyingSummary, error) {
	var summary domain.MPLobbyingSummary
	var window, quarterStart, updatedAt string
	var topOrganizationsJSON []byte
	if err := row.Scan(
		&summary.MemberID,
		&summary.Parliament,
		&quarterStart,
		&window,
		&summary.TotalCommunicationCount,
		&summary.UniqueOrganizationsCount,
		&summary.MostFrequentSubjectMatter,
		&topOrganizationsJSON,
		&summary.TrendVsPreviousParliament.CurrentParliament,
		&summary.TrendVsPreviousParliament.PreviousParliament,
		&summary.PartyAverageCommunications,
		&summary.NationalAverageCommunications,
		&updatedAt,
	); err != nil {
		return domain.MPLobbyingSummary{}, fmt.Errorf("scan MP lobbying summary: %w", err)
	}
	summary.Window = domain.LobbyingExposureWindow(window)
	summary.QuarterStart = parseSQLiteTime(quarterStart)
	summary.UpdatedAt = parseSQLiteTime(updatedAt)
	summary.TrendVsPreviousParliament.Delta = summary.TrendVsPreviousParliament.CurrentParliament - summary.TrendVsPreviousParliament.PreviousParliament
	if len(topOrganizationsJSON) == 0 {
		summary.TopOrganizations = []domain.TopLobbyingOrganization{}
	} else if err := json.Unmarshal(topOrganizationsJSON, &summary.TopOrganizations); err != nil {
		return domain.MPLobbyingSummary{}, fmt.Errorf("decode MP lobbying top organizations: %w", err)
	}
	summary.Citation = domain.OCLCitation
	return summary, nil
}

func decodeRegistrations(data []byte) []domain.LobbyistRegistration {
	var raw []struct {
		ID                   string                    `json:"id"`
		SourceID             string                    `json:"source_id"`
		Status               domain.RegistrationStatus `json:"status"`
		Kind                 domain.LobbyistKind       `json:"kind"`
		RegistrationType     string                    `json:"registration_type"`
		SubjectMatters       []string                  `json:"subject_matters"`
		TargetedInstitutions []string                  `json:"targeted_institutions"`
		SourceURL            string                    `json:"source_url"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return []domain.LobbyistRegistration{}
	}
	out := make([]domain.LobbyistRegistration, 0, len(raw))
	for _, row := range raw {
		id := firstNonEmpty(row.ID, row.SourceID)
		status := row.Status
		if status == "" {
			status = domain.RegistrationStatusExpired
		}
		kind := row.Kind
		if kind == "" {
			kind = kindFromRegistrationType(row.RegistrationType)
		}
		out = append(out, domain.LobbyistRegistration{
			ID:                   id,
			Status:               status,
			Kind:                 kind,
			SubjectMatters:       nonNilStrings(row.SubjectMatters),
			TargetedInstitutions: nonNilStrings(row.TargetedInstitutions),
			SourceURL:            firstNonEmpty(row.SourceURL, registrationSourceURL(id), usecase.SourceURL),
		})
	}
	return out
}

func decodeOrganizationCommunications(data []byte) []domain.LobbyistOrganizationCommunication {
	var raw []struct {
		ID             string   `json:"id"`
		ComlogID       string   `json:"comlog_id"`
		Date           string   `json:"date"`
		DPOHMemberID   string   `json:"dpoh_member_id"`
		DPOHName       string   `json:"dpoh_name"`
		Institution    string   `json:"institution"`
		SubjectMatters []string `json:"subject_matters"`
		SourceURL      string   `json:"source_url"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return []domain.LobbyistOrganizationCommunication{}
	}
	out := make([]domain.LobbyistOrganizationCommunication, 0, len(raw))
	for _, row := range raw {
		out = append(out, domain.LobbyistOrganizationCommunication{
			ID:             firstNonEmpty(row.ID, row.ComlogID),
			Date:           row.Date,
			DPOHMemberID:   row.DPOHMemberID,
			DPOHName:       row.DPOHName,
			Institution:    row.Institution,
			SubjectMatters: nonNilStrings(row.SubjectMatters),
			SourceURL:      firstNonEmpty(row.SourceURL, usecase.SourceURL),
		})
	}
	return out
}

func decodeOrganizationSubjectMatters(data []byte) []domain.LobbyistOrganizationSubjectMatter {
	var raw []struct {
		SubjectMatter      string `json:"subject_matter"`
		Name               string `json:"name"`
		CommunicationCount int    `json:"communication_count"`
		TopicSlug          string `json:"topic_slug"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return []domain.LobbyistOrganizationSubjectMatter{}
	}
	out := make([]domain.LobbyistOrganizationSubjectMatter, 0, len(raw))
	for _, row := range raw {
		out = append(out, domain.LobbyistOrganizationSubjectMatter{
			SubjectMatter:      firstNonEmpty(row.SubjectMatter, row.Name),
			CommunicationCount: row.CommunicationCount,
			TopicSlug:          row.TopicSlug,
		})
	}
	return out
}

func activeSubjectMatterNames(subjects []domain.LobbyistOrganizationSubjectMatter, count int) []string {
	names := []string{}
	for _, subject := range subjects {
		if strings.TrimSpace(subject.SubjectMatter) != "" {
			names = append(names, strings.TrimSpace(subject.SubjectMatter))
		}
	}
	if len(names) > 0 {
		return names
	}
	if count <= 0 {
		return []string{}
	}
	return []string{}
}

func kindFromRegistrationType(value string) domain.LobbyistKind {
	value = strings.ToLower(value)
	if strings.Contains(value, "consultant") || strings.TrimSpace(value) == "1" {
		return domain.LobbyistKindConsultant
	}
	return domain.LobbyistKindInHouse
}

func registrationSourceURL(id string) string {
	id = strings.TrimSpace(id)
	if id == "" {
		return ""
	}
	return registrationReportsURL + id
}

func decodeStringArray(data []byte) []string {
	var values []string
	if err := json.Unmarshal(data, &values); err != nil {
		return []string{}
	}
	return normalizedStrings(values)
}

func normalizedCodes(mappings []usecase.OCLTopicMapping) []string {
	values := make([]string, 0, len(mappings))
	for _, mapping := range mappings {
		if code := usecase.NormalizeOCLCode(mapping.OCLCode); code != "" {
			values = append(values, code)
		}
	}
	return normalizedStrings(values)
}

func normalizedStrings(values []string) []string {
	seen := map[string]struct{}{}
	out := []string{}
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}

func placeholdersFor(values []string) (string, []any) {
	placeholders := make([]string, len(values))
	args := make([]any, len(values))
	for i, value := range values {
		placeholders[i] = "?"
		args[i] = value
	}
	return strings.Join(placeholders, ","), args
}

func fillTenureFromPeriods(profile *usecase.MinisterProfile) {
	var latestEnd string
	hasOpenEnd := false
	for _, period := range profile.PortfolioPeriods {
		if profile.TenureStartDate == "" || dateStringBefore(period.StartDate, profile.TenureStartDate) {
			profile.TenureStartDate = period.StartDate
		}
		if period.EndDate == "" {
			hasOpenEnd = true
			continue
		}
		if latestEnd == "" || dateStringBefore(latestEnd, period.EndDate) {
			latestEnd = period.EndDate
		}
	}
	if profile.TenureEndDate == "" && !hasOpenEnd {
		profile.TenureEndDate = latestEnd
	}
}

func dateStringBefore(left, right string) bool {
	if strings.TrimSpace(left) == "" {
		return false
	}
	if strings.TrimSpace(right) == "" {
		return true
	}
	return left < right
}

func containsInt(values []int, value int) bool {
	for _, existing := range values {
		if existing == value {
			return true
		}
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func nonNilStrings(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func parseSQLiteTime(value string) time.Time {
	for _, layout := range []string{time.RFC3339, "2006-01-02 15:04:05", "2006-01-02"} {
		if parsed, err := time.Parse(layout, strings.TrimSpace(value)); err == nil {
			return parsed
		}
	}
	return time.Time{}
}
