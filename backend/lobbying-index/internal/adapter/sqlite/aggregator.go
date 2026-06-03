package sqlite

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
)

// Aggregator builds derived organization and bill context tables from raw OCL data in SQLite.
type Aggregator struct{}

func NewAggregator() *Aggregator {
	return &Aggregator{}
}

// AggregateOrganizationTables builds lobbyist_communications, lobbyist_registrations,
// lobbyist_subject_matters, and lobbyist_organizations from raw OCL tables.
func (a *Aggregator) AggregateOrganizationTables(ctx context.Context, databasePath string) error {
	if databasePath == "" {
		databasePath = DefaultDatabasePath
	}
	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()

	if _, err := db.ExecContext(ctx, "PRAGMA foreign_keys = OFF"); err != nil {
		return fmt.Errorf("disable foreign keys: %w", err)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if err := createAggregateSchema(ctx, tx); err != nil {
		return err
	}
	if err := populateCommunications(ctx, tx); err != nil {
		return err
	}
	if err := populateRegistrations(ctx, tx); err != nil {
		return err
	}
	if err := populateSubjectMatters(ctx, tx); err != nil {
		return err
	}
	if err := populateOrganizations(ctx, tx); err != nil {
		return err
	}

	return tx.Commit()
}

// SaveBillContextTables builds legisinfo_bill_subject_tags and legisinfo_bill_readings.
func (a *Aggregator) SaveBillContextTables(ctx context.Context, databasePath string, bills []domain.LegisInfoBill, topicMap []domain.TopicMapping) error {
	if databasePath == "" {
		databasePath = DefaultDatabasePath
	}
	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		return fmt.Errorf("open sqlite: %w", err)
	}
	defer db.Close()

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	if err := createBillSchema(ctx, tx); err != nil {
		return err
	}
	if err := insertBillReadings(ctx, tx, bills); err != nil {
		return err
	}
	if err := insertBillSubjectTags(ctx, tx, bills, topicMap); err != nil {
		return err
	}

	return tx.Commit()
}

func createAggregateSchema(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, aggregateSchemaSQL)
	if err != nil {
		return fmt.Errorf("create aggregate schema: %w", err)
	}
	return nil
}

func createBillSchema(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, billSchemaSQL)
	if err != nil {
		return fmt.Errorf("create bill schema: %w", err)
	}
	return nil
}

func populateCommunications(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO lobbyist_communications (
    comlog_id, organization_name, registrant_name, registrant_type, communication_date, source_url, updated_at
)
SELECT
    comlog_id,
    COALESCE(NULLIF(TRIM(COALESCE(en_client_org_corp_nm_an, '')), ''), NULLIF(TRIM(COALESCE(fr_client_org_corp_nm, '')), ''), ''),
    TRIM(TRIM(COALESCE(rgstrnt_1st_nm_prenom_dclrnt, '')) || ' ' || TRIM(COALESCE(rgstrnt_last_nm_dclrnt, ''))),
    COALESCE(NULLIF(TRIM(COALESCE(reg_type_enr, '')), ''), ''),
    DATE(comm_date),
    'https://lobbycanada.gc.ca/en/open-data/',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
FROM ocl_communication_primary`)
	if err != nil {
		return fmt.Errorf("populate lobbyist_communications: %w", err)
	}
	return nil
}

func populateRegistrations(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO lobbyist_registrations (
    reg_id, registration_number, organization_name, registrant_type, effective_date, end_date, source_url, updated_at
)
SELECT
    reg_id_enr,
    COALESCE(NULLIF(TRIM(COALESCE(client_org_corp_num, '')), ''), reg_id_enr),
    COALESCE(NULLIF(TRIM(COALESCE(en_client_org_corp_nm_an, '')), ''), NULLIF(TRIM(COALESCE(fr_client_org_corp_nm, '')), ''), ''),
    COALESCE(NULLIF(TRIM(COALESCE(reg_type_enr, '')), ''), ''),
    DATE(effective_date_vigueur),
    DATE(end_date_fin),
    'https://lobbycanada.gc.ca/en/open-data/',
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
FROM ocl_registration_primary`)
	if err != nil {
		return fmt.Errorf("populate lobbyist_registrations: %w", err)
	}
	return nil
}

func populateSubjectMatters(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, `
INSERT OR IGNORE INTO lobbyist_subject_matters (source_type, source_id, ocl_code)
SELECT 'communication', comlog_id, subject_code_objet
FROM ocl_communication_subject_matters
WHERE NULLIF(TRIM(subject_code_objet), '') IS NOT NULL`)
	if err != nil {
		return fmt.Errorf("populate communication subject matters: %w", err)
	}
	_, err = tx.ExecContext(ctx, `
INSERT OR IGNORE INTO lobbyist_subject_matters (source_type, source_id, ocl_code)
SELECT 'registration', reg_id_enr, subject_code_objet
FROM ocl_registration_subject_matters
WHERE NULLIF(TRIM(subject_code_objet), '') IS NOT NULL`)
	if err != nil {
		return fmt.Errorf("populate registration subject matters: %w", err)
	}
	return nil
}

func populateOrganizations(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, `
INSERT OR REPLACE INTO lobbyist_organizations (
    organization_id, ocl_organization_id, name, type, sector,
    registered_lobbyists, active_subject_matters,
    communication_volume_current_parliament, communication_volume_prior_parliament,
    top_dpohs, registration_status, registrations, recent_communications,
    subject_matters, updated_at
)
WITH org_base AS (
    SELECT
        COALESCE(NULLIF(TRIM(COALESCE(client_org_corp_num, '')), ''), reg_id_enr) AS org_id,
        COALESCE(NULLIF(TRIM(COALESCE(client_org_corp_num, '')), ''), '') AS ocl_org_id,
        COALESCE(NULLIF(TRIM(COALESCE(en_client_org_corp_nm_an, '')), ''),
                 NULLIF(TRIM(COALESCE(fr_client_org_corp_nm, '')), ''), '') AS org_name,
        COALESCE(NULLIF(TRIM(COALESCE(reg_type_enr, '')), ''), '') AS reg_type,
        effective_date_vigueur AS eff_date,
        end_date_fin AS end_date,
        reg_id_enr,
        client_org_corp_profil_id_profil_client_org_corp AS profile_id
    FROM ocl_registration_primary
),
org_names AS (
    SELECT org_id, MAX(org_name) AS org_name, MAX(ocl_org_id) AS ocl_org_id, MAX(reg_type) AS reg_type
    FROM org_base
    GROUP BY org_id
),
org_status AS (
    SELECT org_id,
        CASE WHEN MAX(CASE WHEN end_date IS NULL OR end_date > strftime('%Y-%m-%dT%H:%M:%SZ', 'now') THEN 1 ELSE 0 END) = 1
             THEN 'active' ELSE 'expired' END AS reg_status
    FROM org_base
    GROUP BY org_id
),
distinct_lobbyists AS (
    SELECT DISTINCT ob.org_id,
        TRIM(TRIM(COALESCE(l.lbbyst_first_nm_prenom_lbbyst, '')) || ' ' || TRIM(COALESCE(l.lbbyst_last_nm_lbbyst, ''))) AS lob_name,
        'in_house' AS lob_kind
    FROM org_base ob
    JOIN ocl_registration_in_house_lobbyists l
        ON l.client_org_corp_profil_id_profil_client_org_corp = ob.profile_id
    WHERE NULLIF(TRIM(TRIM(COALESCE(l.lbbyst_first_nm_prenom_lbbyst, '')) || ' ' || TRIM(COALESCE(l.lbbyst_last_nm_lbbyst, ''))), '') IS NOT NULL
    UNION
    SELECT DISTINCT ob.org_id,
        TRIM(TRIM(COALESCE(l.lbbyst_first_nm_prenom_lbbyst, '')) || ' ' || TRIM(COALESCE(l.lbbyst_last_nm_lbbyst, ''))) AS lob_name,
        'consultant' AS lob_kind
    FROM org_base ob
    JOIN ocl_registration_consultant_lobbyists l
        ON l.client_org_corp_profil_id_profil_client_org_corp = ob.profile_id
    WHERE NULLIF(TRIM(TRIM(COALESCE(l.lbbyst_first_nm_prenom_lbbyst, '')) || ' ' || TRIM(COALESCE(l.lbbyst_last_nm_lbbyst, ''))), '') IS NOT NULL
),
org_lobbyists AS (
    SELECT org_id, json_group_array(json_object('name', lob_name, 'kind', lob_kind)) AS lobbyists_json
    FROM (SELECT * FROM distinct_lobbyists ORDER BY org_id, lob_kind, lob_name)
    GROUP BY org_id
),
distinct_reg_subjects AS (
    SELECT DISTINCT ob.org_id,
        COALESCE(NULLIF(smt.smt_en_desc, ''), rsm.subject_code_objet) AS subject_label,
        rsm.subject_code_objet AS ocl_code
    FROM org_base ob
    JOIN ocl_registration_subject_matters rsm ON rsm.reg_id_enr = ob.reg_id_enr
    LEFT JOIN ocl_subject_matter_types smt ON smt.subject_code_objet = rsm.subject_code_objet
),
org_subject_matters AS (
    SELECT org_id,
        json_group_array(json_object('ocl_code', ocl_code, 'name', subject_label)) AS subject_matters_json,
        COUNT(DISTINCT ocl_code) AS subject_count,
        MIN(subject_label) AS first_subject
    FROM (SELECT * FROM distinct_reg_subjects ORDER BY org_id, subject_label)
    GROUP BY org_id
),
org_registrations AS (
    SELECT ob.org_id,
        json_group_array(json_object(
            'source_id', ob.reg_id_enr,
            'registration_type', ob.reg_type,
            'effective_date', DATE(ob.eff_date),
            'end_date', DATE(ob.end_date)
        )) AS registrations_json
    FROM (SELECT * FROM org_base ORDER BY org_id, eff_date DESC)  ob
    GROUP BY ob.org_id
),
comm_by_org AS (
    SELECT
        COALESCE(NULLIF(TRIM(COALESCE(cp.client_org_corp_num, '')), ''), cp.comlog_id) AS org_id,
        cp.comlog_id,
        cp.comm_date
    FROM ocl_communication_primary cp
),
org_comm_counts AS (
    SELECT org_id,
        SUM(CASE WHEN comm_date >= '2025-05-26' THEN 1 ELSE 0 END) AS vol_current,
        SUM(CASE WHEN comm_date >= '2021-09-20' AND comm_date < '2025-05-26' THEN 1 ELSE 0 END) AS vol_prior
    FROM comm_by_org
    GROUP BY org_id
),
recent_comm_rows AS (
    SELECT DISTINCT org_id, comlog_id, comm_date
    FROM comm_by_org
),
org_recent_comms AS (
    SELECT r.org_id,
        json_group_array(json_object('comlog_id', r.comlog_id, 'date', DATE(r.comm_date))) AS recent_comms_json
    FROM (
        SELECT org_id, comlog_id, comm_date,
            ROW_NUMBER() OVER (PARTITION BY org_id ORDER BY comm_date DESC) AS rn
        FROM recent_comm_rows
    ) r
    WHERE r.rn <= 10
    GROUP BY r.org_id
),
distinct_dpoh_rows AS (
    SELECT DISTINCT
        COALESCE(NULLIF(TRIM(COALESCE(cp.client_org_corp_num, '')), ''), cp.comlog_id) AS org_id,
        TRIM(TRIM(COALESCE(d.dpoh_first_nm_prenom_tcpd, '')) || ' ' || TRIM(COALESCE(d.dpoh_last_nm_tcpd, ''))) AS dpoh_name,
        COALESCE(d.institution, '') AS institution
    FROM ocl_communication_dpohs d
    JOIN ocl_communication_primary cp ON cp.comlog_id = d.comlog_id
    WHERE NULLIF(TRIM(TRIM(COALESCE(d.dpoh_first_nm_prenom_tcpd, '')) || ' ' || TRIM(COALESCE(d.dpoh_last_nm_tcpd, ''))), '') IS NOT NULL
),
dpoh_counts AS (
    SELECT org_id, dpoh_name, institution, COUNT(*) AS cnt
    FROM distinct_dpoh_rows
    GROUP BY org_id, dpoh_name, institution
),
org_top_dpohs AS (
    SELECT org_id,
        json_group_array(json_object('name', dpoh_name, 'institution', institution, 'count', cnt)) AS top_dpohs_json
    FROM (
        SELECT org_id, dpoh_name, institution, cnt,
            ROW_NUMBER() OVER (PARTITION BY org_id ORDER BY cnt DESC, dpoh_name) AS rn
        FROM dpoh_counts
    )
    WHERE rn <= 5
    GROUP BY org_id
)
SELECT
    n.org_id,
    n.ocl_org_id,
    n.org_name,
    CASE
        WHEN n.reg_type LIKE '%Corporation%' THEN 'corporation'
        WHEN n.reg_type LIKE '%Organization%' THEN 'association'
        ELSE 'association'
    END AS org_type,
    COALESCE(sm.first_subject, ''),
    COALESCE(ol.lobbyists_json, '[]'),
    COALESCE(sm.subject_count, 0),
    COALESCE(cc.vol_current, 0),
    COALESCE(cc.vol_prior, 0),
    COALESCE(td.top_dpohs_json, '[]'),
    COALESCE(st.reg_status, 'expired'),
    COALESCE(oreg.registrations_json, '[]'),
    COALESCE(rc.recent_comms_json, '[]'),
    COALESCE(sm.subject_matters_json, '[]'),
    strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
FROM org_names n
LEFT JOIN org_status st ON st.org_id = n.org_id
LEFT JOIN org_lobbyists ol ON ol.org_id = n.org_id
LEFT JOIN org_subject_matters sm ON sm.org_id = n.org_id
LEFT JOIN org_registrations oreg ON oreg.org_id = n.org_id
LEFT JOIN org_comm_counts cc ON cc.org_id = n.org_id
LEFT JOIN org_recent_comms rc ON rc.org_id = n.org_id
LEFT JOIN org_top_dpohs td ON td.org_id = n.org_id
WHERE n.org_name != ''`)
	if err != nil {
		return fmt.Errorf("populate lobbyist_organizations: %w", err)
	}
	return nil
}

func insertBillReadings(ctx context.Context, tx *sql.Tx, bills []domain.LegisInfoBill) error {
	stmt, err := tx.PrepareContext(ctx, `
INSERT OR REPLACE INTO legisinfo_bill_readings (legisinfo_id, reading_date, stage_name, source_url, updated_at)
VALUES (?, ?, ?, 'https://www.parl.ca/legisinfo', ?)`)
	if err != nil {
		return fmt.Errorf("prepare bill readings insert: %w", err)
	}
	defer stmt.Close()

	now := time.Now().UTC().Format(time.RFC3339)
	for _, bill := range bills {
		readings := billReadings(bill)
		for _, r := range readings {
			if _, err := stmt.ExecContext(ctx, bill.Number, r.ReadingDate, r.StageName, now); err != nil {
				return fmt.Errorf("insert bill reading for %s: %w", bill.Number, err)
			}
		}
	}
	return nil
}

func billReadings(bill domain.LegisInfoBill) []domain.LegisInfoReading {
	type stageEntry struct {
		raw  string
		name string
	}
	entries := []stageEntry{
		{bill.PassedHouseFirstReadingDateTime, "House First Reading"},
		{bill.PassedHouseSecondReadingDateTime, "House Second Reading"},
		{bill.PassedHouseThirdReadingDateTime, "House Third Reading"},
		{bill.PassedSenateFirstReadingDateTime, "Senate First Reading"},
		{bill.PassedSenateSecondReadingDateTime, "Senate Second Reading"},
		{bill.PassedSenateThirdReadingDateTime, "Senate Third Reading"},
		{bill.ReceivedRoyalAssentDateTime, "Royal Assent"},
	}

	readings := make([]domain.LegisInfoReading, 0, len(entries))
	for _, e := range entries {
		date := parseReadingDate(e.raw)
		if date == "" {
			continue
		}
		readings = append(readings, domain.LegisInfoReading{
			LegisInfoID: bill.Number,
			ReadingDate: date,
			StageName:   e.name,
		})
	}
	return readings
}

func parseReadingDate(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	for _, layout := range []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05.9",
		"2006-01-02T15:04:05",
		"2006-01-02",
	} {
		if t, err := time.Parse(layout, raw); err == nil {
			return t.Format("2006-01-02")
		}
	}
	return ""
}

// titleKeywords maps lowercase keywords found in bill titles to epac topic slugs.
var titleKeywords = []struct {
	keyword string
	slug    string
}{
	{"indigenous", "indigenous"},
	{"first nation", "indigenous"},
	{"aboriginal", "indigenous"},
	{"métis", "indigenous"},
	{"inuit", "indigenous"},
	{"health", "healthcare"},
	{"climat", "climate"},
	{"environment", "climate"},
	{"housing", "housing"},
	{"immigra", "immigration"},
	{"citizen", "immigration"},
	{"agricultur", "agriculture"},
	{"farm", "agriculture"},
	{"defence", "defence"},
	{"defense", "defence"},
	{"military", "defence"},
	{"armed forces", "defence"},
	{"energy", "energy"},
	{"electricity", "energy"},
	{"nuclear", "energy"},
	{"petroleum", "energy"},
	{"labour", "labour"},
	{"labor", "labour"},
	{"worker", "labour"},
	{"employment", "labour"},
	{"transport", "transport"},
	{"railway", "transport"},
	{"aviation", "transport"},
	{"airport", "transport"},
	{"trade", "trade"},
	{"commerce", "trade"},
	{"tariff", "trade"},
	{"import", "trade"},
	{"export", "trade"},
	{"justice", "justice"},
	{"criminal", "justice"},
	{"penal", "justice"},
	{"digital", "digital"},
	{"cyber", "digital"},
	{"internet", "digital"},
	{"data protection", "digital"},
	{"education", "education"},
	{"school", "education"},
	{"university", "education"},
	{"senior", "seniors"},
	{"pension", "seniors"},
	{"retirement", "seniors"},
	{"child care", "childcare"},
	{"childcare", "childcare"},
	{"daycare", "childcare"},
	{"tax", "taxation"},
	{"revenue", "taxation"},
	{"mineral", "naturalresources"},
	{"mining", "naturalresources"},
	{"forestry", "naturalresources"},
	{"natural resource", "naturalresources"},
	{"foreign", "foreign"},
	{"international", "foreign"},
	{"diplomatic", "foreign"},
}

func insertBillSubjectTags(ctx context.Context, tx *sql.Tx, bills []domain.LegisInfoBill, topicMap []domain.TopicMapping) error {
	// Build slug → confidence lookup from topic map (first match wins per slug).
	slugConfidence := make(map[string]float64, len(topicMap))
	for _, tm := range topicMap {
		if _, exists := slugConfidence[tm.EpacTopicSlug]; !exists {
			slugConfidence[tm.EpacTopicSlug] = tm.Confidence
		}
	}

	stmt, err := tx.PrepareContext(ctx, `
INSERT OR IGNORE INTO legisinfo_bill_subject_tags (legisinfo_id, subject_tag, epac_topic_slug, confidence, source_url, updated_at)
VALUES (?, ?, ?, ?, 'https://www.parl.ca/legisinfo', ?)`)
	if err != nil {
		return fmt.Errorf("prepare bill subject tags insert: %w", err)
	}
	defer stmt.Close()

	now := time.Now().UTC().Format(time.RFC3339)
	for _, bill := range bills {
		title := strings.ToLower(bill.LongTitleEn)
		seen := make(map[string]bool)
		for _, kw := range titleKeywords {
			if !strings.Contains(title, kw.keyword) {
				continue
			}
			slug := kw.slug
			if seen[slug] {
				continue
			}
			seen[slug] = true
			conf := slugConfidence[slug]
			if conf == 0 {
				conf = 0.85
			}
			if _, err := stmt.ExecContext(ctx, bill.Number, kw.keyword, slug, conf, now); err != nil {
				return fmt.Errorf("insert bill subject tag for %s: %w", bill.Number, err)
			}
		}
	}
	return nil
}

const aggregateSchemaSQL = `
CREATE TABLE IF NOT EXISTS lobbyist_communications (
    comlog_id         TEXT PRIMARY KEY,
    organization_name TEXT,
    registrant_name   TEXT,
    registrant_type   TEXT,
    communication_date TEXT,
    source_url        TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS lobbyist_registrations (
    reg_id              TEXT PRIMARY KEY,
    registration_number TEXT,
    organization_name   TEXT,
    registrant_type     TEXT,
    effective_date      TEXT,
    end_date            TEXT,
    source_url          TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at          TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE TABLE IF NOT EXISTS lobbyist_subject_matters (
    source_type TEXT NOT NULL CHECK(source_type IN ('communication', 'registration')),
    source_id   TEXT NOT NULL,
    ocl_code    TEXT NOT NULL,
    PRIMARY KEY (source_type, source_id, ocl_code)
);

CREATE INDEX IF NOT EXISTS lobbyist_subject_matters_topic_idx
    ON lobbyist_subject_matters (ocl_code, source_type, source_id);

CREATE INDEX IF NOT EXISTS lobbyist_subject_matters_source_idx
    ON lobbyist_subject_matters (source_type, source_id);

CREATE TABLE IF NOT EXISTS lobbyist_organizations (
    organization_id                    TEXT PRIMARY KEY,
    ocl_organization_id                TEXT,
    name                               TEXT NOT NULL,
    type                               TEXT NOT NULL DEFAULT '',
    sector                             TEXT,
    registered_lobbyists               TEXT NOT NULL DEFAULT '[]',
    active_subject_matters             INTEGER NOT NULL DEFAULT 0,
    communication_volume_current_parliament  INTEGER NOT NULL DEFAULT 0,
    communication_volume_prior_parliament    INTEGER NOT NULL DEFAULT 0,
    top_dpohs                          TEXT NOT NULL DEFAULT '[]',
    registration_status                TEXT NOT NULL DEFAULT 'expired' CHECK(registration_status IN ('active', 'expired')),
    registrations                      TEXT NOT NULL DEFAULT '[]',
    recent_communications              TEXT NOT NULL DEFAULT '[]',
    subject_matters                    TEXT NOT NULL DEFAULT '[]',
    updated_at                         TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))
);

CREATE INDEX IF NOT EXISTS lobbyist_organizations_vol_idx
    ON lobbyist_organizations (communication_volume_current_parliament DESC, name ASC);
`

const billSchemaSQL = `
CREATE TABLE IF NOT EXISTS legisinfo_bill_subject_tags (
    legisinfo_id  TEXT NOT NULL,
    subject_tag   TEXT NOT NULL,
    epac_topic_slug TEXT,
    confidence    REAL NOT NULL DEFAULT 1.0
        CHECK (confidence >= 0 AND confidence <= 1),
    source_url    TEXT NOT NULL DEFAULT 'https://www.parl.ca/legisinfo',
    updated_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    PRIMARY KEY (legisinfo_id, subject_tag)
);

CREATE INDEX IF NOT EXISTS legisinfo_bill_subject_tags_topic_idx
    ON legisinfo_bill_subject_tags (legisinfo_id, epac_topic_slug)
    WHERE epac_topic_slug IS NOT NULL;

CREATE TABLE IF NOT EXISTS legisinfo_bill_readings (
    legisinfo_id TEXT NOT NULL,
    reading_date TEXT NOT NULL,
    stage_name   TEXT NOT NULL DEFAULT '',
    source_url   TEXT NOT NULL DEFAULT 'https://www.parl.ca/legisinfo',
    updated_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
    PRIMARY KEY (legisinfo_id, reading_date, stage_name)
);

CREATE INDEX IF NOT EXISTS legisinfo_bill_readings_latest_idx
    ON legisinfo_bill_readings (legisinfo_id, reading_date DESC);
`
