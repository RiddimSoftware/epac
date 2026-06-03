package application

import (
	"context"
	"errors"
	"testing"
	"time"

	"epac/lobbying/domain"
)

type fakeMPLobbyingRepository struct {
	summary               domain.MPLobbyingSummary
	summaryFound          bool
	timeline              domain.LobbyingTimelinePage
	gotSummary            LoadMPLobbyingSummaryInput
	gotTimeline           ListMPLobbyingTimelineInput
	summaryErr            error
	timelineErr           error
	timelineRefreshCalled bool
	refreshCalled         bool
}

func (r *fakeMPLobbyingRepository) LoadMPLobbyingSummary(_ context.Context, input LoadMPLobbyingSummaryInput) (domain.MPLobbyingSummary, bool, error) {
	r.gotSummary = input
	return r.summary, r.summaryFound, r.summaryErr
}

func (r *fakeMPLobbyingRepository) ListMPLobbyingTimeline(_ context.Context, input ListMPLobbyingTimelineInput) (domain.LobbyingTimelinePage, error) {
	r.gotTimeline = input
	return r.timeline, r.timelineErr
}

func (r *fakeMPLobbyingRepository) RefreshMPLobbyingSummaries(context.Context, RefreshMPLobbyingSummariesInput) error {
	r.refreshCalled = true
	return nil
}

func (r *fakeMPLobbyingRepository) RefreshMPLobbyingTimelineEntries(context.Context, RefreshMPLobbyingTimelineInput) error {
	r.timelineRefreshCalled = true
	return nil
}

type fakeSubjectDistribution struct {
	rows []domain.LobbyingSubjectDistribution
	got  ListMPLobbyingSubjectDistributionInput
	err  error
}

func (q *fakeSubjectDistribution) ListMPLobbyingSubjectDistribution(_ context.Context, input ListMPLobbyingSubjectDistributionInput) ([]domain.LobbyingSubjectDistribution, error) {
	q.got = input
	return q.rows, q.err
}

func TestLoadMPLobbyingExposurePopulatedMP(t *testing.T) {
	repo := &fakeMPLobbyingRepository{
		summaryFound: true,
		summary: domain.MPLobbyingSummary{
			MemberID:                  "278707",
			Parliament:                45,
			Window:                    domain.LobbyingExposureWindow3M,
			TotalCommunicationCount:   2,
			UniqueOrganizationsCount:  2,
			MostFrequentSubjectMatter: "Housing",
			TopOrganizations: []domain.TopLobbyingOrganization{
				{Name: "Example Housing Association", Sector: "Housing", CommunicationCount: 2},
			},
			TrendVsPreviousParliament: domain.MPLobbyingTrend{
				CurrentParliament:  2,
				PreviousParliament: 1,
				Delta:              1,
			},
			PartyAverageCommunications:    1.5,
			NationalAverageCommunications: 0.75,
		},
		timeline: domain.LobbyingTimelinePage{
			Total: 2,
			Rows: []domain.LobbyingTimelineEntry{
				{
					CommunicationID:    "COM-2",
					Date:               "2026-05-20",
					OrganizationName:   "Example Housing Association",
					OrganizationSector: "Housing",
					SubjectMatter:      "Housing",
					CommunicationType:  "meeting",
					Bill: &domain.BillCrossReference{
						BillNumber: "C-1",
						URL:        "https://www.parl.ca/legisinfo/en/bill/45-1/c-1",
						Confidence: 0.93,
					},
				},
				{
					CommunicationID:   "COM-1",
					Date:              "2026-05-01",
					OrganizationName:  "Low Confidence Org",
					SubjectMatter:     "Transport",
					CommunicationType: "written",
					Bill: &domain.BillCrossReference{
						BillNumber: "C-2",
						URL:        "https://www.parl.ca/legisinfo/en/bill/45-1/c-2",
						Confidence: 0.42,
					},
				},
			},
		},
	}
	subjects := &fakeSubjectDistribution{rows: []domain.LobbyingSubjectDistribution{
		{SubjectMatter: "Housing", CommunicationCount: 1},
		{SubjectMatter: "Transport", CommunicationCount: 1},
	}}
	useCase, err := NewLoadMPLobbyingExposure(repo, subjects)
	if err != nil {
		t.Fatalf("new use case: %v", err)
	}

	result, err := useCase.Execute(context.Background(), LoadMPLobbyingExposureInput{
		MemberID:   "278707",
		Parliament: 45,
		Window:     domain.LobbyingExposureWindow3M,
		Page:       1,
		Now:        mustMPExposureTime(t, "2026-06-03T12:00:00Z"),
	})
	if err != nil {
		t.Fatalf("execute: %v", err)
	}

	if result.Summary.TotalCommunicationCount != 2 || result.Summary.Citation != domain.OCLCitation {
		t.Fatalf("summary = %#v", result.Summary)
	}
	if len(result.SubjectBreakdown) != 2 {
		t.Fatalf("subject breakdown = %#v", result.SubjectBreakdown)
	}
	if result.Total != 2 || result.Pages != 1 || len(result.Timeline) != 2 {
		t.Fatalf("timeline result = %#v", result)
	}
	if result.Timeline[0].Citation != domain.OCLCitation || result.Timeline[0].SourceURL != domain.OCLSourceURL {
		t.Fatalf("timeline source fields = %#v", result.Timeline[0])
	}
	if result.Timeline[0].Bill == nil {
		t.Fatal("high-confidence bill link was suppressed")
	}
	if result.Timeline[1].Bill != nil {
		t.Fatalf("low-confidence bill link was not suppressed: %#v", result.Timeline[1].Bill)
	}
}

func TestLoadMPLobbyingExposureEmptyMP(t *testing.T) {
	repo := &fakeMPLobbyingRepository{}
	subjects := &fakeSubjectDistribution{}
	useCase, err := NewLoadMPLobbyingExposure(repo, subjects)
	if err != nil {
		t.Fatalf("new use case: %v", err)
	}

	result, err := useCase.Execute(context.Background(), LoadMPLobbyingExposureInput{
		MemberID:   "278707",
		Parliament: 45,
		Window:     domain.LobbyingExposureWindowAll,
		Page:       1,
		Now:        mustMPExposureTime(t, "2026-06-03T12:00:00Z"),
	})
	if err != nil {
		t.Fatalf("execute: %v", err)
	}

	if result.Total != 0 || len(result.Timeline) != 0 || len(result.SubjectBreakdown) != 0 {
		t.Fatalf("empty response = %#v", result)
	}
	if result.Summary.TotalCommunicationCount != 0 || len(result.Summary.TopOrganizations) != 0 {
		t.Fatalf("empty summary = %#v", result.Summary)
	}
	if result.Summary.Citation != domain.OCLCitation || result.Citation != domain.OCLCitation {
		t.Fatalf("missing citations: %#v", result)
	}
}

func TestLoadMPLobbyingExposurePaginatesTimelineAtFiftyRows(t *testing.T) {
	repo := &fakeMPLobbyingRepository{timeline: domain.LobbyingTimelinePage{Total: 52}}
	subjects := &fakeSubjectDistribution{}
	useCase, err := NewLoadMPLobbyingExposure(repo, subjects)
	if err != nil {
		t.Fatalf("new use case: %v", err)
	}

	result, err := useCase.Execute(context.Background(), LoadMPLobbyingExposureInput{
		MemberID:   "278707",
		Parliament: 45,
		Window:     domain.LobbyingExposureWindow12M,
		Page:       2,
		Now:        mustMPExposureTime(t, "2026-06-03T12:00:00Z"),
	})
	if err != nil {
		t.Fatalf("execute: %v", err)
	}

	if repo.gotTimeline.Page != 2 || repo.gotTimeline.PerPage != MPLobbyingTimelinePerPage {
		t.Fatalf("timeline input = %#v", repo.gotTimeline)
	}
	if result.Page != 2 || result.PerPage != 50 || result.Pages != 2 {
		t.Fatalf("pagination result = %#v", result)
	}
}

func TestLoadMPLobbyingExposureAppliesWindowFilter(t *testing.T) {
	now := mustMPExposureTime(t, "2026-06-03T12:00:00Z")
	tests := []struct {
		name      string
		window    domain.LobbyingExposureWindow
		wantStart string
	}{
		{name: "30d", window: domain.LobbyingExposureWindow30D, wantStart: "2026-05-04"},
		{name: "3m", window: domain.LobbyingExposureWindow3M, wantStart: "2026-03-03"},
		{name: "12m", window: domain.LobbyingExposureWindow12M, wantStart: "2025-06-03"},
		{name: "all", window: domain.LobbyingExposureWindowAll, wantStart: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repo := &fakeMPLobbyingRepository{}
			useCase, err := NewLoadMPLobbyingExposure(repo, &fakeSubjectDistribution{})
			if err != nil {
				t.Fatalf("new use case: %v", err)
			}

			if _, err := useCase.Execute(context.Background(), LoadMPLobbyingExposureInput{
				MemberID:   "278707",
				Parliament: 45,
				Window:     tt.window,
				Page:       1,
				Now:        now,
			}); err != nil {
				t.Fatalf("execute: %v", err)
			}

			if tt.wantStart == "" {
				if repo.gotTimeline.FromDate != nil {
					t.Fatalf("from date = %v, want nil", repo.gotTimeline.FromDate)
				}
				return
			}
			if repo.gotTimeline.FromDate == nil {
				t.Fatalf("from date nil, want %s", tt.wantStart)
			}
			if got := repo.gotTimeline.FromDate.Format("2006-01-02"); got != tt.wantStart {
				t.Fatalf("from date = %s, want %s", got, tt.wantStart)
			}
		})
	}
}

func TestLoadMPLobbyingExposureRejectsInvalidWindow(t *testing.T) {
	useCase, err := NewLoadMPLobbyingExposure(&fakeMPLobbyingRepository{}, &fakeSubjectDistribution{})
	if err != nil {
		t.Fatalf("new use case: %v", err)
	}

	_, err = useCase.Execute(context.Background(), LoadMPLobbyingExposureInput{
		MemberID:   "278707",
		Parliament: 45,
		Window:     "90d",
		Page:       1,
		Now:        mustMPExposureTime(t, "2026-06-03T12:00:00Z"),
	})
	if !errors.Is(err, ErrInvalidLobbyingWindow) {
		t.Fatalf("err = %v, want invalid window", err)
	}
}

func TestRefreshMPLobbyingExposureDelegatesToPrecomputer(t *testing.T) {
	repo := &fakeMPLobbyingRepository{}
	useCase, err := NewRefreshMPLobbyingExposure(repo)
	if err != nil {
		t.Fatalf("new refresh use case: %v", err)
	}

	err = useCase.Execute(context.Background(), RefreshMPLobbyingSummariesInput{
		Parliament:   45,
		QuarterStart: mustMPExposureDate(t, "2026-04-01"),
		QuarterEnd:   mustMPExposureDate(t, "2026-06-30"),
	})
	if err != nil {
		t.Fatalf("execute refresh: %v", err)
	}
	if !repo.timelineRefreshCalled {
		t.Fatal("timeline precompute was not called")
	}
	if !repo.refreshCalled {
		t.Fatal("summary precompute was not called")
	}
}

func mustMPExposureTime(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatalf("parse time %q: %v", value, err)
	}
	return parsed
}

func mustMPExposureDate(t *testing.T, value string) time.Time {
	t.Helper()
	parsed, err := time.Parse("2006-01-02", value)
	if err != nil {
		t.Fatalf("parse date %q: %v", value, err)
	}
	return parsed
}
