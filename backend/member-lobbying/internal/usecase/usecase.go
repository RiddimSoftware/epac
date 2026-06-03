// Package usecase implements MP lobbying exposure API behavior.
package usecase

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	DefaultPerPage = 50
	MaxPerPage     = 100
)

const dateFormat = "2006-01-02"

var ErrNotFound = errors.New("lobbying exposure not found")

type DateRange string

const (
	DateRange30Days DateRange = "30d"
	DateRange3Months DateRange = "3m"
	DateRange12Months DateRange = "365d"
	DateRangeAll    DateRange = "all"
)

func ParseDateRange(raw string) DateRange {
	r := strings.ToLower(strings.TrimSpace(raw))
	switch r {
	case string(DateRange30Days), "30", "30d", "last30", "last_30_days":
		return DateRange30Days
	case string(DateRange3Months), "90", "90d", "3m", "3months", "three_months":
		return DateRange3Months
	case string(DateRange12Months), "365", "365d", "12m", "12months", "12_months":
		return DateRange12Months
	case string(DateRangeAll):
		return DateRangeAll
	default:
		return DateRangeAll
	}
}

type MPLobbyingTimelineEntry struct {
	CommunicationDate         string  `json:"communication_date"`
	OrganizationName          string  `json:"organization_name"`
	OrganizationSector        string  `json:"organization_sector,omitempty"`
	SubjectMatter             string  `json:"subject_matter"`
	CommunicationType         string  `json:"communication_type"`
	OrganizationID            string  `json:"organization_id,omitempty"`
	OrganizationProfileURL    string  `json:"organization_profile_url,omitempty"`
	RelatedBillTitle          string  `json:"related_bill_title,omitempty"`
	RelatedBillURL            string  `json:"related_bill_url,omitempty"`
	RelatedBillConfidence     float64 `json:"related_bill_confidence,omitempty"`
	RelatedBillConfidenceUsed bool    `json:"related_bill_confidence_used"`
	RecordURL                 string  `json:"record_url"`
}

func (e MPLobbyingTimelineEntry) Date() (time.Time, bool) {
	if e.CommunicationDate == "" {
		return time.Time{}, false
	}
	t, err := time.Parse(dateFormat, e.CommunicationDate)
	if err != nil {
		return time.Time{}, false
	}
	return t, true
}

type TopLobbyingOrganization struct {
	OrganizationName       string `json:"organization_name"`
	OrganizationSector     string `json:"organization_sector,omitempty"`
	Count                 int    `json:"count"`
	OrganizationID        string `json:"organization_id,omitempty"`
	OrganizationProfileURL string `json:"organization_profile_url,omitempty"`
}

type LobbyingSubjectDistribution struct {
	Subject    string  `json:"subject"`
	Count     int     `json:"count"`
	Percentage float64 `json:"percentage"`
}

type MPLobbyingSummary struct {
	TotalCommunications           int    `json:"total_communications"`
	UniqueOrganizations           int    `json:"unique_organizations"`
	MostFrequentSubject           string `json:"most_frequent_subject"`
	PreviousParliamentCommunications int   `json:"previous_parliament_communications,omitempty"`
	TrendVsPreviousParliament     float64 `json:"trend_vs_previous_parliament,omitempty"`
}

type CohortComparisonBaseline struct {
	Party           string  `json:"party"`
	PartyAverage    float64 `json:"party_average"`
	NationalAverage float64 `json:"national_average"`
}

type CohortComparison struct {
	Party            string  `json:"party"`
	PartyAverage     float64 `json:"party_average"`
	NationalAverage  float64 `json:"national_average"`
	PartyRatio       float64 `json:"party_ratio"`
	NationalRatio    float64 `json:"national_ratio"`
}

type MPLobbyingResponse struct {
	MemberID            string                      `json:"member_id"`
	Page                int                         `json:"page"`
	PerPage             int                         `json:"per_page"`
	Total               int                         `json:"total"`
	Pages               int                         `json:"pages"`
	Summary             MPLobbyingSummary           `json:"summary"`
	Timeline            []MPLobbyingTimelineEntry   `json:"timeline"`
	SubjectDistribution []LobbyingSubjectDistribution `json:"subject_distribution"`
	TopOrganizations    []TopLobbyingOrganization    `json:"top_organizations"`
	CohortComparison    CohortComparison            `json:"cohort_comparison"`
	AvailableSubjects   []string                    `json:"available_subjects"`
}

type MPLobbyingArtifact struct {
	MemberID            string                      `json:"member_id"`
	Summary             MPLobbyingSummary           `json:"summary"`
	Timeline            []MPLobbyingTimelineEntry   `json:"timeline"`
	SubjectDistribution []LobbyingSubjectDistribution `json:"subject_distribution"`
	TopOrganizations    []TopLobbyingOrganization    `json:"top_organizations"`
	CohortBaseline      CohortComparisonBaseline    `json:"cohort_baseline"`
	AvailableSubjects   []string                    `json:"available_subjects"`
}

type MPLobbyingRepository interface {
	LoadMPLobbyingArtifact(ctx context.Context, memberID string) (MPLobbyingArtifact, error)
}

type LoadMPLobbyingExposure struct {
	repo       MPLobbyingRepository
	comparator CompareMPLobbyingToCohort
}

func NewLoadMPLobbyingExposure(repo MPLobbyingRepository) *LoadMPLobbyingExposure {
	return &LoadMPLobbyingExposure{repo: repo, comparator: CompareMPLobbyingToCohort{}}
}

func (u *LoadMPLobbyingExposure) Execute(ctx context.Context, memberID string, page, perPage int, rangeFilter string, subject string) (MPLobbyingResponse, error) {
	page, perPage = clampPagination(page, perPage)
	artifact, err := u.repo.LoadMPLobbyingArtifact(ctx, memberID)
	if errors.Is(err, ErrNotFound) {
		return emptyExposureResponse(memberID, page, perPage), nil
	}
	if err != nil {
		return MPLobbyingResponse{}, err
	}

	summary := artifact.Summary
	filtered := filterTimeline(artifact.Timeline, ParseDateRange(rangeFilter), subject)
	sort.SliceStable(filtered, func(i, j int) bool {
		ai, aok := filtered[i].Date()
		aj, bok := filtered[j].Date()
		if aok != bok {
			if !aok {
				return false
			}
			if !bok {
				return true
			}
		}
		if aok && bok {
			return ai.After(aj)
		}
		return strings.ToLower(filtered[i].OrganizationName) < strings.ToLower(filtered[j].OrganizationName)
	})

	total := len(filtered)
	start, end := pageWindow(page, perPage, total)
	entries := append([]MPLobbyingTimelineEntry(nil), filtered[start:end]...)
	topOrganizations := truncateOrganizations(artifact.TopOrganizations, 5)
	comparison := u.comparator.Execute(summary.TotalCommunications, artifact.CohortBaseline)

	return MPLobbyingResponse{
		MemberID:            memberID,
		Page:                page,
		PerPage:             perPage,
		Total:               total,
		Pages:               pageCount(total, perPage),
		Summary:             summary,
		Timeline:            entries,
		SubjectDistribution:  copyDistribution(artifact.SubjectDistribution),
		TopOrganizations:    topOrganizations,
		CohortComparison:    comparison,
		AvailableSubjects:   copySubjects(artifact.AvailableSubjects),
	}, nil
}

type CompareMPLobbyingToCohort struct{}

func (CompareMPLobbyingToCohort) Execute(totalCommunications int, baseline CohortComparisonBaseline) CohortComparison {
	partyAverage := baseline.PartyAverage
	nationalAverage := baseline.NationalAverage
	return CohortComparison{
		Party:           baseline.Party,
		PartyAverage:    partyAverage,
		NationalAverage: nationalAverage,
		PartyRatio:      safeRatio(totalCommunications, partyAverage),
		NationalRatio:   safeRatio(totalCommunications, nationalAverage),
	}
}

func safeRatio(numerator, denominator float64) float64 {
	if denominator <= 0 {
		return 0
	}
	return math.Round((float64(numerator)/denominator)*10) / 10
}

func clampPagination(page, perPage int) (int, int) {
	if page <= 0 {
		page = 1
	}
	if perPage <= 0 {
		perPage = DefaultPerPage
	}
	if perPage > MaxPerPage {
		perPage = MaxPerPage
	}
	return page, perPage
}

func filterTimeline(entries []MPLobbyingTimelineEntry, rangeFilter DateRange, subject string) []MPLobbyingTimelineEntry {
	target := subjectThreshold(rangeFilter)
	subject = strings.TrimSpace(strings.ToLower(subject))
	if subject == "" && rangeFilter == DateRangeAll {
		out := make([]MPLobbyingTimelineEntry, len(entries))
		copy(out, entries)
		return out
	}

	filtered := make([]MPLobbyingTimelineEntry, 0, len(entries))
	for _, entry := range entries {
		if subject != "" && !strings.Contains(strings.ToLower(entry.SubjectMatter), subject) {
			continue
		}
		if rangeFilter != DateRangeAll {
			t, ok := entry.Date()
			if !ok || t.Before(target) {
				continue
			}
		}
		filtered = append(filtered, entry)
	}
	return filtered
}

func subjectThreshold(rangeFilter DateRange) time.Time {
	now := time.Now().UTC()
	switch rangeFilter {
	case DateRange30Days:
		return now.AddDate(0, 0, -30)
	case DateRange3Months:
		return now.AddDate(0, -3, 0)
	case DateRange12Months:
		return now.AddDate(-1, 0, 0)
	default:
		return time.Time{}
	}
}

func emptyExposureResponse(memberID string, page, perPage int) MPLobbyingResponse {
	return MPLobbyingResponse{
		MemberID:            memberID,
		Page:                page,
		PerPage:             perPage,
		Summary:             MPLobbyingSummary{},
		Timeline:            []MPLobbyingTimelineEntry{},
		SubjectDistribution: []LobbyingSubjectDistribution{},
		TopOrganizations:   []TopLobbyingOrganization{},
		CohortComparison:   CohortComparison{},
		AvailableSubjects:  []string{},
	}
}

func copyDistribution(distribution []LobbyingSubjectDistribution) []LobbyingSubjectDistribution {
	out := make([]LobbyingSubjectDistribution, len(distribution))
	copy(out, distribution)
	return out
}

func copySubjects(subjects []string) []string {
	out := make([]string, len(subjects))
	copy(out, subjects)
	return out
}

func truncateOrganizations(organizations []TopLobbyingOrganization, max int) []TopLobbyingOrganization {
	if len(organizations) <= max {
		return copyOrganizations(organizations)
	}
	return copyOrganizations(organizations[:max])
}

func copyOrganizations(organizations []TopLobbyingOrganization) []TopLobbyingOrganization {
	out := make([]TopLobbyingOrganization, len(organizations))
	copy(out, organizations)
	return out
}

func pageWindow(page, perPage, total int) (int, int) {
	start := (page - 1) * perPage
	if start >= total {
		return total, total
	}
	end := start + perPage
	if end > total {
		end = total
	}
	return start, end
}

func pageCount(total, perPage int) int {
	if total == 0 {
		return 0
	}
	return int(math.Ceil(float64(total) / float64(perPage)))
}

func ParsePositiveInt(value string, fallback int) int {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	n, err := strconv.Atoi(value)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

func (u *LoadMPLobbyingExposure) ParseDateRange(value string) DateRange {
	return ParseDateRange(value)
}

func DebugThreshold(raw string) (string, error) {
	range := ParseDateRange(raw)
	if range == DateRangeAll {
		return "", nil
	}
	t := subjectThreshold(range)
	if t.IsZero() {
		return "", nil
	}
	return t.Format(dateFormat), nil
}

func ValidatePageValue(value string, fallback int) (int, error) {
	parsed := ParsePositiveInt(value, fallback)
	if parsed <= 0 {
		return 0, fmt.Errorf("invalid page value")
	}
	return parsed, nil
}
