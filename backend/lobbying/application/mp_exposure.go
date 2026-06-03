package application

import (
	"context"
	"errors"
	"strings"
	"time"

	"epac/lobbying/domain"
)

const (
	MPLobbyingTimelinePerPage  = 50
	BillReferenceConfidenceMin = 0.80
)

var (
	ErrMPLobbyingRepositoryRequired = errors.New("mp lobbying repository is required")
	ErrSubjectDistributionRequired  = errors.New("lobbying subject distribution query is required")
	ErrInvalidLobbyingWindow        = errors.New("window must be one of 30d, 3m, 12m, or all")
	ErrInvalidMPLobbyingInput       = errors.New("member id, parliament, and page are required")
)

type MPLobbyingRepository interface {
	LoadMPLobbyingSummary(ctx context.Context, input LoadMPLobbyingSummaryInput) (domain.MPLobbyingSummary, bool, error)
	ListMPLobbyingTimeline(ctx context.Context, input ListMPLobbyingTimelineInput) (domain.LobbyingTimelinePage, error)
}

type LobbyingSubjectDistributionQuery interface {
	ListMPLobbyingSubjectDistribution(ctx context.Context, input ListMPLobbyingSubjectDistributionInput) ([]domain.LobbyingSubjectDistribution, error)
}

type MPLobbyingSummaryPrecomputer interface {
	RefreshMPLobbyingTimelineEntries(ctx context.Context, input RefreshMPLobbyingTimelineInput) error
	RefreshMPLobbyingSummaries(ctx context.Context, input RefreshMPLobbyingSummariesInput) error
}

type LoadMPLobbyingExposureInput struct {
	MemberID   string
	Parliament int
	Window     domain.LobbyingExposureWindow
	Page       int
	Now        time.Time
}

type LoadMPLobbyingSummaryInput struct {
	MemberID   string
	Parliament int
	Window     domain.LobbyingExposureWindow
}

type ListMPLobbyingTimelineInput struct {
	MemberID   string
	Parliament int
	FromDate   *time.Time
	Page       int
	PerPage    int
}

type ListMPLobbyingSubjectDistributionInput struct {
	MemberID   string
	Parliament int
	Window     domain.LobbyingExposureWindow
}

type RefreshMPLobbyingSummariesInput struct {
	Parliament   int
	QuarterStart time.Time
	QuarterEnd   time.Time
	UpdatedAt    time.Time
}

type RefreshMPLobbyingTimelineInput struct {
	Parliament int
	FromDate   time.Time
	ToDate     time.Time
	UpdatedAt  time.Time
}

type MPLobbyingExposureResult struct {
	MemberID         string                               `json:"member_id"`
	Parliament       int                                  `json:"parliament"`
	Window           domain.LobbyingExposureWindow        `json:"window"`
	Page             int                                  `json:"page"`
	PerPage          int                                  `json:"per_page"`
	Total            int                                  `json:"total"`
	Pages            int                                  `json:"pages"`
	Summary          domain.MPLobbyingSummary             `json:"summary"`
	SubjectBreakdown []domain.LobbyingSubjectDistribution `json:"subject_breakdown"`
	Timeline         []domain.LobbyingTimelineEntry       `json:"timeline"`
	Citation         string                               `json:"citation"`
	SourceURL        string                               `json:"source_url"`
}

type LoadMPLobbyingExposure struct {
	repository MPLobbyingRepository
	subjects   LobbyingSubjectDistributionQuery
}

func NewLoadMPLobbyingExposure(
	repository MPLobbyingRepository,
	subjects LobbyingSubjectDistributionQuery,
) (*LoadMPLobbyingExposure, error) {
	if repository == nil {
		return nil, ErrMPLobbyingRepositoryRequired
	}
	if subjects == nil {
		return nil, ErrSubjectDistributionRequired
	}
	return &LoadMPLobbyingExposure{repository: repository, subjects: subjects}, nil
}

func (u *LoadMPLobbyingExposure) Execute(ctx context.Context, input LoadMPLobbyingExposureInput) (MPLobbyingExposureResult, error) {
	input.MemberID = strings.TrimSpace(input.MemberID)
	if input.Window == "" {
		input.Window = domain.LobbyingExposureWindow3M
	}
	if input.Page == 0 {
		input.Page = 1
	}
	if input.Now.IsZero() {
		input.Now = time.Now().UTC()
	}
	if input.MemberID == "" || input.Parliament <= 0 || input.Page < 1 {
		return MPLobbyingExposureResult{}, ErrInvalidMPLobbyingInput
	}
	if !IsValidLobbyingWindow(input.Window) {
		return MPLobbyingExposureResult{}, ErrInvalidLobbyingWindow
	}

	summary, found, err := u.repository.LoadMPLobbyingSummary(ctx, LoadMPLobbyingSummaryInput{
		MemberID:   input.MemberID,
		Parliament: input.Parliament,
		Window:     input.Window,
	})
	if err != nil {
		return MPLobbyingExposureResult{}, err
	}
	if !found {
		summary = emptyMPLobbyingSummary(input)
	}
	normalizeSummary(&summary)

	subjectBreakdown, err := u.subjects.ListMPLobbyingSubjectDistribution(ctx, ListMPLobbyingSubjectDistributionInput{
		MemberID:   input.MemberID,
		Parliament: input.Parliament,
		Window:     input.Window,
	})
	if err != nil {
		return MPLobbyingExposureResult{}, err
	}
	if subjectBreakdown == nil {
		subjectBreakdown = []domain.LobbyingSubjectDistribution{}
	}

	timelinePage, err := u.repository.ListMPLobbyingTimeline(ctx, ListMPLobbyingTimelineInput{
		MemberID:   input.MemberID,
		Parliament: input.Parliament,
		FromDate:   WindowStart(input.Window, input.Now),
		Page:       input.Page,
		PerPage:    MPLobbyingTimelinePerPage,
	})
	if err != nil {
		return MPLobbyingExposureResult{}, err
	}
	timeline := timelinePage.Rows
	if timeline == nil {
		timeline = []domain.LobbyingTimelineEntry{}
	}
	for i := range timeline {
		normalizeTimelineEntry(&timeline[i])
	}

	return MPLobbyingExposureResult{
		MemberID:         input.MemberID,
		Parliament:       input.Parliament,
		Window:           input.Window,
		Page:             input.Page,
		PerPage:          MPLobbyingTimelinePerPage,
		Total:            timelinePage.Total,
		Pages:            pageCount(timelinePage.Total, MPLobbyingTimelinePerPage),
		Summary:          summary,
		SubjectBreakdown: subjectBreakdown,
		Timeline:         timeline,
		Citation:         domain.OCLCitation,
		SourceURL:        domain.OCLSourceURL,
	}, nil
}

type RefreshMPLobbyingExposure struct {
	precomputer MPLobbyingSummaryPrecomputer
}

func NewRefreshMPLobbyingExposure(precomputer MPLobbyingSummaryPrecomputer) (*RefreshMPLobbyingExposure, error) {
	if precomputer == nil {
		return nil, ErrMPLobbyingRepositoryRequired
	}
	return &RefreshMPLobbyingExposure{precomputer: precomputer}, nil
}

func (u *RefreshMPLobbyingExposure) Execute(ctx context.Context, input RefreshMPLobbyingSummariesInput) error {
	if input.Parliament <= 0 || input.QuarterStart.IsZero() || input.QuarterEnd.IsZero() {
		return ErrInvalidMPLobbyingInput
	}
	if input.UpdatedAt.IsZero() {
		input.UpdatedAt = time.Now().UTC()
	}
	if err := u.precomputer.RefreshMPLobbyingTimelineEntries(ctx, RefreshMPLobbyingTimelineInput{
		Parliament: input.Parliament,
		FromDate:   input.QuarterStart,
		ToDate:     input.QuarterEnd,
		UpdatedAt:  input.UpdatedAt,
	}); err != nil {
		return err
	}
	return u.precomputer.RefreshMPLobbyingSummaries(ctx, input)
}

func IsValidLobbyingWindow(window domain.LobbyingExposureWindow) bool {
	switch window {
	case domain.LobbyingExposureWindow30D,
		domain.LobbyingExposureWindow3M,
		domain.LobbyingExposureWindow12M,
		domain.LobbyingExposureWindowAll:
		return true
	default:
		return false
	}
}

func ParseLobbyingWindow(raw string) (domain.LobbyingExposureWindow, error) {
	window := domain.LobbyingExposureWindow(strings.ToLower(strings.TrimSpace(raw)))
	if window == "" {
		window = domain.LobbyingExposureWindow3M
	}
	if !IsValidLobbyingWindow(window) {
		return "", ErrInvalidLobbyingWindow
	}
	return window, nil
}

func WindowStart(window domain.LobbyingExposureWindow, now time.Time) *time.Time {
	if now.IsZero() {
		now = time.Now().UTC()
	}
	now = dateOnly(now)
	var start time.Time
	switch window {
	case domain.LobbyingExposureWindow30D:
		start = now.AddDate(0, 0, -30)
	case domain.LobbyingExposureWindow3M:
		start = now.AddDate(0, -3, 0)
	case domain.LobbyingExposureWindow12M:
		start = now.AddDate(-1, 0, 0)
	case domain.LobbyingExposureWindowAll:
		return nil
	default:
		return nil
	}
	return &start
}

func QuarterStart(now time.Time) time.Time {
	now = dateOnly(now)
	month := int(now.Month())
	quarterMonth := time.Month(((month-1)/3)*3 + 1)
	return time.Date(now.Year(), quarterMonth, 1, 0, 0, 0, 0, time.UTC)
}

func emptyMPLobbyingSummary(input LoadMPLobbyingExposureInput) domain.MPLobbyingSummary {
	return domain.MPLobbyingSummary{
		MemberID:         input.MemberID,
		Parliament:       input.Parliament,
		QuarterStart:     QuarterStart(input.Now),
		Window:           input.Window,
		TopOrganizations: []domain.TopLobbyingOrganization{},
		Citation:         domain.OCLCitation,
		UpdatedAt:        input.Now.UTC(),
	}
}

func normalizeSummary(summary *domain.MPLobbyingSummary) {
	if summary.TopOrganizations == nil {
		summary.TopOrganizations = []domain.TopLobbyingOrganization{}
	}
	if summary.Citation == "" {
		summary.Citation = domain.OCLCitation
	}
}

func normalizeTimelineEntry(entry *domain.LobbyingTimelineEntry) {
	if entry.Citation == "" {
		entry.Citation = domain.OCLCitation
	}
	if entry.SourceURL == "" {
		entry.SourceURL = domain.OCLSourceURL
	}
	if entry.Bill != nil && (entry.Bill.Confidence < BillReferenceConfidenceMin || strings.TrimSpace(entry.Bill.URL) == "") {
		entry.Bill = nil
	}
}

func pageCount(total, perPage int) int {
	if total <= 0 || perPage <= 0 {
		return 0
	}
	return (total + perPage - 1) / perPage
}

func dateOnly(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
