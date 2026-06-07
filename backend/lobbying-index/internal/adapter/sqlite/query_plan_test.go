package sqlite

import (
	"database/sql"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

// Baseline on Apple Silicon / modernc.org/sqlite v1.39.1:
// BenchmarkRefreshTimelineSQL-12  1  10291346042 ns/op @ 50k OCL rows/table with comlog_id index lookups.
func TestRefreshTimelineSQLUsesComlogIdIndexes(t *testing.T) {
	db := openInMemorySQLite(t)
	defer db.Close()

	planDetails := explainRefreshTimelinePlan(t, db, refreshTimelineSQL)
	assertPlanContains(t, planDetails, "SEARCH dpoh USING INDEX ocl_communication_dpohs_comlog_id_idx")
	assertPlanContains(t, planDetails, "SEARCH csm USING INDEX ocl_communication_subject_matters_comlog_id_idx")
	assertPlanOmits(t, planDetails, "SCAN dpoh")
	assertPlanOmits(t, planDetails, "SCAN csm")
	assertPlanOmits(t, planDetails, "SCAN ocl_communication_dpohs")
	assertPlanOmits(t, planDetails, "SCAN ocl_communication_subject_matters")
}

func BenchmarkRefreshTimelineSQL(b *testing.B) {
	if testing.Short() {
		b.Skip("skipping 50k-row refreshTimelineSQL benchmark in short mode")
	}

	db := openInMemorySQLite(b)
	defer db.Close()
	insertSyntheticOCLRows(b, db, 50_000)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		if _, err := db.Exec(refreshTimelineSQL, 45, nil, nil, "2026-06-07T00:00:00Z", DefaultSourceURL); err != nil {
			b.Fatalf("refresh timeline SQL: %v", err)
		}
	}
}

func openInMemorySQLite(tb testing.TB) *sql.DB {
	tb.Helper()

	db, err := sql.Open("sqlite", ":memory:")
	if err != nil {
		tb.Fatalf("open in-memory sqlite: %v", err)
	}
	db.SetMaxOpenConns(1)

	for _, statement := range []string{schemaSQL, oclIndexesSQL, readModelSchemaSQL} {
		if _, err := db.Exec(statement); err != nil {
			db.Close()
			tb.Fatalf("apply sqlite setup SQL: %v", err)
		}
	}
	seedRefreshTimelinePlannerStats(tb, db)
	return db
}

func seedRefreshTimelinePlannerStats(tb testing.TB, db *sql.DB) {
	tb.Helper()

	if _, err := db.Exec(`ANALYZE`); err != nil {
		tb.Fatalf("create sqlite_stat1: %v", err)
	}
	// These stats mirror a one-member, 50k-row OCL fixture. The composite
	// primary-key autoindexes are intentionally marked non-selective so the
	// planner proves refreshTimelineSQL can use the explicit EPAC-2244 indexes.
	if _, err := db.Exec(`
DELETE FROM sqlite_stat1;
INSERT INTO sqlite_stat1 (tbl, idx, stat) VALUES
    ('members', 'members_from_date_to_date_idx', '1 1 1'),
    ('members', 'members_full_name_idx', '1 1'),
    ('members', 'sqlite_autoindex_members_1', '1 1'),
    ('ocl_communication_dpohs', 'ocl_communication_dpohs_comlog_id_idx', '50000 1'),
    ('ocl_communication_dpohs', 'ocl_communication_dpohs_full_name_idx', '50000 50000'),
    ('ocl_communication_dpohs', 'sqlite_autoindex_ocl_communication_dpohs_1', '50000 50000 50000 50000 50000'),
    ('ocl_communication_primary', 'ocl_communication_primary_client_org_corp_num_idx', '50000 1'),
    ('ocl_communication_primary', 'ocl_communication_primary_comlog_id_idx', '50000 1'),
    ('ocl_communication_primary', 'ocl_communication_primary_comm_date_idx', '50000 50000'),
    ('ocl_communication_primary', 'sqlite_autoindex_ocl_communication_primary_1', '50000 1'),
    ('ocl_communication_subject_matters', 'ocl_communication_subject_matters_comlog_id_idx', '50000 1'),
    ('ocl_communication_subject_matters', 'sqlite_autoindex_ocl_communication_subject_matters_1', '50000 50000 50000 50000');
ANALYZE sqlite_schema;
`); err != nil {
		tb.Fatalf("seed planner stats: %v", err)
	}
}

func explainRefreshTimelinePlan(tb testing.TB, db *sql.DB, query string) []string {
	tb.Helper()

	rows, err := db.Query("EXPLAIN QUERY PLAN "+query, 45, nil, nil, "2026-06-07T00:00:00Z", DefaultSourceURL)
	if err != nil {
		tb.Fatalf("explain refresh timeline SQL: %v", err)
	}
	defer rows.Close()

	var details []string
	for rows.Next() {
		var id, parent, notused int
		var detail string
		if err := rows.Scan(&id, &parent, &notused, &detail); err != nil {
			tb.Fatalf("scan query plan row: %v", err)
		}
		details = append(details, detail)
	}
	if err := rows.Err(); err != nil {
		tb.Fatalf("iterate query plan rows: %v", err)
	}
	return details
}

func assertPlanContains(t *testing.T, details []string, want string) {
	t.Helper()
	for _, detail := range details {
		if strings.Contains(detail, want) {
			return
		}
	}
	t.Fatalf("query plan missing %q; plan:\n%s", want, strings.Join(details, "\n"))
}

func assertPlanOmits(t *testing.T, details []string, unwanted string) {
	t.Helper()
	for _, detail := range details {
		if detail == unwanted || strings.HasPrefix(detail, unwanted+" ") {
			t.Fatalf("query plan contains unwanted %q row %q; plan:\n%s", unwanted, detail, strings.Join(details, "\n"))
		}
	}
}

func insertSyntheticOCLRows(tb testing.TB, db *sql.DB, rowCount int) {
	tb.Helper()

	if _, err := db.Exec(`
INSERT INTO members (person_id, first_name, last_name, caucus, constituency, province, from_date, to_date)
VALUES ('1', 'Alex', 'Smith', 'Liberal', 'Ottawa Centre', 'ON', '2020-01-01', NULL);
INSERT INTO ocl_subject_matter_types (subject_code_objet, smt_en_desc)
VALUES ('AGR', 'Agriculture');
`); err != nil {
		tb.Fatalf("seed synthetic member/reference rows: %v", err)
	}

	if _, err := db.Exec(`
WITH RECURSIVE ids(i) AS (
    VALUES(1)
    UNION ALL
    SELECT i + 1 FROM ids WHERE i < ?
)
INSERT INTO ocl_communication_primary (
    comlog_id,
    en_client_org_corp_nm_an,
    fr_client_org_corp_nm,
    client_org_corp_num,
    rgstrnt_1st_nm_prenom_dclrnt,
    rgstrnt_last_nm_dclrnt,
    reg_type_enr,
    comm_date
)
SELECT
    'COM-' || i,
    'Organization ' || i,
    NULL,
    'ORG-' || i,
    'Registrar',
    'Person',
    'In-house (Corporation)',
    printf('2026-05-%02dT12:00:00Z', ((i - 1) % 28) + 1)
FROM ids;
`, rowCount); err != nil {
		tb.Fatalf("seed synthetic communication rows: %v", err)
	}

	if _, err := db.Exec(`
WITH RECURSIVE ids(i) AS (
    VALUES(1)
    UNION ALL
    SELECT i + 1 FROM ids WHERE i < ?
)
INSERT INTO ocl_communication_dpohs (
    comlog_id,
    dpoh_first_nm_prenom_tcpd,
    dpoh_last_nm_tcpd,
    institution
)
SELECT
    'COM-' || i,
    'Alex',
    'Smith',
    'House of Commons'
FROM ids;
`, rowCount); err != nil {
		tb.Fatalf("seed synthetic dpoh rows: %v", err)
	}

	if _, err := db.Exec(`
WITH RECURSIVE ids(i) AS (
    VALUES(1)
    UNION ALL
    SELECT i + 1 FROM ids WHERE i < ?
)
INSERT INTO ocl_communication_subject_matters (
    comlog_id,
    subject_code_objet,
    custom_subj_objet_perso
)
SELECT
    'COM-' || i,
    'AGR',
    ''
FROM ids;
`, rowCount); err != nil {
		tb.Fatalf("seed synthetic subject matter rows: %v", err)
	}
}
