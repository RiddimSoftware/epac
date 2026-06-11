package main

import (
	"archive/zip"
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
)

func TestAcceptanceBuildsBillsAndMembersSQLiteIndex(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "lobbying-index.sqlite")
	installAcceptanceTransport(t)

	cfg := &runtimeConfig{
		dbPath:     dbPath,
		parliament: 45,
		session:    1,
	}

	if err := ingestOCLData(context.Background(), cfg); err != nil {
		t.Fatalf("ingestOCLData: %v", err)
	}
	if err := buildBillContextTables(context.Background(), cfg); err != nil {
		t.Fatalf("buildBillContextTables: %v", err)
	}

	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("open sqlite: %v", err)
	}
	defer db.Close()

	var quickCheck string
	if err := db.QueryRow("PRAGMA quick_check").Scan(&quickCheck); err != nil {
		t.Fatalf("quick_check: %v", err)
	}
	if quickCheck != "ok" {
		t.Fatalf("quick_check = %q, want ok", quickCheck)
	}

	var firstName, lastName, caucus string
	if err := db.QueryRow(`
SELECT first_name, last_name, caucus
FROM members
WHERE person_id = '278707'`).Scan(&firstName, &lastName, &caucus); err != nil {
		t.Fatalf("query member mapping: %v", err)
	}
	if firstName != "Ada" || lastName != "Example" || caucus != "Liberal" {
		t.Fatalf("member mapping = %q %q %q", firstName, lastName, caucus)
	}

	var stageName, slug string
	if err := db.QueryRow(`
SELECT stage_name
FROM legisinfo_bill_readings
WHERE legisinfo_id = 'C-44' AND reading_date = '2026-05-01'`).Scan(&stageName); err != nil {
		t.Fatalf("query bill reading by bill number: %v", err)
	}
	if stageName != "House First Reading" {
		t.Fatalf("stage_name = %q, want House First Reading", stageName)
	}
	if err := db.QueryRow(`
SELECT epac_topic_slug
FROM legisinfo_bill_subject_tags
WHERE legisinfo_id = 'C-44' AND subject_tag = 'housing'`).Scan(&slug); err != nil {
		t.Fatalf("query bill subject tag by bill number: %v", err)
	}
	if slug != "housing" {
		t.Fatalf("epac_topic_slug = %q, want housing", slug)
	}
}

func installAcceptanceTransport(t *testing.T) {
	t.Helper()

	communicationsZip := acceptanceZip(t, map[string]string{
		"Communication_PrimaryExport.csv": `"COMLOG_ID","CLIENT_ORG_CORP_NUM","EN_CLIENT_ORG_CRP_NM_AN","FR_CLIENT_ORG_CRP_NM","RGSTRNT_1ST_NM_PRENOM_DCLRNT","RGSTRNT_LAST_NM_DCLRNT","REG_TYPE_ENR","COMM_DATE"
"COM-1","ORG-44","Housing Alliance","","Riley","Stone","In-house (Organization)","2026-05-03"`,
		"Communication_DpohExport.csv": `"COMLOG_ID","DPOH_LAST_NM_TCPD","DPOH_FIRST_NM_PRENOM_TCPD","INSTITUTION"
"COM-1","Example","Ada","House of Commons"`,
		"Communication_SubjectMattersExport.csv": `"COMLOG_ID","SUBJECT_CODE_OBJET","CUSTOM_SUBJ_OBJET_PERSO"
"COM-1","SMT-44",""`,
	})
	registrationsZip := acceptanceZip(t, map[string]string{
		"Registration_PrimaryExport.csv": `"REG_ID_ENR","REG_TYPE_ENR","CLIENT_ORG_CORP_NUM","EN_CLIENT_ORG_CORP_NM_AN","FR_CLIENT_ORG_CORP_NM","CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","EFFECTIVE_DATE_VIGUEUR","END_DATE_FIN"
"REG-44","In-house (Organization)","ORG-44","Housing Alliance","","PROFILE-44","2026-01-01",""`,
		"Registration_SubjectMattersExport.csv": `"REG_ID_ENR","SUBJECT_CODE_OBJET","CUSTOM_SUBJ_OBJET_PERSO"
"REG-44","SMT-44",""`,
		"Registration_InHouseLobbyistsExport.csv": `"CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","LBBYST_ID_LBBYST","LBBYST_1ST_NM_PRENOM_LBBYST","LBBYST_LAST_NM_LBBYST"
"PROFILE-44","LOB-1","Riley","Stone"`,
		"Registration_ConsultantLobbyistsExport.csv": `"CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","LBBYST_ID_LBBYST","LBBYST_1ST_NM_PRENOM_LBBYST","LBBYST_LAST_NM_LBBYST"
`,
	})
	membersXML := `<ArrayOfMemberOfParliament>
<MemberOfParliament>
<PersonId>278707</PersonId>
<PersonShortHonorific>Hon.</PersonShortHonorific>
<PersonOfficialFirstName>Ada</PersonOfficialFirstName>
<PersonOfficialLastName>Example</PersonOfficialLastName>
<ConstituencyName>Ottawa Centre</ConstituencyName>
<ConstituencyProvinceTerritoryName>Ontario</ConstituencyProvinceTerritoryName>
<CaucusShortName>Liberal</CaucusShortName>
<FromDateTime>2025-05-26T00:00:00</FromDateTime>
<ToDateTime></ToDateTime>
</MemberOfParliament>
</ArrayOfMemberOfParliament>`
	subjectHTML := `<html><body><table><tr><td>Housing</td><td><a href="/x?adv_2001_subjectMatter=SMT-44">Housing</a></td></tr></table></body></html>`
	billsJSON := `[{
		"BillNumberFormatted": "C-44",
		"ParliamentNumber": 45,
		"SessionNumber": 1,
		"LongTitleEn": "An Act respecting housing affordability",
		"BillTypeEn": "Government Bill",
		"PassedHouseFirstReadingDateTime": "2026-05-01T14:30:00"
	}]`

	originalTransport := http.DefaultTransport
	http.DefaultTransport = acceptanceTransport{responses: map[string][]byte{
		"lobbycanada.gc.ca/media/mqbbmaqk/communications_ocl_cal.zip":                communicationsZip,
		"lobbycanada.gc.ca/media/zwcjycef/registrations_enregistrements_ocl_cal.zip": registrationsZip,
		"www.ourcommons.ca/Members/en/search/XML":                                    []byte(membersXML),
		"lobbycanada.gc.ca/app/secure/ocl/lrs/do/regSms?lang=eng":                    []byte(subjectHTML),
		"lobbycanada.gc.ca/app/secure/ocl/lrs/do/regSms?lang=fra":                    []byte(subjectHTML),
		"www.parl.ca/legisinfo/en/bills/json?parlsession=45-1&load=yes":              []byte(billsJSON),
	}}
	t.Cleanup(func() {
		http.DefaultTransport = originalTransport
	})
}

type acceptanceTransport struct {
	responses map[string][]byte
}

func (t acceptanceTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	key := req.URL.Host + req.URL.Path
	if req.URL.RawQuery != "" &&
		(strings.HasPrefix(key, "lobbycanada.gc.ca/app/secure/ocl/lrs/do/regSms") ||
			strings.HasPrefix(key, "www.parl.ca/legisinfo/en/bills/json")) {
		key += "?" + req.URL.RawQuery
	}
	body, ok := t.responses[key]
	if !ok {
		return nil, fmt.Errorf("unexpected acceptance fixture request: %s", req.URL.String())
	}
	return &http.Response{
		StatusCode: http.StatusOK,
		Status:     "200 OK",
		Header:     make(http.Header),
		Body:       io.NopCloser(bytes.NewReader(body)),
		Request:    req,
	}, nil
}

func acceptanceZip(t *testing.T, files map[string]string) []byte {
	t.Helper()

	var buffer bytes.Buffer
	writer := zip.NewWriter(&buffer)
	for name, content := range files {
		entry, err := writer.Create(name)
		if err != nil {
			t.Fatalf("create zip entry %s: %v", name, err)
		}
		if _, err := entry.Write([]byte(content)); err != nil {
			t.Fatalf("write zip entry %s: %v", name, err)
		}
	}
	if err := writer.Close(); err != nil {
		t.Fatalf("close zip: %v", err)
	}
	return buffer.Bytes()
}
