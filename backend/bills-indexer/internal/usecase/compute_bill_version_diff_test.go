package usecase

import (
	"reflect"
	"testing"

	"epac/bills-indexer/internal/domain"
)

func TestDiffClauses(t *testing.T) {
	from := []domain.VersionSection{
		{Label: "1", Text: "Original text of section 1"},
		{Label: "2", Text: "Original text of section 2"},
		{Label: "3", Text: "Original text of section 3"},
	}

	to := []domain.VersionSection{
		{Label: "1", Text: "Original text of section 1"},
		{Label: "2", Text: "Modified text of section 2"},
		{Label: "2.1", Text: "Added text of section 2.1"},
	}

	expected := []domain.BillClauseDiff{
		{
			Label:      "1",
			ChangeType: "unchanged",
			FromText:   "Original text of section 1",
			ToText:     "Original text of section 1",
		},
		{
			Label:      "2",
			ChangeType: "modified",
			FromText:   "Original text of section 2",
			ToText:     "Modified text of section 2",
		},
		{
			Label:      "3",
			ChangeType: "removed",
			FromText:   "Original text of section 3",
			ToText:     "",
		},
		{
			Label:      "2.1",
			ChangeType: "added",
			FromText:   "",
			ToText:     "Added text of section 2.1",
		},
	}

	diffs := DiffClauses(from, to)

	if !reflect.DeepEqual(diffs, expected) {
		t.Errorf("diff mismatch.\nExpected: %+v\nGot:      %+v", expected, diffs)
	}
}

func TestComputeBillVersionDiffCases(t *testing.T) {
	// Case 1: Multi-version bill (3 versions) with text available
	v1 := domain.BillVersion{
		ID:        "v1",
		SortOrder: 1,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "Hello"},
		},
		TextHash:      ptrString("hash-1"),
		TextSourceURL: ptrString("https://example.test/xml1"),
	}
	v2 := domain.BillVersion{
		ID:        "v2",
		SortOrder: 2,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "Hello World"},
		},
		TextHash:      ptrString("hash-2"),
		TextSourceURL: ptrString("https://example.test/xml2"),
	}
	v3 := domain.BillVersion{
		ID:        "v3",
		SortOrder: 3,
		Sections: []domain.VersionSection{
			{Label: "1", Text: "Hello Universe"},
		},
		TextHash:      ptrString("hash-3"),
		TextSourceURL: ptrString("https://example.test/xml3"),
	}

	diffs := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1, v2, v3}, "https://example.test/bill")
	if len(diffs) != 3 {
		t.Fatalf("expected 3 diffs, got %d", len(diffs))
	}
	
	// Check v1 -> v2
	if diffs[0].FromVersionID != "v1" || diffs[0].ToVersionID != "v2" {
		t.Errorf("incorrect version pair in diff 0: %+v", diffs[0])
	}
	if len(diffs[0].Clauses) != 1 || diffs[0].Clauses[0].Label != "1" || diffs[0].Clauses[0].ChangeType != "modified" {
		t.Errorf("expected modified clause in diff 0, got: %+v", diffs[0].Clauses)
	}

	// Check v1 -> v3
	if diffs[1].FromVersionID != "v1" || diffs[1].ToVersionID != "v3" {
		t.Errorf("incorrect version pair in diff 1: %+v", diffs[1])
	}
	if len(diffs[1].Clauses) != 1 || diffs[1].Clauses[0].Label != "1" || diffs[1].Clauses[0].ChangeType != "modified" {
		t.Errorf("expected modified clause in diff 1, got: %+v", diffs[1].Clauses)
	}

	// Check v2 -> v3
	if diffs[2].FromVersionID != "v2" || diffs[2].ToVersionID != "v3" {
		t.Errorf("incorrect version pair in diff 2: %+v", diffs[2])
	}
	if len(diffs[2].Clauses) != 1 || diffs[2].Clauses[0].Label != "1" || diffs[2].Clauses[0].ChangeType != "modified" {
		t.Errorf("expected modified clause in diff 2, got: %+v", diffs[2].Clauses)
	}

	// Case 2: One-version bill -> no diff records should be built
	diffsOne := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1}, "https://example.test/bill")
	if len(diffsOne) != 0 {
		t.Errorf("expected 0 diffs for single version, got %d", len(diffsOne))
	}

	// Case 3: Multi-version bill with missing text on some versions
	// v1 and v3 have text, v2 has missing text.
	// - v1 -> v2 (adjacent): emitted, 0 clauses
	// - v2 -> v3 (adjacent): emitted, 0 clauses
	// - v1 -> v3 (non-adjacent, both have text): emitted, 1 clause
	v1Partial := domain.BillVersion{
		ID:            "v1",
		SortOrder:     1,
		Sections:      []domain.VersionSection{{Label: "1", Text: "Hello"}},
		TextHash:      ptrString("hash-1"),
		TextSourceURL: ptrString("https://example.test/xml1"),
	}
	v2Partial := domain.BillVersion{
		ID:            "v2",
		SortOrder:     2,
		TextHash:      nil,
		TextSourceURL: nil,
	}
	v3Partial := domain.BillVersion{
		ID:            "v3",
		SortOrder:     3,
		Sections:      []domain.VersionSection{{Label: "1", Text: "Hello Universe"}},
		TextHash:      ptrString("hash-3"),
		TextSourceURL: ptrString("https://example.test/xml3"),
	}
	diffsPartial := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1Partial, v2Partial, v3Partial}, "https://example.test/bill")
	if len(diffsPartial) != 3 {
		t.Fatalf("expected 3 diffs, got %d", len(diffsPartial))
	}
	// Check v1 -> v2 (adjacent, no clauses)
	if diffsPartial[0].FromVersionID != "v1" || diffsPartial[0].ToVersionID != "v2" || len(diffsPartial[0].Clauses) != 0 {
		t.Errorf("expected empty adjacent v1->v2, got: %+v", diffsPartial[0])
	}
	// Check v1 -> v3 (non-adjacent, has clauses)
	if diffsPartial[1].FromVersionID != "v1" || diffsPartial[1].ToVersionID != "v3" || len(diffsPartial[1].Clauses) != 1 {
		t.Errorf("expected populated non-adjacent v1->v3, got: %+v", diffsPartial[1])
	}
	// Check v2 -> v3 (adjacent, no clauses)
	if diffsPartial[2].FromVersionID != "v2" || diffsPartial[2].ToVersionID != "v3" || len(diffsPartial[2].Clauses) != 0 {
		t.Errorf("expected empty adjacent v2->v3, got: %+v", diffsPartial[2])
	}

	// Case 4: Multi-version bill with all versions missing text
	// Only adjacent pairs (v1->v2, v2->v3) should be emitted. Non-adjacent (v1->v3) should be skipped.
	v1NoText := domain.BillVersion{ID: "v1", SortOrder: 1}
	v2NoText := domain.BillVersion{ID: "v2", SortOrder: 2}
	v3NoText := domain.BillVersion{ID: "v3", SortOrder: 3}
	diffsNoText := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1NoText, v2NoText, v3NoText}, "https://example.test/bill")
	if len(diffsNoText) != 2 {
		t.Fatalf("expected 2 diffs (adjacent only) when all lack text, got %d: %+v", len(diffsNoText), diffsNoText)
	}
	if diffsNoText[0].FromVersionID != "v1" || diffsNoText[0].ToVersionID != "v2" {
		t.Errorf("expected v1->v2 as first diff, got %+v", diffsNoText[0])
	}
	if diffsNoText[1].FromVersionID != "v2" || diffsNoText[1].ToVersionID != "v3" {
		t.Errorf("expected v2->v3 as second diff, got %+v", diffsNoText[1])
	}
}

func ptrString(s string) *string {
	return &s
}
