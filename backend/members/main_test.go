package main

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	sqliteadapter "epac/members/internal/adapter/sqlite"
	"epac/members/internal/usecase"
	"github.com/aws/aws-lambda-go/events"
	_ "modernc.org/sqlite"
)

func TestHandleRequestReadsSQLiteArtifact(t *testing.T) {
	dir := t.TempDir()
	writeMemberSQLiteUnitFixture(t, dir, []Member{
		{ID: "2269", Name: "Jane Example", Riding: "Ottawa Centre", Province: "ON", Party: "Liberal", SourceURL: "https://www.ourcommons.ca/members/en"},
		{ID: "2270", Name: "Sam Example", Riding: "Vancouver East", Province: "BC", Party: "NDP", SourceURL: "https://www.ourcommons.ca/members/en"},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"province": "Ontario", "party": "liberal"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body MembersResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Members) != 1 || body.Members[0].ID != "2269" {
		t.Fatalf("members = %+v", body.Members)
	}
}

func TestHandleRequestGetsMemberProfile(t *testing.T) {
	dir := t.TempDir()
	writeMemberSQLiteUnitFixture(t, dir, []Member{
		{ID: "2269", Name: "Jane Example", Riding: "Ottawa Centre", Province: "ON", Party: "Liberal", SourceURL: "https://www.ourcommons.ca/members/en"},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		Path: "/api/v1/members/2269",
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body MemberProfileResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Member.ID != "2269" || body.Member.Name != "Jane Example" {
		t.Fatalf("member = %+v", body.Member)
	}
	if len(body.Member.Attendance) != 1 {
		t.Fatalf("attendance = %+v", body.Member.Attendance)
	}
	if body.Member.Biography == nil || body.Member.Biography.Summary != "Jane Example is a former physician." {
		t.Fatalf("biography = %+v", body.Member.Biography)
	}
	if len(body.Member.Biography.YearsServed) != 1 || body.Member.Biography.YearsServed[0].Label != "Ottawa Centre, Ontario" {
		t.Fatalf("years served = %+v", body.Member.Biography.YearsServed)
	}
	if len(body.Member.Biography.PreviousRoles) != 1 || body.Member.Biography.PreviousRoles[0].Organization != "Health" {
		t.Fatalf("previous roles = %+v", body.Member.Biography.PreviousRoles)
	}
	if len(body.Member.Biography.Education) != 1 || body.Member.Biography.Education[0] != "University of Ottawa, MD" {
		t.Fatalf("education = %+v", body.Member.Biography.Education)
	}
	if len(body.Member.Biography.ProfessionalBackground) != 1 || body.Member.Biography.ProfessionalBackground[0] != "Family physician" {
		t.Fatalf("professional background = %+v", body.Member.Biography.ProfessionalBackground)
	}
	if len(body.Member.PMBSponsorships) != 1 || body.Member.PMBSponsorships[0].BillNumber != "C-234" {
		t.Fatalf("pmb sponsorships = %+v", body.Member.PMBSponsorships)
	}
	record := body.Member.Attendance[0]
	if record.SittingDate != "2026-06-01" || record.Present == nil || !*record.Present {
		t.Fatalf("attendance record = %+v", record)
	}
}

func TestHandleRequestFiltersMembers(t *testing.T) {
	dir := t.TempDir()
	writeMemberSQLiteUnitFixture(t, dir, []Member{
		{ID: "1", Name: "Ada Lovelace", Province: "ON", Party: "Liberal"},
		{ID: "2", Name: "Grace Hopper", Province: "BC", Party: "NDP"},
	})
	withLocalIndex(t, dir)

	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{
		QueryStringParameters: map[string]string{"province": "Ontario", "party": "liberal"},
	})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	var body MembersResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Members) != 1 || body.Members[0].ID != "1" {
		t.Fatalf("members = %+v", body.Members)
	}
}

func TestHandleRequestMissingArtifactReturns404(t *testing.T) {
	withLocalIndex(t, t.TempDir())
	resp, err := HandleRequest(context.Background(), events.APIGatewayProxyRequest{})
	if err != nil {
		t.Fatalf("HandleRequest error: %v", err)
	}
	if resp.StatusCode != 404 {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func withLocalIndex(t *testing.T, dir string) {
	t.Helper()
	t.Setenv("EPAC_ARTIFACTS_DIR", dir)
	t.Setenv("MEMBERS_INDEX_PREFIX", "members/v1")
	original := memberData
	memberData = newMembersRuntime(openMembersIndexFromEnv, openSQLiteReadOnly, func(db *sql.DB) usecase.MemberRepository {
		return sqliteadapter.New(db)
	})
	t.Cleanup(func() { memberData = original })
}

func writeMemberSQLiteUnitFixture(t *testing.T, dir string, members []Member) {
	t.Helper()
	path := filepath.Join(dir, "members", "v1", "index.sqlite")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir sqlite fixture: %v", err)
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatalf("open sqlite fixture: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE members (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		riding TEXT NOT NULL DEFAULT '',
		province TEXT NOT NULL DEFAULT '',
		party TEXT NOT NULL DEFAULT '',
		source_url TEXT NOT NULL DEFAULT ''
	)`); err != nil {
		t.Fatalf("create members table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE mp_attendance (
		member_id TEXT NOT NULL,
		sitting_date TEXT NOT NULL,
		status TEXT NOT NULL DEFAULT '',
		present INTEGER,
		source_url TEXT NOT NULL DEFAULT '',
		parliament INTEGER,
		session INTEGER
	)`); err != nil {
		t.Fatalf("create mp attendance table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE member_biographies (
		member_id TEXT PRIMARY KEY,
		summary TEXT NOT NULL DEFAULT '',
		preferred_language TEXT NOT NULL DEFAULT '',
		photo_url TEXT NOT NULL DEFAULT '',
		source_url TEXT NOT NULL DEFAULT '',
		years_served_json TEXT NOT NULL DEFAULT '[]',
		previous_roles_json TEXT NOT NULL DEFAULT '[]',
		education_json TEXT NOT NULL DEFAULT '[]',
		professional_background_json TEXT NOT NULL DEFAULT '[]'
	)`); err != nil {
		t.Fatalf("create member biographies table: %v", err)
	}
	if _, err := db.Exec(`CREATE TABLE pmb_sponsorships (
		member_id TEXT NOT NULL,
		id TEXT NOT NULL,
		bill_number TEXT NOT NULL DEFAULT '',
		title TEXT NOT NULL DEFAULT '',
		relationship TEXT NOT NULL DEFAULT '',
		legis_info_url TEXT NOT NULL DEFAULT ''
	)`); err != nil {
		t.Fatalf("create PMB sponsorships table: %v", err)
	}
	for _, member := range members {
		if _, err := db.Exec(`
			INSERT INTO members (id, name, riding, province, party, source_url)
			VALUES (?, ?, ?, ?, ?, ?)`,
			member.ID, member.Name, member.Riding, member.Province, member.Party, member.SourceURL,
		); err != nil {
			t.Fatalf("insert member fixture: %v", err)
		}
	}
	if _, err := db.Exec(`
		INSERT INTO mp_attendance (member_id, sitting_date, status, present, source_url, parliament, session)
		VALUES ('2269', '2026-06-01', 'present', 1, 'https://www.ourcommons.ca/attendance', 45, 1)`); err != nil {
		t.Fatalf("insert attendance fixture: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO member_biographies (
			member_id, summary, preferred_language, photo_url, source_url,
			years_served_json, previous_roles_json, education_json, professional_background_json
		)
		VALUES (
			'2269',
			'Jane Example is a former physician.',
			'English',
			'https://www.ourcommons.ca/photo.jpg',
			'https://www.ourcommons.ca/Members/en/2269',
			'[{"label":"Ottawa Centre, Ontario","from_date":"2025-04-28"}]',
			'[{"title":"Member","organization":"Health","start_date":"2025-06-01"}]',
			'["University of Ottawa, MD"]',
			'["Family physician"]'
		)`); err != nil {
		t.Fatalf("insert biography fixture: %v", err)
	}
	if _, err := db.Exec(`
		INSERT INTO pmb_sponsorships (member_id, id, bill_number, title, relationship, legis_info_url)
		VALUES ('2269', 'sponsored-c-234', 'C-234', 'Living Donor Recognition Medal Act', 'sponsored', 'https://www.parl.ca/legisinfo/en/bill/45-1/c-234')`); err != nil {
		t.Fatalf("insert PMB sponsorship fixture: %v", err)
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close sqlite fixture: %v", err)
	}
	writeManifest(t, path, "members/v1/index.sqlite")
}

func writeManifest(t *testing.T, sqlitePath, sqliteKey string) {
	t.Helper()
	data, err := os.ReadFile(sqlitePath)
	if err != nil {
		t.Fatalf("read sqlite fixture: %v", err)
	}
	sum := sha256.Sum256(data)
	manifest := fmt.Sprintf(`{"version":"v1","sqlite_key":%q,"sqlite_size_bytes":%d,"sqlite_sha256":"%x"}`, sqliteKey, len(data), sum[:])
	path := filepath.Join(filepath.Dir(sqlitePath), "manifest.json")
	if err := os.WriteFile(path, []byte(manifest), 0o644); err != nil {
		t.Fatalf("write manifest fixture: %v", err)
	}
}
