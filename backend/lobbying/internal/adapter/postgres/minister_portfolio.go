package postgres

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"epac/lobbying/internal/usecase"

	"github.com/jackc/pgx/v5"
)

func (r *Repository) LoadMinisterProfile(ctx context.Context, memberID string) (usecase.MinisterProfile, error) {
	rows, err := r.conn.Query(ctx, ministerProfilesSQL+`
		WHERE member_id = $1
		ORDER BY start_date NULLS FIRST, portfolio_name
	`, strings.TrimSpace(memberID))
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
	rows, err := r.conn.Query(ctx, ministerProfilesSQL+`
		WHERE ($1 = 0 OR parliament_number = $1)
		  AND ($2 = '' OR portfolio_name ILIKE '%' || $2 || '%')
		ORDER BY minister_name, start_date NULLS FIRST, portfolio_name
	`, filter.Parliament, strings.TrimSpace(filter.Portfolio))
	if err != nil {
		return nil, fmt.Errorf("query cabinet ministers: %w", err)
	}
	defer rows.Close()
	return scanMinisterProfiles(rows)
}

func (r *Repository) ListMandatePolicyAreas(ctx context.Context, memberID string) ([]usecase.MandatePolicyArea, error) {
	rows, err := r.conn.Query(ctx, `
		SELECT epac_topic_slug, confidence::double precision
		FROM minister_mandate_topic_mappings
		WHERE member_id = $1
		ORDER BY confidence DESC, epac_topic_slug
	`, strings.TrimSpace(memberID))
	if err != nil {
		return nil, fmt.Errorf("query minister mandate policy areas: %w", err)
	}
	defer rows.Close()

	var areas []usecase.MandatePolicyArea
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
	lastName := strings.TrimSpace(filter.LastName)
	if lastName == "" {
		return []usecase.MinisterLobbyingCommunication{}, nil
	}

	var startDate any
	if strings.TrimSpace(filter.StartDate) != "" {
		startDate = strings.TrimSpace(filter.StartDate)
	}
	var endDate any
	if strings.TrimSpace(filter.EndDate) != "" {
		endDate = strings.TrimSpace(filter.EndDate)
	}

	rows, err := r.conn.Query(ctx, ministerCommunicationsSQL,
		lastName,
		strings.TrimSpace(filter.FirstName),
		startDate,
		endDate,
	)
	if err != nil {
		return nil, fmt.Errorf("query minister lobbying communications: %w", err)
	}
	defer rows.Close()

	var communications []usecase.MinisterLobbyingCommunication
	for rows.Next() {
		var communication usecase.MinisterLobbyingCommunication
		var subjects []string
		var codes []string
		if err := rows.Scan(
			&communication.ID,
			&communication.OrganizationName,
			&communication.RegistrantName,
			&communication.RegistrantType,
			&communication.CommunicationDate,
			&subjects,
			&codes,
		); err != nil {
			return nil, fmt.Errorf("scan minister lobbying communication: %w", err)
		}
		communication.SubjectMatters = subjects
		communication.OCLCodes = codes
		communication.Citation = usecase.Citation
		communication.SourceURL = usecase.SourceURL
		communications = append(communications, communication)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate minister lobbying communications: %w", err)
	}
	if communications == nil {
		communications = []usecase.MinisterLobbyingCommunication{}
	}
	return communications, nil
}

func (r *Repository) RecordPortfolioBoundaryGap(ctx context.Context, gap usecase.PortfolioBoundaryGap) error {
	payload, err := json.Marshal(map[string]string{
		"event":         "portfolio_boundary_gap",
		"member_id":     gap.MemberID,
		"minister_name": gap.MinisterName,
		"reason":        gap.Reason,
	})
	if err != nil {
		return fmt.Errorf("marshal portfolio boundary gap: %w", err)
	}
	_, err = r.conn.Exec(ctx, `
		INSERT INTO pipeline_health (name, last_run_at, last_error, expected_interval_hours)
		VALUES ('minister-lobbying-portfolio-boundaries', NOW(), $1, 24)
		ON CONFLICT (name) DO UPDATE SET
			last_run_at = EXCLUDED.last_run_at,
			last_error = EXCLUDED.last_error
	`, string(payload))
	if err != nil {
		return fmt.Errorf("record portfolio boundary gap: %w", err)
	}
	return nil
}

const ministerProfilesSQL = `
	SELECT
		member_id,
		minister_name,
		COALESCE(first_name, ''),
		COALESCE(last_name, ''),
		portfolio_name,
		COALESCE(to_char(start_date, 'YYYY-MM-DD'), ''),
		COALESCE(to_char(end_date, 'YYYY-MM-DD'), ''),
		COALESCE(to_char(tenure_start_date, 'YYYY-MM-DD'), ''),
		COALESCE(to_char(tenure_end_date, 'YYYY-MM-DD'), ''),
		COALESCE(parliament_number, 0)
	FROM minister_portfolio_periods
`

const ministerCommunicationsSQL = `
	WITH matched_dpohs AS (
		SELECT DISTINCT comlog_id::TEXT AS source_id
		FROM ocl_communication_dpohs
		WHERE LOWER(BTRIM(dpoh_last_nm_tcpd)) = LOWER(BTRIM($1))
		  AND ($2 = '' OR LOWER(BTRIM(dpoh_first_nm_prenom_tcpd)) LIKE '%' || LOWER(BTRIM($2)) || '%')
		  AND LOWER(COALESCE(NULLIF(institution, 'null'), '')) LIKE '%house of commons%'
	),
	communication_subjects AS (
		SELECT
			csm.comlog_id::TEXT AS source_id,
			ARRAY_AGG(
				DISTINCT COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet::TEXT)
				ORDER BY COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet::TEXT)
			) AS subject_matters,
			ARRAY_AGG(DISTINCT csm.subject_code_objet::TEXT ORDER BY csm.subject_code_objet::TEXT) AS ocl_codes
		FROM ocl_communication_subject_matters csm
		LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = csm.subject_code_objet
		GROUP BY csm.comlog_id::TEXT
	)
	SELECT
		cp.comlog_id::TEXT,
		COALESCE(NULLIF(cp.en_client_org_corp_nm_an, 'null'), NULLIF(cp.fr_client_org_corp_nm, 'null'), ''),
		BTRIM(CONCAT(cp.rgstrnt_1st_nm_prenom_dclrnt, ' ', cp.rgstrnt_last_nm_dclrnt)),
		CASE cp.reg_type_enr::TEXT
			WHEN '1' THEN 'Consultant'
			WHEN '2' THEN 'In-house (corporation)'
			WHEN '3' THEN 'In-house (organization)'
			ELSE COALESCE(cp.reg_type_enr::TEXT, '')
		END,
		COALESCE(to_char(NULLIF(cp.comm_date::TEXT, 'null')::date, 'YYYY-MM-DD'), ''),
		COALESCE(subjects.subject_matters, ARRAY[]::TEXT[]),
		COALESCE(subjects.ocl_codes, ARRAY[]::TEXT[])
	FROM matched_dpohs md
	JOIN ocl_communication_primary cp ON cp.comlog_id::TEXT = md.source_id
	LEFT JOIN communication_subjects subjects ON subjects.source_id = cp.comlog_id::TEXT
	WHERE ($3::date IS NULL OR NULLIF(cp.comm_date::TEXT, 'null')::date >= $3::date)
	  AND ($4::date IS NULL OR NULLIF(cp.comm_date::TEXT, 'null')::date <= $4::date)
	ORDER BY NULLIF(cp.comm_date::TEXT, 'null')::date DESC NULLS LAST, cp.comlog_id::TEXT
`

func scanMinisterProfiles(rows pgx.Rows) ([]usecase.MinisterProfile, error) {
	byMemberID := make(map[string]*usecase.MinisterProfile)
	order := []string{}
	for rows.Next() {
		var (
			memberID         string
			ministerName     string
			firstName        string
			lastName         string
			portfolioName    string
			startDate        string
			endDate          string
			tenureStartDate  string
			tenureEndDate    string
			parliamentNumber int
		)
		if err := rows.Scan(
			&memberID,
			&ministerName,
			&firstName,
			&lastName,
			&portfolioName,
			&startDate,
			&endDate,
			&tenureStartDate,
			&tenureEndDate,
			&parliamentNumber,
		); err != nil {
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
