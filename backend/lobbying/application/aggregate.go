package application

import (
	"context"
	"errors"
	"net/url"
	"sort"
	"strings"
	"time"

	"epac/lobbying/domain"
)

var (
	ErrDirectoryRequired  = errors.New("organization directory query is required")
	ErrRepositoryRequired = errors.New("lobbyist organization repository is required")
)

const oclRegistrationReportsURL = "https://www.lobbycanada.gc.ca/app/secure/ocl/lrs/do/rgstrnCmmnctnRprts?lang=eng&regId="

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
	SourceID             string
	OCLOrganizationID    string
	OrganizationName     string
	RegistrationType     string
	Sector               string
	EffectiveDate        *time.Time
	EndDate              *time.Time
	Lobbyists            []domain.RegisteredLobbyist
	SubjectMatters       []string
	TargetedInstitutions []string
}

type OrganizationCommunication struct {
	SourceID          string
	OCLOrganizationID string
	OrganizationName  string
	RegistrantName    string
	RegistrantType    string
	CommunicationDate *time.Time
	SubjectMatters    []string
	SubjectMatterRefs []OrganizationSubjectMatter
	DPOHs             []domain.DPOHContact
}

type OrganizationSubjectMatter struct {
	OCLCode string `json:"ocl_code"`
	Name    string `json:"name"`
}

type SubjectTopicMapping struct {
	TopicSlug  string
	Confidence float64
}

type OCLSubjectTopicSource interface {
	TopicMappingsForOCLCode(oclCode string) []SubjectTopicMapping
}

type AggregateLobbyistOrganizationsInput struct {
	CurrentParliament domain.ParliamentSession
	PriorParliament   domain.ParliamentSession
	Now               time.Time
}

type BrowseLobbyistOrganizationsInput struct {
	Search        string
	Sector        string
	Limit         int
	Offset        int
	SortDirection string
}

type AggregateLobbyistOrganizations struct {
	directory  OrganizationDirectoryQuery
	repository LobbyistOrganizationRepository
	normalizer NameAliasNormalizer
	topics     OCLSubjectTopicSource
}

type AggregateLobbyistOrganizationsOption func(*AggregateLobbyistOrganizations)

func WithOCLSubjectTopicSource(source OCLSubjectTopicSource) AggregateLobbyistOrganizationsOption {
	return func(u *AggregateLobbyistOrganizations) {
		u.topics = source
	}
}

func NewAggregateLobbyistOrganizations(
	directory OrganizationDirectoryQuery,
	repository LobbyistOrganizationRepository,
	normalizer NameAliasNormalizer,
	options ...AggregateLobbyistOrganizationsOption,
) (*AggregateLobbyistOrganizations, error) {
	if directory == nil {
		return nil, ErrDirectoryRequired
	}
	if repository == nil {
		return nil, ErrRepositoryRequired
	}
	useCase := &AggregateLobbyistOrganizations{directory: directory, repository: repository, normalizer: normalizer}
	for _, option := range options {
		option(useCase)
	}
	return useCase, nil
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
		builder.applyCommunication(communication, input.CurrentParliament, input.PriorParliament, u.topics)
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
	registrations        map[string]domain.LobbyistRegistration
	recentCommunications []domain.LobbyistOrganizationCommunication
	subjectCounts        map[string]subjectMatterCount
}

type subjectMatterCount struct {
	count     int
	topicSlug string
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
			registrations:        map[string]domain.LobbyistRegistration{},
			subjectCounts:        map[string]subjectMatterCount{},
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
	b.applyRegistrationProfileRow(registration, activeOn)
}

func (b *organizationBuilder) applyCommunication(
	communication OrganizationCommunication,
	current domain.ParliamentSession,
	prior domain.ParliamentSession,
	topics OCLSubjectTopicSource,
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
	subjects := communicationSubjectMatters(communication, topics)
	subjectNames := make([]string, 0, len(subjects))
	for _, subject := range subjects {
		subjectNames = append(subjectNames, subject.name)
		b.countSubjectMatter(subject)
	}
	for _, dpoh := range communication.DPOHs {
		dpoh.MemberID = cleanNullableString(dpoh.MemberID)
		dpoh.Name = cleanNullableString(dpoh.Name)
		dpoh.Institution = cleanNullableString(dpoh.Institution)
		if dpoh.Name == "" {
			continue
		}
		key := NormalizeOrganizationName(dpoh.Name) + "|" + NormalizeOrganizationName(dpoh.Institution)
		if dpoh.MemberID != "" {
			key = "member:" + dpoh.MemberID
		}
		existing := b.dpohCounts[key]
		if existing.Count == 0 {
			existing = domain.DPOHContact{MemberID: dpoh.MemberID, Name: dpoh.Name, Institution: dpoh.Institution}
		}
		if existing.MemberID == "" {
			existing.MemberID = dpoh.MemberID
		}
		increment := dpoh.Count
		if increment <= 0 {
			increment = 1
		}
		existing.Count += increment
		b.dpohCounts[key] = existing
		b.recentCommunications = append(b.recentCommunications, domain.LobbyistOrganizationCommunication{
			ID:             communication.SourceID,
			Date:           dateString(communication.CommunicationDate),
			DPOHMemberID:   dpoh.MemberID,
			DPOHName:       dpoh.Name,
			Institution:    dpoh.Institution,
			SubjectMatters: subjectNames,
			SourceURL:      domain.OCLSourceURL,
		})
	}
}

func (b *organizationBuilder) countSubjectMatter(subject countedSubjectMatter) {
	existing := b.subjectCounts[subject.name]
	existing.count++
	if existing.topicSlug == "" && subject.topicSlug != "" {
		existing.topicSlug = subject.topicSlug
	}
	b.subjectCounts[subject.name] = existing
}

func (b *organizationBuilder) applyRegistrationProfileRow(registration OrganizationRegistration, activeOn time.Time) {
	registrationID := cleanNullableString(registration.SourceID)
	if registrationID == "" {
		return
	}
	status := domain.RegistrationStatusExpired
	if isRegistrationActive(registration, activeOn) {
		status = domain.RegistrationStatusActive
	}
	b.registrations[registrationID] = domain.LobbyistRegistration{
		ID:                   registrationID,
		Status:               status,
		Kind:                 lobbyistKindForRegistration(registration.RegistrationType),
		SubjectMatters:       cleanStringList(registration.SubjectMatters),
		TargetedInstitutions: cleanStringList(registration.TargetedInstitutions),
		SourceURL:            registrationSourceURL(registrationID),
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
		RegistrationStatus:   registrationStatus(b.registrations),
		Registrations:        sortedRegistrations(b.registrations),
		RecentCommunications: recentCommunications(b.recentCommunications, 10),
		SubjectMatters:       topSubjectMatters(b.subjectCounts, 10),
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

type countedSubjectMatter struct {
	name      string
	topicSlug string
}

func communicationSubjectMatters(
	communication OrganizationCommunication,
	topics OCLSubjectTopicSource,
) []countedSubjectMatter {
	byName := map[string]countedSubjectMatter{}
	for _, subject := range communication.SubjectMatterRefs {
		name := cleanNullableString(subject.Name)
		if name == "" {
			continue
		}
		counted := byName[name]
		if counted.name == "" {
			counted.name = name
		}
		if counted.topicSlug == "" {
			counted.topicSlug = preferredTopicSlug(subject.OCLCode, topics)
		}
		byName[name] = counted
	}
	if len(byName) == 0 {
		for _, subject := range cleanStringList(communication.SubjectMatters) {
			byName[subject] = countedSubjectMatter{name: subject}
		}
	}
	out := make([]countedSubjectMatter, 0, len(byName))
	for _, subject := range byName {
		out = append(out, subject)
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].name < out[j].name
	})
	return out
}

func preferredTopicSlug(oclCode string, topics OCLSubjectTopicSource) string {
	if topics == nil {
		return ""
	}
	mappings := topics.TopicMappingsForOCLCode(oclCode)
	bestSlug := ""
	bestConfidence := -1.0
	for _, mapping := range mappings {
		slug := strings.TrimSpace(mapping.TopicSlug)
		if slug == "" {
			continue
		}
		if bestSlug == "" || mapping.Confidence > bestConfidence ||
			(mapping.Confidence == bestConfidence && slug < bestSlug) {
			bestSlug = slug
			bestConfidence = mapping.Confidence
		}
	}
	return bestSlug
}

func cleanStringList(values []string) []string {
	seen := make(map[string]struct{}, len(values))
	out := make([]string, 0, len(values))
	for _, value := range values {
		value = cleanNullableString(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func registrationStatus(values map[string]domain.LobbyistRegistration) domain.RegistrationStatus {
	for _, value := range values {
		if value.Status == domain.RegistrationStatusActive {
			return domain.RegistrationStatusActive
		}
	}
	return domain.RegistrationStatusExpired
}

func sortedRegistrations(values map[string]domain.LobbyistRegistration) []domain.LobbyistRegistration {
	out := make([]domain.LobbyistRegistration, 0, len(values))
	for _, value := range values {
		out = append(out, value)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Status != out[j].Status {
			return out[i].Status == domain.RegistrationStatusActive
		}
		if out[i].Kind != out[j].Kind {
			return out[i].Kind < out[j].Kind
		}
		return out[i].ID < out[j].ID
	})
	return out
}

func recentCommunications(
	values []domain.LobbyistOrganizationCommunication,
	limit int,
) []domain.LobbyistOrganizationCommunication {
	out := append([]domain.LobbyistOrganizationCommunication(nil), values...)
	sort.Slice(out, func(i, j int) bool {
		if out[i].Date != out[j].Date {
			return out[i].Date > out[j].Date
		}
		if out[i].ID != out[j].ID {
			return out[i].ID > out[j].ID
		}
		return out[i].DPOHName < out[j].DPOHName
	})
	if len(out) > limit {
		return out[:limit]
	}
	return out
}

func topSubjectMatters(
	counts map[string]subjectMatterCount,
	limit int,
) []domain.LobbyistOrganizationSubjectMatter {
	out := make([]domain.LobbyistOrganizationSubjectMatter, 0, len(counts))
	for subject, count := range counts {
		out = append(out, domain.LobbyistOrganizationSubjectMatter{
			SubjectMatter:      subject,
			CommunicationCount: count.count,
			TopicSlug:          count.topicSlug,
		})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CommunicationCount != out[j].CommunicationCount {
			return out[i].CommunicationCount > out[j].CommunicationCount
		}
		return out[i].SubjectMatter < out[j].SubjectMatter
	})
	if len(out) > limit {
		return out[:limit]
	}
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

func dateString(value *time.Time) string {
	if value == nil || value.IsZero() {
		return ""
	}
	return value.UTC().Format("2006-01-02")
}

func registrationSourceURL(registrationID string) string {
	registrationID = cleanNullableString(registrationID)
	if registrationID == "" {
		return domain.OCLSourceURL
	}
	return oclRegistrationReportsURL + url.QueryEscape(registrationID)
}

func cleanNullableString(value string) string {
	value = strings.TrimSpace(value)
	if strings.EqualFold(value, "null") {
		return ""
	}
	return value
}
