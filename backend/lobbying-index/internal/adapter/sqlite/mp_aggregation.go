package sqlite

import (
	"database/sql"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

const (
	DefaultParliament = 45
	DefaultSourceURL  = "https://lobbycanada.gc.ca/en/open-data/"

	window30D = "30d"
	window3M  = "3m"
	window12M = "12m"
	windowAll = "all"
)

type Clock interface {
	Now() time.Time
}

type SystemClock struct{}

func (SystemClock) Now() time.Time { return time.Now().UTC() }

type AggregationRunner struct {
	parliament   int
	quarterStart time.Time
	quarterEnd   time.Time
	fromDate     *time.Time
	toDate       *time.Time
	clock        Clock
	sourceURL    string
}

type AggregationOption func(*AggregationRunner)

func NewAggregationRunner(options ...AggregationOption) *AggregationRunner {
	runner := &AggregationRunner{
		parliament: DefaultParliament,
		clock:      SystemClock{},
		sourceURL:  DefaultSourceURL,
	}
	for _, option := range options {
		option(runner)
	}
	return runner
}

func WithParliament(parliament int) AggregationOption {
	return func(r *AggregationRunner) {
		if parliament > 0 {
			r.parliament = parliament
		}
	}
}

func WithQuarter(start, end time.Time) AggregationOption {
	return func(r *AggregationRunner) {
		r.quarterStart = dateOnly(start)
		r.quarterEnd = dateOnly(end)
	}
}

func WithCommunicationDateRange(from, to *time.Time) AggregationOption {
	return func(r *AggregationRunner) {
		r.fromDate = dateOnlyPtr(from)
		r.toDate = dateOnlyPtr(to)
	}
}

func WithClock(clock Clock) AggregationOption {
	return func(r *AggregationRunner) {
		if clock != nil {
			r.clock = clock
		}
	}
}

func WithSourceURL(sourceURL string) AggregationOption {
	return func(r *AggregationRunner) {
		if strings.TrimSpace(sourceURL) != "" {
			r.sourceURL = strings.TrimSpace(sourceURL)
		}
	}
}

func (r *AggregationRunner) BuildMPLobbyingTables(db *sql.DB) error {
	if db == nil {
		return fmt.Errorf("database is required")
	}
	if err := r.defaultQuarter(db); err != nil {
		return err
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin MP lobbying aggregation: %w", err)
	}
	defer tx.Rollback()

	if _, err := tx.Exec(readModelSchemaSQL); err != nil {
		return fmt.Errorf("create MP lobbying read-model schema: %w", err)
	}

	updatedAt := r.clock.Now().UTC().Format(time.RFC3339)
	if _, err := tx.Exec(refreshTimelineSQL,
		r.parliament,
		dateParam(r.fromDate),
		dateParam(r.toDate),
		updatedAt,
		r.sourceURL,
	); err != nil {
		return fmt.Errorf("refresh MP lobbying timeline entries: %w", err)
	}

	for _, window := range []string{window30D, window3M, window12M, windowAll} {
		if err := r.refreshWindow(tx, window, updatedAt); err != nil {
			return err
		}
	}

	if err := r.refreshCohortAverages(tx, updatedAt); err != nil {
		return err
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit MP lobbying aggregation: %w", err)
	}
	return nil
}

func (r *AggregationRunner) defaultQuarter(db *sql.DB) error {
	if !r.quarterStart.IsZero() && !r.quarterEnd.IsZero() {
		return nil
	}

	var maxDate sql.NullString
	if err := db.QueryRow(`
SELECT MAX(date(NULLIF(NULLIF(CAST(comm_date AS TEXT), 'null'), '')))
FROM ocl_communication_primary
WHERE NULLIF(NULLIF(CAST(comm_date AS TEXT), 'null'), '') IS NOT NULL`).Scan(&maxDate); err != nil {
		return fmt.Errorf("read latest OCL communication date: %w", err)
	}
	if !maxDate.Valid || strings.TrimSpace(maxDate.String) == "" {
		now := r.clock.Now().UTC()
		r.quarterStart = quarterStart(now)
		r.quarterEnd = dateOnly(now)
		return nil
	}

	parsed, err := time.Parse("2006-01-02", maxDate.String)
	if err != nil {
		return fmt.Errorf("parse latest OCL communication date %q: %w", maxDate.String, err)
	}
	r.quarterStart = quarterStart(parsed)
	r.quarterEnd = dateOnly(parsed)
	return nil
}

func (r *AggregationRunner) refreshWindow(tx *sql.Tx, window, updatedAt string) error {
	fromDate := windowStart(window, r.quarterEnd)
	if _, err := tx.Exec(`
DELETE FROM mp_lobbying_summaries
WHERE parliament = ? AND quarter_start = ? AND "window" = ?`,
		r.parliament, formatDate(r.quarterStart), window); err != nil {
		return fmt.Errorf("delete MP lobbying summaries for %s: %w", window, err)
	}

	if _, err := tx.Exec(refreshSummarySQL,
		r.parliament,
		formatDate(r.quarterStart),
		formatDate(r.quarterEnd),
		window,
		dateParam(fromDate),
		updatedAt,
	); err != nil {
		return fmt.Errorf("refresh MP lobbying summaries for %s: %w", window, err)
	}

	if _, err := tx.Exec(`
DELETE FROM mp_lobbying_subject_breakdowns
WHERE parliament = ? AND quarter_start = ? AND "window" = ?`,
		r.parliament, formatDate(r.quarterStart), window); err != nil {
		return fmt.Errorf("delete MP lobbying subject breakdowns for %s: %w", window, err)
	}

	if _, err := tx.Exec(refreshSubjectBreakdownSQL,
		r.parliament,
		formatDate(r.quarterStart),
		formatDate(r.quarterEnd),
		window,
		dateParam(fromDate),
		updatedAt,
	); err != nil {
		return fmt.Errorf("refresh MP lobbying subject breakdowns for %s: %w", window, err)
	}
	return nil
}

func (r *AggregationRunner) refreshCohortAverages(tx *sql.Tx, computedAt string) error {
	if _, err := tx.Exec(`
DELETE FROM lobbying_cohort_averages
WHERE parliament = ?`, r.parliament); err != nil {
		return fmt.Errorf("delete lobbying cohort averages: %w", err)
	}
	if _, err := tx.Exec(refreshCohortAveragesSQL, r.parliament, computedAt); err != nil {
		return fmt.Errorf("refresh lobbying cohort averages: %w", err)
	}
	return nil
}

func windowStart(window string, end time.Time) *time.Time {
	switch window {
	case window30D:
		value := end.AddDate(0, 0, -30)
		return &value
	case window3M:
		value := end.AddDate(0, -3, 0)
		return &value
	case window12M:
		value := end.AddDate(-1, 0, 0)
		return &value
	default:
		return nil
	}
}

func quarterStart(value time.Time) time.Time {
	value = dateOnly(value)
	month := int(value.Month())
	startMonth := time.Month(((month - 1) / 3 * 3) + 1)
	return time.Date(value.Year(), startMonth, 1, 0, 0, 0, 0, time.UTC)
}

func dateOnly(value time.Time) time.Time {
	year, month, day := value.UTC().Date()
	return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
}

func dateOnlyPtr(value *time.Time) *time.Time {
	if value == nil {
		return nil
	}
	date := dateOnly(*value)
	return &date
}

func dateParam(value *time.Time) any {
	if value == nil {
		return nil
	}
	return formatDate(*value)
}

func formatDate(value time.Time) string {
	return dateOnly(value).Format("2006-01-02")
}

const readModelSchemaSQL = `
CREATE TABLE IF NOT EXISTS mp_lobbying_timeline_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    member_id TEXT NOT NULL,
    parliament INTEGER NOT NULL,
    communication_id TEXT NOT NULL,
    communication_date TEXT NOT NULL,
    organization_name TEXT NOT NULL,
    organization_sector TEXT,
    subject_matter TEXT NOT NULL,
    communication_type TEXT NOT NULL CHECK (communication_type IN ('meeting', 'written')),
    bill_number TEXT,
    bill_title TEXT,
    bill_url TEXT,
    bill_mapping_confidence REAL,
    source_url TEXT NOT NULL DEFAULT 'https://lobbycanada.gc.ca/en/open-data/',
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (member_id, parliament, communication_id, subject_matter)
);
CREATE INDEX IF NOT EXISTS mp_lobbying_timeline_member_date_idx
    ON mp_lobbying_timeline_entries (member_id, parliament, communication_date DESC, communication_id DESC);
CREATE INDEX IF NOT EXISTS mp_lobbying_timeline_parliament_date_idx
    ON mp_lobbying_timeline_entries (parliament, communication_date DESC);

CREATE TABLE IF NOT EXISTS mp_lobbying_summaries (
    member_id TEXT NOT NULL,
    parliament INTEGER NOT NULL,
    quarter_start TEXT NOT NULL,
    "window" TEXT NOT NULL CHECK ("window" IN ('30d', '3m', '12m', 'all')),
    total_communication_count INTEGER NOT NULL DEFAULT 0,
    unique_organizations_count INTEGER NOT NULL DEFAULT 0,
    most_frequent_subject_matter TEXT,
    top_organizations TEXT NOT NULL DEFAULT '[]',
    current_parliament_communication_count INTEGER NOT NULL DEFAULT 0,
    previous_parliament_communication_count INTEGER NOT NULL DEFAULT 0,
    party_average_communications NUMERIC NOT NULL DEFAULT 0,
    national_average_communications NUMERIC NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id, parliament, quarter_start, "window")
);
CREATE INDEX IF NOT EXISTS mp_lobbying_summaries_lookup_idx
    ON mp_lobbying_summaries (member_id, parliament, "window", quarter_start DESC);

CREATE TABLE IF NOT EXISTS mp_lobbying_subject_breakdowns (
    member_id TEXT NOT NULL,
    parliament INTEGER NOT NULL,
    quarter_start TEXT NOT NULL,
    "window" TEXT NOT NULL CHECK ("window" IN ('30d', '3m', '12m', 'all')),
    subject_matter TEXT NOT NULL,
    communication_count INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (member_id, parliament, quarter_start, "window", subject_matter)
);
CREATE INDEX IF NOT EXISTS mp_lobbying_subject_breakdowns_lookup_idx
    ON mp_lobbying_subject_breakdowns (member_id, parliament, "window", quarter_start DESC, communication_count DESC);

CREATE TABLE IF NOT EXISTS lobbying_cohort_averages (
    parliament INTEGER NOT NULL,
    party TEXT,
    avg_communications NUMERIC,
    computed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX IF NOT EXISTS lobbying_cohort_averages_unique_idx
    ON lobbying_cohort_averages (parliament, COALESCE(party, '__national__'));
CREATE INDEX IF NOT EXISTS lobbying_cohort_averages_parliament_idx
    ON lobbying_cohort_averages (parliament);
`

const refreshTimelineSQL = `
WITH communication_source AS (
    SELECT
        CAST(cp.comlog_id AS TEXT) AS communication_id,
        COALESCE(NULLIF(CAST(cp.client_org_corp_num AS TEXT), ''), '') AS ocl_organization_id,
        COALESCE(NULLIF(cp.en_client_org_corp_nm_an, 'null'), NULLIF(cp.fr_client_org_corp_nm, 'null'), '') AS organization_name,
        date(NULLIF(NULLIF(CAST(cp.comm_date AS TEXT), 'null'), '')) AS communication_date
    FROM ocl_communication_primary cp
    WHERE NULLIF(NULLIF(CAST(cp.comm_date AS TEXT), 'null'), '') IS NOT NULL
),
matched_candidates AS (
    SELECT
        CAST(m.person_id AS TEXT) AS member_id,
        cs.communication_id,
        cs.communication_date,
        COALESCE(NULLIF(cs.organization_name, ''), 'Unknown organization') AS organization_name,
        COALESCE(NULLIF(smt.smt_en_desc, ''), '') AS organization_sector,
        COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet, 'Unspecified') AS subject_matter,
        ROW_NUMBER() OVER (
            PARTITION BY
                m.person_id,
                cs.communication_id,
                COALESCE(NULLIF(smt.smt_en_desc, ''), csm.subject_code_objet, 'Unspecified')
            ORDER BY cs.communication_date DESC
        ) AS rn
    FROM communication_source cs
    JOIN ocl_communication_dpohs dpoh
        ON CAST(dpoh.comlog_id AS TEXT) = cs.communication_id
    JOIN members m
        -- OCL DPOH rows do not carry a stable MP ID, so the builder uses the
        -- same exact full-name match as the serving-side Postgres query. This
        -- has known false negatives for abbreviations and accents in source data.
        ON lower(trim(COALESCE(m.first_name, '') || ' ' || COALESCE(m.last_name, ''))) =
           lower(trim(COALESCE(dpoh.dpoh_first_nm_prenom_tcpd, '') || ' ' || COALESCE(dpoh.dpoh_last_nm_tcpd, '')))
        AND (m.from_date IS NULL OR date(m.from_date) <= cs.communication_date)
        AND (m.to_date IS NULL OR date(m.to_date) >= cs.communication_date)
    LEFT JOIN ocl_communication_subject_matters csm
        ON CAST(csm.comlog_id AS TEXT) = cs.communication_id
    LEFT JOIN ocl_subject_matter_types smt
        ON smt.subject_code_objet = csm.subject_code_objet
    WHERE (?2 IS NULL OR cs.communication_date >= date(?2))
        AND (?3 IS NULL OR cs.communication_date <= date(?3))
),
matched_communications AS (
    SELECT *
    FROM matched_candidates
    WHERE rn = 1
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
    ?1 AS parliament,
    communication_id,
    communication_date,
    organization_name,
    organization_sector,
    subject_matter,
    'meeting' AS communication_type,
    ?5 AS source_url,
    ?4 AS updated_at
FROM matched_communications
WHERE true
ON CONFLICT(member_id, parliament, communication_id, subject_matter)
DO UPDATE SET
    communication_date = excluded.communication_date,
    organization_name = excluded.organization_name,
    organization_sector = excluded.organization_sector,
    communication_type = excluded.communication_type,
    source_url = excluded.source_url,
    updated_at = excluded.updated_at`

const refreshSummarySQL = `
WITH active_members AS (
    SELECT
        CAST(person_id AS TEXT) AS member_id,
        COALESCE(NULLIF(caucus, ''), 'Unknown') AS party
    FROM members
    WHERE (from_date IS NULL OR date(from_date) <= date(?3))
        AND (to_date IS NULL OR date(to_date) >= date(?2))
),
timeline_members AS (
    SELECT DISTINCT
        t.member_id,
        COALESCE(NULLIF(m.caucus, ''), 'Unknown') AS party
    FROM mp_lobbying_timeline_entries t
    LEFT JOIN members m ON CAST(m.person_id AS TEXT) = t.member_id
    WHERE t.parliament = ?1
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
        COUNT(DISTINCT t.communication_id) AS total_count,
        COUNT(DISTINCT NULLIF(t.organization_name, '')) AS unique_org_count
    FROM cohort
    LEFT JOIN mp_lobbying_timeline_entries t
        ON t.member_id = cohort.member_id
        AND t.parliament = ?1
        AND date(t.communication_date) <= date(?3)
        AND (?5 IS NULL OR date(t.communication_date) >= date(?5))
    GROUP BY cohort.member_id, cohort.party
),
previous_counts AS (
    SELECT
        member_id,
        COUNT(DISTINCT communication_id) AS previous_count
    FROM mp_lobbying_timeline_entries
    WHERE parliament = (?1 - 1)
    GROUP BY member_id
),
subject_counts AS (
    SELECT
        member_id,
        subject_matter,
        COUNT(DISTINCT communication_id) AS subject_count,
        ROW_NUMBER() OVER (
            PARTITION BY member_id
            ORDER BY COUNT(DISTINCT communication_id) DESC, subject_matter ASC
        ) AS subject_rank
    FROM mp_lobbying_timeline_entries
    WHERE parliament = ?1
        AND date(communication_date) <= date(?3)
        AND (?5 IS NULL OR date(communication_date) >= date(?5))
    GROUP BY member_id, subject_matter
),
organization_counts AS (
    SELECT
        member_id,
        organization_name,
        COALESCE(NULLIF(organization_sector, ''), '') AS organization_sector,
        COUNT(DISTINCT communication_id) AS communication_count,
        ROW_NUMBER() OVER (
            PARTITION BY member_id
            ORDER BY COUNT(DISTINCT communication_id) DESC, organization_name ASC
        ) AS organization_rank
    FROM mp_lobbying_timeline_entries
    WHERE parliament = ?1
        AND date(communication_date) <= date(?3)
        AND (?5 IS NULL OR date(communication_date) >= date(?5))
        AND NULLIF(organization_name, '') IS NOT NULL
    GROUP BY member_id, organization_name, COALESCE(NULLIF(organization_sector, ''), '')
),
top_organizations AS (
    SELECT
        member_id,
        json_group_array(json_object(
            'name', organization_name,
            'sector', organization_sector,
            'communication_count', communication_count
        )) AS top_organizations
    FROM (
        SELECT member_id, organization_name, organization_sector, communication_count
        FROM organization_counts
        WHERE organization_rank <= 3
        ORDER BY member_id, communication_count DESC, organization_name ASC
    )
    GROUP BY member_id
),
party_averages AS (
    SELECT party, AVG(total_count) AS party_average
    FROM current_counts
    GROUP BY party
),
national_average AS (
    SELECT COALESCE(AVG(total_count), 0) AS value
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
    ?1 AS parliament,
    ?2 AS quarter_start,
    ?4 AS "window",
    cc.total_count,
    cc.unique_org_count,
    sc.subject_matter,
    COALESCE(tops.top_organizations, '[]'),
    cc.total_count,
    COALESCE(pc.previous_count, 0),
    COALESCE(pa.party_average, 0),
    (SELECT value FROM national_average),
    ?6 AS updated_at
FROM current_counts cc
LEFT JOIN subject_counts sc
    ON sc.member_id = cc.member_id AND sc.subject_rank = 1
LEFT JOIN top_organizations tops ON tops.member_id = cc.member_id
LEFT JOIN previous_counts pc ON pc.member_id = cc.member_id
LEFT JOIN party_averages pa ON pa.party = cc.party
WHERE true
ON CONFLICT(member_id, parliament, quarter_start, "window")
DO UPDATE SET
    total_communication_count = excluded.total_communication_count,
    unique_organizations_count = excluded.unique_organizations_count,
    most_frequent_subject_matter = excluded.most_frequent_subject_matter,
    top_organizations = excluded.top_organizations,
    current_parliament_communication_count = excluded.current_parliament_communication_count,
    previous_parliament_communication_count = excluded.previous_parliament_communication_count,
    party_average_communications = excluded.party_average_communications,
    national_average_communications = excluded.national_average_communications,
    updated_at = excluded.updated_at`

const refreshSubjectBreakdownSQL = `
INSERT INTO mp_lobbying_subject_breakdowns (
    member_id, parliament, quarter_start, "window", subject_matter, communication_count, updated_at
)
SELECT
    member_id,
    parliament,
    ?2 AS quarter_start,
    ?4 AS "window",
    subject_matter,
    COUNT(DISTINCT communication_id) AS communication_count,
    ?6 AS updated_at
FROM mp_lobbying_timeline_entries
WHERE parliament = ?1
    AND date(communication_date) <= date(?3)
    AND (?5 IS NULL OR date(communication_date) >= date(?5))
GROUP BY member_id, parliament, subject_matter
ON CONFLICT(member_id, parliament, quarter_start, "window", subject_matter)
DO UPDATE SET
    communication_count = excluded.communication_count,
    updated_at = excluded.updated_at`

const refreshCohortAveragesSQL = `
WITH current_members AS (
    SELECT
        CAST(person_id AS TEXT) AS member_id,
        caucus AS party
    FROM members
    WHERE person_id IS NOT NULL
        AND person_id <> ''
        AND caucus IS NOT NULL
        AND caucus <> ''
        AND to_date IS NULL
),
known_parties AS (
    SELECT DISTINCT party
    FROM current_members
),
member_totals AS (
    SELECT
        parliament,
        member_id,
        COUNT(DISTINCT communication_id) AS total_communications
    FROM mp_lobbying_timeline_entries
    WHERE parliament = ?1
    GROUP BY parliament, member_id
    HAVING total_communications > 0
),
eligible_totals AS (
    SELECT
        mt.parliament,
        mt.member_id,
        cm.party,
        mt.total_communications
    FROM member_totals mt
    JOIN current_members cm ON cm.member_id = mt.member_id
),
party_rows AS (
    SELECT
        ?1 AS parliament,
        kp.party,
        CASE
            WHEN COUNT(et.total_communications) >= 5 THEN AVG(et.total_communications)
            ELSE NULL
        END AS avg_communications
    FROM known_parties kp
    LEFT JOIN eligible_totals et ON et.party = kp.party
    WHERE EXISTS (SELECT 1 FROM eligible_totals)
    GROUP BY kp.party
),
national_row AS (
    SELECT
        ?1 AS parliament,
        NULL AS party,
        AVG(total_communications) AS avg_communications
    FROM eligible_totals
    HAVING COUNT(*) > 0
)
INSERT INTO lobbying_cohort_averages (
    parliament, party, avg_communications, computed_at
)
SELECT parliament, party, avg_communications, ?2 AS computed_at FROM national_row
UNION ALL
SELECT parliament, party, avg_communications, ?2 AS computed_at FROM party_rows`
