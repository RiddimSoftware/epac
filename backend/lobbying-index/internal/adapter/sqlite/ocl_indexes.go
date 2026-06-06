package sqlite

import (
	"context"
	"database/sql"
	"fmt"
)

func EnsureOCLIndexes(ctx context.Context, databasePath string) error {
	if databasePath == "" {
		databasePath = DefaultDatabasePath
	}

	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()

	if _, err := db.ExecContext(ctx, oclIndexesSQL); err != nil {
		return fmt.Errorf("create OCL indexes: %w", err)
	}
	return nil
}

const oclIndexesSQL = `
CREATE INDEX IF NOT EXISTS ocl_communication_primary_comlog_id_idx
ON ocl_communication_primary (comlog_id);

CREATE INDEX IF NOT EXISTS ocl_communication_primary_comm_date_idx
ON ocl_communication_primary (comm_date);

CREATE INDEX IF NOT EXISTS ocl_communication_primary_client_org_corp_num_idx
ON ocl_communication_primary (client_org_corp_num);

CREATE INDEX IF NOT EXISTS ocl_communication_dpohs_comlog_id_idx
ON ocl_communication_dpohs (comlog_id);

CREATE INDEX IF NOT EXISTS ocl_communication_dpohs_full_name_idx
ON ocl_communication_dpohs (lower(trim(COALESCE(dpoh_first_nm_prenom_tcpd, '') || ' ' || COALESCE(dpoh_last_nm_tcpd, ''))));

CREATE INDEX IF NOT EXISTS ocl_communication_subject_matters_comlog_id_idx
ON ocl_communication_subject_matters (comlog_id);

CREATE INDEX IF NOT EXISTS members_full_name_idx
ON members (lower(trim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''))));

CREATE INDEX IF NOT EXISTS members_from_date_to_date_idx
ON members (from_date, to_date);

CREATE INDEX IF NOT EXISTS ocl_registration_primary_client_org_profile_idx
ON ocl_registration_primary (client_org_corp_profil_id_profil_client_org_corp);

CREATE INDEX IF NOT EXISTS ocl_registration_primary_reg_id_enr_idx
ON ocl_registration_primary (reg_id_enr);

CREATE INDEX IF NOT EXISTS ocl_registration_in_house_lobbyists_client_org_profile_idx
ON ocl_registration_in_house_lobbyists (client_org_corp_profil_id_profil_client_org_corp);

CREATE INDEX IF NOT EXISTS ocl_registration_consultant_lobbyists_client_org_profile_idx
ON ocl_registration_consultant_lobbyists (client_org_corp_profil_id_profil_client_org_corp);

CREATE INDEX IF NOT EXISTS ocl_registration_subject_matters_reg_id_enr_idx
ON ocl_registration_subject_matters (reg_id_enr);
`
