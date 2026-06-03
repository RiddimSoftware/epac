package sqlite

import (
	"database/sql"
	"encoding/json"
	"math"
	"testing"
	"time"

	"epac/lobbying-index/internal/usecase"

	_ "modernc.org/sqlite"
)

type fixedClock struct {
	now time.Time
}

func (c fixedClock) Now() time.Time { return c.now }

func TestAggregationRunnerBuildsMPLobbyingReadTables(t *testing.T) {
	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	execSQL(t, db, rawFixtureSchemaSQL)
	execSQL(t, db, rawFixtureDataSQL)

	quarterStart := time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC)
	quarterEnd := time.Date(2026, 6, 30, 0, 0, 0, 0, time.UTC)
	runner := NewAggregationRunner(
		WithParliament(45),
		WithQuarter(quarterStart, quarterEnd),
		WithClock(fixedClock{now: time.Date(2026, 7, 1, 12, 0, 0, 0, time.UTC)}),
	)

	if err := usecase.BuildMPLobbyingTables(db, runner); err != nil {
		t.Fatalf("build MP lobbying tables: %v", err)
	}

	var timelineRows int
	if err := db.QueryRow(`SELECT COUNT(*) FROM mp_lobbying_timeline_entries WHERE member_id = '1'`).Scan(&timelineRows); err != nil {
		t.Fatalf("count timeline rows: %v", err)
	}
	if timelineRows != 3 {
		t.Fatalf("expected 3 timeline rows for member 1, got %d", timelineRows)
	}

	var summary struct {
		total            int
		uniqueOrgs       int
		subject          sql.NullString
		topOrganizations string
		partyAverage     float64
		nationalAverage  float64
	}
	if err := db.QueryRow(`
SELECT
    total_communication_count,
    unique_organizations_count,
    most_frequent_subject_matter,
    top_organizations,
    party_average_communications,
    national_average_communications
FROM mp_lobbying_summaries
WHERE member_id = '1'
    AND parliament = 45
    AND quarter_start = '2026-04-01'
    AND "window" = 'all'`).Scan(
		&summary.total,
		&summary.uniqueOrgs,
		&summary.subject,
		&summary.topOrganizations,
		&summary.partyAverage,
		&summary.nationalAverage,
	); err != nil {
		t.Fatalf("load all-window summary: %v", err)
	}

	if summary.total != 3 {
		t.Fatalf("expected all-window total 3, got %d", summary.total)
	}
	if summary.uniqueOrgs != 2 {
		t.Fatalf("expected 2 unique organizations, got %d", summary.uniqueOrgs)
	}
	if !summary.subject.Valid || summary.subject.String != "Agriculture" {
		t.Fatalf("expected Agriculture as most frequent subject, got %v", summary.subject)
	}
	if !nearlyEqual(summary.partyAverage, 1.5) {
		t.Fatalf("expected Liberal party average 1.5, got %f", summary.partyAverage)
	}
	if !nearlyEqual(summary.nationalAverage, 1.0) {
		t.Fatalf("expected national average 1.0, got %f", summary.nationalAverage)
	}

	var topOrganizations []struct {
		Name               string `json:"name"`
		Sector             string `json:"sector"`
		CommunicationCount int    `json:"communication_count"`
	}
	if err := json.Unmarshal([]byte(summary.topOrganizations), &topOrganizations); err != nil {
		t.Fatalf("decode top organizations: %v", err)
	}
	if len(topOrganizations) != 2 {
		t.Fatalf("expected 2 top organizations, got %d", len(topOrganizations))
	}
	if topOrganizations[0].Name != "Acme Agriculture" || topOrganizations[0].CommunicationCount != 2 {
		t.Fatalf("unexpected first top organization: %+v", topOrganizations[0])
	}

	var subjectCount int
	if err := db.QueryRow(`
SELECT communication_count
FROM mp_lobbying_subject_breakdowns
WHERE member_id = '1'
    AND parliament = 45
    AND quarter_start = '2026-04-01'
    AND "window" = 'all'
    AND subject_matter = 'Agriculture'`).Scan(&subjectCount); err != nil {
		t.Fatalf("load subject breakdown: %v", err)
	}
	if subjectCount != 2 {
		t.Fatalf("expected Agriculture subject count 2, got %d", subjectCount)
	}

	var nationalAverage float64
	if err := db.QueryRow(`
SELECT avg_communications
FROM lobbying_cohort_averages
WHERE parliament = 45 AND party IS NULL`).Scan(&nationalAverage); err != nil {
		t.Fatalf("load national cohort average: %v", err)
	}
	if !nearlyEqual(nationalAverage, 3.0) {
		t.Fatalf("expected national cohort average 3.0, got %f", nationalAverage)
	}
}

func execSQL(t *testing.T, db *sql.DB, statement string) {
	t.Helper()
	if _, err := db.Exec(statement); err != nil {
		t.Fatalf("exec fixture SQL: %v", err)
	}
}

func nearlyEqual(left, right float64) bool {
	return math.Abs(left-right) < 0.000001
}

const rawFixtureSchemaSQL = `
CREATE TABLE members (
    person_id TEXT PRIMARY KEY,
    honorific TEXT,
    first_name TEXT,
    last_name TEXT,
    caucus TEXT,
    constituency TEXT,
    province TEXT,
    from_date TEXT,
    to_date TEXT
);
CREATE TABLE ocl_subject_matter_types (
    subject_code_objet TEXT PRIMARY KEY,
    smt_en_desc TEXT
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

const rawFixtureDataSQL = `
INSERT INTO members (person_id, first_name, last_name, caucus, constituency, province, from_date, to_date) VALUES
    ('1', 'Alex', 'Smith', 'Liberal', 'Ottawa Centre', 'ON', '2024-01-01', NULL),
    ('2', 'Jamie', 'Jones', 'Liberal', 'Halifax', 'NS', '2024-01-01', NULL),
    ('3', 'Pat', 'Green', 'Conservative', 'Calgary Centre', 'AB', '2024-01-01', NULL);

INSERT INTO ocl_subject_matter_types (subject_code_objet, smt_en_desc) VALUES
    ('AGR', 'Agriculture'),
    ('HEA', 'Health');

INSERT INTO ocl_communication_primary (
    comlog_id,
    en_client_org_corp_nm_an,
    fr_client_org_corp_nm,
    client_org_corp_num,
    comm_date
) VALUES
    ('100', 'Acme Agriculture', NULL, 'ORG-1', '2026-05-15'),
    ('101', 'Beta Health', NULL, 'ORG-2', '2026-05-20'),
    ('102', 'Acme Agriculture', NULL, 'ORG-1', '2026-01-10'),
    ('103', 'Acme Agriculture', NULL, 'ORG-1', '2026-05-15');

INSERT INTO ocl_communication_dpohs (
    comlog_id,
    dpoh_first_nm_prenom_tcpd,
    dpoh_last_nm_tcpd,
    institution
) VALUES
    ('100', 'Alex', 'Smith', 'House of Commons'),
    ('100', 'Alex', 'Smith', 'House of Commons duplicate source row'),
    ('101', 'Alex', 'Smith', 'House of Commons'),
    ('102', 'Alex', 'Smith', 'House of Commons'),
    ('103', 'No', 'Match', 'House of Commons');

INSERT INTO ocl_communication_subject_matters (comlog_id, subject_code_objet, custom_subj_objet_perso) VALUES
    ('100', 'AGR', ''),
    ('101', 'HEA', ''),
    ('102', 'AGR', ''),
    ('103', 'AGR', '');
`
