package postgres

import (
	"context"
	"testing"

	"epac/lobbying/internal/usecase"
)

func TestRepositoryListByOCLCodesEmptyMappingsDoesNotRequireConnection(t *testing.T) {
	page, err := New(nil).ListByOCLCodes(context.Background(), nil, usecase.Pagination{Page: 1, PerPage: 50})
	if err != nil {
		t.Fatalf("ListByOCLCodes: %v", err)
	}
	if page.Total != 0 || len(page.Rows) != 0 {
		t.Fatalf("page = %#v, want empty", page)
	}
}
