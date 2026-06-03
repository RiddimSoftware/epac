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

type stubBillLobbyingContextService struct {
	gotInput usecase.BillLobbyingContextInput
	result   usecase.BillLobbyingContext
	err      error
}

func (s *stubBillLobbyingContextService) Execute(_ context.Context, input usecase.BillLobbyingContextInput) (usecase.BillLobbyingContext, error) {
	s.gotInput = input
	return s.result, s.err
}

func TestHandleRequestReturnsBillLobbyingContext(t *testing.T) {
	stub := &stubBillLobbyingContextService{
		result: usecase.BillLobbyingContext{
			LegisInfoID:         "13854949",
			WindowMonths:        6,
			WindowStartDate:     "2025-11-15",
			WindowEndDate:       "2026-05-15",
			SubjectTags:         []string{"Housing"},
			TotalCommunications: 2,
			CountByOrganization: []usecase.OrganizationCommunicationCount{
				{OrganizationName: "Housing Alliance", Count: 2},
			},
			CountBySubjectMatter: []usecase.SubjectMatterCommunicationCount{
				{OCLCode: "SMT-44", SubjectMatter: "Housing", Count: 2},
			},
			TopOrganizations: []usecase.OrganizationCommunicationCount{
				{OrganizationName: "Housing Alliance", Count: 2},
			},
			Citation:  usecase.Citation,
			SourceURL: usecase.SourceURL,
		},
	}
	setBillLobbyingContextServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/api/v1/bills/13854949/lobbying-context",
		QueryStringParameters: map[string]string{"window_months": "6"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput != (usecase.BillLobbyingContextInput{LegisInfoID: "13854949", WindowMonths: 6}) {
		t.Fatalf("input = %#v", stub.gotInput)
	}

	var body usecase.BillLobbyingContext
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.TotalCommunications != 2 || body.Citation != usecase.Citation || body.SourceURL != usecase.SourceURL {
		t.Fatalf("unexpected body: %#v", body)
	}
}

func TestHandleRequestReturnsEmptyBillLobbyingContextForNoSubjectTags(t *testing.T) {
	stub := &stubBillLobbyingContextService{
		result: usecase.BillLobbyingContext{
			LegisInfoID:          "C-2",
			WindowMonths:         usecase.DefaultBillLobbyingWindowMonths,
			WindowStartDate:      "2025-06-03",
			WindowEndDate:        "2026-06-03",
			SubjectTags:          []string{},
			CountByOrganization:  []usecase.OrganizationCommunicationCount{},
			CountBySubjectMatter: []usecase.SubjectMatterCommunicationCount{},
			TopOrganizations:     []usecase.OrganizationCommunicationCount{},
			Citation:             usecase.Citation,
			SourceURL:            usecase.SourceURL,
		},
	}
	setBillLobbyingContextServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		PathParameters: map[string]string{"legisinfo_id": "C-2"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput != (usecase.BillLobbyingContextInput{LegisInfoID: "C-2", WindowMonths: usecase.DefaultBillLobbyingWindowMonths}) {
		t.Fatalf("input = %#v", stub.gotInput)
	}

	var body usecase.BillLobbyingContext
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.TotalCommunications != 0 || len(body.SubjectTags) != 0 || body.Citation != usecase.Citation {
		t.Fatalf("unexpected empty body: %#v", body)
	}
}

func TestHandleRequestRejectsInvalidBillLobbyingWindow(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/api/v1/bills/C-2/lobbying-context",
		QueryStringParameters: map[string]string{"window_months": "0"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestHandleRequestMapsBillLobbyingServiceInitError(t *testing.T) {
	setBillLobbyingContextServiceForTest(t, nil, errors.New("not configured"))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/bills/C-2/lobbying-context",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}
}

func setBillLobbyingContextServiceForTest(t *testing.T, service billLobbyingContextExecutor, err error) {
	t.Helper()
	original := newBillLobbyingContextService
	newBillLobbyingContextService = func(context.Context) (billLobbyingContextExecutor, closeFunc, error) {
		return service, noopClose, err
	}
	t.Cleanup(func() { newBillLobbyingContextService = original })
}
