package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
)

type stubByTopicService struct {
	gotSlug       string
	gotPagination usecase.Pagination
	result        usecase.LobbyingByTopicResult
	err           error
}

func (s *stubByTopicService) Execute(_ context.Context, slug string, pagination usecase.Pagination) (usecase.LobbyingByTopicResult, error) {
	s.gotSlug = slug
	s.gotPagination = pagination
	return s.result, s.err
}

func TestHandleRequestReturnsTopicRows(t *testing.T) {
	stub := &stubByTopicService{
		result: usecase.LobbyingByTopicResult{
			TopicSlug: "housing",
			Page:      2,
			PerPage:   1,
			Total:     2,
			Citation:  usecase.Citation,
			SourceURL: usecase.SourceURL,
			Rows: []usecase.LobbyingByTopicRecord{
				{
					Kind:              "communication",
					OCLID:             "COM-2",
					OCLCode:           "SMT-44",
					EpacTopicSlug:     "housing",
					MappingConfidence: 1,
					SubjectMatter:     "Housing",
					OrganizationName:  "Example Org",
					Citation:          usecase.Citation,
					SourceURL:         usecase.SourceURL,
				},
			},
		},
	}
	setByTopicServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		PathParameters: map[string]string{"slug": "housing"},
		QueryStringParameters: map[string]string{
			"page":     "2",
			"per_page": "1",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotSlug != "housing" || stub.gotPagination != (usecase.Pagination{Page: 2, PerPage: 1}) {
		t.Fatalf("service args slug=%q pagination=%#v", stub.gotSlug, stub.gotPagination)
	}

	var body usecase.LobbyingByTopicResult
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Total != 2 || len(body.Rows) != 1 {
		t.Fatalf("unexpected body: %#v", body)
	}
	if body.Rows[0].Citation != usecase.Citation || body.Rows[0].SourceURL != usecase.SourceURL {
		t.Fatalf("row missing source citation: %#v", body.Rows[0])
	}
}

func TestHandleRequestReturnsEmptyTopicResponse(t *testing.T) {
	stub := &stubByTopicService{
		result: usecase.LobbyingByTopicResult{
			TopicSlug: "pharma",
			Page:      1,
			PerPage:   usecase.DefaultPerPage,
			Total:     0,
			Citation:  usecase.Citation,
			SourceURL: usecase.SourceURL,
			Rows:      []usecase.LobbyingByTopicRecord{},
		},
	}
	setByTopicServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/by-topic/pharma",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}

	var body usecase.LobbyingByTopicResult
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Total != 0 || len(body.Rows) != 0 || body.SourceURL != usecase.SourceURL {
		t.Fatalf("unexpected empty body: %#v", body)
	}
}

func TestHandleRequestCapsPerPage(t *testing.T) {
	stub := &stubByTopicService{
		result: usecase.LobbyingByTopicResult{
			TopicSlug: "housing",
			Page:      1,
			PerPage:   usecase.MaxPerPage,
			Rows:      []usecase.LobbyingByTopicRecord{},
		},
	}
	setByTopicServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/lobbying/by-topic/housing",
		QueryStringParameters: map[string]string{"per_page": "999"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotPagination.PerPage != usecase.MaxPerPage {
		t.Fatalf("perPage = %d, want %d", stub.gotPagination.PerPage, usecase.MaxPerPage)
	}
}

func TestHandleRequestRejectsInvalidPaging(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/api/v1/lobbying/by-topic/housing",
		QueryStringParameters: map[string]string{"page": "0"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestHandleRequestMapsServiceInitError(t *testing.T) {
	setByTopicServiceForTest(t, nil, errors.New("not configured"))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/by-topic/housing",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}
}

func setByTopicServiceForTest(t *testing.T, service byTopicExecutor, err error) {
	t.Helper()
	original := newByTopicService
	newByTopicService = func(context.Context) (byTopicExecutor, closeFunc, error) {
		return service, noopClose, err
	}
	t.Cleanup(func() { newByTopicService = original })
}
