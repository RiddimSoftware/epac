package domain

import (
	"testing"
	"time"
)

func TestParliamentSessionContainsDateInclusively(t *testing.T) {
	session := ParliamentSession{
		From: time.Date(2025, 9, 15, 14, 30, 0, 0, time.UTC),
		To:   time.Date(2026, 6, 3, 9, 0, 0, 0, time.UTC),
	}

	for _, date := range []time.Time{
		time.Date(2025, 9, 15, 0, 0, 0, 0, time.UTC),
		time.Date(2026, 6, 3, 23, 59, 0, 0, time.UTC),
	} {
		if !session.Contains(date) {
			t.Fatalf("expected session to contain %s", date)
		}
	}

	if session.Contains(time.Time{}) {
		t.Fatal("zero time should not be contained")
	}
	if session.Contains(time.Date(2026, 6, 4, 0, 0, 0, 0, time.UTC)) {
		t.Fatal("date after session should not be contained")
	}
}
