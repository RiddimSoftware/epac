package ocl

import (
	"archive/zip"
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
)

func TestFetcher_ParsesFixtureZips(t *testing.T) {
	commZip := buildFixtureZip(map[string]string{
		"Communication_PrimaryExport.csv": `"COMLOG_ID","CLIENT_ORG_CORP_NUM","EN_CLIENT_ORG_CRP_NM_AN","FR_CLIENT_ORG_CRP_NM","RGSTRNT_1ST_NM_PRENOM_DCLRNT","RGSTRNT_LAST_NM_DCLRNT","REG_TYPE_ENR","COMM_DATE"
"1","111","Alpha","Alpha FR","Jane","Doe","2","2026-06-03"
"2","222","Beta","Beta FR","null","Smith","1","null"`,
		"Communication_DpohExport.csv": `"COMLOG_ID","DPOH_LAST_NM_TCPD","DPOH_FIRST_NM_PRENOM_TCPD","INSTITUTION"
"1","Contact","John","Treasury"`,
		"Communication_SubjectMattersExport.csv": `"COMLOG_ID","SUBJECT_CODE_OBJET","CUSTOM_SUBJ_OBJET_PERSO"
"1","SMT-14",""`,
	})
	regZip := buildFixtureZip(map[string]string{
		"Registration_PrimaryExport.csv": `"REG_ID_ENR","REG_TYPE_ENR","CLIENT_ORG_CORP_NUM","EN_CLIENT_ORG_CORP_NM_AN","FR_CLIENT_ORG_CORP_NM","CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","EFFECTIVE_DATE_VIGUEUR","END_DATE_FIN"
"9","1","333","Gamma","Gamma FR","444","2026-01-01","2026-06-30"`,
		"Registration_SubjectMattersExport.csv": `"REG_ID_ENR","SUBJECT_CODE_OBJET","CUSTOM_SUBJ_OBJET_PERSO"
"9","SMT-14",""`,
		"Registration_InHouseLobbyistsExport.csv": `"CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","LBBYST_ID_LBBYST","LBBYST_1ST_NM_PRENOM_LBBYST","LBBYST_LAST_NM_LBBYST"
"444","1","Aiden","House"`,
		"Registration_ConsultantLobbyistsExport.csv": `"CLIENT_ORG_CORP_PROFIL_ID_PROFIL_CLIENT_ORG_CORP","LBBYST_ID_LBBYST","LBBYST_1ST_NM_PRENOM_LBBYST","LBBYST_LAST_NM_LBBYST"
"444","2","Bea","Consult"`,
	})

	commServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(commZip)
	}))
	defer commServer.Close()
	regServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write(regZip)
	}))
	defer regServer.Close()

	fetcher := NewFetcher(
		WithHTTPClient(commServer.Client()),
		WithCommunicationZipURL(commServer.URL),
		WithRegistrationZipURL(regServer.URL),
	)

	data, err := fetcher.FetchOCLData(context.Background())
	if err != nil {
		t.Fatalf("fetch data: %v", err)
	}

	if got, want := len(data.CommunicationsPrimary), 2; got != want {
		t.Fatalf("unexpected communication primary rows: got %d want %d", got, want)
	}
	if got, want := len(data.CommunicationsDPOHs), 1; got != want {
		t.Fatalf("unexpected dpoh rows: got %d want %d", got, want)
	}
	if got, want := len(data.CommunicationsSubjectMatters), 1; got != want {
		t.Fatalf("unexpected communication subject rows: got %d want %d", got, want)
	}
	if got, want := len(data.RegistrationPrimary), 1; got != want {
		t.Fatalf("unexpected registration primary rows: got %d want %d", got, want)
	}
	if got, want := len(data.RegistrationSubjectMatters), 1; got != want {
		t.Fatalf("unexpected registration subject rows: got %d want %d", got, want)
	}
	if got, want := len(data.RegistrationInHouseLobbyists), 1; got != want {
		t.Fatalf("unexpected in-house lobbyist rows: got %d want %d", got, want)
	}
	if got, want := len(data.RegistrationConsultantLobbyists), 1; got != want {
		t.Fatalf("unexpected consultant lobbyist rows: got %d want %d", got, want)
	}

	if data.CommunicationsDPOHs[0].FirstName == nil || *data.CommunicationsDPOHs[0].FirstName != "John" {
		t.Fatalf("expected first name parsed as John")
	}
	if data.RegistrationInHouseLobbyists[0].LbbystLastNm == nil || *data.RegistrationInHouseLobbyists[0].LbbystLastNm != "House" {
		t.Fatalf("expected in-house lobbyist last name parsed as House")
	}
}

func buildFixtureZip(files map[string]string) []byte {
	var buffer bytes.Buffer
	writer := zip.NewWriter(&buffer)
	for name, content := range files {
		entry, err := writer.Create(name)
		if err != nil {
			panic(err)
		}
		_, _ = entry.Write([]byte(content))
	}
	if err := writer.Close(); err != nil {
		panic(err)
	}
	return buffer.Bytes()
}

func TestFetcher_Integration(t *testing.T) {
	if os.Getenv("OCL_INTEGRATION") != "1" {
		t.Skip("OCL_INTEGRATION not set")
	}

	fetcher := NewFetcher()
	batch, err := fetcher.FetchOCLData(context.Background())
	if err != nil {
		t.Fatalf("fetch ocl data: %v", err)
	}
	if len(batch.CommunicationsPrimary) == 0 {
		t.Fatalf("expected communication rows")
	}
}
