package sqlite_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"testing"

	"epac/lobbying-index/internal/adapter/sqlite"
	"epac/lobbying-index/internal/domain"

	_ "modernc.org/sqlite"
)

func seedTestDB(t *testing.T, dbPath string) {
	t.Helper()
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open seed db: %v", err)
	}
	defer db.Close()

	schema := `
CREATE TABLE members (person_id TEXT PRIMARY KEY, honorific TEXT, first_name TEXT, last_name TEXT, constituency TEXT, province TEXT, caucus TEXT, from_date TIMESTAMP, to_date TIMESTAMP);
CREATE TABLE ocl_subject_matter_types (subject_code_objet TEXT PRIMARY KEY, smt_en_desc TEXT);
CREATE TABLE ocl_communication_primary (comlog_id TEXT PRIMARY KEY, en_client_org_corp_nm_an TEXT, fr_client_org_corp_nm TEXT, client_org_corp_num TEXT, rgstrnt_1st_nm_prenom_dclrnt TEXT, rgstrnt_last_nm_dclrnt TEXT, reg_type_enr TEXT, comm_date TIMESTAMP);
CREATE TABLE ocl_communication_dpohs (comlog_id TEXT NOT NULL, dpoh_first_nm_prenom_tcpd TEXT, dpoh_last_nm_tcpd TEXT, institution TEXT, PRIMARY KEY (comlog_id, dpoh_first_nm_prenom_tcpd, dpoh_last_nm_tcpd, institution));
CREATE TABLE ocl_communication_subject_matters (comlog_id TEXT NOT NULL, subject_code_objet TEXT NOT NULL, custom_subj_objet_perso TEXT, PRIMARY KEY (comlog_id, subject_code_objet, custom_subj_objet_perso));
CREATE TABLE ocl_registration_primary (reg_id_enr TEXT PRIMARY KEY, reg_type_enr TEXT, client_org_corp_num TEXT, en_client_org_corp_nm_an TEXT, fr_client_org_corp_nm TEXT, client_org_corp_profil_id_profil_client_org_corp TEXT, effective_date_vigueur TIMESTAMP, end_date_fin TIMESTAMP);
CREATE TABLE ocl_registration_subject_matters (reg_id_enr TEXT NOT NULL, subject_code_objet TEXT NOT NULL, custom_subj_objet_perso TEXT, PRIMARY KEY (reg_id_enr, subject_code_objet, custom_subj_objet_perso));
CREATE TABLE ocl_registration_in_house_lobbyists (client_org_corp_profil_id_profil_client_org_corp TEXT NOT NULL, lbbyst_id_lbbyst TEXT, lbbyst_first_nm_prenom_lbbyst TEXT, lbbyst_last_nm_lbbyst TEXT, PRIMARY KEY (client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst));
CREATE TABLE ocl_registration_consultant_lobbyists (client_org_corp_profil_id_profil_client_org_corp TEXT NOT NULL, lbbyst_id_lbbyst TEXT, lbbyst_first_nm_prenom_lbbyst TEXT, lbbyst_last_nm_lbbyst TEXT, PRIMARY KEY (client_org_corp_profil_id_profil_client_org_corp, lbbyst_id_lbbyst));`

	if _, err := db.Exec(schema); err != nil {
		t.Fatalf("create seed schema: %v", err)
	}

	seed := `
INSERT INTO ocl_subject_matter_types VALUES ('SMT-18', 'Health');
INSERT INTO ocl_subject_matter_types VALUES ('SMT-11', 'Energy');

INSERT INTO ocl_registration_primary VALUES
  ('REG-1', 'In-house (Corporation)', 'ORG-100', 'Acme Corp', NULL, 'PROF-1', '2024-01-01', NULL),
  ('REG-2', 'In-house (Organization)', 'ORG-200', 'Green Alliance', NULL, 'PROF-2', '2023-06-01', '2024-12-31');

INSERT INTO ocl_registration_subject_matters VALUES ('REG-1', 'SMT-18', ''), ('REG-1', 'SMT-11', ''), ('REG-2', 'SMT-11', '');
INSERT INTO ocl_registration_in_house_lobbyists VALUES ('PROF-1', 'L1', 'Alice', 'Smith'), ('PROF-2', 'L2', 'Bob', 'Jones');

INSERT INTO ocl_communication_primary VALUES
  ('COM-1', 'Acme Corp', NULL, 'ORG-100', 'Alice', 'Smith', 'In-house (Corporation)', '2025-06-01'),
  ('COM-2', 'Green Alliance', NULL, 'ORG-200', 'Bob', 'Jones', 'In-house (Organization)', '2024-01-15');

INSERT INTO ocl_communication_subject_matters VALUES ('COM-1', 'SMT-18', ''), ('COM-2', 'SMT-11', '');
INSERT INTO ocl_communication_dpohs VALUES ('COM-1', 'Jane', 'Doe', 'Health Canada');`

	if _, err := db.Exec(seed); err != nil {
		t.Fatalf("seed data: %v", err)
	}
}

func TestAggregator_AggregateOrganizationTables(t *testing.T) {
	dbPath := t.TempDir() + "/test.sqlite"
	seedTestDB(t, dbPath)

	agg := sqlite.NewAggregator()
	if err := agg.AggregateOrganizationTables(context.Background(), dbPath); err != nil {
		t.Fatalf("AggregateOrganizationTables: %v", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open result db: %v", err)
	}
	defer db.Close()

	var commCount, regCount, smCount, orgCount int
	db.QueryRow("SELECT COUNT(*) FROM lobbyist_communications").Scan(&commCount)
	db.QueryRow("SELECT COUNT(*) FROM lobbyist_registrations").Scan(&regCount)
	db.QueryRow("SELECT COUNT(*) FROM lobbyist_subject_matters").Scan(&smCount)
	db.QueryRow("SELECT COUNT(*) FROM lobbyist_organizations").Scan(&orgCount)

	if commCount != 2 {
		t.Errorf("expected 2 communications, got %d", commCount)
	}
	if regCount != 2 {
		t.Errorf("expected 2 registrations, got %d", regCount)
	}
	// 2 communication subjects + 3 registration subjects (REG-1: SMT-18, SMT-11; REG-2: SMT-11)
	if smCount != 5 {
		t.Errorf("expected 5 subject matter rows, got %d", smCount)
	}
	if orgCount != 2 {
		t.Errorf("expected 2 organizations, got %d", orgCount)
	}

	var name, status, lobbyistsJSON string
	db.QueryRow("SELECT name, registration_status, registered_lobbyists FROM lobbyist_organizations WHERE organization_id = 'ORG-100'").Scan(&name, &status, &lobbyistsJSON)
	if name != "Acme Corp" {
		t.Errorf("expected name 'Acme Corp', got %q", name)
	}
	if status != "active" {
		t.Errorf("expected status 'active' (no end date), got %q", status)
	}
	var lobbyists []map[string]string
	json.Unmarshal([]byte(lobbyistsJSON), &lobbyists)
	if len(lobbyists) == 0 {
		t.Error("expected registered_lobbyists to be non-empty")
	}

	var expiredStatus string
	db.QueryRow("SELECT registration_status FROM lobbyist_organizations WHERE organization_id = 'ORG-200'").Scan(&expiredStatus)
	if expiredStatus != "expired" {
		t.Errorf("expected status 'expired' (end_date in past), got %q", expiredStatus)
	}
}

func TestAggregator_SaveBillContextTables(t *testing.T) {
	dbPath := t.TempDir() + "/bills.sqlite"

	bills := []domain.LegisInfoBill{
		{
			Number:                          "C-10",
			Parliament:                      45,
			Session:                         1,
			LongTitleEn:                     "An Act respecting health insurance",
			PassedHouseFirstReadingDateTime: "2025-09-26T12:10:20",
			PassedHouseSecondReadingDateTime: "2025-10-15T14:00:00",
		},
		{
			Number:      "C-11",
			Parliament:  45,
			Session:     1,
			LongTitleEn: "An Act relating to railways and transport",
			PassedSenateFirstReadingDateTime: "2025-09-26T10:30:00",
		},
	}
	topicMap := []domain.TopicMapping{
		{OCLCode: "SMT-18", EpacTopicSlug: "healthcare", Confidence: 1.0},
		{OCLCode: "SMT-21", EpacTopicSlug: "transport", Confidence: 0.95},
	}

	agg := sqlite.NewAggregator()
	if err := agg.SaveBillContextTables(context.Background(), dbPath, bills, topicMap); err != nil {
		t.Fatalf("SaveBillContextTables: %v", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open result db: %v", err)
	}
	defer db.Close()

	var readingCount, tagCount int
	db.QueryRow("SELECT COUNT(*) FROM legisinfo_bill_readings").Scan(&readingCount)
	db.QueryRow("SELECT COUNT(*) FROM legisinfo_bill_subject_tags").Scan(&tagCount)

	if readingCount != 3 {
		t.Errorf("expected 3 readings, got %d", readingCount)
	}
	if tagCount == 0 {
		t.Error("expected at least 1 subject tag from title keyword matching")
	}

	var slug string
	db.QueryRow("SELECT epac_topic_slug FROM legisinfo_bill_subject_tags WHERE legisinfo_id = 'C-10' AND subject_tag = 'health'").Scan(&slug)
	if slug != "healthcare" {
		t.Errorf("expected epac_topic_slug 'healthcare', got %q", slug)
	}
}
