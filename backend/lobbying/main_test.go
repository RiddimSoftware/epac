package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"epac/lobbying/application"
	"epac/lobbying/domain"
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

type stubMinisterPortfolioService struct {
	gotMemberID string
	result      usecase.MinisterLobbyingByPortfolioResult
	err         error
}

func (s *stubMinisterPortfolioService) Execute(_ context.Context, memberID string) (usecase.MinisterLobbyingByPortfolioResult, error) {
	s.gotMemberID = memberID
	return s.result, s.err
}

type stubCabinetOverviewService struct {
	gotInput usecase.CabinetLobbyingOverviewInput
	result   usecase.CabinetLobbyingOverviewResult
	err      error
}

func (s *stubCabinetOverviewService) Execute(_ context.Context, input usecase.CabinetLobbyingOverviewInput) (usecase.CabinetLobbyingOverviewResult, error) {
	s.gotInput = input
	return s.result, s.err
}

type stubMPLobbyingExposureService struct {
	gotInput application.LoadMPLobbyingExposureInput
	result   application.MPLobbyingExposureResult
	err      error
}

func (s *stubMPLobbyingExposureService) Execute(_ context.Context, input application.LoadMPLobbyingExposureInput) (application.MPLobbyingExposureResult, error) {
	s.gotInput = input
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

func TestHandleRequestReturnsMPLobbyingExposure(t *testing.T) {
	stub := &stubMPLobbyingExposureService{
		result: application.MPLobbyingExposureResult{
			MemberID:   "278707",
			Parliament: 45,
			Window:     domain.LobbyingExposureWindow3M,
			Page:       2,
			PerPage:    application.MPLobbyingTimelinePerPage,
			Total:      1,
			Pages:      1,
			Summary: domain.MPLobbyingSummary{
				MemberID:                 "278707",
				Parliament:               45,
				Window:                   domain.LobbyingExposureWindow3M,
				TotalCommunicationCount:  1,
				UniqueOrganizationsCount: 1,
				TopOrganizations: []domain.TopLobbyingOrganization{
					{Name: "Example Org", Sector: "Housing", CommunicationCount: 1},
				},
				Citation: domain.OCLCitation,
			},
			SubjectBreakdown: []domain.LobbyingSubjectDistribution{
				{SubjectMatter: "Housing", CommunicationCount: 1},
			},
			Timeline: []domain.LobbyingTimelineEntry{
				{
					CommunicationID:   "COM-1",
					Date:              "2026-05-20",
					OrganizationName:  "Example Org",
					SubjectMatter:     "Housing",
					CommunicationType: "meeting",
					Citation:          domain.OCLCitation,
					SourceURL:         domain.OCLSourceURL,
				},
			},
			Citation:  domain.OCLCitation,
			SourceURL: domain.OCLSourceURL,
		},
	}
	setMPLobbyingExposureServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/members/278707/lobbying-exposure",
		QueryStringParameters: map[string]string{
			"parliament": "45",
			"window":     "3m",
			"page":       "2",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput.MemberID != "278707" ||
		stub.gotInput.Parliament != 45 ||
		stub.gotInput.Window != domain.LobbyingExposureWindow3M ||
		stub.gotInput.Page != 2 {
		t.Fatalf("service input = %#v", stub.gotInput)
	}

	var body application.MPLobbyingExposureResult
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Summary.TotalCommunicationCount != 1 || len(body.Timeline) != 1 || len(body.SubjectBreakdown) != 1 {
		t.Fatalf("unexpected body: %#v", body)
	}
	if body.Timeline[0].Citation != domain.OCLCitation {
		t.Fatalf("row missing citation: %#v", body.Timeline[0])
	}
}

func TestHandleRequestSupportsUnversionedMPLobbyingExposurePath(t *testing.T) {
	stub := &stubMPLobbyingExposureService{
		result: application.MPLobbyingExposureResult{
			MemberID:         "278707",
			Parliament:       45,
			Window:           domain.LobbyingExposureWindowAll,
			Page:             1,
			PerPage:          application.MPLobbyingTimelinePerPage,
			Summary:          domain.MPLobbyingSummary{TopOrganizations: []domain.TopLobbyingOrganization{}, Citation: domain.OCLCitation},
			SubjectBreakdown: []domain.LobbyingSubjectDistribution{},
			Timeline:         []domain.LobbyingTimelineEntry{},
			Citation:         domain.OCLCitation,
			SourceURL:        domain.OCLSourceURL,
		},
	}
	setMPLobbyingExposureServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/members/278707/lobbying-exposure",
		QueryStringParameters: map[string]string{"parliament": "45", "window": "all"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput.MemberID != "278707" || stub.gotInput.Window != domain.LobbyingExposureWindowAll {
		t.Fatalf("service input = %#v", stub.gotInput)
	}
}

func TestHandleRequestRejectsInvalidMPLobbyingExposureQuery(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/api/v1/members/278707/lobbying-exposure",
		QueryStringParameters: map[string]string{"window": "90d"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
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

func TestHandleRequestMapsArtifactLoadErrorToRetryableUnavailable(t *testing.T) {
	setByTopicServiceForTest(t, nil, usecase.ErrChecksumMismatch)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/by-topic/housing",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable || resp.Headers["Retry-After"] != lobbyingRetryAfter {
		t.Fatalf("response = %#v", resp)
	}
}

func TestLobbyingRuntimeCachesSQLiteDB(t *testing.T) {
	openIndexCalls := 0
	openDBCalls := 0
	runtime := newLobbyingRuntime(
		func(context.Context) (usecase.LobbyingIndex, error) {
			openIndexCalls++
			return usecase.LobbyingIndex{LocalPath: ":memory:"}, nil
		},
		func(context.Context, string) (*sql.DB, error) {
			openDBCalls++
			return sql.Open("sqlite", ":memory:")
		},
	)

	first, err := runtime.DB(context.Background())
	if err != nil {
		t.Fatalf("first DB: %v", err)
	}
	second, err := runtime.DB(context.Background())
	if err != nil {
		t.Fatalf("second DB: %v", err)
	}
	t.Cleanup(func() { _ = first.Close() })

	if first != second || openIndexCalls != 1 || openDBCalls != 1 {
		t.Fatalf("cached db=%v openIndex=%d openDB=%d", first == second, openIndexCalls, openDBCalls)
	}
}

func TestHandleRequestReturnsMinisterLobbyingByPortfolio(t *testing.T) {
	stub := &stubMinisterPortfolioService{
		result: usecase.MinisterLobbyingByPortfolioResult{
			MemberID:            "314774",
			MinisterName:        "Mark Carney",
			TotalCommunications: 1,
			Citation:            usecase.Citation,
			SourceURL:           usecase.SourceURL,
			Portfolios: []usecase.MinisterPortfolioLobbyingPeriod{
				{
					PortfolioName: "Prime Minister of Canada",
					StartDate:     "2026-04-28",
					EndDate:       "",
					Communications: []usecase.MinisterLobbyingCommunication{
						{ID: "COM-1", OrganizationName: "Example Org", Citation: usecase.Citation, SourceURL: usecase.SourceURL},
					},
				},
			},
		},
	}
	setMinisterPortfolioServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/ministers/314774/lobbying-by-portfolio",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotMemberID != "314774" {
		t.Fatalf("member id = %q, want 314774", stub.gotMemberID)
	}

	var body usecase.MinisterLobbyingByPortfolioResult
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.TotalCommunications != 1 || len(body.Portfolios) != 1 {
		t.Fatalf("unexpected body: %#v", body)
	}
}

func TestHandleRequestMapsMissingMinisterToNotFound(t *testing.T) {
	setMinisterPortfolioServiceForTest(t, &stubMinisterPortfolioService{err: usecase.ErrMinisterNotFound}, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		PathParameters: map[string]string{"member_id": "missing"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestHandleRequestReturnsCabinetLobbyingOverview(t *testing.T) {
	stub := &stubCabinetOverviewService{
		result: usecase.CabinetLobbyingOverviewResult{
			Parliament:      45,
			PortfolioFilter: "Finance",
			Citation:        usecase.Citation,
			SourceURL:       usecase.SourceURL,
			Ministers: []usecase.CabinetLobbyingSummary{
				{MemberID: "123", MinisterName: "Finance Minister", TotalCommunications: 3},
			},
		},
	}
	setCabinetOverviewServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/cabinet/lobbying-overview",
		QueryStringParameters: map[string]string{
			"parliament": "45",
			"portfolio":  "Finance",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput != (usecase.CabinetLobbyingOverviewInput{Parliament: 45, Portfolio: "Finance"}) {
		t.Fatalf("input = %#v", stub.gotInput)
	}

	var body usecase.CabinetLobbyingOverviewResult
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if len(body.Ministers) != 1 || body.Ministers[0].TotalCommunications != 3 {
		t.Fatalf("unexpected body: %#v", body)
	}
}

func TestHandleRequestUsesRouteKeyForCabinetLobbyingOverview(t *testing.T) {
	stub := &stubCabinetOverviewService{
		result: usecase.CabinetLobbyingOverviewResult{
			Parliament: 45,
			Citation:   usecase.Citation,
			SourceURL:  usecase.SourceURL,
		},
	}
	setCabinetOverviewServiceForTest(t, stub, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:  "/",
		RouteKey: "GET /api/v1/cabinet/lobbying-overview",
		QueryStringParameters: map[string]string{
			"parliament": "45",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if stub.gotInput.Parliament != 45 {
		t.Fatalf("input = %#v", stub.gotInput)
	}
}

func TestHandleRequestRequiresCabinetParliament(t *testing.T) {
	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/cabinet/lobbying-overview",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
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

func setMinisterPortfolioServiceForTest(t *testing.T, service ministerPortfolioExecutor, err error) {
	t.Helper()
	original := newMinisterPortfolioService
	newMinisterPortfolioService = func(context.Context) (ministerPortfolioExecutor, closeFunc, error) {
		return service, noopClose, err
	}
	t.Cleanup(func() { newMinisterPortfolioService = original })
}

func setCabinetOverviewServiceForTest(t *testing.T, service cabinetOverviewExecutor, err error) {
	t.Helper()
	original := newCabinetOverviewService
	newCabinetOverviewService = func(context.Context) (cabinetOverviewExecutor, closeFunc, error) {
		return service, noopClose, err
	}
	t.Cleanup(func() { newCabinetOverviewService = original })
}

func setMPLobbyingExposureServiceForTest(t *testing.T, service mpLobbyingExposureExecutor, err error) {
	t.Helper()
	original := newMPLobbyingExposureService
	newMPLobbyingExposureService = func(context.Context) (mpLobbyingExposureExecutor, closeFunc, error) {
		return service, noopClose, err
	}
	t.Cleanup(func() { newMPLobbyingExposureService = original })
}
