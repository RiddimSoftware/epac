package usecase

import (
	"context"
	"errors"
	"testing"
)

type fakeMinisterRepository struct {
	profiles map[string]MinisterProfile
	cabinet  []MinisterProfile
	err      error
}

func (r fakeMinisterRepository) LoadMinisterProfile(_ context.Context, memberID string) (MinisterProfile, error) {
	if r.err != nil {
		return MinisterProfile{}, r.err
	}
	profile, ok := r.profiles[memberID]
	if !ok {
		return MinisterProfile{}, ErrMinisterNotFound
	}
	return profile, nil
}

func (r fakeMinisterRepository) ListCabinetMinisters(_ context.Context, _ CabinetMinisterFilter) ([]MinisterProfile, error) {
	if r.err != nil {
		return nil, r.err
	}
	return append([]MinisterProfile(nil), r.cabinet...), nil
}

type fakeMinisterLobbyingRepository struct {
	communications map[string][]MinisterLobbyingCommunication
	err            error
}

func (r fakeMinisterLobbyingRepository) ListMinisterCommunications(_ context.Context, filter MinisterCommunicationsFilter) ([]MinisterLobbyingCommunication, error) {
	if r.err != nil {
		return nil, r.err
	}
	rows := r.communications[filter.MemberID]
	return append([]MinisterLobbyingCommunication(nil), rows...), nil
}

type fakeMandateRepository struct {
	areas []MandatePolicyArea
}

func (r fakeMandateRepository) ListMandatePolicyAreas(context.Context, string) ([]MandatePolicyArea, error) {
	return append([]MandatePolicyArea(nil), r.areas...), nil
}

type fakeTopicMapper struct {
	byCode map[string][]OCLTopicMapping
}

func (m fakeTopicMapper) TopicMappingsForOCLCode(code string) []OCLTopicMapping {
	return append([]OCLTopicMapping(nil), m.byCode[NormalizeOCLCode(code)]...)
}

type fakeBoundaryLogger struct {
	gaps []PortfolioBoundaryGap
}

func (l *fakeBoundaryLogger) WarnPortfolioBoundaryGap(_ context.Context, gap PortfolioBoundaryGap) {
	l.gaps = append(l.gaps, gap)
}

func TestLoadMinisterLobbyingByPortfolioGroupsTwoPortfoliosAndFlagsMandateMatches(t *testing.T) {
	profile := MinisterProfile{
		MemberID:        "m-1",
		MinisterName:    "Alex Minister",
		FirstName:       "Alex",
		LastName:        "Minister",
		TenureStartDate: "2026-01-01",
		PortfolioPeriods: []MinisterPortfolioPeriod{
			{PortfolioName: "Minister of Transport", StartDate: "2026-01-01", EndDate: "2026-03-31"},
			{PortfolioName: "Minister of Health", StartDate: "2026-04-01", EndDate: ""},
		},
	}
	lobbying := fakeMinisterLobbyingRepository{communications: map[string][]MinisterLobbyingCommunication{
		"m-1": {
			{ID: "COM-1", OrganizationName: "Rail Association", CommunicationDate: "2026-01-15", OCLCodes: []string{"21"}},
			{ID: "COM-2", OrganizationName: "Rail Association", CommunicationDate: "2026-02-20", OCLCodes: []string{"SMT-21"}},
			{ID: "COM-3", OrganizationName: "Health Coalition", CommunicationDate: "2026-04-10", OCLCodes: []string{"SMT-18"}},
		},
	}}
	uc := NewLoadMinisterLobbyingByPortfolio(
		fakeMinisterRepository{profiles: map[string]MinisterProfile{"m-1": profile}},
		lobbying,
		fakeMandateRepository{areas: []MandatePolicyArea{{EpacTopicSlug: "healthcare", Confidence: 1}}},
		fakeTopicMapper{byCode: map[string][]OCLTopicMapping{
			"SMT-18": {{OCLCode: "SMT-18", EpacTopicSlug: "healthcare", Confidence: 1}},
			"SMT-21": {{OCLCode: "SMT-21", EpacTopicSlug: "transport", Confidence: 0.95}},
		}},
		nil,
	)

	result, err := uc.Execute(context.Background(), "m-1")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result.TotalCommunications != 3 || len(result.Portfolios) != 2 {
		t.Fatalf("unexpected result: %#v", result)
	}
	if got := result.Portfolios[0].PortfolioName; got != "Minister of Transport" {
		t.Fatalf("first portfolio = %q", got)
	}
	if len(result.Portfolios[0].Communications) != 2 {
		t.Fatalf("transport communications = %d, want 2", len(result.Portfolios[0].Communications))
	}
	if len(result.Portfolios[0].TopOrganizations) != 1 || result.Portfolios[0].TopOrganizations[0].Count != 2 {
		t.Fatalf("transport top organizations = %#v", result.Portfolios[0].TopOrganizations)
	}
	healthCommunication := result.Portfolios[1].Communications[0]
	if !healthCommunication.MandateMatch {
		t.Fatalf("health communication mandate_match = false: %#v", healthCommunication)
	}
	if healthCommunication.OCLCodes[0] != "SMT-18" {
		t.Fatalf("normalized OCL code = %q", healthCommunication.OCLCodes[0])
	}
}

func TestLoadMinisterLobbyingByPortfolioReturnsEmptyPeriodsWhenNoCommunications(t *testing.T) {
	profile := MinisterProfile{
		MemberID:     "m-2",
		MinisterName: "Blair Minister",
		FirstName:    "Blair",
		LastName:     "Minister",
		PortfolioPeriods: []MinisterPortfolioPeriod{
			{PortfolioName: "Minister of Finance", StartDate: "2026-01-01", EndDate: ""},
		},
	}
	uc := NewLoadMinisterLobbyingByPortfolio(
		fakeMinisterRepository{profiles: map[string]MinisterProfile{"m-2": profile}},
		fakeMinisterLobbyingRepository{communications: map[string][]MinisterLobbyingCommunication{}},
		nil,
		nil,
		nil,
	)

	result, err := uc.Execute(context.Background(), "m-2")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result.TotalCommunications != 0 || len(result.Portfolios) != 1 || len(result.Portfolios[0].Communications) != 0 {
		t.Fatalf("unexpected empty result: %#v", result)
	}
}

func TestLoadMinisterLobbyingByPortfolioFallsBackToTenureAndLogsGap(t *testing.T) {
	logger := &fakeBoundaryLogger{}
	profile := MinisterProfile{
		MemberID:        "m-3",
		MinisterName:    "Casey Minister",
		FirstName:       "Casey",
		LastName:        "Minister",
		TenureStartDate: "2026-01-01",
		TenureEndDate:   "2026-12-31",
		PortfolioPeriods: []MinisterPortfolioPeriod{
			{PortfolioName: "Minister of Transport", StartDate: "2026-01-01", EndDate: ""},
			{PortfolioName: "Minister of Health", StartDate: "2026-04-01", EndDate: ""},
		},
	}
	uc := NewLoadMinisterLobbyingByPortfolio(
		fakeMinisterRepository{profiles: map[string]MinisterProfile{"m-3": profile}},
		fakeMinisterLobbyingRepository{communications: map[string][]MinisterLobbyingCommunication{
			"m-3": {{ID: "COM-1", OrganizationName: "Example Org", CommunicationDate: "2026-05-01"}},
		}},
		nil,
		nil,
		logger,
	)

	result, err := uc.Execute(context.Background(), "m-3")
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if len(result.Portfolios) != 1 || result.Portfolios[0].PortfolioName != fallbackPortfolioName {
		t.Fatalf("fallback portfolios = %#v", result.Portfolios)
	}
	if len(logger.gaps) != 1 || logger.gaps[0].Reason != "open_ended_period_before_next_portfolio" {
		t.Fatalf("boundary gaps = %#v", logger.gaps)
	}
}

func TestLoadCabinetLobbyingOverviewRanksMinistersAndIncludesEmptyRows(t *testing.T) {
	profiles := []MinisterProfile{
		{
			MemberID:     "m-1",
			MinisterName: "Alex Minister",
			FirstName:    "Alex",
			LastName:     "Minister",
			PortfolioPeriods: []MinisterPortfolioPeriod{
				{PortfolioName: "Minister of Transport", StartDate: "2026-01-01", EndDate: ""},
			},
		},
		{
			MemberID:     "m-2",
			MinisterName: "Blair Minister",
			FirstName:    "Blair",
			LastName:     "Minister",
			PortfolioPeriods: []MinisterPortfolioPeriod{
				{PortfolioName: "Minister of Finance", StartDate: "2026-01-01", EndDate: ""},
			},
		},
	}
	lobbying := fakeMinisterLobbyingRepository{communications: map[string][]MinisterLobbyingCommunication{
		"m-1": {
			{ID: "COM-1", OrganizationName: "Org A", CommunicationDate: "2026-01-02"},
			{ID: "COM-2", OrganizationName: "Org B", CommunicationDate: "2026-01-03"},
		},
	}}
	uc := NewLoadCabinetLobbyingOverview(
		fakeMinisterRepository{cabinet: profiles},
		lobbying,
		nil,
	)

	result, err := uc.Execute(context.Background(), CabinetLobbyingOverviewInput{Parliament: 45, Portfolio: "Transport"})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if result.Parliament != 45 || result.PortfolioFilter != "Transport" || len(result.Ministers) != 2 {
		t.Fatalf("unexpected overview: %#v", result)
	}
	if result.Ministers[0].MemberID != "m-1" || result.Ministers[0].TotalCommunications != 2 {
		t.Fatalf("first summary = %#v", result.Ministers[0])
	}
	if result.Ministers[1].MemberID != "m-2" || result.Ministers[1].TotalCommunications != 0 {
		t.Fatalf("second summary = %#v", result.Ministers[1])
	}
}

func TestLoadCabinetLobbyingOverviewReturnsEmpty(t *testing.T) {
	uc := NewLoadCabinetLobbyingOverview(
		fakeMinisterRepository{cabinet: []MinisterProfile{}},
		fakeMinisterLobbyingRepository{communications: map[string][]MinisterLobbyingCommunication{}},
		nil,
	)

	result, err := uc.Execute(context.Background(), CabinetLobbyingOverviewInput{Parliament: 45})
	if err != nil {
		t.Fatalf("Execute: %v", err)
	}
	if len(result.Ministers) != 0 || result.Citation != Citation || result.SourceURL != SourceURL {
		t.Fatalf("unexpected empty overview: %#v", result)
	}
}

func TestLoadMinisterLobbyingByPortfolioPropagatesRepositoryError(t *testing.T) {
	want := errors.New("boom")
	uc := NewLoadMinisterLobbyingByPortfolio(
		fakeMinisterRepository{profiles: map[string]MinisterProfile{
			"m-1": {MemberID: "m-1", PortfolioPeriods: []MinisterPortfolioPeriod{{PortfolioName: "Minister", StartDate: "2026-01-01"}}},
		}},
		fakeMinisterLobbyingRepository{err: want},
		nil,
		nil,
		nil,
	)

	if _, err := uc.Execute(context.Background(), "m-1"); !errors.Is(err, want) {
		t.Fatalf("err = %v, want %v", err, want)
	}
}
