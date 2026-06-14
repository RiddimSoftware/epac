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
	// Case 1: Multi-version bill with text available
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

	diffs := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1, v2}, "https://example.test/bill")
	if len(diffs) != 1 {
		t.Fatalf("expected 1 diff, got %d", len(diffs))
	}
	if diffs[0].FromVersionID != "v1" || diffs[0].ToVersionID != "v2" {
		t.Errorf("incorrect version pair in diff: %+v", diffs[0])
	}
	if len(diffs[0].Clauses) != 1 || diffs[0].Clauses[0].Label != "1" || diffs[0].Clauses[0].ChangeType != "modified" {
		t.Errorf("expected modified clause, got: %+v", diffs[0].Clauses)
	}

	// Case 2: One-version bill -> no diff records should be built
	diffsOne := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1}, "https://example.test/bill")
	if len(diffsOne) != 0 {
		t.Errorf("expected 0 diffs for single version, got %d", len(diffsOne))
	}

	// Case 3: Multi-version bill with missing text -> creates diff records but no clauses
	v1Missing := domain.BillVersion{
		ID:            "v1",
		SortOrder:     1,
		TextHash:      nil,
		TextSourceURL: nil,
	}
	v2Missing := domain.BillVersion{
		ID:            "v2",
		SortOrder:     2,
		TextHash:      nil,
		TextSourceURL: nil,
	}
	diffsMissing := ComputeBillVersionDiff("C-2", []domain.BillVersion{v1Missing, v2Missing}, "https://example.test/bill")
	if len(diffsMissing) != 1 {
		t.Fatalf("expected 1 diff, got %d", len(diffsMissing))
	}
	if len(diffsMissing[0].Clauses) != 0 {
		t.Errorf("expected 0 clauses in diff when text is missing, got %d", len(diffsMissing[0].Clauses))
	}
}

func ptrString(s string) *string {
	return &s
}
