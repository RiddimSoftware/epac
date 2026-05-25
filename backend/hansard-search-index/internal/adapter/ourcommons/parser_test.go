package ourcommons

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParserExtractsInterventionsFromRealHansardFixture(t *testing.T) {
	fixture := filepath.Join("..", "..", "..", "testdata", "hansard_451_001_slice.xml")
	body, err := os.ReadFile(fixture)
	if err != nil {
		t.Fatalf("read fixture: %v", err)
	}

	got, err := NewParser(nil).Parse(body)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if len(got) != 2 {
		t.Fatalf("intervention count = %d, want 2", len(got))
	}

	first := got[0]
	if first.ParliamentNumber != 45 || first.SessionNumber != 1 {
		t.Fatalf("session = %d-%d, want 45-1", first.ParliamentNumber, first.SessionNumber)
	}
	if gotDate := first.SittingDate.Format("2006-01-02"); gotDate != "2025-05-26" {
		t.Fatalf("sitting date = %q", gotDate)
	}
	if first.InterventionID != "13077673" {
		t.Fatalf("intervention id = %q", first.InterventionID)
	}
	if first.SpeakerFirstName != "John" || first.SpeakerLastName != "Nater" {
		t.Fatalf("speaker = %q %q, want John Nater", first.SpeakerFirstName, first.SpeakerLastName)
	}
	if first.PartyAbbreviation != "CPC" {
		t.Fatalf("party = %q, want CPC", first.PartyAbbreviation)
	}
	if first.RidingName != "Perth—Wellington" {
		t.Fatalf("riding = %q, want Perth—Wellington", first.RidingName)
	}
	if first.Topic != "Election of Speaker" {
		t.Fatalf("topic = %q, want Election of Speaker", first.Topic)
	}
	if len(first.Messages) != 1 {
		t.Fatalf("messages = %d, want 1", len(first.Messages))
	}
	if first.Messages[0].MessageID != "8830321" || first.Messages[0].Position != 1 {
		t.Fatalf("message metadata = %#v", first.Messages[0])
	}
	if first.Messages[0].Text == "" {
		t.Fatal("message text must not be empty")
	}

	second := got[1]
	if second.InterventionID != "13077675" {
		t.Fatalf("second intervention id = %q", second.InterventionID)
	}
	if second.SpeakerFirstName != "Chris" || second.SpeakerLastName != "d'Entremont" {
		t.Fatalf("second speaker = %q %q", second.SpeakerFirstName, second.SpeakerLastName)
	}
	if len(second.Messages) != 2 {
		t.Fatalf("second messages = %d, want 2", len(second.Messages))
	}
	if second.Messages[1].MessageID != "8830323" || second.Messages[1].Position != 2 {
		t.Fatalf("second message metadata = %#v", second.Messages[1])
	}
}
