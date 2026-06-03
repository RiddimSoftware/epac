package sqlite

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	"epac/lobbying/internal/usecase"

	_ "modernc.org/sqlite"
)

func TestRepositoryListByOCLCodesReturnsCommunicationsAndRegistrationsPaged(t *testing.T) {
	db := newTestDB(t)
	repo := New(db)

	page, err := repo.ListByOCLCodes(context.Background(), []usecase.OCLTopicMapping{
		{OCLCode: "SMT-44", Confidence: 0.9},
	}, usecase.Pagination{Page: 1, PerPage: 10})
	if err != nil {
		t.Fatalf("ListByOCLCodes: %v", err)
	}
	if page.Total != 2 || len(page.Rows) != 2 {
		t.Fatalf("page = %#v", page)
	}
	if page.Rows[0].Kind != "communication" || page.Rows[0].OCLID != "COM-1" || page.Rows[0].SubjectMatter != "Housing" {
		t.Fatalf("first row = %#v", page.Rows[0])
	}
	if page.Rows[1].Kind != "registration" || page.Rows[1].OCLID != "REG-1" {
		t.Fatalf("second row = %#v", page.Rows[1])
	}
}

func TestRepositoryLoadsMinisterPortfolioAndPrebakedCommunications(t *testing.T) {
	db := newTestDB(t)
	repo := New(db)

	profile, err := repo.LoadMinisterProfile(context.Background(), "m-1")
	if err != nil {
		t.Fatalf("LoadMinisterProfile: %v", err)
	}
	if profile.MinisterName != "Alex Minister" || len(profile.PortfolioPeriods) != 1 || profile.TenureStartDate != "2026-01-01" {
		t.Fatalf("profile = %#v", profile)
	}

	cabinet, err := repo.ListCabinetMinisters(context.Background(), usecase.CabinetMinisterFilter{Parliament: 45, Portfolio: "housing"})
	if err != nil {
		t.Fatalf("ListCabinetMinisters: %v", err)
	}
	if len(cabinet) != 1 || cabinet[0].MemberID != "m-1" {
		t.Fatalf("cabinet = %#v", cabinet)
	}

	comms, err := repo.ListMinisterCommunications(context.Background(), usecase.MinisterCommunicationsFilter{
		MemberID:  "m-1",
		StartDate: "2026-01-01",
		EndDate:   "2026-12-31",
	})
	if err != nil {
		t.Fatalf("ListMinisterCommunications: %v", err)
	}
	if len(comms) != 1 || comms[0].ID != "COM-1" || comms[0].SubjectMatters[0] != "Housing" {
		t.Fatalf("communications = %#v", comms)
	}

	areas, err := repo.ListMandatePolicyAreas(context.Background(), "m-1")
	if err != nil {
		t.Fatalf("ListMandatePolicyAreas: %v", err)
	}
	if len(areas) != 1 || areas[0].EpacTopicSlug != "housing" {
		t.Fatalf("areas = %#v", areas)
	}
}

func TestRepositoryLoadsOrganizationDirectoryAndProfile(t *testing.T) {
	db := newTestDB(t)
	repo := New(db)

	rows, err := repo.BrowseLobbyistOrganizations(context.Background(), application.BrowseLobbyistOrganizationsInput{
		Search:        "housing",
		Sector:        "Housing",
		Limit:         10,
		SortDirection: "desc",
	})
	if err != nil {
		t.Fatalf("BrowseLobbyistOrganizations: %v", err)
	}
	if len(rows) != 1 || rows[0].ID != "ocl:42" || rows[0].CommunicationVolume.CurrentParliament != 8 {
		t.Fatalf("rows = %#v", rows)
	}

	org, err := repo.LoadLobbyistOrganization(context.Background(), "ocl:42")
	if err != nil {
		t.Fatalf("LoadLobbyistOrganization: %v", err)
	}
	if org.Name != "Housing Alliance" || len(org.ActiveSubjectMatters) != 1 || org.ActiveSubjectMatters[0] != "Housing" {
		t.Fatalf("org = %#v", org)
	}
	if len(org.Registrations) != 1 || org.Registrations[0].ID != "REG-1" || org.Registrations[0].Kind != domain.LobbyistKindConsultant {
		t.Fatalf("registrations = %#v", org.Registrations)
	}
	if org.Registrations[0].SourceURL != registrationReportsURL+"REG-1" {
		t.Fatalf("registration source URL = %q", org.Registrations[0].SourceURL)
	}
}

func TestRepositoryLoadsMPLobbyingExposureReadModels(t *testing.T) {
	db := newTestDB(t)
	repo := New(db)

	summary, found, err := repo.LoadMPLobbyingSummary(context.Background(), application.LoadMPLobbyingSummaryInput{
		MemberID:   "m-1",
		Parliament: 45,
		Window:     domain.LobbyingExposureWindow3M,
	})
	if err != nil {
		t.Fatalf("LoadMPLobbyingSummary: %v", err)
	}
	if !found || summary.TotalCommunicationCount != 2 || len(summary.TopOrganizations) != 1 {
		t.Fatalf("summary found=%v value=%#v", found, summary)
	}

	from := mustDate(t, "2026-01-01")
	page, err := repo.ListMPLobbyingTimeline(context.Background(), application.ListMPLobbyingTimelineInput{
		MemberID:   "m-1",
		Parliament: 45,
		FromDate:   &from,
		Page:       1,
		PerPage:    10,
	})
	if err != nil {
		t.Fatalf("ListMPLobbyingTimeline: %v", err)
	}
	if page.Total != 1 || len(page.Rows) != 1 || page.Rows[0].Bill == nil {
		t.Fatalf("timeline = %#v", page)
	}

	subjects, err := repo.ListMPLobbyingSubjectDistribution(context.Background(), application.ListMPLobbyingSubjectDistributionInput{
		MemberID:   "m-1",
		Parliament: 45,
		Window:     domain.LobbyingExposureWindow3M,
	})
	if err != nil {
		t.Fatalf("ListMPLobbyingSubjectDistribution: %v", err)
	}
	if len(subjects) != 1 || subjects[0].SubjectMatter != "Housing" {
		t.Fatalf("subjects = %#v", subjects)
	}
}

func TestRepositoryLoadsBillSubjectContextAndLobbyingCommunications(t *testing.T) {
	db := newTestDB(t)
	repo := New(db)

	ctx, err := repo.LoadBillSubjectContext(context.Background(), "C-1")
	if err != nil {
		t.Fatalf("LoadBillSubjectContext: %v", err)
	}
	if len(ctx.SubjectTags) != 1 || ctx.SubjectTags[0] != "Housing" || ctx.MostRecentReadingDate != "2026-05-01" {
		t.Fatalf("context = %#v", ctx)
	}

	comms, err := repo.ListBillLobbyingCommunications(context.Background(), []usecase.OCLTopicMapping{
		{OCLCode: "SMT-44", Confidence: 1},
	}, usecase.DateWindow{StartDate: "2026-01-01", EndDate: "2026-12-31"})
	if err != nil {
		t.Fatalf("ListBillLobbyingCommunications: %v", err)
	}
	if len(comms) != 1 || comms[0].ID != "COM-1" || comms[0].SubjectMatter != "Housing" {
		t.Fatalf("communications = %#v", comms)
	}
}

func newTestDB(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", "file:sqlite-adapter-test?mode=memory&cache=shared")
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	execScript(t, db, `
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE ocl_subject_matter_types (subject_code_objet TEXT PRIMARY KEY, smt_en_desc TEXT);
CREATE TABLE lobbyist_communications (
	comlog_id TEXT PRIMARY KEY,
	organization_name TEXT,
	registrant_name TEXT,
	registrant_type TEXT,
	communication_date TEXT,
	source_url TEXT
);
CREATE TABLE lobbyist_registrations (
	reg_id TEXT PRIMARY KEY,
	registration_number TEXT,
	organization_name TEXT,
	registrant_type TEXT,
	effective_date TEXT,
	end_date TEXT,
	source_url TEXT
);
CREATE TABLE lobbyist_subject_matters (
	source_type TEXT NOT NULL,
	source_id TEXT NOT NULL,
	ocl_code TEXT NOT NULL,
	PRIMARY KEY (source_type, source_id, ocl_code)
);
CREATE TABLE minister_portfolio_periods (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	member_id TEXT NOT NULL,
	minister_name TEXT NOT NULL,
	first_name TEXT,
	last_name TEXT,
	portfolio_name TEXT NOT NULL,
	start_date TEXT,
	end_date TEXT,
	tenure_start_date TEXT,
	tenure_end_date TEXT,
	parliament_number INTEGER,
	source_url TEXT,
	updated_at TEXT
);
CREATE TABLE minister_mandate_topic_mappings (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	member_id TEXT NOT NULL,
	portfolio_name TEXT,
	epac_topic_slug TEXT NOT NULL,
	confidence REAL NOT NULL,
	source_url TEXT,
	updated_at TEXT
);
CREATE TABLE minister_communications (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	member_id TEXT NOT NULL,
	comlog_id TEXT NOT NULL,
	organization_name TEXT,
	registrant_name TEXT,
	registrant_type TEXT,
	communication_date TEXT,
	subject_matter_codes TEXT NOT NULL DEFAULT '[]',
	source_url TEXT,
	updated_at TEXT
);
CREATE TABLE lobbyist_organizations (
	organization_id TEXT PRIMARY KEY,
	ocl_organization_id TEXT,
	name TEXT NOT NULL,
	type TEXT NOT NULL,
	sector TEXT,
	registered_lobbyists TEXT NOT NULL DEFAULT '[]',
	active_subject_matters INTEGER NOT NULL DEFAULT 0,
	communication_volume_current_parliament INTEGER NOT NULL DEFAULT 0,
	communication_volume_prior_parliament INTEGER NOT NULL DEFAULT 0,
	top_dpohs TEXT NOT NULL DEFAULT '[]',
	registration_status TEXT NOT NULL DEFAULT 'expired',
	registrations TEXT NOT NULL DEFAULT '[]',
	recent_communications TEXT NOT NULL DEFAULT '[]',
	subject_matters TEXT NOT NULL DEFAULT '[]',
	updated_at TEXT
);
CREATE TABLE mp_lobbying_timeline_entries (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	member_id TEXT NOT NULL,
	parliament INTEGER NOT NULL,
	communication_id TEXT NOT NULL,
	communication_date TEXT NOT NULL,
	organization_name TEXT NOT NULL,
	organization_sector TEXT,
	subject_matter TEXT NOT NULL,
	communication_type TEXT NOT NULL,
	bill_number TEXT,
	bill_title TEXT,
	bill_url TEXT,
	bill_mapping_confidence REAL,
	source_url TEXT,
	updated_at TEXT
);
CREATE TABLE mp_lobbying_summaries (
	member_id TEXT NOT NULL,
	parliament INTEGER NOT NULL,
	quarter_start TEXT NOT NULL,
	"window" TEXT NOT NULL,
	total_communication_count INTEGER NOT NULL DEFAULT 0,
	unique_organizations_count INTEGER NOT NULL DEFAULT 0,
	most_frequent_subject_matter TEXT,
	top_organizations TEXT NOT NULL DEFAULT '[]',
	current_parliament_communication_count INTEGER NOT NULL DEFAULT 0,
	previous_parliament_communication_count INTEGER NOT NULL DEFAULT 0,
	party_average_communications NUMERIC NOT NULL DEFAULT 0,
	national_average_communications NUMERIC NOT NULL DEFAULT 0,
	updated_at TEXT NOT NULL
);
CREATE TABLE mp_lobbying_subject_breakdowns (
	member_id TEXT NOT NULL,
	parliament INTEGER NOT NULL,
	quarter_start TEXT NOT NULL,
	"window" TEXT NOT NULL,
	subject_matter TEXT NOT NULL,
	communication_count INTEGER NOT NULL DEFAULT 0,
	updated_at TEXT
);
CREATE TABLE legisinfo_bill_subject_tags (
	legisinfo_id TEXT NOT NULL,
	subject_tag TEXT NOT NULL,
	epac_topic_slug TEXT,
	confidence REAL NOT NULL,
	source_url TEXT,
	updated_at TEXT
);
CREATE TABLE legisinfo_bill_readings (
	legisinfo_id TEXT NOT NULL,
	reading_date TEXT NOT NULL,
	stage_name TEXT NOT NULL,
	source_url TEXT,
	updated_at TEXT
);
INSERT INTO meta (key, value) VALUES ('version', 'v1');
INSERT INTO ocl_subject_matter_types VALUES ('SMT-44', 'Housing');
INSERT INTO lobbyist_communications VALUES ('COM-1', 'Housing Alliance', 'Jane Lobbyist', '1', '2026-05-20', 'https://lobbycanada.gc.ca/en/open-data/');
INSERT INTO lobbyist_registrations VALUES ('REG-1', 'REG-1', 'Housing Alliance', '1', '2026-01-01', NULL, 'https://lobbycanada.gc.ca/en/open-data/');
INSERT INTO lobbyist_subject_matters VALUES ('communication', 'COM-1', 'SMT-44');
INSERT INTO lobbyist_subject_matters VALUES ('registration', 'REG-1', 'SMT-44');
INSERT INTO minister_portfolio_periods (member_id, minister_name, first_name, last_name, portfolio_name, start_date, end_date, tenure_start_date, tenure_end_date, parliament_number)
VALUES ('m-1', 'Alex Minister', 'Alex', 'Minister', 'Minister of Housing', '2026-01-01', NULL, '2026-01-01', NULL, 45);
INSERT INTO minister_mandate_topic_mappings (member_id, epac_topic_slug, confidence) VALUES ('m-1', 'housing', 1.0);
INSERT INTO minister_communications (member_id, comlog_id, organization_name, registrant_name, registrant_type, communication_date, subject_matter_codes, source_url)
VALUES ('m-1', 'COM-1', 'Housing Alliance', 'Jane Lobbyist', '1', '2026-05-20', '["SMT-44"]', 'https://lobbycanada.gc.ca/en/open-data/');
INSERT INTO lobbyist_organizations (
	organization_id, ocl_organization_id, name, type, sector, registered_lobbyists, active_subject_matters,
	communication_volume_current_parliament, communication_volume_prior_parliament, top_dpohs, registration_status,
	registrations, recent_communications, subject_matters, updated_at
) VALUES (
	'ocl:42', '42', 'Housing Alliance', 'association', 'Housing',
	'[{"name":"Jane Lobbyist","kind":"consultant"}]', 1, 8, 5,
	'[{"name":"Alex Minister","institution":"House of Commons","count":3}]',
	'active',
	'[{"source_id":"REG-1","registration_type":"Consultant","effective_date":"2026-01-01"}]',
	'[{"comlog_id":"COM-1","date":"2026-05-20"}]',
	'[{"name":"Housing","communication_count":6,"topic_slug":"housing"}]',
	'2026-06-03T00:00:00Z'
);
INSERT INTO mp_lobbying_summaries VALUES (
	'm-1', 45, '2026-04-01', '3m', 2, 1, 'Housing',
	'[{"name":"Housing Alliance","sector":"Housing","communication_count":2}]',
	2, 1, 1.5, 0.75, '2026-06-03T00:00:00Z'
);
INSERT INTO mp_lobbying_timeline_entries (
	member_id, parliament, communication_id, communication_date, organization_name, organization_sector,
	subject_matter, communication_type, bill_number, bill_title, bill_url, bill_mapping_confidence, source_url
) VALUES (
	'm-1', 45, 'COM-1', '2026-05-20', 'Housing Alliance', 'Housing',
	'Housing', 'meeting', 'C-1', 'Housing bill', 'https://www.parl.ca/legisinfo/en/bill/45-1/c-1', 0.95,
	'https://lobbycanada.gc.ca/en/open-data/'
);
INSERT INTO mp_lobbying_subject_breakdowns VALUES ('m-1', 45, '2026-04-01', '3m', 'Housing', 2, '2026-06-03T00:00:00Z');
INSERT INTO legisinfo_bill_subject_tags VALUES ('C-1', 'Housing', 'housing', 0.95, 'https://www.parl.ca/legisinfo', '2026-06-03T00:00:00Z');
INSERT INTO legisinfo_bill_readings VALUES ('C-1', '2026-05-01', 'First reading', 'https://www.parl.ca/legisinfo', '2026-06-03T00:00:00Z');
`)
	return db
}

func execScript(t *testing.T, db *sql.DB, script string) {
	t.Helper()
	if _, err := db.ExecContext(context.Background(), script); err != nil {
		t.Fatalf("exec schema: %v", err)
	}
}

func mustDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date: %v", err)
	}
	return parsed
}
