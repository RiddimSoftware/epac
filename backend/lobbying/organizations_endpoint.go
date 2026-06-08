package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"epac/lobbying/application"
	"epac/lobbying/domain"
	sqliteadapter "epac/lobbying/internal/adapter/sqlite"
	"epac/lobbying/internal/usecase"

	"github.com/aws/aws-lambda-go/events"
)

type organizationBrowser interface {
	Execute(context.Context, application.BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error)
}

type organizationProfileLoader interface {
	Execute(context.Context, string) (domain.LobbyistOrganization, error)
}

type organizationServices struct {
	browser organizationBrowser
	profile organizationProfileLoader
}

var newOrganizationServices = newProductionOrganizationServices

type organizationDirectoryResponse struct {
	Page      int                        `json:"page"`
	PerPage   int                        `json:"per_page"`
	Citation  string                     `json:"citation"`
	SourceURL string                     `json:"source_url"`
	Rows      []organizationDirectoryRow `json:"rows"`
}

type organizationDirectoryRow struct {
	ID                         string                  `json:"id"`
	Name                       string                  `json:"name"`
	Type                       domain.OrganizationType `json:"type"`
	Sector                     string                  `json:"sector,omitempty"`
	CommunicationVolumeCurrent int                     `json:"communication_volume_current_parliament"`
}

type organizationProfileResponse struct {
	ID                   string                                     `json:"id"`
	OCLOrganizationID    string                                     `json:"ocl_organization_id,omitempty"`
	Name                 string                                     `json:"name"`
	Type                 domain.OrganizationType                    `json:"type"`
	Sector               string                                     `json:"sector,omitempty"`
	RegisteredLobbyists  []domain.RegisteredLobbyist                `json:"registered_lobbyists"`
	ActiveSubjectMatters []string                                   `json:"active_subject_matters"`
	CommunicationVolume  domain.CommunicationCount                  `json:"communication_volume"`
	TopDPOHsContacted    []domain.DPOHContact                       `json:"top_dpohs_contacted"`
	RegistrationStatus   domain.RegistrationStatus                  `json:"registration_status"`
	Registrations        []domain.LobbyistRegistration              `json:"registrations"`
	RecentCommunications []domain.LobbyistOrganizationCommunication `json:"recent_communications"`
	SubjectMatters       []domain.LobbyistOrganizationSubjectMatter `json:"subject_matters"`
	Citation             string                                     `json:"citation"`
	SourceURL            string                                     `json:"source_url"`
}

func handleOrganizationRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if profileID, ok := organizationProfileIDFromRequest(req); ok {
		return handleOrganizationProfile(ctx, req, profileID)
	}
	if isOrganizationDirectoryRequest(req) {
		return handleOrganizationDirectory(ctx, req)
	}
	return jsonError(http.StatusNotFound, "not found"), nil
}

func handleOrganizationDirectory(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	pagination, err := parsePagination(req.QueryStringParameters)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}
	sortDirection, err := parseOrganizationSort(req.QueryStringParameters)
	if err != nil {
		return jsonError(http.StatusBadRequest, err.Error()), nil
	}

	services, closeServices, err := newOrganizationServices(ctx)
	if err != nil {
		slog.Error("organization service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeServices(ctx)

	organizations, err := services.browser.Execute(ctx, application.BrowseLobbyistOrganizationsInput{
		Search:        strings.TrimSpace(req.QueryStringParameters["search"]),
		Sector:        strings.TrimSpace(req.QueryStringParameters["sector"]),
		Limit:         pagination.PerPage,
		Offset:        (pagination.Page - 1) * pagination.PerPage,
		SortDirection: sortDirection,
	})
	if err != nil {
		slog.Error("organization directory request failed", "error", err)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}

	rows := make([]organizationDirectoryRow, 0, len(organizations))
	for _, organization := range organizations {
		rows = append(rows, organizationDirectoryRow{
			ID:                         organization.ID,
			Name:                       organization.Name,
			Type:                       organization.Type,
			Sector:                     organization.Sector,
			CommunicationVolumeCurrent: organization.CommunicationVolume.CurrentParliament,
		})
	}
	body, err := json.Marshal(organizationDirectoryResponse{
		Page:      pagination.Page,
		PerPage:   pagination.PerPage,
		Citation:  usecase.Citation,
		SourceURL: usecase.SourceURL,
		Rows:      rows,
	})
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func handleOrganizationProfile(ctx context.Context, _ events.APIGatewayV2HTTPRequest, organizationID string) (events.APIGatewayV2HTTPResponse, error) {
	organizationID = strings.TrimSpace(organizationID)
	if organizationID == "" {
		return jsonError(http.StatusBadRequest, "missing organization id"), nil
	}

	services, closeServices, err := newOrganizationServices(ctx)
	if err != nil {
		slog.Error("organization service initialization failed", "error", err)
		return serviceUnavailableError(err), nil
	}
	defer closeServices(ctx)

	organization, err := services.profile.Execute(ctx, organizationID)
	if err != nil {
		slog.Error("organization profile request failed", "error", err, "organization_id", organizationID)
		return jsonError(http.StatusInternalServerError, "internal error"), nil
	}

	body, err := json.Marshal(profileResponseFor(organization))
	if err != nil {
		return jsonError(http.StatusInternalServerError, "marshal error"), nil
	}
	return jsonResponse(http.StatusOK, body), nil
}

func newProductionOrganizationServices(ctx context.Context) (organizationServices, closeFunc, error) {
	db, err := lobbyingDB.DB(ctx)
	if err != nil {
		return organizationServices{}, noopClose, err
	}
	repo := sqliteadapter.New(db)
	browser, err := application.NewBrowseLobbyistOrganizations(repo)
	if err != nil {
		return organizationServices{}, noopClose, err
	}
	profile, err := application.NewLoadLobbyistOrganizationProfile(repo)
	if err != nil {
		return organizationServices{}, noopClose, err
	}
	return organizationServices{browser: browser, profile: profile}, noopClose, nil
}

func parseOrganizationSort(params map[string]string) (string, error) {
	sortBy := strings.TrimSpace(params["sort"])
	if sortBy != "" && sortBy != "communication_volume" && sortBy != "communication_volume_current_parliament" {
		return "", errors.New("sort must be communication_volume")
	}
	direction := strings.ToLower(strings.TrimSpace(params["direction"]))
	switch direction {
	case "", "desc":
		return "desc", nil
	case "asc":
		return "asc", nil
	default:
		return "", errors.New("direction must be asc or desc")
	}
}

func profileResponseFor(organization domain.LobbyistOrganization) organizationProfileResponse {
	return organizationProfileResponse{
		ID:                   organization.ID,
		OCLOrganizationID:    organization.OCLOrganizationID,
		Name:                 organization.Name,
		Type:                 organization.Type,
		Sector:               organization.Sector,
		RegisteredLobbyists:  nonNilLobbyists(organization.RegisteredLobbyists),
		ActiveSubjectMatters: nonNilStrings(organization.ActiveSubjectMatters),
		CommunicationVolume:  organization.CommunicationVolume,
		TopDPOHsContacted:    nonNilDPOHs(organization.TopDPOHsContacted),
		RegistrationStatus:   normalizedRegistrationStatus(organization.RegistrationStatus),
		Registrations:        nonNilRegistrations(organization.Registrations),
		RecentCommunications: nonNilCommunications(organization.RecentCommunications),
		SubjectMatters:       nonNilSubjectMatters(organization.SubjectMatters),
		Citation:             usecase.Citation,
		SourceURL:            organizationSourceURL(organization),
	}
}

func isOrganizationRequest(req events.APIGatewayV2HTTPRequest) bool {
	if isOrganizationDirectoryRequest(req) {
		return true
	}
	_, ok := organizationProfileIDFromRequest(req)
	return ok
}

func isOrganizationDirectoryRequest(req events.APIGatewayV2HTTPRequest) bool {
	for _, path := range requestPaths(req) {
		if path == "/api/v1/lobbying/organizations" || path == "/lobbying/organizations" {
			return true
		}
	}
	return false
}

func organizationProfileIDFromRequest(req events.APIGatewayV2HTTPRequest) (string, bool) {
	for _, path := range requestPaths(req) {
		for _, prefix := range []string{"/api/v1/lobbying/organizations/", "/lobbying/organizations/"} {
			if !strings.HasPrefix(path, prefix) {
				continue
			}
			id := strings.TrimSpace(req.PathParameters["id"])
			if id == "" {
				id = strings.TrimPrefix(path, prefix)
			}
			if id != "" && !strings.Contains(id, "/") {
				return unescapePathPart(id), true
			}
		}
	}
	return "", false
}

func nonNilLobbyists(values []domain.RegisteredLobbyist) []domain.RegisteredLobbyist {
	if values == nil {
		return []domain.RegisteredLobbyist{}
	}
	return values
}

func nonNilStrings(values []string) []string {
	if values == nil {
		return []string{}
	}
	return values
}

func nonNilDPOHs(values []domain.DPOHContact) []domain.DPOHContact {
	if values == nil {
		return []domain.DPOHContact{}
	}
	return values
}

func normalizedRegistrationStatus(value domain.RegistrationStatus) domain.RegistrationStatus {
	if value == "" {
		return domain.RegistrationStatusExpired
	}
	return value
}

func nonNilRegistrations(values []domain.LobbyistRegistration) []domain.LobbyistRegistration {
	if values == nil {
		return []domain.LobbyistRegistration{}
	}
	return values
}

func nonNilCommunications(
	values []domain.LobbyistOrganizationCommunication,
) []domain.LobbyistOrganizationCommunication {
	if values == nil {
		return []domain.LobbyistOrganizationCommunication{}
	}
	return values
}

func nonNilSubjectMatters(
	values []domain.LobbyistOrganizationSubjectMatter,
) []domain.LobbyistOrganizationSubjectMatter {
	if values == nil {
		return []domain.LobbyistOrganizationSubjectMatter{}
	}
	return values
}

func organizationSourceURL(organization domain.LobbyistOrganization) string {
	for _, registration := range organization.Registrations {
		if registration.SourceURL != "" {
			return registration.SourceURL
		}
	}
	return usecase.SourceURL
}
