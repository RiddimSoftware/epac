package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

type Queryer interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type PostgresLobbyistOrganizationRepository struct {
	db Queryer
}

func NewPostgresLobbyistOrganizationRepository(db Queryer) *PostgresLobbyistOrganizationRepository {
	return &PostgresLobbyistOrganizationRepository{db: db}
}

func (r *PostgresLobbyistOrganizationRepository) FindOrganizationIDsByNormalizedName(ctx context.Context, normalizedName string) ([]string, error) {
	rows, err := r.db.Query(ctx, `
		SELECT organization_id
		FROM organization_aliases
		WHERE normalized_name = $1
		ORDER BY organization_id
	`, normalizedName)
	if err != nil {
		return nil, fmt.Errorf("query organization aliases: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan organization alias: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate organization aliases: %w", err)
	}
	return ids, nil
}

func (r *PostgresLobbyistOrganizationRepository) LogPendingOrganizationAlias(ctx context.Context, pending application.PendingOrganizationAlias) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO pending_organization_aliases (
			normalized_name, observed_name, source_table, source_id, candidate_organization_ids
		)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (normalized_name, observed_name, source_table, source_id_key) DO UPDATE SET
			candidate_organization_ids = EXCLUDED.candidate_organization_ids,
			last_seen_at = NOW(),
			occurrences = pending_organization_aliases.occurrences + 1
	`, pending.NormalizedName, pending.ObservedName, pending.SourceTable, pending.SourceID, pending.CandidateOrganizationIDs)
	if err != nil {
		return fmt.Errorf("log pending organization alias: %w", err)
	}
	return nil
}

func (r *PostgresLobbyistOrganizationRepository) SaveLobbyistOrganizations(ctx context.Context, organizations []domain.LobbyistOrganization) error {
	for _, organization := range organizations {
		lobbyists, err := json.Marshal(organization.RegisteredLobbyists)
		if err != nil {
			return fmt.Errorf("marshal registered lobbyists for %s: %w", organization.ID, err)
		}
		dpohs, err := json.Marshal(organization.TopDPOHsContacted)
		if err != nil {
			return fmt.Errorf("marshal top dpohs for %s: %w", organization.ID, err)
		}
		_, err = r.db.Exec(ctx, `
			INSERT INTO lobbyist_organizations (
				organization_id, ocl_organization_id, name, type, sector,
				registered_lobbyists, active_subject_matters,
				communication_volume_current_parliament, communication_volume_prior_parliament,
				top_dpohs, updated_at
			)
			VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8, $9, $10::jsonb, $11)
			ON CONFLICT (organization_id) DO UPDATE SET
				ocl_organization_id = EXCLUDED.ocl_organization_id,
				name = EXCLUDED.name,
				type = EXCLUDED.type,
				sector = EXCLUDED.sector,
				registered_lobbyists = EXCLUDED.registered_lobbyists,
				active_subject_matters = EXCLUDED.active_subject_matters,
				communication_volume_current_parliament = EXCLUDED.communication_volume_current_parliament,
				communication_volume_prior_parliament = EXCLUDED.communication_volume_prior_parliament,
				top_dpohs = EXCLUDED.top_dpohs,
				updated_at = EXCLUDED.updated_at
		`, organization.ID, nullString(organization.OCLOrganizationID), organization.Name, string(organization.Type),
			nullString(organization.Sector), string(lobbyists), organization.ActiveSubjectMatters,
			organization.CommunicationVolume.CurrentParliament, organization.CommunicationVolume.PriorParliament,
			string(dpohs), organization.UpdatedAt)
		if err != nil {
			return fmt.Errorf("save lobbyist organization %s: %w", organization.ID, err)
		}
	}
	return nil
}

func (r *PostgresLobbyistOrganizationRepository) LoadLobbyistOrganization(ctx context.Context, organizationID string) (domain.LobbyistOrganization, error) {
	row := r.db.QueryRow(ctx, `
		SELECT organization_id, COALESCE(ocl_organization_id, ''), name, type, COALESCE(sector, ''),
			registered_lobbyists, active_subject_matters,
			communication_volume_current_parliament, communication_volume_prior_parliament,
			top_dpohs, updated_at
		FROM lobbyist_organizations
		WHERE organization_id = $1
	`, organizationID)
	return scanOrganization(row)
}

func (r *PostgresLobbyistOrganizationRepository) BrowseLobbyistOrganizations(ctx context.Context, input application.BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	search := strings.TrimSpace(input.Search)
	sector := strings.TrimSpace(input.Sector)
	direction := "DESC"
	if strings.EqualFold(strings.TrimSpace(input.SortDirection), "asc") {
		direction = "ASC"
	}
	query := `
		SELECT organization_id, COALESCE(ocl_organization_id, ''), name, type, COALESCE(sector, ''),
			registered_lobbyists, active_subject_matters,
			communication_volume_current_parliament, communication_volume_prior_parliament,
			top_dpohs, updated_at
		FROM lobbyist_organizations
		WHERE ($1 = '' OR name ILIKE '%' || $1 || '%' OR organization_id ILIKE '%' || $1 || '%')
			AND ($2 = '' OR LOWER(sector) = LOWER($2))
		ORDER BY communication_volume_current_parliament ` + direction + `, name ASC
		LIMIT $3 OFFSET $4
	`
	rows, err := r.db.Query(ctx, query, search, sector, limit, max(input.Offset, 0))
	if err != nil {
		return nil, fmt.Errorf("browse lobbyist organizations: %w", err)
	}
	defer rows.Close()

	var organizations []domain.LobbyistOrganization
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

func (r *PostgresLobbyistOrganizationRepository) ListOrganizationRegistrations(ctx context.Context) ([]application.OrganizationRegistration, error) {
	rows, err := r.db.Query(ctx, `
		WITH registration_subjects AS (
			SELECT
				reg_id_enr::TEXT AS source_id,
				ARRAY_AGG(DISTINCT COALESCE(NULLIF(smt.smt_en_desc, ''), rsm.subject_code_objet) ORDER BY COALESCE(NULLIF(smt.smt_en_desc, ''), rsm.subject_code_objet)) AS subject_matters
			FROM ocl_registration_subject_matters rsm
			LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = rsm.subject_code_objet
			GROUP BY reg_id_enr::TEXT
		),
		registration_lobbyists AS (
			SELECT
				client_org_corp_profil_id_profil_client_org_corp::TEXT AS profile_id,
				JSONB_AGG(JSONB_BUILD_OBJECT('name', name, 'kind', kind) ORDER BY kind, name) AS lobbyists
			FROM (
				SELECT
					client_org_corp_profil_id_profil_client_org_corp,
					BTRIM(CONCAT(lbbyst_1st_nm_prenom_lbbyst, ' ', lbbyst_last_nm_lbbyst)) AS name,
					'consultant' AS kind
				FROM ocl_registration_consultant_lobbyists
				UNION ALL
				SELECT
					client_org_corp_profil_id_profil_client_org_corp,
					BTRIM(CONCAT(lbbyst_first_nm_prenom_lbbyst, ' ', lbbyst_last_nm_lbbyst)) AS name,
					'in_house' AS kind
				FROM ocl_registration_in_house_lobbyists
			) lobbyists
			WHERE NULLIF(name, '') IS NOT NULL
			GROUP BY client_org_corp_profil_id_profil_client_org_corp::TEXT
		)
		SELECT
			rp.reg_id_enr::TEXT,
			COALESCE(NULLIF(rp.client_org_corp_num::TEXT, ''), ''),
			COALESCE(NULLIF(rp.en_client_org_corp_nm_an, 'null'), NULLIF(rp.fr_client_org_corp_nm, 'null'), ''),
			rp.reg_type_enr::TEXT,
			COALESCE((subjects.subject_matters)[1], ''),
			NULLIF(rp.effective_date_vigueur::TEXT, 'null'),
			NULLIF(rp.end_date_fin::TEXT, 'null'),
			COALESCE(lobbyists.lobbyists, '[]'::jsonb),
			COALESCE(subjects.subject_matters, ARRAY[]::TEXT[])
		FROM ocl_registration_primary rp
		LEFT JOIN registration_subjects subjects ON subjects.source_id = rp.reg_id_enr::TEXT
		LEFT JOIN registration_lobbyists lobbyists
			ON lobbyists.profile_id = rp.client_org_corp_profil_id_profil_client_org_corp::TEXT
	`)
	if err != nil {
		return nil, fmt.Errorf("query OCL registration rows: %w", err)
	}
	defer rows.Close()

	var registrations []application.OrganizationRegistration
	for rows.Next() {
		registration, err := scanRegistration(rows)
		if err != nil {
			return nil, err
		}
		registrations = append(registrations, registration)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate OCL registration rows: %w", err)
	}
	return registrations, nil
}

func (r *PostgresLobbyistOrganizationRepository) ListOrganizationCommunications(ctx context.Context) ([]application.OrganizationCommunication, error) {
	rows, err := r.db.Query(ctx, `
		WITH communication_subjects AS (
			SELECT
				csm.comlog_id::TEXT AS source_id,
				ARRAY_AGG(DISTINCT COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet) ORDER BY COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet)) AS subject_matters
			FROM ocl_communication_subject_matters csm
			LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = csm.subject_code_objet
			GROUP BY csm.comlog_id::TEXT
		),
		communication_dpohs AS (
			SELECT
				comlog_id::TEXT AS source_id,
				JSONB_AGG(
					JSONB_BUILD_OBJECT(
						'member_id', COALESCE(m.person_id, ''),
						'name', BTRIM(CONCAT(dpoh_first_nm_prenom_tcpd, ' ', dpoh_last_nm_tcpd)),
						'institution', COALESCE(NULLIF(institution, 'null'), ''),
						'count', 1
					)
					ORDER BY dpoh_last_nm_tcpd, dpoh_first_nm_prenom_tcpd, institution
				) AS dpohs
			FROM ocl_communication_dpohs
			LEFT JOIN members m
				ON LOWER(BTRIM(CONCAT(m.first_name, ' ', m.last_name))) = LOWER(BTRIM(CONCAT(dpoh_first_nm_prenom_tcpd, ' ', dpoh_last_nm_tcpd)))
			GROUP BY comlog_id::TEXT
		)
		SELECT
			cp.comlog_id::TEXT,
			COALESCE(NULLIF(cp.client_org_corp_num::TEXT, ''), ''),
			COALESCE(NULLIF(cp.en_client_org_corp_nm_an, 'null'), NULLIF(cp.fr_client_org_corp_nm, 'null'), ''),
			BTRIM(CONCAT(cp.rgstrnt_1st_nm_prenom_dclrnt, ' ', cp.rgstrnt_last_nm_dclrnt)),
			cp.reg_type_enr::TEXT,
			NULLIF(cp.comm_date::TEXT, 'null'),
			COALESCE(subjects.subject_matters, ARRAY[]::TEXT[]),
			COALESCE(dpohs.dpohs, '[]'::jsonb)
		FROM ocl_communication_primary cp
		LEFT JOIN communication_subjects subjects ON subjects.source_id = cp.comlog_id::TEXT
		LEFT JOIN communication_dpohs dpohs ON dpohs.source_id = cp.comlog_id::TEXT
	`)
	if err != nil {
		return nil, fmt.Errorf("query OCL communication rows: %w", err)
	}
	defer rows.Close()

	var communications []application.OrganizationCommunication
	for rows.Next() {
		communication, err := scanCommunication(rows)
		if err != nil {
			return nil, err
		}
		communications = append(communications, communication)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate OCL communication rows: %w", err)
	}
	return communications, nil
}

func scanOrganization(row interface {
	Scan(dest ...any) error
}) (domain.LobbyistOrganization, error) {
	var organization domain.LobbyistOrganization
	var organizationType string
	var lobbyistsJSON []byte
	var topDPOHsJSON []byte
	if err := row.Scan(
		&organization.ID,
		&organization.OCLOrganizationID,
		&organization.Name,
		&organizationType,
		&organization.Sector,
		&lobbyistsJSON,
		&organization.ActiveSubjectMatters,
		&organization.CommunicationVolume.CurrentParliament,
		&organization.CommunicationVolume.PriorParliament,
		&topDPOHsJSON,
		&organization.UpdatedAt,
	); err != nil {
		return domain.LobbyistOrganization{}, fmt.Errorf("scan lobbyist organization: %w", err)
	}
	organization.Type = domain.OrganizationType(organizationType)
	if err := json.Unmarshal(lobbyistsJSON, &organization.RegisteredLobbyists); err != nil {
		return domain.LobbyistOrganization{}, fmt.Errorf("decode registered lobbyists: %w", err)
	}
	if err := json.Unmarshal(topDPOHsJSON, &organization.TopDPOHsContacted); err != nil {
		return domain.LobbyistOrganization{}, fmt.Errorf("decode top dpohs: %w", err)
	}
	return organization, nil
}

func scanRegistration(rows pgx.Rows) (application.OrganizationRegistration, error) {
	var registration application.OrganizationRegistration
	var effectiveDate sql.NullString
	var endDate sql.NullString
	var lobbyistsJSON []byte
	if err := rows.Scan(
		&registration.SourceID,
		&registration.OCLOrganizationID,
		&registration.OrganizationName,
		&registration.RegistrationType,
		&registration.Sector,
		&effectiveDate,
		&endDate,
		&lobbyistsJSON,
		&registration.SubjectMatters,
	); err != nil {
		return application.OrganizationRegistration{}, fmt.Errorf("scan registration row: %w", err)
	}
	registration.EffectiveDate = parseDatePtr(effectiveDate)
	registration.EndDate = parseDatePtr(endDate)
	if err := json.Unmarshal(lobbyistsJSON, &registration.Lobbyists); err != nil {
		return application.OrganizationRegistration{}, fmt.Errorf("decode registration lobbyists: %w", err)
	}
	return registration, nil
}

func scanCommunication(rows pgx.Rows) (application.OrganizationCommunication, error) {
	var communication application.OrganizationCommunication
	var communicationDate sql.NullString
	var dpohsJSON []byte
	if err := rows.Scan(
		&communication.SourceID,
		&communication.OCLOrganizationID,
		&communication.OrganizationName,
		&communication.RegistrantName,
		&communication.RegistrantType,
		&communicationDate,
		&communication.SubjectMatters,
		&dpohsJSON,
	); err != nil {
		return application.OrganizationCommunication{}, fmt.Errorf("scan communication row: %w", err)
	}
	communication.CommunicationDate = parseDatePtr(communicationDate)
	if err := json.Unmarshal(dpohsJSON, &communication.DPOHs); err != nil {
		return application.OrganizationCommunication{}, fmt.Errorf("decode communication dpohs: %w", err)
	}
	return communication, nil
}

func parseDatePtr(value sql.NullString) *time.Time {
	if !value.Valid {
		return nil
	}
	raw := strings.TrimSpace(value.String)
	if raw == "" || strings.EqualFold(raw, "null") {
		return nil
	}
	for _, layout := range []string{"2006-01-02", time.RFC3339} {
		parsed, err := time.Parse(layout, raw)
		if err == nil {
			return &parsed
		}
	}
	return nil
}

func nullString(value string) any {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return value
}
