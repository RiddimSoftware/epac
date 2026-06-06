package sqlite

import (
	"context"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"

	"epac/lobbying-index/internal/domain"

	_ "modernc.org/sqlite"
)

func TestEnsureOCLIndexesCreatesExpectedIndexes(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "ocl-indexes.sqlite")
	if err := NewWriter().Write(context.Background(), dbPath, domain.OCLIngestionBatch{}, nil, nil); err != nil {
		t.Fatalf("write empty raw schema: %v", err)
	}

	if err := EnsureOCLIndexes(context.Background(), dbPath); err != nil {
		t.Fatalf("ensure indexes: %v", err)
	}
	if err := EnsureOCLIndexes(context.Background(), dbPath); err != nil {
		t.Fatalf("ensure indexes is idempotent: %v", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open indexed db: %v", err)
	}
	defer db.Close()

	expectedIndexes := map[string]string{
		"ocl_communication_primary_comlog_id_idx":                      "ON ocl_communication_primary (comlog_id)",
		"ocl_communication_primary_comm_date_idx":                      "ON ocl_communication_primary (comm_date)",
		"ocl_communication_primary_client_org_corp_num_idx":            "ON ocl_communication_primary (client_org_corp_num)",
		"ocl_communication_dpohs_comlog_id_idx":                        "ON ocl_communication_dpohs (comlog_id)",
		"ocl_communication_dpohs_full_name_idx":                        "ON ocl_communication_dpohs (lower(trim(COALESCE(dpoh_first_nm_prenom_tcpd, '') || ' ' || COALESCE(dpoh_last_nm_tcpd, ''))))",
		"ocl_communication_subject_matters_comlog_id_idx":              "ON ocl_communication_subject_matters (comlog_id)",
		"members_full_name_idx":                                        "ON members (lower(trim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, ''))))",
		"members_from_date_to_date_idx":                                "ON members (from_date, to_date)",
		"ocl_registration_primary_client_org_profile_idx":              "ON ocl_registration_primary (client_org_corp_profil_id_profil_client_org_corp)",
		"ocl_registration_primary_reg_id_enr_idx":                      "ON ocl_registration_primary (reg_id_enr)",
		"ocl_registration_in_house_lobbyists_client_org_profile_idx":   "ON ocl_registration_in_house_lobbyists (client_org_corp_profil_id_profil_client_org_corp)",
		"ocl_registration_consultant_lobbyists_client_org_profile_idx": "ON ocl_registration_consultant_lobbyists (client_org_corp_profil_id_profil_client_org_corp)",
		"ocl_registration_subject_matters_reg_id_enr_idx":              "ON ocl_registration_subject_matters (reg_id_enr)",
	}

	for indexName, wantSQL := range expectedIndexes {
		var gotSQL string
		if err := db.QueryRow("SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?", indexName).Scan(&gotSQL); err != nil {
			t.Fatalf("find index %s: %v", indexName, err)
		}
		if !strings.Contains(gotSQL, wantSQL) {
			t.Fatalf("index %s SQL = %q, want fragment %q", indexName, gotSQL, wantSQL)
		}
	}
}

func TestOCLFullNameIndexesMatchTimelineJoinExpressions(t *testing.T) {
	memberNameExpression := "lower(trim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')))"
	dpohNameExpression := "lower(trim(COALESCE(dpoh_first_nm_prenom_tcpd, '') || ' ' || COALESCE(dpoh_last_nm_tcpd, '')))"

	for _, expression := range []string{memberNameExpression, dpohNameExpression} {
		if !strings.Contains(oclIndexesSQL, expression) {
			t.Fatalf("oclIndexesSQL missing expression %q", expression)
		}
		if !strings.Contains(refreshTimelineSQL, expression) {
			t.Fatalf("refreshTimelineSQL missing expression %q", expression)
		}
	}
}
