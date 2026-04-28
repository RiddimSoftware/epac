package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

const sampleHansardXML = `<?xml version="1.0" encoding="UTF-8"?>
<House>
  <ExtractedItem Name="ParliamentNumber">44</ExtractedItem>
  <ExtractedItem Name="SessionNumber">1</ExtractedItem>
  <ExtractedItem Name="Date">Monday, November 14, 2022</ExtractedItem>
  <SubjectOfBusiness>
    <SubjectOfBusinessTitle>Question Period</SubjectOfBusinessTitle>
    <Intervention id="11034856">
      <PersonSpeaking>
        <Affiliation DbId="25453">Alice Tremblay</Affiliation>
      </PersonSpeaking>
      <Content>
        <ParaText>Thank you Mr. Speaker. My question is about housing affordability in our communities.</ParaText>
      </Content>
    </Intervention>
    <Intervention id="11034857">
      <PersonSpeaking>
        <Affiliation DbId="25001">Bob Chen</Affiliation>
      </PersonSpeaking>
      <Content>
        <ParaText>I thank the honourable member for the question.</ParaText>
      </Content>
    </Intervention>
  </SubjectOfBusiness>
</House>`

func TestParseHansard(t *testing.T) {
	interventions, err := parseHansard(strings.NewReader(sampleHansardXML), "44-1-HAN100-E.XML")
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 2 {
		t.Fatalf("got %d interventions, want 2", len(interventions))
	}

	first := interventions[0]
	if first.Id != "11034856" {
		t.Errorf("first.Id = %q, want 11034856", first.Id)
	}
	if first.MemberId != "25453" {
		t.Errorf("first.MemberId = %q, want 25453", first.MemberId)
	}
	if first.Speaker != "Alice Tremblay" {
		t.Errorf("first.Speaker = %q, want 'Alice Tremblay'", first.Speaker)
	}
	if first.SubjectTitle != "Question Period" {
		t.Errorf("first.SubjectTitle = %q, want 'Question Period'", first.SubjectTitle)
	}
	if first.InterventionSeq != 0 {
		t.Errorf("first.InterventionSeq = %d, want 0", first.InterventionSeq)
	}
	if first.ParliamentNum != 44 {
		t.Errorf("first.ParliamentNum = %d, want 44", first.ParliamentNum)
	}
	if first.SessionNum != 1 {
		t.Errorf("first.SessionNum = %d, want 1", first.SessionNum)
	}
	if first.Filename != "44-1-HAN100-E.XML" {
		t.Errorf("first.Filename = %q, want '44-1-HAN100-E.XML'", first.Filename)
	}
	if first.SittingDate.IsZero() {
		t.Error("first.SittingDate should not be zero")
	}
	wantDate := time.Date(2022, 11, 14, 0, 0, 0, 0, time.UTC)
	if !first.SittingDate.Equal(wantDate) {
		t.Errorf("first.SittingDate = %v, want %v", first.SittingDate, wantDate)
	}
	if first.WordCount <= 0 {
		t.Errorf("first.WordCount = %d, want > 0", first.WordCount)
	}

	second := interventions[1]
	if second.Id != "11034857" {
		t.Errorf("second.Id = %q, want 11034857", second.Id)
	}
	if second.InterventionSeq != 1 {
		t.Errorf("second.InterventionSeq = %d, want 1", second.InterventionSeq)
	}
	if second.MemberId != "25001" {
		t.Errorf("second.MemberId = %q, want 25001", second.MemberId)
	}
	if second.SubjectTitle != "Question Period" {
		t.Errorf("second.SubjectTitle = %q, want 'Question Period'", second.SubjectTitle)
	}
}

func TestParseHansard_InterventionWithoutContent(t *testing.T) {
	// An intervention with no <Content> block is still parsed;
	// upsertSpeeches filters out empty-content rows before the DB write.
	const xml = `<House>
  <ExtractedItem Name="Date">Friday, September 20, 2024</ExtractedItem>
  <SubjectOfBusiness>
    <SubjectOfBusinessTitle>Statements by Members</SubjectOfBusinessTitle>
    <Intervention id="99999">
      <PersonSpeaking>
        <Affiliation DbId="111">Test Speaker</Affiliation>
      </PersonSpeaking>
    </Intervention>
  </SubjectOfBusiness>
</House>`
	interventions, err := parseHansard(strings.NewReader(xml), "test.XML")
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 1 {
		t.Fatalf("got %d interventions, want 1", len(interventions))
	}
	if interventions[0].Content != "" {
		t.Errorf("expected empty content, got %q", interventions[0].Content)
	}
	if interventions[0].WordCount != 0 {
		t.Errorf("expected word count 0, got %d", interventions[0].WordCount)
	}
}

func TestParseHansard_MultipleSubjects(t *testing.T) {
	const xml = `<House>
  <ExtractedItem Name="Date">Monday, March 4, 2024</ExtractedItem>
  <SubjectOfBusiness>
    <SubjectOfBusinessTitle>Oral Questions</SubjectOfBusinessTitle>
    <Intervention id="1">
      <PersonSpeaking><Affiliation DbId="10">Speaker A</Affiliation></PersonSpeaking>
      <Content><ParaText>First question.</ParaText></Content>
    </Intervention>
  </SubjectOfBusiness>
  <SubjectOfBusiness>
    <SubjectOfBusinessTitle>Adjournment Proceedings</SubjectOfBusinessTitle>
    <Intervention id="2">
      <PersonSpeaking><Affiliation DbId="20">Speaker B</Affiliation></PersonSpeaking>
      <Content><ParaText>Adjournment speech.</ParaText></Content>
    </Intervention>
  </SubjectOfBusiness>
</House>`
	interventions, err := parseHansard(strings.NewReader(xml), "test.XML")
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 2 {
		t.Fatalf("got %d interventions, want 2", len(interventions))
	}
	if interventions[0].SubjectTitle != "Oral Questions" {
		t.Errorf("first subject = %q, want 'Oral Questions'", interventions[0].SubjectTitle)
	}
	if interventions[1].SubjectTitle != "Adjournment Proceedings" {
		t.Errorf("second subject = %q, want 'Adjournment Proceedings'", interventions[1].SubjectTitle)
	}
	// seq resets per subject
	if interventions[0].InterventionSeq != 0 {
		t.Errorf("first seq = %d, want 0", interventions[0].InterventionSeq)
	}
	if interventions[1].InterventionSeq != 0 {
		t.Errorf("second seq = %d, want 0 (resets per subject)", interventions[1].InterventionSeq)
	}
}

func TestHandleRequest_MissingDatabaseURL(t *testing.T) {
	// Ensure DATABASE_URL is unset so HandleRequest returns early without a DB dial.
	os.Unsetenv("DATABASE_URL")
	err := HandleRequest(context.Background())
	if err == nil {
		t.Error("expected error when DATABASE_URL is not set")
	}
}

func TestDownloadAndParse_InvalidURL(t *testing.T) {
	client := &http.Client{}
	_, err := downloadAndParse(client, "://invalid-url", "test.XML")
	if err == nil {
		t.Error("expected error for invalid URL, got nil")
	}
}

func TestDownloadAndParse_OK(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("User-Agent") == "" {
			t.Error("expected User-Agent header")
		}
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(sampleHansardXML))
	}))
	defer srv.Close()

	interventions, err := downloadAndParse(srv.Client(), srv.URL+"/test.XML", "44-1-HAN100-E.XML")
	if err != nil {
		t.Fatalf("downloadAndParse returned error: %v", err)
	}
	if len(interventions) != 2 {
		t.Errorf("got %d interventions, want 2", len(interventions))
	}
}

func TestDownloadAndParse_NotFound(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	interventions, err := downloadAndParse(srv.Client(), srv.URL+"/missing.XML", "test.XML")
	if err != nil {
		t.Fatalf("expected nil error for 404, got: %v", err)
	}
	if interventions != nil {
		t.Errorf("expected nil interventions for 404, got %v", interventions)
	}
}

func TestDownloadAndParse_ServerError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer srv.Close()

	_, err := downloadAndParse(srv.Client(), srv.URL+"/error.XML", "test.XML")
	if err == nil {
		t.Error("expected error for 500 response, got nil")
	}
}

func TestParseHansardDate(t *testing.T) {
	wantUTC := func(year int, month time.Month, day int) time.Time {
		return time.Date(year, month, day, 0, 0, 0, 0, time.UTC)
	}
	cases := []struct {
		input string
		want  time.Time
	}{
		{"Monday, November 14, 2022", wantUTC(2022, 11, 14)},
		{"Tuesday, March 5, 2024", wantUTC(2024, 3, 5)},
		{"Wednesday, January 1, 2025", wantUTC(2025, 1, 1)},
		{"Thursday, June 13, 2019", wantUTC(2019, 6, 13)},
		{"Friday, September 20, 2019", wantUTC(2019, 9, 20)},
		{"Saturday, December 31, 2022", wantUTC(2022, 12, 31)},
		{"Sunday, February 4, 2024", wantUTC(2024, 2, 4)},
		{"November 14, 2022", wantUTC(2022, 11, 14)},
		{"", time.Time{}},
		{"not a date", time.Time{}},
	}
	for _, c := range cases {
		got := parseHansardDate(c.input)
		if !got.Equal(c.want) {
			t.Errorf("parseHansardDate(%q) = %v, want %v", c.input, got, c.want)
		}
	}
}

func TestWordCount(t *testing.T) {
	cases := []struct {
		input string
		want  int
	}{
		{"Hello world", 2},
		{"one", 1},
		{"", 0},
		{"  leading and trailing  ", 3},
		{"one  two  three", 3},
		{"Thank you Mr. Speaker.", 4},
	}
	for _, c := range cases {
		if got := wordCount(c.input); got != c.want {
			t.Errorf("wordCount(%q) = %d, want %d", c.input, got, c.want)
		}
	}
}
