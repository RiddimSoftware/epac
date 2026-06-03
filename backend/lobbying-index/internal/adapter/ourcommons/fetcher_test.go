package ourcommons

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestFetcher_ParsesFixtureXML(t *testing.T) {
	payload := `<ArrayOfMemberOfParliament xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><MemberOfParliament><PersonId>1</PersonId><PersonShortHonorific>Hon.</PersonShortHonorific><PersonOfficialFirstName>Anne</PersonOfficialFirstName><PersonOfficialLastName>Tester</PersonOfficialLastName><ConstituencyName>Riding</ConstituencyName><ConstituencyProvinceTerritoryName>Ontario</ConstituencyProvinceTerritoryName><CaucusShortName>Liberal</CaucusShortName><FromDateTime>2026-01-01T00:00:00</FromDateTime><ToDateTime xsi:nil="true" /></MemberOfParliament><MemberOfParliament><PersonId>2</PersonId><PersonShortHonorific /><PersonOfficialFirstName>Bob</PersonOfficialFirstName><PersonOfficialLastName>Writer</PersonOfficialLastName><ConstituencyName>City</ConstituencyName><ConstituencyProvinceTerritoryName>Alberta</ConstituencyProvinceTerritoryName><CaucusShortName>Conservative</CaucusShortName><FromDateTime>2026-01-15T00:00:00</FromDateTime><ToDateTime xsi:nil="true" /></MemberOfParliament></ArrayOfMemberOfParliament>`

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(payload))
	}))
	defer srv.Close()

	fetcher := NewFetcher(WithHTTPClient(srv.Client()), WithURL(srv.URL))
	members, err := fetcher.FetchMembers(context.Background())
	if err != nil {
		t.Fatalf("fetch members: %v", err)
	}

	if got, want := len(members), 2; got != want {
		t.Fatalf("unexpected members count: got %d want %d", got, want)
	}
	if got, want := members[0].PersonID, "1"; got != want {
		t.Fatalf("unexpected person id: got %s want %s", got, want)
	}
	if got, want := members[1].FirstName, ptr("Bob"); got == nil || *got != *want {
		t.Fatalf("unexpected member first name")
	}
	if members[0].FromDate == nil || members[0].FromDate.UTC() != time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC) {
		t.Fatalf("unexpected from date")
	}
}

func TestFetcher_Integration(t *testing.T) {
	if strings.TrimSpace(os.Getenv("OCL_INTEGRATION")) != "1" {
		t.Skip("OCL_INTEGRATION not set")
	}

	fetcher := NewFetcher()
	members, err := fetcher.FetchMembers(context.Background())
	if err != nil {
		t.Fatalf("fetch members: %v", err)
	}
	if len(members) == 0 {
		t.Fatalf("expected members rows")
	}
}

func ptr(value string) *string {
	v := strings.TrimSpace(value)
	return &v
}
