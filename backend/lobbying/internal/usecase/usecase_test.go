package usecase

import (
	"context"
	"errors"
	"testing"
)

type fakeSource struct {
	mappings []OCLTopicMapping
	ok       bool
}

func (s fakeSource) CodesForTopic(string) ([]OCLTopicMapping, bool) {
	return s.mappings, s.ok
}

type fakeRepo struct {
	called        bool
	gotMappings   []OCLTopicMapping
	gotPagination Pagination
	page          LobbyingByTopicPage
	err           error
}

func (r *fakeRepo) ListByOCLCodes(_ context.Context, mappings []OCLTopicMapping, pagination Pagination) (LobbyingByTopicPage, error) {
	r.called = true
	r.gotMappings = mappings
	r.gotPagination = pagination
	return r.page, r.err
}

type fakeLogger struct {
	warnings []OCLTopicMapping
}

func (l *fakeLogger) WarnLowConfidenceMapping(_ context.Context, mapping OCLTopicMapping) {
	l.warnings = append(l.warnings, mapping)
}

func TestExecuteMappingHitIncludesLowConfidenceRowsAndLogsWarning(t *testing.T) {
	repo := &fakeRepo{
		page: LobbyingByTopicPage{
			Total: 1,
			Rows: []LobbyingByTopicRecord{
				{
					Kind:          "communication",
					OCLID:         "COM-1",
					OCLCode:       "SMT-7",
					SubjectMatter: "Consumer Issues",
				},
			},
		},
	}
	logger := &fakeLogger{}
	uc := New(repo, fakeSource{
		ok: true,
		mappings: []OCLTopicMapping{
			{OCLCode: "SMT-7", EpacTopicSlug: "economy", Confidence: 0.55},
		},
	}, logger)

	result, err := uc.Execute(context.Background(), " Economy ", Pagination{Page: 2, PerPage: 10})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if !repo.called {
		t.Fatal("repo was not called")
	}
	if repo.gotPagination != (Pagination{Page: 2, PerPage: 10}) {
		t.Fatalf("pagination = %#v", repo.gotPagination)
	}
	if len(logger.warnings) != 1 || logger.warnings[0].OCLCode != "SMT-7" {
		t.Fatalf("warnings = %#v, want SMT-7", logger.warnings)
	}
	if result.TopicSlug != "economy" || result.Total != 1 || len(result.Rows) != 1 {
		t.Fatalf("unexpected result: %#v", result)
	}
	row := result.Rows[0]
	if row.EpacTopicSlug != "economy" || row.MappingConfidence != 0.55 {
		t.Fatalf("row mapping fields = %#v", row)
	}
	if row.Citation != Citation || row.SourceURL != SourceURL {
		t.Fatalf("row source fields = %#v", row)
	}
}

func TestExecuteMappingMissReturnsEmptyWithoutRepoCall(t *testing.T) {
	repo := &fakeRepo{}
	uc := New(repo, fakeSource{ok: false}, nil)

	result, err := uc.Execute(context.Background(), "unknown", Pagination{Page: 1, PerPage: DefaultPerPage})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if repo.called {
		t.Fatal("repo should not be called on mapping miss")
	}
	if result.TopicSlug != "unknown" || result.Total != 0 || len(result.Rows) != 0 {
		t.Fatalf("unexpected empty result: %#v", result)
	}
	if result.Citation != Citation || result.SourceURL != SourceURL {
		t.Fatalf("empty response source fields = %#v", result)
	}
}

func TestExecutePropagatesRepositoryError(t *testing.T) {
	want := errors.New("boom")
	repo := &fakeRepo{err: want}
	uc := New(repo, fakeSource{
		ok:       true,
		mappings: []OCLTopicMapping{{OCLCode: "SMT-44", EpacTopicSlug: "housing", Confidence: 1}},
	}, nil)

	if _, err := uc.Execute(context.Background(), "housing", Pagination{Page: 1, PerPage: 1}); !errors.Is(err, want) {
		t.Fatalf("err = %v, want %v", err, want)
	}
}

func TestNewPaginationCapsPerPage(t *testing.T) {
	pagination, err := NewPagination(1, 999)
	if err != nil {
		t.Fatalf("NewPagination: %v", err)
	}
	if pagination.PerPage != MaxPerPage {
		t.Fatalf("perPage = %d, want %d", pagination.PerPage, MaxPerPage)
	}
}
