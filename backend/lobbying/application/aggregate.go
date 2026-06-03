package application

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"

	"epac/lobbying/domain"
)

var (
	ErrDirectoryRequired  = errors.New("organization directory query is required")
	ErrRepositoryRequired = errors.New("lobbyist organization repository is required")
)

type OrganizationDirectoryQuery interface {
	ListOrganizationRegistrations(ctx context.Context) ([]OrganizationRegistration, error)
	ListOrganizationCommunications(ctx context.Context) ([]OrganizationCommunication, error)
}

type LobbyistOrganizationRepository interface {
	SaveLobbyistOrganizations(ctx context.Context, organizations []domain.LobbyistOrganization) error
	LoadLobbyistOrganization(ctx context.Context, organizationID string) (domain.LobbyistOrganization, error)
	BrowseLobbyistOrganizations(ctx context.Context, input BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error)
}

type OrganizationRegistration struct {
	SourceID          string
	OCLOrganizationID string
	OrganizationName  string
	RegistrationType  string
	Sector            string
	EffectiveDate     *time.Time
	EndDate           *time.Time
	Lobbyists         []domain.RegisteredLobbyist
	SubjectMatters    []string
}

type OrganizationCommunication struct {
	SourceID          string
	OCLOrganizationID string
	OrganizationName  string
	RegistrantName    string
	RegistrantType    string
	CommunicationDate *time.Time
	SubjectMatters    []string
	DPOHs             []domain.DPOHContact
}

type AggregateLobbyistOrganizationsInput struct {
	CurrentParliament domain.ParliamentSession
	PriorParliament   domain.ParliamentSession
	Now               time.Time
}

type BrowseLobbyistOrganizationsInput struct {
	Search string
	Limit  int
	Offset int
}

type AggregateLobbyistOrganizations struct {
	directory  OrganizationDirectoryQuery
	repository LobbyistOrganizationRepository
	normalizer NameAliasNormalizer
}

func NewAggregateLobbyistOrganizations(
	directory OrganizationDirectoryQuery,
	repository LobbyistOrganizationRepository,
	normalizer NameAliasNormalizer,
) (*AggregateLobbyistOrganizations, error) {
	if directory == nil {
		return nil, ErrDirectoryRequired
	}
	if repository == nil {
		return nil, ErrRepositoryRequired
	}
	return &AggregateLobbyistOrganizations{directory: directory, repository: repository, normalizer: normalizer}, nil
}

func (u *AggregateLobbyistOrganizations) Execute(ctx context.Context, input AggregateLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	now := input.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}

	registrations, err := u.directory.ListOrganizationRegistrations(ctx)
	if err != nil {
		return nil, err
	}
	communications, err := u.directory.ListOrganizationCommunications(ctx)
	if err != nil {
		return nil, err
	}

	builders := make(map[string]*organizationBuilder)
	for _, registration := range registrations {
		resolution, err := u.normalizer.Resolve(ctx, OrganizationNameCandidate{
			OCLOrganizationID: registration.OCLOrganizationID,
			Name:              registration.OrganizationName,
			SourceTable:       "ocl_registration_primary",
			SourceID:          registration.SourceID,
		})
		if err != nil {
			return nil, err
		}
		builder := builderFor(builders, resolution.OrganizationID, registration.OCLOrganizationID, registration.OrganizationName)
		builder.applyRegistration(registration, now)
	}

	for _, communication := range communications {
		resolution, err := u.normalizer.Resolve(ctx, OrganizationNameCandidate{
			OCLOrganizationID: communication.OCLOrganizationID,
			Name:              communication.OrganizationName,
			SourceTable:       "ocl_communication_primary",
			SourceID:          communication.SourceID,
		})
		if err != nil {
			return nil, err
		}
		builder := builderFor(builders, resolution.OrganizationID, communication.OCLOrganizationID, communication.OrganizationName)
		builder.applyCommunication(communication, input.CurrentParliament, input.PriorParliament)
	}

	organizations := make([]domain.LobbyistOrganization, 0, len(builders))
	for _, builder := range builders {
		organizations = append(organizations, builder.organization(now))
	}
	sort.Slice(organizations, func(i, j int) bool {
		return organizations[i].ID < organizations[j].ID
	})
	if err := u.repository.SaveLobbyistOrganizations(ctx, organizations); err != nil {
		return nil, err
	}
	return organizations, nil
}

type LoadLobbyistOrganizationProfile struct {
	repository LobbyistOrganizationRepository
}

func NewLoadLobbyistOrganizationProfile(repository LobbyistOrganizationRepository) (*LoadLobbyistOrganizationProfile, error) {
	if repository == nil {
		return nil, ErrRepositoryRequired
	}
	return &LoadLobbyistOrganizationProfile{repository: repository}, nil
}

func (u *LoadLobbyistOrganizationProfile) Execute(ctx context.Context, organizationID string) (domain.LobbyistOrganization, error) {
	return u.repository.LoadLobbyistOrganization(ctx, organizationID)
}

type BrowseLobbyistOrganizations struct {
	repository LobbyistOrganizationRepository
}

func NewBrowseLobbyistOrganizations(repository LobbyistOrganizationRepository) (*BrowseLobbyistOrganizations, error) {
	if repository == nil {
		return nil, ErrRepositoryRequired
	}
	return &BrowseLobbyistOrganizations{repository: repository}, nil
}

func (u *BrowseLobbyistOrganizations) Execute(ctx context.Context, input BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	return u.repository.BrowseLobbyistOrganizations(ctx, input)
}

type organizationBuilder struct {
	id                   string
	oclOrganizationID    string
	name                 string
	orgType              domain.OrganizationType
	orgTypeRank          int
	sectorCounts         map[string]int
	lobbyists            map[string]domain.RegisteredLobbyist
	activeSubjectMatters map[string]struct{}
	communicationVolume  domain.CommunicationCount
	dpohCounts           map[string]domain.DPOHContact
}

func builderFor(builders map[string]*organizationBuilder, id, oclOrganizationID, name string) *organizationBuilder {
	builder, ok := builders[id]
	if !ok {
		builder = &organizationBuilder{
			id:                   id,
			orgType:              domain.OrganizationTypeCorporation,
			sectorCounts:         map[string]int{},
			lobbyists:            map[string]domain.RegisteredLobbyist{},
			activeSubjectMatters: map[string]struct{}{},
			dpohCounts:           map[string]domain.DPOHContact{},
		}
		builders[id] = builder
	}
	if builder.oclOrganizationID == "" && strings.TrimSpace(oclOrganizationID) != "" {
		builder.oclOrganizationID = strings.TrimSpace(oclOrganizationID)
	}
	if builder.oclOrganizationID == "" && strings.HasPrefix(id, "ocl:") {
		builder.oclOrganizationID = strings.TrimPrefix(id, "ocl:")
	}
	if builder.name == "" || strings.TrimSpace(oclOrganizationID) != "" {
		builder.name = cleanNullableString(name)
	}
	return builder
}

func (b *organizationBuilder) applyRegistration(registration OrganizationRegistration, activeOn time.Time) {
	orgType := classifyOrganization(registration.RegistrationType, registration.OrganizationName)
	if rank := organizationTypeRank(orgType); rank > b.orgTypeRank {
		b.orgType = orgType
		b.orgTypeRank = rank
	}
	if sector := cleanNullableString(registration.Sector); sector != "" {
		b.sectorCounts[sector]++
	}
	for _, lobbyist := range registration.Lobbyists {
		lobbyist.Name = cleanNullableString(lobbyist.Name)
		if lobbyist.Name == "" {
			continue
		}
		if lobbyist.Kind == "" {
			lobbyist.Kind = lobbyistKindForRegistration(registration.RegistrationType)
		}
		b.lobbyists[NormalizeOrganizationName(lobbyist.Name)+"|"+string(lobbyist.Kind)] = lobbyist
	}
	if isRegistrationActive(registration, activeOn) {
		for _, subject := range registration.SubjectMatters {
			subject = cleanNullableString(subject)
			if subject != "" {
				b.activeSubjectMatters[subject] = struct{}{}
			}
		}
	}
}

func (b *organizationBuilder) applyCommunication(
	communication OrganizationCommunication,
	current domain.ParliamentSession,
	prior domain.ParliamentSession,
) {
	if name := cleanNullableString(communication.RegistrantName); name != "" {
		b.lobbyists[NormalizeOrganizationName(name)+"|"+string(lobbyistKindForRegistration(communication.RegistrantType))] = domain.RegisteredLobbyist{
			Name: name,
			Kind: lobbyistKindForRegistration(communication.RegistrantType),
		}
	}
	if communication.CommunicationDate != nil {
		switch {
		case current.Contains(*communication.CommunicationDate):
			b.communicationVolume.CurrentParliament++
		case prior.Contains(*communication.CommunicationDate):
			b.communicationVolume.PriorParliament++
		}
	}
	for _, dpoh := range communication.DPOHs {
		dpoh.Name = cleanNullableString(dpoh.Name)
		dpoh.Institution = cleanNullableString(dpoh.Institution)
		if dpoh.Name == "" {
			continue
		}
		key := NormalizeOrganizationName(dpoh.Name) + "|" + NormalizeOrganizationName(dpoh.Institution)
		existing := b.dpohCounts[key]
		if existing.Count == 0 {
			existing = domain.DPOHContact{Name: dpoh.Name, Institution: dpoh.Institution}
		}
		increment := dpoh.Count
		if increment <= 0 {
			increment = 1
		}
		existing.Count += increment
		b.dpohCounts[key] = existing
	}
}

func (b organizationBuilder) organization(updatedAt time.Time) domain.LobbyistOrganization {
	return domain.LobbyistOrganization{
		ID:                   b.id,
		OCLOrganizationID:    b.oclOrganizationID,
		Name:                 b.name,
		Type:                 b.orgType,
		Sector:               topSector(b.sectorCounts),
		RegisteredLobbyists:  sortedLobbyists(b.lobbyists),
		ActiveSubjectMatters: sortedStringsFromSet(b.activeSubjectMatters),
		CommunicationVolume:  b.communicationVolume,
		TopDPOHsContacted:    topDPOHs(b.dpohCounts, 5),
		UpdatedAt:            updatedAt.UTC(),
	}
}

func isRegistrationActive(registration OrganizationRegistration, activeOn time.Time) bool {
	if activeOn.IsZero() {
		return true
	}
	if registration.EffectiveDate != nil && registration.EffectiveDate.After(activeOn) {
		return false
	}
	return registration.EndDate == nil || registration.EndDate.IsZero() || !registration.EndDate.Before(activeOn)
}

func classifyOrganization(registrationType, name string) domain.OrganizationType {
	normalizedName := NormalizeOrganizationName(name)
	switch {
	case containsAnyToken(normalizedName, "first nation", "metis", "inuit", "tribal council", "cree nation", "anishinabek", "indigenous"):
		return domain.OrganizationTypeIndigenousOrganization
	case containsAnyToken(normalizedName, "foundation", "charity", "society", "non profit", "not for profit"):
		return domain.OrganizationTypeNonProfit
	case containsAnyToken(normalizedName, "association", "federation", "chamber", "coalition", "council", "alliance", "union"):
		return domain.OrganizationTypeAssociation
	case containsAnyToken(normalizedName, "inc", "incorporated", "ltd", "limited", "corp", "corporation", "company"):
		return domain.OrganizationTypeCorporation
	}

	switch registrationTypeName(registrationType) {
	case "in-house organization":
		return domain.OrganizationTypeAssociation
	default:
		return domain.OrganizationTypeCorporation
	}
}

func lobbyistKindForRegistration(registrationType string) domain.LobbyistKind {
	if registrationTypeName(registrationType) == "consultant" {
		return domain.LobbyistKindConsultant
	}
	return domain.LobbyistKindInHouse
}

func registrationTypeName(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "1", "consultant":
		return "consultant"
	case "2", "in-house corporation", "in house corporation", "in-house (corporation)":
		return "in-house corporation"
	case "3", "in-house organization", "in house organization", "in-house (organization)":
		return "in-house organization"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

func organizationTypeRank(value domain.OrganizationType) int {
	switch value {
	case domain.OrganizationTypeIndigenousOrganization:
		return 4
	case domain.OrganizationTypeNonProfit:
		return 3
	case domain.OrganizationTypeAssociation:
		return 2
	default:
		return 1
	}
}

func containsAnyToken(value string, tokens ...string) bool {
	for _, token := range tokens {
		if strings.Contains(value, token) {
			return true
		}
	}
	return false
}

func topSector(counts map[string]int) string {
	type sectorCount struct {
		sector string
		count  int
	}
	values := make([]sectorCount, 0, len(counts))
	for sector, count := range counts {
		values = append(values, sectorCount{sector: sector, count: count})
	}
	sort.Slice(values, func(i, j int) bool {
		if values[i].count != values[j].count {
			return values[i].count > values[j].count
		}
		return values[i].sector < values[j].sector
	})
	if len(values) == 0 {
		return ""
	}
	return values[0].sector
}

func sortedLobbyists(values map[string]domain.RegisteredLobbyist) []domain.RegisteredLobbyist {
	out := make([]domain.RegisteredLobbyist, 0, len(values))
	for _, value := range values {
		out = append(out, value)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Kind != out[j].Kind {
			return out[i].Kind < out[j].Kind
		}
		return out[i].Name < out[j].Name
	})
	return out
}

func sortedStringsFromSet(values map[string]struct{}) []string {
	out := make([]string, 0, len(values))
	for value := range values {
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func topDPOHs(values map[string]domain.DPOHContact, limit int) []domain.DPOHContact {
	out := make([]domain.DPOHContact, 0, len(values))
	for _, value := range values {
		out = append(out, value)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		if out[i].Name != out[j].Name {
			return out[i].Name < out[j].Name
		}
		return out[i].Institution < out[j].Institution
	})
	if len(out) > limit {
		return out[:limit]
	}
	return out
}

func cleanNullableString(value string) string {
	value = strings.TrimSpace(value)
	if strings.EqualFold(value, "null") {
		return ""
	}
	return value
}
