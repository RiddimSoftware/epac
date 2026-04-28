package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

const sampleHansardXML = `<?xml version="1.0" encoding="UTF-8"?>
<Hansard xml:lang="EN" id="13316067">
  <ExtractedInformation>
    <ExtractedItem Name="Date">Tuesday, January 27, 2026</ExtractedItem>
    <ExtractedItem Name="SessionNumber">1</ExtractedItem>
    <ExtractedItem Name="ParliamentNumber">45</ExtractedItem>
  </ExtractedInformation>
  <HansardBody>
    <OrderOfBusiness id="13316072" Rubric="RoutineProceedings">
      <OrderOfBusinessTitle>Routine Proceedings</OrderOfBusinessTitle>
      <SubjectOfBusiness id="13316144">
        <FloorLanguage language="FR">[Translation]</FloorLanguage>
        <SubjectOfBusinessTitle>Fair Representation Act</SubjectOfBusinessTitle>
        <SubjectOfBusinessQualifier>Introduction and first reading</SubjectOfBusinessQualifier>
        <SubjectOfBusinessContent>
          <Intervention Type="Question" id="13316086">
            <PersonSpeaking>
              <Affiliation DbId="318008" Type="2">Heather McPherson (Edmonton Strathcona, NDP)</Affiliation>
            </PersonSpeaking>
            <Content>
              <ParaText id="9120217">moved for leave to introduce Bill <Document DbId="13854949" Type="4">C-259</Document>.</ParaText>
              <ParaText id="9120218">She said: Mr. Speaker, I rise today to table the fair representation act.</ParaText>
            </Content>
          </Intervention>
        </SubjectOfBusinessContent>
      </SubjectOfBusiness>
    </OrderOfBusiness>
  </HansardBody>
</Hansard>`

func TestParseHansardCapturesProvenanceAndLinks(t *testing.T) {
	meta := SourceMetadata{
		URL:          "https://www.ourcommons.ca/Content/House/451/Debates/074/HAN074-E.XML",
		RawXMLPath:   "/archive/45-1-HAN074-E.XML",
		ETag:         `"abc"`,
		LastModified: "Tue, 27 Jan 2026 18:00:00 GMT",
	}
	interventions, err := parseHansard(strings.NewReader(sampleHansardXML), "45-1-HAN074-E.XML", meta)
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 1 {
		t.Fatalf("got %d interventions, want 1", len(interventions))
	}
	got := interventions[0]
	if got.Id != "13316086" {
		t.Errorf("Id = %q, want 13316086", got.Id)
	}
	if got.MemberId != "318008" {
		t.Errorf("MemberId = %q, want 318008", got.MemberId)
	}
	if got.Speaker != "Heather McPherson (Edmonton Strathcona, NDP)" {
		t.Errorf("Speaker = %q", got.Speaker)
	}
	if got.OrderTitle != "Routine Proceedings" {
		t.Errorf("OrderTitle = %q", got.OrderTitle)
	}
	if got.SubjectTitle != "Fair Representation Act" {
		t.Errorf("SubjectTitle = %q", got.SubjectTitle)
	}
	if got.SubjectQualifier != "Introduction and first reading" {
		t.Errorf("SubjectQualifier = %q", got.SubjectQualifier)
	}
	if got.Language != "fr" {
		t.Errorf("Language = %q, want fr", got.Language)
	}
	if got.ParliamentNum != 45 || got.SessionNum != 1 {
		t.Errorf("parliament/session = %d/%d, want 45/1", got.ParliamentNum, got.SessionNum)
	}
	wantDate := time.Date(2026, 1, 27, 0, 0, 0, 0, time.UTC)
	if !got.SittingDate.Equal(wantDate) {
		t.Errorf("SittingDate = %v, want %v", got.SittingDate, wantDate)
	}
	if !reflect.DeepEqual(got.RelatedBillIDs, []string{"13854949"}) {
		t.Errorf("RelatedBillIDs = %v", got.RelatedBillIDs)
	}
	if !reflect.DeepEqual(got.ParagraphIDs, []string{"9120217", "9120218"}) {
		t.Errorf("ParagraphIDs = %v", got.ParagraphIDs)
	}
	if got.SourceURL != meta.URL || got.RawXMLPath != meta.RawXMLPath || got.SourceETag != meta.ETag {
		t.Errorf("source metadata not copied: %+v", got)
	}
}

func TestFetchOrReadArchiveIsIdempotent(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		if r.Header.Get("User-Agent") == "" {
			t.Error("missing User-Agent")
		}
		w.Header().Set("Content-Type", "text/xml")
		w.Header().Set("ETag", `"v1"`)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(sampleHansardXML))
	}))
	defer server.Close()

	cfg := Config{
		ArchiveDir: t.TempDir(),
		BaseURL:    server.URL,
		UserAgent:  defaultUserAgent,
	}
	ref := SittingRef{Session: Session{Parliament: 45, SessionNumber: 1}, Sitting: 74}

	body, meta, downloaded, missing, err := fetchOrReadArchive(context.Background(), server.Client(), cfg, ref)
	if err != nil {
		t.Fatalf("first fetch error: %v", err)
	}
	if missing || !downloaded || len(body) == 0 {
		t.Fatalf("first fetch got downloaded=%v missing=%v len=%d", downloaded, missing, len(body))
	}
	if meta.ETag != `"v1"` {
		t.Errorf("ETag = %q, want v1", meta.ETag)
	}

	body, _, downloaded, missing, err = fetchOrReadArchive(context.Background(), server.Client(), cfg, ref)
	if err != nil {
		t.Fatalf("second fetch error: %v", err)
	}
	if missing || downloaded || len(body) == 0 {
		t.Fatalf("second fetch got downloaded=%v missing=%v len=%d", downloaded, missing, len(body))
	}
	if requests != 1 {
		t.Errorf("server requests = %d, want 1", requests)
	}

	if _, err := os.Stat(filepath.Join(cfg.ArchiveDir, "45-1", "45-1-HAN074-E.XML.json")); err != nil {
		t.Errorf("metadata sidecar missing: %v", err)
	}
}

func TestSessionAndURLFormatting(t *testing.T) {
	sessions, err := parseSessions("43-2,44-1, 45-1")
	if err != nil {
		t.Fatalf("parseSessions error: %v", err)
	}
	want := []Session{{43, 2}, {44, 1}, {45, 1}}
	if !reflect.DeepEqual(sessions, want) {
		t.Errorf("sessions = %+v, want %+v", sessions, want)
	}

	ref := SittingRef{Session: Session{Parliament: 45, SessionNumber: 1}, Sitting: 7}
	if ref.Filename() != "45-1-HAN007-E.XML" {
		t.Errorf("Filename = %q", ref.Filename())
	}
	gotURL := ref.URL("https://www.ourcommons.ca/Content/House")
	wantURL := "https://www.ourcommons.ca/Content/House/451/Debates/007/HAN007-E.XML"
	if gotURL != wantURL {
		t.Errorf("URL = %q, want %q", gotURL, wantURL)
	}
}

func TestFilterByDate(t *testing.T) {
	parse := func(s string) time.Time {
		t.Helper()
		d, err := time.Parse("2006-01-02", s)
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	rows := []Intervention{
		{Id: "old", SittingDate: parse("2021-01-01")},
		{Id: "keep", SittingDate: parse("2025-01-01")},
		{Id: "future", SittingDate: parse("2027-01-01")},
	}
	got := filterByDate(rows, parse("2024-01-01"), parse("2026-01-01"))
	if len(got) != 1 || got[0].Id != "keep" {
		t.Fatalf("filtered rows = %+v", got)
	}
}
