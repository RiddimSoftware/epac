package main

import (
	"strings"
	"testing"
)

func TestParseVotes(t *testing.T) {
	json := `{
		"result": {
			"records": [{
				"_id": 42,
				"First Name": "Olivia",
				"Last Name": "Chow",
				"Date/Time": "2026-04-23 16:22 PM",
				"Agenda Item #": "2026.MM40.46",
				"Agenda Item Title": "Affordable Housing Delivery",
				"Motion Type": "Amend Item",
				"Vote": "Yes",
				"Result": "Carried, 22-0",
				"Vote Description": "Additional housing direction"
			}]
		}
	}`

	votes, err := parseVotes(strings.NewReader(json))
	if err != nil {
		t.Fatalf("parseVotes returned error: %v", err)
	}
	if len(votes) != 1 {
		t.Fatalf("got %d votes, want 1", len(votes))
	}
	vote := votes[0]
	if vote.SourceID != "42" || vote.AgendaItemNumber != "2026.MM40.46" {
		t.Fatalf("unexpected identity: %+v", vote)
	}
	if vote.CouncillorFirst != "Olivia" || vote.CouncillorLast != "Chow" {
		t.Fatalf("unexpected councillor: %+v", vote)
	}
	if vote.VoteDetail != "Yes" {
		t.Fatalf("got vote detail %q, want Yes", vote.VoteDetail)
	}
	if vote.Category != "Housing" {
		t.Fatalf("got category %q, want Housing", vote.Category)
	}
	if vote.VoteDate.IsZero() {
		t.Fatal("expected parsed vote date")
	}
}

func TestNormalizeVote(t *testing.T) {
	cases := map[string]string{
		"yes":                           "Yes",
		"No":                            "No",
		"Absent":                        "Absent",
		"Absent - Conflict of Interest": "Conflict",
	}
	for input, want := range cases {
		if got := normalizeVote(input); got != want {
			t.Fatalf("normalizeVote(%q) = %q, want %q", input, got, want)
		}
	}
}

func TestParseTorontoDateAcceptsDateOnlyOpenDataValue(t *testing.T) {
	date := parseTorontoDate("2026-04-16")
	if date.IsZero() {
		t.Fatal("expected parsed date")
	}
	if got := date.Format("2006-01-02"); got != "2026-04-16" {
		t.Fatalf("got %q, want 2026-04-16", got)
	}
}

func TestClassifyVote(t *testing.T) {
	if got := classifyVote("Transit priority traffic lane"); got != "Transportation" {
		t.Fatalf("got %q, want Transportation", got)
	}
	if got := classifyVote("Community shelter funding"); got != "Social Services" {
		t.Fatalf("got %q, want Social Services", got)
	}
}
