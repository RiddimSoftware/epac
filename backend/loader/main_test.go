package main

import (
	"encoding/xml"
	"strings"
	"testing"
	"time"
)

const sampleHansardXML = `<?xml version="1.0" encoding="UTF-8"?>
<House>
  <ExtractedItem Name="ParliamentNumber">44</ExtractedItem>
  <ExtractedItem Name="SessionNumber">1</ExtractedItem>
  <ExtractedItem Name="Date">Tuesday, February 7, 2023</ExtractedItem>
  <SubjectOfBusiness>
    <SubjectOfBusinessTitle>Oral Questions</SubjectOfBusinessTitle>
    <Intervention id="11050001">
      <PersonSpeaking>
        <Affiliation DbId="30001">Alice Tremblay</Affiliation>
      </PersonSpeaking>
      <Content>
        <ParaText>Mr. Speaker, my question concerns infrastructure funding for rural communities.</ParaText>
      </Content>
    </Intervention>
    <Intervention id="11050002">
      <PersonSpeaking>
        <Affiliation DbId="30002">Bob Chen</Affiliation>
      </PersonSpeaking>
      <Content>
        <ParaText>I thank the member for the question about infrastructure.</ParaText>
      </Content>
    </Intervention>
  </SubjectOfBusiness>
</House>`

func TestParseHansard(t *testing.T) {
	interventions, err := parseHansard(strings.NewReader(sampleHansardXML), "44-1-HAN200-E.XML")
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 2 {
		t.Fatalf("got %d interventions, want 2", len(interventions))
	}

	first := interventions[0]
	if first.Id != "11050001" {
		t.Errorf("first.Id = %q, want 11050001", first.Id)
	}
	if first.MemberId != "30001" {
		t.Errorf("first.MemberId = %q, want 30001", first.MemberId)
	}
	if first.Speaker != "Alice Tremblay" {
		t.Errorf("first.Speaker = %q, want 'Alice Tremblay'", first.Speaker)
	}
	if first.SubjectTitle != "Oral Questions" {
		t.Errorf("first.SubjectTitle = %q, want 'Oral Questions'", first.SubjectTitle)
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
	if first.Filename != "44-1-HAN200-E.XML" {
		t.Errorf("first.Filename = %q, want '44-1-HAN200-E.XML'", first.Filename)
	}
	wantDate := time.Date(2023, 2, 7, 0, 0, 0, 0, time.UTC)
	if !first.SittingDate.Equal(wantDate) {
		t.Errorf("first.SittingDate = %v, want %v", first.SittingDate, wantDate)
	}
	if first.WordCount <= 0 {
		t.Errorf("first.WordCount = %d, want > 0", first.WordCount)
	}
	if first.Language != "und" {
		t.Errorf("first.Language = %q, want und when FloorLanguage is absent", first.Language)
	}

	second := interventions[1]
	if second.InterventionSeq != 1 {
		t.Errorf("second.InterventionSeq = %d, want 1", second.InterventionSeq)
	}
}

func TestParseHansard_LanguageFromFloorLanguage(t *testing.T) {
	const xmlSample = `<House>
  <SubjectOfBusiness>
    <FloorLanguage language="EN">[English]</FloorLanguage>
    <SubjectOfBusinessTitle>Budget</SubjectOfBusinessTitle>
    <Intervention id="1">
      <PersonSpeaking><Affiliation DbId="10">Speaker A</Affiliation></PersonSpeaking>
      <Content><ParaText>Budget implementation is before the House.</ParaText></Content>
    </Intervention>
    <FloorLanguage language="FR">[Translation]</FloorLanguage>
    <Intervention id="2">
      <PersonSpeaking><Affiliation DbId="20">Speaker B</Affiliation></PersonSpeaking>
      <Content><ParaText>La politique budgétaire est devant la Chambre.</ParaText></Content>
    </Intervention>
    <Intervention id="3">
      <PersonSpeaking><Affiliation DbId="30">Speaker C</Affiliation></PersonSpeaking>
      <Content>
        <ParaText>La première partie est en français.</ParaText>
        <FloorLanguage language="EN">[English]</FloorLanguage>
        <ParaText>The second part is in English.</ParaText>
      </Content>
    </Intervention>
  </SubjectOfBusiness>
</House>`

	interventions, err := parseHansard(strings.NewReader(xmlSample), "44-1-HAN200-E.XML")
	if err != nil {
		t.Fatalf("parseHansard returned error: %v", err)
	}
	if len(interventions) != 3 {
		t.Fatalf("got %d interventions, want 3", len(interventions))
	}
	if interventions[0].Language != "en" {
		t.Errorf("first language = %q, want en", interventions[0].Language)
	}
	if interventions[1].Language != "fr" {
		t.Errorf("second language = %q, want fr", interventions[1].Language)
	}
	if interventions[2].Language != "mixed" {
		t.Errorf("third language = %q, want mixed", interventions[2].Language)
	}
}

func TestParseMembersXML(t *testing.T) {
	const xmlSample = `<?xml version="1.0" encoding="UTF-8"?>
<ArrayOfMemberOfParliament>
  <MemberOfParliament>
    <PersonId>30001</PersonId>
    <PersonShortHonorific>Ms.</PersonShortHonorific>
    <PersonOfficialFirstName>Alice</PersonOfficialFirstName>
    <PersonOfficialLastName>Tremblay</PersonOfficialLastName>
    <ConstituencyName>Lac-Saint-Louis</ConstituencyName>
    <ConstituencyProvinceTerritoryName>Quebec</ConstituencyProvinceTerritoryName>
    <CaucusShortName>Liberal</CaucusShortName>
    <FromDateTime>2021-11-22T00:00:00</FromDateTime>
  </MemberOfParliament>
  <MemberOfParliament>
    <PersonId>30002</PersonId>
    <PersonShortHonorific>Mr.</PersonShortHonorific>
    <PersonOfficialFirstName>Bob</PersonOfficialFirstName>
    <PersonOfficialLastName>Chen</PersonOfficialLastName>
    <ConstituencyName>Burnaby South</ConstituencyName>
    <ConstituencyProvinceTerritoryName>British Columbia</ConstituencyProvinceTerritoryName>
    <CaucusShortName>NDP</CaucusShortName>
    <FromDateTime>2019-10-21T00:00:00</FromDateTime>
    <ToDateTime>2025-04-28T00:00:00</ToDateTime>
  </MemberOfParliament>
</ArrayOfMemberOfParliament>`

	var ma MemberArray
	if err := xml.NewDecoder(strings.NewReader(xmlSample)).Decode(&ma); err != nil {
		t.Fatalf("xml decode error: %v", err)
	}
	if len(ma.Members) != 2 {
		t.Fatalf("got %d members, want 2", len(ma.Members))
	}

	active := ma.Members[0]
	if active.PersonId != "30001" {
		t.Errorf("PersonId = %q, want 30001", active.PersonId)
	}
	if active.FirstName != "Alice" || active.LastName != "Tremblay" {
		t.Errorf("name = %q %q, want Alice Tremblay", active.FirstName, active.LastName)
	}
	if active.Constituency != "Lac-Saint-Louis" {
		t.Errorf("Constituency = %q, want Lac-Saint-Louis", active.Constituency)
	}
	if active.Province != "Quebec" {
		t.Errorf("Province = %q, want Quebec", active.Province)
	}
	if active.Caucus != "Liberal" {
		t.Errorf("Caucus = %q, want Liberal", active.Caucus)
	}
	if active.ToDate != nil {
		t.Errorf("ToDate should be nil for active member, got %q", *active.ToDate)
	}

	former := ma.Members[1]
	if former.ToDate == nil {
		t.Error("ToDate should be non-nil for former member")
	}
}

func TestParseMembersXML_DateParsing(t *testing.T) {
	const xmlSample = `<ArrayOfMemberOfParliament>
  <MemberOfParliament>
    <PersonId>1</PersonId>
    <PersonOfficialFirstName>Test</PersonOfficialFirstName>
    <PersonOfficialLastName>Member</PersonOfficialLastName>
    <ConstituencyName>Test Riding</ConstituencyName>
    <ConstituencyProvinceTerritoryName>Ontario</ConstituencyProvinceTerritoryName>
    <CaucusShortName>Liberal</CaucusShortName>
    <FromDateTime>2021-11-22T00:00:00</FromDateTime>
  </MemberOfParliament>
</ArrayOfMemberOfParliament>`

	var ma MemberArray
	if err := xml.NewDecoder(strings.NewReader(xmlSample)).Decode(&ma); err != nil {
		t.Fatalf("xml decode error: %v", err)
	}
	m := ma.Members[0]
	fromDate, err := time.Parse("2006-01-02T15:04:05", m.FromDate)
	if err != nil {
		t.Fatalf("failed to parse FromDate %q: %v", m.FromDate, err)
	}
	want := time.Date(2021, 11, 22, 0, 0, 0, 0, time.UTC)
	if !fromDate.Equal(want) {
		t.Errorf("FromDate = %v, want %v", fromDate, want)
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
		{"Tuesday, February 7, 2023", wantUTC(2023, 2, 7)},
		{"Monday, November 14, 2022", wantUTC(2022, 11, 14)},
		{"Friday, September 20, 2019", wantUTC(2019, 9, 20)},
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
		{"Mr. Speaker, my question is about infrastructure.", 7},
	}
	for _, c := range cases {
		if got := wordCount(c.input); got != c.want {
			t.Errorf("wordCount(%q) = %d, want %d", c.input, got, c.want)
		}
	}
}
