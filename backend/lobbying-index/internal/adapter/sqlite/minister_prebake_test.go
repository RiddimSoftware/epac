package sqlite_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"testing"
	"time"

	"epac/lobbying-index/internal/adapter/sqlite"
	"epac/lobbying-index/internal/domain"

	_ "modernc.org/sqlite"
)

func TestAggregator_SaveMinisterTables(t *testing.T) {
	dbPath := t.TempDir() + "/minister-prebake.sqlite"
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	execSQL(t, db, ministerRawSchemaSQL)
	execSQL(t, db, ministerRawDataSQL)

	startDate := time.Date(2025, 5, 21, 0, 0, 0, 0, time.UTC)
	snapshot := domain.CabinetSnapshot{
		PortfolioPeriods: []domain.CabinetPortfolioPeriod{
			{
				MinisterName:     "Alex Smith",
				FirstName:        "Alex",
				LastName:         "Smith",
				PortfolioName:    "Minister of Transport",
				StartDate:        &startDate,
				ParliamentNumber: 45,
				SourceURL:        "https://www.pm.gc.ca/en/cabinet",
			},
			{
				MinisterName:     "Casey Unknown",
				FirstName:        "Casey",
				LastName:         "Unknown",
				PortfolioName:    "Minister of Housing",
				StartDate:        &startDate,
				ParliamentNumber: 45,
				SourceURL:        "https://www.pm.gc.ca/en/cabinet",
			},
		},
		MandateTopics: []domain.CabinetMandateTopic{
			{EpacTopicSlug: "housing", Confidence: 0.85, SourceURL: "https://www.pm.gc.ca/en/mandate-letters/2025/05/21/mandate-letter"},
			{EpacTopicSlug: "transport", Confidence: 0.85, SourceURL: "https://www.pm.gc.ca/en/mandate-letters/2025/05/21/mandate-letter"},
		},
	}

	agg := sqlite.NewAggregator()
	result, err := agg.SaveMinisterTables(context.Background(), dbPath, snapshot)
	if err != nil {
		t.Fatalf("SaveMinisterTables: %v", err)
	}

	if result.PortfolioRows != 2 {
		t.Fatalf("portfolio rows = %d, want 2", result.PortfolioRows)
	}
	if result.MandateRows != 4 {
		t.Fatalf("mandate rows = %d, want 4", result.MandateRows)
	}
	if result.CommunicationRows != 1 {
		t.Fatalf("communication rows = %d, want 1", result.CommunicationRows)
	}
	if result.MemberResolutionMissCount != 1 {
		t.Fatalf("member resolution misses = %d, want 1", result.MemberResolutionMissCount)
	}
	if result.MinistersWithoutCommunications != 1 {
		t.Fatalf("ministers without communications = %d, want 1", result.MinistersWithoutCommunications)
	}

	var memberID, start string
	if err := db.QueryRow(`
SELECT member_id, start_date
FROM minister_portfolio_periods
WHERE minister_name = 'Alex Smith'`).Scan(&memberID, &start); err != nil {
		t.Fatalf("load portfolio period: %v", err)
	}
	if memberID != "1" || start != "2025-05-21" {
		t.Fatalf("unexpected portfolio period row: member_id=%q start=%q", memberID, start)
	}

	var unresolvedCount int
	if err := db.QueryRow(`
SELECT COUNT(*)
FROM minister_portfolio_periods
WHERE member_id = ''`).Scan(&unresolvedCount); err != nil {
		t.Fatalf("count unresolved portfolio rows: %v", err)
	}
	if unresolvedCount != 1 {
		t.Fatalf("unresolved portfolio rows = %d, want 1", unresolvedCount)
	}

	var mappingCount int
	if err := db.QueryRow(`
SELECT COUNT(*)
FROM minister_mandate_topic_mappings
WHERE member_id = '1'`).Scan(&mappingCount); err != nil {
		t.Fatalf("count mandate mappings: %v", err)
	}
	if mappingCount != 2 {
		t.Fatalf("mandate mappings for member 1 = %d, want 2", mappingCount)
	}

	var subjectCodesJSON string
	if err := db.QueryRow(`
SELECT subject_matter_codes
FROM minister_communications
WHERE member_id = '1'`).Scan(&subjectCodesJSON); err != nil {
		t.Fatalf("load minister communication: %v", err)
	}
	var subjectCodes []string
	if err := json.Unmarshal([]byte(subjectCodesJSON), &subjectCodes); err != nil {
		t.Fatalf("decode subject codes: %v", err)
	}
	if len(subjectCodes) != 2 || subjectCodes[0] != "SMT-18" || subjectCodes[1] != "SMT-21" {
		t.Fatalf("subject codes = %#v, want [SMT-18 SMT-21]", subjectCodes)
	}
}

func execSQL(t *testing.T, db *sql.DB, statement string) {
	t.Helper()
	if _, err := db.Exec(statement); err != nil {
		t.Fatalf("exec SQL: %v", err)
	}
}

const ministerRawSchemaSQL = `
CREATE TABLE members (
    person_id TEXT PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    from_date TEXT,
    to_date TEXT
);
CREATE TABLE ocl_communication_primary (
    comlog_id TEXT PRIMARY KEY,
    en_client_org_corp_nm_an TEXT,
    fr_client_org_corp_nm TEXT,
    client_org_corp_num TEXT,
    rgstrnt_1st_nm_prenom_dclrnt TEXT,
    rgstrnt_last_nm_dclrnt TEXT,
    reg_type_enr TEXT,
    comm_date TEXT
);
CREATE TABLE ocl_communication_dpohs (
    comlog_id TEXT NOT NULL,
    dpoh_first_nm_prenom_tcpd TEXT,
    dpoh_last_nm_tcpd TEXT,
    institution TEXT,
    PRIMARY KEY (comlog_id, dpoh_first_nm_prenom_tcpd, dpoh_last_nm_tcpd, institution)
);
CREATE TABLE ocl_communication_subject_matters (
    comlog_id TEXT NOT NULL,
    subject_code_objet TEXT NOT NULL,
    custom_subj_objet_perso TEXT,
    PRIMARY KEY (comlog_id, subject_code_objet, custom_subj_objet_perso)
);
`

const ministerRawDataSQL = `
INSERT INTO members (person_id, first_name, last_name, from_date, to_date) VALUES
    ('1', 'Alex', 'Smith', '2024-01-01', NULL),
    ('2', 'Jamie', 'Jones', '2024-01-01', NULL);

INSERT INTO ocl_communication_primary (
    comlog_id,
    en_client_org_corp_nm_an,
    fr_client_org_corp_nm,
    client_org_corp_num,
    rgstrnt_1st_nm_prenom_dclrnt,
    rgstrnt_last_nm_dclrnt,
    reg_type_enr,
    comm_date
) VALUES
    ('COM-1', 'Transit Council', NULL, 'ORG-1', 'Robin', 'Lobbyist', '2', '2025-06-10'),
    ('COM-2', 'Transit Council', NULL, 'ORG-1', 'Robin', 'Lobbyist', '2', '2024-04-10');

INSERT INTO ocl_communication_dpohs (comlog_id, dpoh_first_nm_prenom_tcpd, dpoh_last_nm_tcpd, institution) VALUES
    ('COM-1', 'Alex P.', 'Smith', 'House of Commons'),
    ('COM-2', 'Alex P.', 'Smith', 'House of Commons');

INSERT INTO ocl_communication_subject_matters (comlog_id, subject_code_objet, custom_subj_objet_perso) VALUES
    ('COM-1', 'SMT-21', ''),
    ('COM-1', 'SMT-18', ''),
    ('COM-2', 'SMT-21', '');
`
