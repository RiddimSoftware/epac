package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"testing"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
)

type stubOrganizationBrowser struct {
	gotInput      application.BrowseLobbyistOrganizationsInput
	organizations []domain.LobbyistOrganization
	err           error
}

func (s *stubOrganizationBrowser) Execute(_ context.Context, input application.BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	s.gotInput = input
	return s.organizations, s.err
}

type stubOrganizationProfile struct {
	gotID        string
	organization domain.LobbyistOrganization
	err          error
}

func (s *stubOrganizationProfile) Execute(_ context.Context, organizationID string) (domain.LobbyistOrganization, error) {
	s.gotID = organizationID
	return s.organization, s.err
}

func TestHandleRequestReturnsOrganizationDirectoryFilteredSearchedAndSorted(t *testing.T) {
	browser := &stubOrganizationBrowser{
		organizations: []domain.LobbyistOrganization{
			{
				ID:     "ocl:200",
				Name:   "Clean Energy Canada",
				Type:   domain.OrganizationTypeNonProfit,
				Sector: "Energy",
				CommunicationVolume: domain.CommunicationCount{
					CurrentParliament: 17,
				},
			},
		},
	}
	setOrganizationServicesForTest(t, browser, &stubOrganizationProfile{}, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/organizations",
		QueryStringParameters: map[string]string{
			"search":    "energy",
			"sector":    "Energy",
			"sort":      "communication_volume",
			"direction": "desc",
			"page":      "2",
			"per_page":  "10",
		},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	wantInput := application.BrowseLobbyistOrganizationsInput{
		Search:        "energy",
		Sector:        "Energy",
		Limit:         10,
		Offset:        10,
		SortDirection: "desc",
	}
	if browser.gotInput != wantInput {
		t.Fatalf("browse input = %#v, want %#v", browser.gotInput, wantInput)
	}

	var body organizationDirectoryResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Citation != usecase.Citation || body.SourceURL != usecase.SourceURL {
		t.Fatalf("directory response missing source fields: %#v", body)
	}
	if len(body.Rows) != 1 || body.Rows[0].Name != "Clean Energy Canada" || body.Rows[0].CommunicationVolumeCurrent != 17 {
		t.Fatalf("directory rows = %#v", body.Rows)
	}
}

func TestHandleRequestReturnsEmptyOrganizationDirectory(t *testing.T) {
	setOrganizationServicesForTest(t, &stubOrganizationBrowser{}, &stubOrganizationProfile{}, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/lobbying/organizations",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}

	var body organizationDirectoryResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Page != 1 || body.PerPage != usecase.DefaultPerPage || len(body.Rows) != 0 || body.Citation != usecase.Citation {
		t.Fatalf("empty directory body = %#v", body)
	}
}

func TestHandleRequestReturnsPopulatedOrganizationProfile(t *testing.T) {
	profile := &stubOrganizationProfile{
		organization: domain.LobbyistOrganization{
			ID:                "ocl:42",
			OCLOrganizationID: "42",
			Name:              "Canadian Housing Alliance",
			Type:              domain.OrganizationTypeAssociation,
			Sector:            "Housing",
			RegisteredLobbyists: []domain.RegisteredLobbyist{
				{Name: "Jane Lobbyist", Kind: domain.LobbyistKindConsultant},
			},
			ActiveSubjectMatters: []string{"Housing", "Infrastructure"},
			CommunicationVolume: domain.CommunicationCount{
				CurrentParliament: 8,
				PriorParliament:   5,
			},
			TopDPOHsContacted: []domain.DPOHContact{
				{MemberID: "278707", Name: "Example Minister", Institution: "House of Commons", Count: 4},
			},
		},
	}
	setOrganizationServicesForTest(t, &stubOrganizationBrowser{}, profile, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/organizations/ocl%3A42",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}
	if profile.gotID != "ocl:42" {
		t.Fatalf("profile id = %q, want ocl:42", profile.gotID)
	}

	var body organizationProfileResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.Citation != usecase.Citation || body.CommunicationVolume.CurrentParliament != 8 {
		t.Fatalf("profile body = %#v", body)
	}
	if len(body.TopDPOHsContacted) != 1 || body.TopDPOHsContacted[0].MemberID != "278707" {
		t.Fatalf("top dpohs = %#v", body.TopDPOHsContacted)
	}
}

func TestHandleRequestReturnsProfileWithNoCommunications(t *testing.T) {
	profile := &stubOrganizationProfile{
		organization: domain.LobbyistOrganization{
			ID:                   "ocl:empty",
			Name:                 "Quiet Organization",
			Type:                 domain.OrganizationTypeCorporation,
			RegisteredLobbyists:  nil,
			ActiveSubjectMatters: nil,
			TopDPOHsContacted:    nil,
		},
	}
	setOrganizationServicesForTest(t, &stubOrganizationBrowser{}, profile, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		PathParameters: map[string]string{"id": "ocl:empty"},
		RawPath:        "/api/v1/lobbying/organizations/ocl:empty",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, body = %s", resp.StatusCode, resp.Body)
	}

	var body organizationProfileResponse
	if err := json.Unmarshal([]byte(resp.Body), &body); err != nil {
		t.Fatalf("decode body: %v", err)
	}
	if body.CommunicationVolume.CurrentParliament != 0 || body.CommunicationVolume.PriorParliament != 0 {
		t.Fatalf("communication volume = %#v", body.CommunicationVolume)
	}
	if len(body.TopDPOHsContacted) != 0 || len(body.RegisteredLobbyists) != 0 || len(body.ActiveSubjectMatters) != 0 {
		t.Fatalf("expected empty arrays in no-communications profile: %#v", body)
	}
}

func TestHandleRequestRejectsInvalidOrganizationSort(t *testing.T) {
	setOrganizationServicesForTest(t, &stubOrganizationBrowser{}, &stubOrganizationProfile{}, nil)

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath:               "/api/v1/lobbying/organizations",
		QueryStringParameters: map[string]string{"sort": "name"},
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

func TestOrganizationRequestDoesNotClaimGenericIDOnOtherRoutes(t *testing.T) {
	if isOrganizationRequest(events.APIGatewayV2HTTPRequest{
		PathParameters: map[string]string{"id": "314774"},
		RawPath:        "/api/v1/ministers/314774/lobbying-by-portfolio",
	}) {
		t.Fatal("minister route with generic id path parameter was claimed as organization request")
	}
}

func TestHandleRequestMapsOrganizationServiceInitError(t *testing.T) {
	setOrganizationServicesForTest(t, nil, nil, errors.New("not configured"))

	resp, err := HandleRequest(context.Background(), events.APIGatewayV2HTTPRequest{
		RawPath: "/api/v1/lobbying/organizations",
	})
	if err != nil {
		t.Fatalf("HandleRequest: %v", err)
	}
	if resp.StatusCode != http.StatusServiceUnavailable {
		t.Fatalf("status = %d, want 503", resp.StatusCode)
	}
}

func setOrganizationServicesForTest(t *testing.T, browser organizationBrowser, profile organizationProfileLoader, err error) {
	t.Helper()
	original := newOrganizationServices
	newOrganizationServices = func(context.Context) (organizationServices, closeFunc, error) {
		return organizationServices{browser: browser, profile: profile}, noopClose, err
	}
	t.Cleanup(func() { newOrganizationServices = original })
}
