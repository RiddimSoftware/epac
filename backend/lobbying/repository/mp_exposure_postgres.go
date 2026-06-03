package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	"github.com/jackc/pgx/v5"
)

type PostgresMPLobbyingRepository struct {
	db Queryer
}

func NewPostgresMPLobbyingRepository(db Queryer) *PostgresMPLobbyingRepository {
	return &PostgresMPLobbyingRepository{db: db}
}

func (r *PostgresMPLobbyingRepository) LoadMPLobbyingSummary(ctx context.Context, input application.LoadMPLobbyingSummaryInput) (domain.MPLobbyingSummary, bool, error) {
	row := r.db.QueryRow(ctx, `
		SELECT
			member_id,
			parliament,
			quarter_start,
			"window",
			total_communication_count,
			unique_organizations_count,
			COALESCE(most_frequent_subject_matter, ''),
			top_organizations,
			current_parliament_communication_count,
			previous_parliament_communication_count,
			party_average_communications::float8,
			national_average_communications::float8,
			updated_at
		FROM mp_lobbying_summaries
		WHERE member_id = $1
			AND parliament = $2
			AND "window" = $3
		ORDER BY quarter_start DESC
		LIMIT 1
	`, input.MemberID, input.Parliament, string(input.Window))

	summary, err := scanMPLobbyingSummary(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.MPLobbyingSummary{}, false, nil
	}
	if err != nil {
		return domain.MPLobbyingSummary{}, false, err
	}
	return summary, true, nil
}

func (r *PostgresMPLobbyingRepository) ListMPLobbyingTimeline(ctx context.Context, input application.ListMPLobbyingTimelineInput) (domain.LobbyingTimelinePage, error) {
	if input.Page < 1 {
		input.Page = 1
	}
	if input.PerPage <= 0 {
		input.PerPage = application.MPLobbyingTimelinePerPage
	}

	page := domain.LobbyingTimelinePage{Rows: []domain.LobbyingTimelineEntry{}}
	if err := r.db.QueryRow(ctx, `
		SELECT COUNT(*)::int
		FROM mp_lobbying_timeline_entries
		WHERE member_id = $1
			AND parliament = $2
			AND ($3::date IS NULL OR communication_date >= $3::date)
	`, input.MemberID, input.Parliament, dateArg(input.FromDate)).Scan(&page.Total); err != nil {
		return domain.LobbyingTimelinePage{}, fmt.Errorf("count MP lobbying timeline: %w", err)
	}
	if page.Total == 0 {
		return page, nil
	}

	rows, err := r.db.Query(ctx, `
		SELECT
			communication_id,
			to_char(communication_date, 'YYYY-MM-DD') AS communication_date,
			organization_name,
			COALESCE(organization_sector, ''),
			subject_matter,
			communication_type,
			COALESCE(bill_number, ''),
			COALESCE(bill_title, ''),
			COALESCE(bill_url, ''),
			bill_mapping_confidence,
			COALESCE(source_url, $6)
		FROM mp_lobbying_timeline_entries
		WHERE member_id = $1
			AND parliament = $2
			AND ($3::date IS NULL OR communication_date >= $3::date)
		ORDER BY communication_date DESC, communication_id DESC, subject_matter ASC
		LIMIT $4 OFFSET $5
	`, input.MemberID, input.Parliament, dateArg(input.FromDate), input.PerPage, (input.Page-1)*input.PerPage, domain.OCLSourceURL)
	if err != nil {
		return domain.LobbyingTimelinePage{}, fmt.Errorf("query MP lobbying timeline: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var entry domain.LobbyingTimelineEntry
		var billNumber sql.NullString
		var billTitle sql.NullString
		var billURL sql.NullString
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
		if billURL.Valid && strings.TrimSpace(billURL.String) != "" {
			entry.Bill = &domain.BillCrossReference{
				BillNumber: strings.TrimSpace(billNumber.String),
				BillTitle:  strings.TrimSpace(billTitle.String),
				URL:        strings.TrimSpace(billURL.String),
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

func (r *PostgresMPLobbyingRepository) ListMPLobbyingSubjectDistribution(ctx context.Context, input application.ListMPLobbyingSubjectDistributionInput) ([]domain.LobbyingSubjectDistribution, error) {
	rows, err := r.db.Query(ctx, `
		WITH latest AS (
			SELECT quarter_start
			FROM mp_lobbying_summaries
			WHERE member_id = $1
				AND parliament = $2
				AND "window" = $3
			ORDER BY quarter_start DESC
			LIMIT 1
		)
		SELECT subject_matter, communication_count
		FROM mp_lobbying_subject_breakdowns
		JOIN latest USING (quarter_start)
		WHERE member_id = $1
			AND parliament = $2
			AND "window" = $3
		ORDER BY communication_count DESC, subject_matter ASC
	`, input.MemberID, input.Parliament, string(input.Window))
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

func (r *PostgresMPLobbyingRepository) RefreshMPLobbyingTimelineEntries(ctx context.Context, input application.RefreshMPLobbyingTimelineInput) error {
	_, err := r.db.Exec(ctx, refreshMPLobbyingTimelineSQL,
		input.Parliament,
		dateOnlyForSQL(input.FromDate),
		dateOnlyForSQL(input.ToDate),
		input.UpdatedAt,
		domain.OCLSourceURL,
	)
	if err != nil {
		return fmt.Errorf("refresh MP lobbying timeline entries: %w", err)
	}
	return nil
}

func (r *PostgresMPLobbyingRepository) RefreshMPLobbyingSummaries(ctx context.Context, input application.RefreshMPLobbyingSummariesInput) error {
	windows := []domain.LobbyingExposureWindow{
		domain.LobbyingExposureWindow30D,
		domain.LobbyingExposureWindow3M,
		domain.LobbyingExposureWindow12M,
		domain.LobbyingExposureWindowAll,
	}
	for _, window := range windows {
		if err := r.refreshSummaryWindow(ctx, input, window); err != nil {
			return err
		}
		if err := r.refreshSubjectWindow(ctx, input, window); err != nil {
			return err
		}
	}
	return nil
}

func (r *PostgresMPLobbyingRepository) refreshSummaryWindow(ctx context.Context, input application.RefreshMPLobbyingSummariesInput, window domain.LobbyingExposureWindow) error {
	fromDate := application.WindowStart(window, input.QuarterEnd)
	if _, err := r.db.Exec(ctx, `
		DELETE FROM mp_lobbying_summaries
		WHERE parliament = $1 AND quarter_start = $2 AND "window" = $3
	`, input.Parliament, dateOnlyForSQL(input.QuarterStart), string(window)); err != nil {
		return fmt.Errorf("delete MP lobbying summaries: %w", err)
	}

	_, err := r.db.Exec(ctx, refreshMPLobbyingSummarySQL,
		input.Parliament,
		dateOnlyForSQL(input.QuarterStart),
		dateOnlyForSQL(input.QuarterEnd),
		string(window),
		dateArg(fromDate),
		input.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("refresh MP lobbying summaries for %s: %w", window, err)
	}
	return nil
}

func (r *PostgresMPLobbyingRepository) refreshSubjectWindow(ctx context.Context, input application.RefreshMPLobbyingSummariesInput, window domain.LobbyingExposureWindow) error {
	fromDate := application.WindowStart(window, input.QuarterEnd)
	if _, err := r.db.Exec(ctx, `
		DELETE FROM mp_lobbying_subject_breakdowns
		WHERE parliament = $1 AND quarter_start = $2 AND "window" = $3
	`, input.Parliament, dateOnlyForSQL(input.QuarterStart), string(window)); err != nil {
		return fmt.Errorf("delete MP lobbying subject breakdowns: %w", err)
	}

	_, err := r.db.Exec(ctx, `
		INSERT INTO mp_lobbying_subject_breakdowns (
			member_id, parliament, quarter_start, "window", subject_matter, communication_count, updated_at
		)
		SELECT
			member_id,
			parliament,
			$2::date AS quarter_start,
			$4::text AS "window",
			subject_matter,
			COUNT(DISTINCT communication_id)::int AS communication_count,
			$6::timestamptz AS updated_at
		FROM mp_lobbying_timeline_entries
		WHERE parliament = $1
			AND communication_date <= $3::date
			AND ($5::date IS NULL OR communication_date >= $5::date)
		GROUP BY member_id, parliament, subject_matter
		ON CONFLICT (member_id, parliament, quarter_start, "window", subject_matter)
		DO UPDATE SET
			communication_count = EXCLUDED.communication_count,
			updated_at = EXCLUDED.updated_at
	`, input.Parliament, dateOnlyForSQL(input.QuarterStart), dateOnlyForSQL(input.QuarterEnd), string(window), dateArg(fromDate), input.UpdatedAt)
	if err != nil {
		return fmt.Errorf("refresh MP lobbying subject breakdowns for %s: %w", window, err)
	}
	return nil
}

func scanMPLobbyingSummary(row interface {
	Scan(dest ...any) error
}) (domain.MPLobbyingSummary, error) {
	var summary domain.MPLobbyingSummary
	var window string
	var topOrganizationsJSON []byte
	if err := row.Scan(
		&summary.MemberID,
		&summary.Parliament,
		&summary.QuarterStart,
		&window,
		&summary.TotalCommunicationCount,
		&summary.UniqueOrganizationsCount,
		&summary.MostFrequentSubjectMatter,
		&topOrganizationsJSON,
		&summary.TrendVsPreviousParliament.CurrentParliament,
		&summary.TrendVsPreviousParliament.PreviousParliament,
		&summary.PartyAverageCommunications,
		&summary.NationalAverageCommunications,
		&summary.UpdatedAt,
	); err != nil {
		return domain.MPLobbyingSummary{}, fmt.Errorf("scan MP lobbying summary: %w", err)
	}
	summary.Window = domain.LobbyingExposureWindow(window)
	summary.TrendVsPreviousParliament.Delta = summary.TrendVsPreviousParliament.CurrentParliament - summary.TrendVsPreviousParliament.PreviousParliament
	if len(topOrganizationsJSON) == 0 {
		summary.TopOrganizations = []domain.TopLobbyingOrganization{}
	} else if err := json.Unmarshal(topOrganizationsJSON, &summary.TopOrganizations); err != nil {
		return domain.MPLobbyingSummary{}, fmt.Errorf("decode MP lobbying top organizations: %w", err)
	}
	summary.Citation = domain.OCLCitation
	return summary, nil
}

func dateArg(value *time.Time) any {
	if value == nil {
		return nil
	}
	date := dateOnlyForSQL(*value)
	return date
}

func dateOnlyForSQL(value time.Time) time.Time {
	y, m, d := value.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

const refreshMPLobbyingTimelineSQL = `
WITH communication_source AS (
	SELECT
		cp.comlog_id::text AS communication_id,
		COALESCE(NULLIF(cp.client_org_corp_num::text, ''), '') AS ocl_organization_id,
		COALESCE(NULLIF(cp.en_client_org_corp_nm_an, 'null'), NULLIF(cp.fr_client_org_corp_nm, 'null'), '') AS organization_name,
		NULLIF(NULLIF(cp.comm_date::text, 'null'), '')::date AS communication_date
	FROM ocl_communication_primary cp
	WHERE NULLIF(NULLIF(cp.comm_date::text, 'null'), '') IS NOT NULL
),
matched_communications AS (
	SELECT DISTINCT ON (
		m.person_id,
		cs.communication_id,
		COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet, 'Unspecified')
	)
		m.person_id::text AS member_id,
		cs.communication_id,
		cs.communication_date,
		COALESCE(NULLIF(cs.organization_name, ''), 'Unknown organization') AS organization_name,
		COALESCE(NULLIF(lo.sector, ''), NULLIF(smt.smt_en_desc, ''), '') AS organization_sector,
		COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet, 'Unspecified') AS subject_matter
	FROM communication_source cs
	JOIN ocl_communication_dpohs dpoh
		ON dpoh.comlog_id::text = cs.communication_id
	JOIN members m
		ON lower(btrim(concat(m.first_name, ' ', m.last_name))) =
		   lower(btrim(concat(dpoh.dpoh_first_nm_prenom_tcpd, ' ', dpoh.dpoh_last_nm_tcpd)))
		AND (m.from_date IS NULL OR m.from_date::date <= cs.communication_date)
		AND (m.to_date IS NULL OR m.to_date::date >= cs.communication_date)
	LEFT JOIN ocl_communication_subject_matters csm
		ON csm.comlog_id::text = cs.communication_id
	LEFT JOIN ocl_subject_matter_types smt
		ON smt.subject_code_objet = csm.subject_code_objet
	LEFT JOIN lobbyist_organizations lo
		ON lo.ocl_organization_id = cs.ocl_organization_id
	WHERE cs.communication_date >= $2::date
		AND cs.communication_date <= $3::date
	ORDER BY
		m.person_id,
		cs.communication_id,
		COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet, 'Unspecified'),
		cs.communication_date DESC
)
INSERT INTO mp_lobbying_timeline_entries (
	member_id,
	parliament,
	communication_id,
	communication_date,
	organization_name,
	organization_sector,
	subject_matter,
	communication_type,
	source_url,
	updated_at
)
SELECT
	member_id,
	$1::int AS parliament,
	communication_id,
	communication_date,
	organization_name,
	organization_sector,
	subject_matter,
	'meeting' AS communication_type,
	$5::text AS source_url,
	$4::timestamptz AS updated_at
FROM matched_communications
ON CONFLICT (member_id, parliament, communication_id, subject_matter)
DO UPDATE SET
	communication_date = EXCLUDED.communication_date,
	organization_name = EXCLUDED.organization_name,
	organization_sector = EXCLUDED.organization_sector,
	communication_type = EXCLUDED.communication_type,
	source_url = EXCLUDED.source_url,
	updated_at = EXCLUDED.updated_at`

const refreshMPLobbyingSummarySQL = `
WITH active_members AS (
	SELECT
		person_id::text AS member_id,
		COALESCE(NULLIF(caucus, ''), 'Unknown') AS party
	FROM members
	WHERE (from_date IS NULL OR from_date::date <= $3::date)
		AND (to_date IS NULL OR to_date::date >= $2::date)
),
timeline_members AS (
	SELECT DISTINCT
		t.member_id,
		COALESCE(NULLIF(m.caucus, ''), 'Unknown') AS party
	FROM mp_lobbying_timeline_entries t
	LEFT JOIN members m ON m.person_id::text = t.member_id
	WHERE t.parliament = $1
),
cohort AS (
	SELECT member_id, party FROM active_members
	UNION
	SELECT tm.member_id, tm.party
	FROM timeline_members tm
	WHERE NOT EXISTS (
		SELECT 1 FROM active_members am WHERE am.member_id = tm.member_id
	)
),
current_counts AS (
	SELECT
		cohort.member_id,
		cohort.party,
		COUNT(DISTINCT t.communication_id)::int AS total_count,
		COUNT(DISTINCT NULLIF(t.organization_name, ''))::int AS unique_org_count
	FROM cohort
	LEFT JOIN mp_lobbying_timeline_entries t
		ON t.member_id = cohort.member_id
		AND t.parliament = $1
		AND t.communication_date <= $3::date
		AND ($5::date IS NULL OR t.communication_date >= $5::date)
	GROUP BY cohort.member_id, cohort.party
),
previous_counts AS (
	SELECT
		member_id,
		COUNT(DISTINCT communication_id)::int AS previous_count
	FROM mp_lobbying_timeline_entries
	WHERE parliament = ($1 - 1)
	GROUP BY member_id
),
subject_counts AS (
	SELECT
		member_id,
		subject_matter,
		COUNT(DISTINCT communication_id)::int AS subject_count,
		ROW_NUMBER() OVER (
			PARTITION BY member_id
			ORDER BY COUNT(DISTINCT communication_id) DESC, subject_matter ASC
		) AS subject_rank
	FROM mp_lobbying_timeline_entries
	WHERE parliament = $1
		AND communication_date <= $3::date
		AND ($5::date IS NULL OR communication_date >= $5::date)
	GROUP BY member_id, subject_matter
),
organization_counts AS (
	SELECT
		member_id,
		organization_name,
		COALESCE(NULLIF(organization_sector, ''), '') AS organization_sector,
		COUNT(DISTINCT communication_id)::int AS communication_count,
		ROW_NUMBER() OVER (
			PARTITION BY member_id
			ORDER BY COUNT(DISTINCT communication_id) DESC, organization_name ASC
		) AS organization_rank
	FROM mp_lobbying_timeline_entries
	WHERE parliament = $1
		AND communication_date <= $3::date
		AND ($5::date IS NULL OR communication_date >= $5::date)
		AND NULLIF(organization_name, '') IS NOT NULL
	GROUP BY member_id, organization_name, COALESCE(NULLIF(organization_sector, ''), '')
),
top_organizations AS (
	SELECT
		member_id,
		JSONB_AGG(
			JSONB_BUILD_OBJECT(
				'name', organization_name,
				'sector', organization_sector,
				'communication_count', communication_count
			)
			ORDER BY communication_count DESC, organization_name ASC
		) AS top_organizations
	FROM organization_counts
	WHERE organization_rank <= 3
	GROUP BY member_id
),
party_averages AS (
	SELECT party, AVG(total_count)::float8 AS party_average
	FROM current_counts
	GROUP BY party
),
national_average AS (
	SELECT COALESCE(AVG(total_count)::float8, 0)::float8 AS value
	FROM current_counts
)
INSERT INTO mp_lobbying_summaries (
	member_id,
	parliament,
	quarter_start,
	"window",
	total_communication_count,
	unique_organizations_count,
	most_frequent_subject_matter,
	top_organizations,
	current_parliament_communication_count,
	previous_parliament_communication_count,
	party_average_communications,
	national_average_communications,
	updated_at
)
SELECT
	cc.member_id,
	$1::int AS parliament,
	$2::date AS quarter_start,
	$4::text AS "window",
	cc.total_count,
	cc.unique_org_count,
	sc.subject_matter,
	COALESCE(tops.top_organizations, '[]'::jsonb),
	cc.total_count,
	COALESCE(pc.previous_count, 0),
	COALESCE(pa.party_average, 0),
	(SELECT value FROM national_average),
	$6::timestamptz AS updated_at
FROM current_counts cc
LEFT JOIN subject_counts sc
	ON sc.member_id = cc.member_id AND sc.subject_rank = 1
LEFT JOIN top_organizations tops ON tops.member_id = cc.member_id
LEFT JOIN previous_counts pc ON pc.member_id = cc.member_id
LEFT JOIN party_averages pa ON pa.party = cc.party
ON CONFLICT (member_id, parliament, quarter_start, "window")
DO UPDATE SET
	total_communication_count = EXCLUDED.total_communication_count,
	unique_organizations_count = EXCLUDED.unique_organizations_count,
	most_frequent_subject_matter = EXCLUDED.most_frequent_subject_matter,
	top_organizations = EXCLUDED.top_organizations,
	current_parliament_communication_count = EXCLUDED.current_parliament_communication_count,
	previous_parliament_communication_count = EXCLUDED.previous_parliament_communication_count,
	party_average_communications = EXCLUDED.party_average_communications,
	national_average_communications = EXCLUDED.national_average_communications,
	updated_at = EXCLUDED.updated_at`
