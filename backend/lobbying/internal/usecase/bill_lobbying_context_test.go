package usecase

import (
	"context"
	"errors"
	"reflect"
	"testing"
	"time"
)

type fakeBillSubjectsRepository struct {
	context BillSubjectContext
	err     error
}

func (r fakeBillSubjectsRepository) LoadBillSubjectContext(_ context.Context, legisInfoID string) (BillSubjectContext, error) {
	if r.err != nil {
		return BillSubjectContext{}, r.err
	}
	out := r.context
	out.LegisInfoID = legisInfoID
	return out, nil
}

type fakeBillLobbyingRepository struct {
	called      bool
	gotMappings []OCLTopicMapping
	gotWindow   DateWindow
	rows        []BillLobbyingCommunication
	err         error
}

func (r *fakeBillLobbyingRepository) ListBillLobbyingCommunications(_ context.Context, mappings []OCLTopicMapping, window DateWindow) ([]BillLobbyingCommunication, error) {
	r.called = true
	r.gotMappings = append([]OCLTopicMapping(nil), mappings...)
	r.gotWindow = window
	return r.rows, r.err
}

type fakeBillSubjectMapper struct {
	bySlug map[string][]OCLTopicMapping
}

func (m fakeBillSubjectMapper) CodesForTopic(slug string) ([]OCLTopicMapping, bool) {
	mappings, ok := m.bySlug[slug]
	return append([]OCLTopicMapping(nil), mappings...), ok
}

type fixedClock struct {
	now time.Time
}

func (c fixedClock) Now() time.Time {
	return c.now
}

func TestLoadBillLobbyingContextReturnsCountsForMatchingCommunications(t *testing.T) {
	lobbying := &fakeBillLobbyingRepository{
		rows: []BillLobbyingCommunication{
			{ID: "COM-1", OrganizationName: "Housing Alliance", SubjectMatter: "Housing", OCLCode: "44", CommunicationDate: "2026-03-01"},
			{ID: "COM-2", OrganizationName: "Housing Alliance", SubjectMatter: "Housing", OCLCode: "SMT-44", CommunicationDate: "2026-02-01"},
			{ID: "COM-2", OrganizationName: "Housing Alliance", SubjectMatter: "Housing", OCLCode: "SMT-44", CommunicationDate: "2026-02-01"},
			{ID: "COM-3", OrganizationName: "Builders Canada", SubjectMatter: "Infrastructure", OCLCode: "SMT-30", CommunicationDate: "2026-01-15"},
		},
	}
	uc := NewLoadBillLobbyingContext(
		fakeBillSubjectsRepository{context: BillSubjectContext{
			SubjectTags:           []string{"Housing policy", "Economy", "Infrastructure Canada"},
			TopicSlugs:            []string{"housing", "economy", "infrastructure"},
			MostRecentReadingDate: "2026-05-15",
		}},
		lobbying,
		fakeBillSubjectMapper{bySlug: map[string][]OCLTopicMapping{
			"housing":        {{OCLCode: "SMT-44", EpacTopicSlug: "housing", Confidence: 1}},
			"economy":        {{OCLCode: "SMT-7", EpacTopicSlug: "economy", Confidence: 0.55}},
			"infrastructure": {{OCLCode: "SMT-30", EpacTopicSlug: "infrastructure", Confidence: 0.92}},
		}},
		fixedClock{now: time.Date(2026, 6, 3, 12, 0, 0, 0, time.UTC)},
	)

	result, err := uc.Execute(context.Background(), BillLobbyingContextInput{
		LegisInfoID:  "13854949",
		WindowMonths: 12,
	})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if !lobbying.called {
		t.Fatal("lobbying repository was not called")
	}
	if lobbying.gotWindow != (DateWindow{StartDate: "2025-05-15", EndDate: "2026-05-15"}) {
		t.Fatalf("window = %#v", lobbying.gotWindow)
	}
	if got, want := mappingCodes(lobbying.gotMappings), []string{"SMT-30", "SMT-44"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("mapping codes = %#v, want %#v", got, want)
	}
	if result.TotalCommunications != 3 {
		t.Fatalf("total communications = %d, want 3", result.TotalCommunications)
	}
	if got, want := result.SubjectTags, []string{"Economy", "Housing policy", "Infrastructure Canada"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("subject tags = %#v, want %#v", got, want)
	}
	if got, want := result.CountByOrganization, []OrganizationCommunicationCount{
		{OrganizationName: "Housing Alliance", Count: 2},
		{OrganizationName: "Builders Canada", Count: 1},
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("organization counts = %#v, want %#v", got, want)
	}
	if got, want := result.CountBySubjectMatter, []SubjectMatterCommunicationCount{
		{OCLCode: "SMT-44", SubjectMatter: "Housing", Count: 2},
		{OCLCode: "SMT-30", SubjectMatter: "Infrastructure", Count: 1},
	}; !reflect.DeepEqual(got, want) {
		t.Fatalf("subject counts = %#v, want %#v", got, want)
	}
	if len(result.TopOrganizations) != 2 || result.TopOrganizations[0].OrganizationName != "Housing Alliance" {
		t.Fatalf("top organizations = %#v", result.TopOrganizations)
	}
	if result.Citation != Citation || result.SourceURL != SourceURL {
		t.Fatalf("source fields = %#v", result)
	}
}

func TestLoadBillLobbyingContextZeroCommunications(t *testing.T) {
	lobbying := &fakeBillLobbyingRepository{}
	uc := NewLoadBillLobbyingContext(
		fakeBillSubjectsRepository{context: BillSubjectContext{
			SubjectTags:           []string{"Healthcare"},
			MostRecentReadingDate: "2026-04-01",
		}},
		lobbying,
		fakeBillSubjectMapper{bySlug: map[string][]OCLTopicMapping{
			"healthcare": {{OCLCode: "SMT-18", EpacTopicSlug: "healthcare", Confidence: 1}},
		}},
		fixedClock{now: time.Date(2026, 6, 3, 12, 0, 0, 0, time.UTC)},
	)

	result, err := uc.Execute(context.Background(), BillLobbyingContextInput{LegisInfoID: "C-9"})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if !lobbying.called {
		t.Fatal("lobbying repository was not called")
	}
	if result.WindowMonths != DefaultBillLobbyingWindowMonths || result.TotalCommunications != 0 {
		t.Fatalf("unexpected result = %#v", result)
	}
	if len(result.CountByOrganization) != 0 || len(result.CountBySubjectMatter) != 0 || len(result.TopOrganizations) != 0 {
		t.Fatalf("empty counts not empty arrays: %#v", result)
	}
}

func TestLoadBillLobbyingContextNoSubjectTagsReturnsEmptyWithoutLobbyingQuery(t *testing.T) {
	lobbying := &fakeBillLobbyingRepository{}
	uc := NewLoadBillLobbyingContext(
		fakeBillSubjectsRepository{context: BillSubjectContext{SubjectTags: []string{}}},
		lobbying,
		fakeBillSubjectMapper{},
		fixedClock{now: time.Date(2026, 6, 3, 12, 0, 0, 0, time.UTC)},
	)

	result, err := uc.Execute(context.Background(), BillLobbyingContextInput{LegisInfoID: "C-2", WindowMonths: 6})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if lobbying.called {
		t.Fatal("lobbying repository should not be called for no subject tags")
	}
	if result.TotalCommunications != 0 || len(result.SubjectTags) != 0 {
		t.Fatalf("unexpected empty result: %#v", result)
	}
	if result.WindowStartDate != "2025-12-03" || result.WindowEndDate != "2026-06-03" {
		t.Fatalf("fallback current-date window = %s..%s", result.WindowStartDate, result.WindowEndDate)
	}
}

func TestLoadBillLobbyingContextPropagatesRepositoryError(t *testing.T) {
	want := errors.New("boom")
	uc := NewLoadBillLobbyingContext(
		fakeBillSubjectsRepository{err: want},
		&fakeBillLobbyingRepository{},
		fakeBillSubjectMapper{},
		fixedClock{now: time.Date(2026, 6, 3, 12, 0, 0, 0, time.UTC)},
	)

	if _, err := uc.Execute(context.Background(), BillLobbyingContextInput{LegisInfoID: "C-1"}); !errors.Is(err, want) {
		t.Fatalf("err = %v, want %v", err, want)
	}
}

func TestNormalizeSubjectTagSlug(t *testing.T) {
	tests := map[string]string{
		"Natural Resources": "naturalresources",
		"Health care":       "healthcare",
		"SMT-44":            "smt44",
	}
	for input, want := range tests {
		if got := NormalizeSubjectTagSlug(input); got != want {
			t.Fatalf("NormalizeSubjectTagSlug(%q) = %q, want %q", input, got, want)
		}
	}
}

func mappingCodes(mappings []OCLTopicMapping) []string {
	out := make([]string, 0, len(mappings))
	for _, mapping := range mappings {
		out = append(out, mapping.OCLCode)
	}
	return out
}
