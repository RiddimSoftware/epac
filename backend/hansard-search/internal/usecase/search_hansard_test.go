package usecase_test

import (
	"context"
	"errors"
	"testing"

	"epac/hansard-search/internal/usecase"
)

type stubHansardSearchRepository struct {
	gotQuery      usecase.SearchQuery
	gotPagination usecase.Pagination
	results       usecase.SearchResults
	err           error
}

func (s *stubHansardSearchRepository) Search(_ context.Context, q usecase.SearchQuery, p usecase.Pagination) (usecase.SearchResults, error) {
	s.gotQuery = q
	s.gotPagination = p
	return s.results, s.err
}

func TestSearchHansardExecuteReturnsRepositoryResults(t *testing.T) {
	repo := &stubHansardSearchRepository{
		results: usecase.SearchResults{
			Total: 1,
			Hits: []usecase.SearchHit{
				{
					InterventionID: "intervention-1",
					MessageID:      "message-1",
				},
			},
		},
	}

	got, err := usecase.SearchHansard{Repo: repo}.Execute(
		context.Background(),
		usecase.SearchQuery{Query: "climate"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
	if got.Total != 1 || len(got.Hits) != 1 || got.Hits[0].InterventionID != "intervention-1" {
		t.Fatalf("unexpected results: %#v", got)
	}
	if repo.gotQuery.Query != "climate" {
		t.Fatalf("query = %q, want climate", repo.gotQuery.Query)
	}
	if repo.gotPagination != (usecase.Pagination{Page: 1, PerPage: 10}) {
		t.Fatalf("pagination = %#v", repo.gotPagination)
	}
}

func TestSearchHansardExecuteReturnsInvalidQueryForEmptyInput(t *testing.T) {
	repo := &stubHansardSearchRepository{}

	_, err := usecase.SearchHansard{Repo: repo}.Execute(
		context.Background(),
		usecase.SearchQuery{Query: " \n\t "},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if !errors.Is(err, usecase.ErrInvalidQuery) {
		t.Fatalf("error = %v, want ErrInvalidQuery", err)
	}
}

func TestSearchHansardExecuteReturnsInvalidPagination(t *testing.T) {
	tests := []struct {
		name       string
		pagination usecase.Pagination
	}{
		{name: "page zero", pagination: usecase.Pagination{Page: 0, PerPage: 10}},
		{name: "per page zero", pagination: usecase.Pagination{Page: 1, PerPage: 0}},
		{name: "per page too large", pagination: usecase.Pagination{Page: 1, PerPage: 101}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &stubHansardSearchRepository{}
			_, err := usecase.SearchHansard{Repo: repo}.Execute(
				context.Background(),
				usecase.SearchQuery{Query: "climate"},
				tt.pagination,
			)
			if !errors.Is(err, usecase.ErrInvalidPagination) {
				t.Fatalf("error = %v, want ErrInvalidPagination", err)
			}
		})
	}
}

func TestSearchHansardExecutePreservesInvalidQuerySyntax(t *testing.T) {
	repo := &stubHansardSearchRepository{err: usecase.ErrInvalidQuerySyntax}

	_, err := usecase.SearchHansard{Repo: repo}.Execute(
		context.Background(),
		usecase.SearchQuery{Query: "\"unclosed"},
		usecase.Pagination{Page: 1, PerPage: 10},
	)
	if !errors.Is(err, usecase.ErrInvalidQuerySyntax) {
		t.Fatalf("error = %v, want ErrInvalidQuerySyntax", err)
	}
}
