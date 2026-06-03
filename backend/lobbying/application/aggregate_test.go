package application

import (
	"context"
	"reflect"
	"testing"
	"time"

	"epac/lobbying/domain"
)

type fakeDirectory struct {
	registrations  []OrganizationRegistration
	communications []OrganizationCommunication
}

func (d fakeDirectory) ListOrganizationRegistrations(context.Context) ([]OrganizationRegistration, error) {
	return d.registrations, nil
}

func (d fakeDirectory) ListOrganizationCommunications(context.Context) ([]OrganizationCommunication, error) {
	return d.communications, nil
}

type fakeOrganizationRepo struct {
	saved []domain.LobbyistOrganization
}

func (r *fakeOrganizationRepo) SaveLobbyistOrganizations(_ context.Context, organizations []domain.LobbyistOrganization) error {
	r.saved = append([]domain.LobbyistOrganization(nil), organizations...)
	return nil
}

func (r *fakeOrganizationRepo) LoadLobbyistOrganization(_ context.Context, organizationID string) (domain.LobbyistOrganization, error) {
	for _, organization := range r.saved {
		if organization.ID == organizationID {
			return organization, nil
		}
	}
	return domain.LobbyistOrganization{}, nil
}

func (r *fakeOrganizationRepo) BrowseLobbyistOrganizations(context.Context, BrowseLobbyistOrganizationsInput) ([]domain.LobbyistOrganization, error) {
	return append([]domain.LobbyistOrganization(nil), r.saved...), nil
}

type fakeAliases struct {
	matches map[string][]string
	pending []PendingOrganizationAlias
}

func (a *fakeAliases) FindOrganizationIDsByNormalizedName(_ context.Context, normalizedName string) ([]string, error) {
	return append([]string(nil), a.matches[normalizedName]...), nil
}

func (a *fakeAliases) LogPendingOrganizationAlias(_ context.Context, pending PendingOrganizationAlias) error {
	a.pending = append(a.pending, pending)
	return nil
}

func TestAggregateFromFixtureRegistrations(t *testing.T) {
	currentFrom := mustDate(t, "2026-01-01")
	currentTo := mustDate(t, "2026-12-31")
	priorFrom := mustDate(t, "2025-01-01")
	priorTo := mustDate(t, "2025-12-31")
	regStart := mustDate(t, "2024-01-01")
	currentComm := mustDate(t, "2026-04-12")
	currentComm2 := mustDate(t, "2026-05-01")
	priorComm := mustDate(t, "2025-11-02")
	repo := &fakeOrganizationRepo{}
	useCase, err := NewAggregateLobbyistOrganizations(fakeDirectory{
		registrations: []OrganizationRegistration{
			{
				SourceID:          "990018",
				OCLOrganizationID: "5876",
				OrganizationName:  "Kashechewan First Nation",
				RegistrationType:  "1",
				Sector:            "Aboriginal Affairs",
				EffectiveDate:     &regStart,
				Lobbyists: []domain.RegisteredLobbyist{
					{Name: "Jane Doe", Kind: domain.LobbyistKindConsultant},
				},
				SubjectMatters: []string{"Aboriginal Affairs", "Infrastructure"},
			},
		},
		communications: []OrganizationCommunication{
			{
				SourceID:          "c-1",
				OCLOrganizationID: "5876",
				OrganizationName:  "Kashechewan First Nation",
				RegistrantName:    "Jane Doe",
				RegistrantType:    "Consultant",
				CommunicationDate: &currentComm,
				SubjectMatters:    []string{"Aboriginal Affairs"},
				DPOHs:             []domain.DPOHContact{{Name: "Alex Minister", Institution: "Indigenous Services Canada"}},
			},
			{
				SourceID:          "c-2",
				OCLOrganizationID: "5876",
				OrganizationName:  "Kashechewan First Nation",
				RegistrantName:    "Jane Doe",
				RegistrantType:    "Consultant",
				CommunicationDate: &currentComm2,
				DPOHs:             []domain.DPOHContact{{Name: "Alex Minister", Institution: "Indigenous Services Canada"}},
			},
			{
				SourceID:          "c-3",
				OCLOrganizationID: "5876",
				OrganizationName:  "Kashechewan First Nation",
				RegistrantName:    "Jane Doe",
				RegistrantType:    "Consultant",
				CommunicationDate: &priorComm,
				DPOHs:             []domain.DPOHContact{{Name: "Blair Official", Institution: "Crown-Indigenous Relations"}},
			},
		},
	}, repo, NewNameAliasNormalizer(nil))
	if err != nil {
		t.Fatalf("new aggregate use case: %v", err)
	}

	organizations, err := useCase.Execute(context.Background(), AggregateLobbyistOrganizationsInput{
		CurrentParliament: domain.ParliamentSession{ParliamentNumber: 45, SessionNumber: 1, From: currentFrom, To: currentTo},
		PriorParliament:   domain.ParliamentSession{ParliamentNumber: 44, SessionNumber: 1, From: priorFrom, To: priorTo},
		Now:               mustTime(t, "2026-06-03T12:00:00Z"),
	})
	if err != nil {
		t.Fatalf("execute aggregate: %v", err)
	}

	if len(organizations) != 1 {
		t.Fatalf("organization count = %d, want 1", len(organizations))
	}
	got := organizations[0]
	if got.ID != "ocl:5876" || got.OCLOrganizationID != "5876" {
		t.Fatalf("organization id = %q/%q, want ocl:5876/5876", got.ID, got.OCLOrganizationID)
	}
	if got.Type != domain.OrganizationTypeIndigenousOrganization {
		t.Fatalf("type = %q, want indigenous_organization", got.Type)
	}
	if got.Sector != "Aboriginal Affairs" {
		t.Fatalf("sector = %q, want Aboriginal Affairs", got.Sector)
	}
	if !reflect.DeepEqual(got.ActiveSubjectMatters, []string{"Aboriginal Affairs", "Infrastructure"}) {
		t.Fatalf("active subject matters = %#v", got.ActiveSubjectMatters)
	}
	if got.CommunicationVolume.CurrentParliament != 2 || got.CommunicationVolume.PriorParliament != 1 {
		t.Fatalf("communication volume = %#v", got.CommunicationVolume)
	}
	if len(got.RegisteredLobbyists) != 1 || got.RegisteredLobbyists[0].Kind != domain.LobbyistKindConsultant {
		t.Fatalf("registered lobbyists = %#v", got.RegisteredLobbyists)
	}
	if len(got.TopDPOHsContacted) != 2 || got.TopDPOHsContacted[0].Name != "Alex Minister" || got.TopDPOHsContacted[0].Count != 2 {
		t.Fatalf("top dpohs = %#v", got.TopDPOHsContacted)
	}
	if len(repo.saved) != 1 {
		t.Fatalf("saved organization count = %d, want 1", len(repo.saved))
	}
}

func TestAliasLookupHitAndMiss(t *testing.T) {
	aliases := &fakeAliases{matches: map[string][]string{
		"acme canada": {"ocl:100"},
	}}
	normalizer := NewNameAliasNormalizer(aliases)

	hit, err := normalizer.Resolve(context.Background(), OrganizationNameCandidate{Name: "ACME Canada"})
	if err != nil {
		t.Fatalf("resolve hit: %v", err)
	}
	if hit.OrganizationID != "ocl:100" {
		t.Fatalf("hit organization id = %q, want ocl:100", hit.OrganizationID)
	}

	miss, err := normalizer.Resolve(context.Background(), OrganizationNameCandidate{Name: "Unmapped Org"})
	if err != nil {
		t.Fatalf("resolve miss: %v", err)
	}
	if miss.OrganizationID != "name:unmapped org" {
		t.Fatalf("miss organization id = %q, want name:unmapped org", miss.OrganizationID)
	}
	if len(aliases.pending) != 0 {
		t.Fatalf("pending aliases = %#v, want none for miss", aliases.pending)
	}
}

func TestAggregateAliasHitCarriesCanonicalOCLID(t *testing.T) {
	aliases := &fakeAliases{matches: map[string][]string{
		"acme canada": {"ocl:100"},
	}}
	repo := &fakeOrganizationRepo{}
	useCase, err := NewAggregateLobbyistOrganizations(fakeDirectory{
		registrations: []OrganizationRegistration{
			{
				SourceID:         "r-1",
				OrganizationName: "ACME Canada",
				RegistrationType: "2",
				Sector:           "Industry",
				SubjectMatters:   []string{"Industry"},
			},
		},
	}, repo, NewNameAliasNormalizer(aliases))
	if err != nil {
		t.Fatalf("new aggregate use case: %v", err)
	}

	organizations, err := useCase.Execute(context.Background(), AggregateLobbyistOrganizationsInput{
		CurrentParliament: domain.ParliamentSession{
			From: mustDate(t, "2026-01-01"),
			To:   mustDate(t, "2026-12-31"),
		},
		Now: mustTime(t, "2026-06-03T12:00:00Z"),
	})
	if err != nil {
		t.Fatalf("execute aggregate: %v", err)
	}
	if len(organizations) != 1 {
		t.Fatalf("organization count = %d, want 1", len(organizations))
	}
	if organizations[0].ID != "ocl:100" || organizations[0].OCLOrganizationID != "100" {
		t.Fatalf("canonical ids = %q/%q, want ocl:100/100", organizations[0].ID, organizations[0].OCLOrganizationID)
	}
}

func TestAmbiguousMatchGoesToPendingLog(t *testing.T) {
	aliases := &fakeAliases{matches: map[string][]string{
		"shared acronym": {"ocl:101", "ocl:202"},
	}}
	normalizer := NewNameAliasNormalizer(aliases)

	resolution, err := normalizer.Resolve(context.Background(), OrganizationNameCandidate{
		Name:        "Shared Acronym",
		SourceTable: "ocl_communication_primary",
		SourceID:    "c-9",
	})
	if err != nil {
		t.Fatalf("resolve ambiguous: %v", err)
	}

	if !resolution.Ambiguous || resolution.OrganizationID != "name:shared acronym" {
		t.Fatalf("resolution = %#v", resolution)
	}
	if len(aliases.pending) != 1 {
		t.Fatalf("pending count = %d, want 1", len(aliases.pending))
	}
	pending := aliases.pending[0]
	if pending.NormalizedName != "shared acronym" || pending.SourceID != "c-9" {
		t.Fatalf("pending alias = %#v", pending)
	}
	if !reflect.DeepEqual(pending.CandidateOrganizationIDs, []string{"ocl:101", "ocl:202"}) {
		t.Fatalf("candidate organization ids = %#v", pending.CandidateOrganizationIDs)
	}
}

func mustDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return parsed
}

func mustTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatalf("parse time %q: %v", value, err)
	}
	return parsed
}
