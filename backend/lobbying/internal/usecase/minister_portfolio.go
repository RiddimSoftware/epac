package usecase

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"
)

const fallbackPortfolioName = "Cabinet minister tenure"

var ErrMinisterNotFound = errors.New("minister not found")

type MinisterPortfolioPeriod struct {
	PortfolioName string `json:"portfolio_name"`
	StartDate     string `json:"start_date"`
	EndDate       string `json:"end_date"`
}

type MinisterProfile struct {
	MemberID          string
	MinisterName      string
	FirstName         string
	LastName          string
	TenureStartDate   string
	TenureEndDate     string
	PortfolioPeriods  []MinisterPortfolioPeriod
	ParliamentNumbers []int
}

type MinisterCommunicationsFilter struct {
	MemberID  string
	FirstName string
	LastName  string
	StartDate string
	EndDate   string
}

type MinisterLobbyingCommunication struct {
	ID                string   `json:"id"`
	OrganizationName  string   `json:"organization_name,omitempty"`
	RegistrantName    string   `json:"registrant_name,omitempty"`
	RegistrantType    string   `json:"registrant_type,omitempty"`
	CommunicationDate string   `json:"communication_date,omitempty"`
	SubjectMatters    []string `json:"subject_matters"`
	OCLCodes          []string `json:"ocl_codes"`
	MandateMatch      bool     `json:"mandate_match"`
	Citation          string   `json:"citation"`
	SourceURL         string   `json:"source_url"`
}

type PortfolioTopOrganization struct {
	OrganizationName string `json:"organization_name"`
	Count            int    `json:"count"`
}

type MinisterPortfolioLobbyingPeriod struct {
	PortfolioName    string                          `json:"portfolio_name"`
	StartDate        string                          `json:"start_date"`
	EndDate          string                          `json:"end_date"`
	TopOrganizations []PortfolioTopOrganization      `json:"top_organizations"`
	Communications   []MinisterLobbyingCommunication `json:"communications"`
}

type MinisterLobbyingByPortfolioResult struct {
	MemberID            string                            `json:"member_id"`
	MinisterName        string                            `json:"minister_name"`
	TotalCommunications int                               `json:"total_communications"`
	Citation            string                            `json:"citation"`
	SourceURL           string                            `json:"source_url"`
	Portfolios          []MinisterPortfolioLobbyingPeriod `json:"portfolios"`
}

type CabinetLobbyingOverviewInput struct {
	Parliament int
	Portfolio  string
}

type CabinetLobbyingSummary struct {
	MemberID            string                     `json:"member_id"`
	MinisterName        string                     `json:"minister_name"`
	Portfolios          []MinisterPortfolioPeriod  `json:"portfolios"`
	TotalCommunications int                        `json:"total_communications"`
	TopOrganizations    []PortfolioTopOrganization `json:"top_organizations"`
}

type CabinetLobbyingOverviewResult struct {
	Parliament      int                      `json:"parliament"`
	PortfolioFilter string                   `json:"portfolio_filter,omitempty"`
	Citation        string                   `json:"citation"`
	SourceURL       string                   `json:"source_url"`
	Ministers       []CabinetLobbyingSummary `json:"ministers"`
}

type MandatePolicyArea struct {
	EpacTopicSlug string
	Confidence    float64
}

type CabinetMinisterFilter struct {
	Parliament int
	Portfolio  string
}

type MinisterRepository interface {
	LoadMinisterProfile(ctx context.Context, memberID string) (MinisterProfile, error)
	ListCabinetMinisters(ctx context.Context, filter CabinetMinisterFilter) ([]MinisterProfile, error)
}

type MinisterLobbyingRepository interface {
	ListMinisterCommunications(ctx context.Context, filter MinisterCommunicationsFilter) ([]MinisterLobbyingCommunication, error)
}

type MandateLetterRepository interface {
	ListMandatePolicyAreas(ctx context.Context, memberID string) ([]MandatePolicyArea, error)
}

type OCLTopicMapper interface {
	TopicMappingsForOCLCode(oclCode string) []OCLTopicMapping
}

type PortfolioBoundaryGap struct {
	MemberID     string
	MinisterName string
	Reason       string
}

type PortfolioBoundaryGapLogger interface {
	WarnPortfolioBoundaryGap(ctx context.Context, gap PortfolioBoundaryGap)
}

type NoopPortfolioBoundaryGapLogger struct{}

func (NoopPortfolioBoundaryGapLogger) WarnPortfolioBoundaryGap(context.Context, PortfolioBoundaryGap) {
}

type LoadMinisterLobbyingByPortfolio struct {
	ministers MinisterRepository
	lobbying  MinisterLobbyingRepository
	mandates  MandateLetterRepository
	topics    OCLTopicMapper
	logger    PortfolioBoundaryGapLogger
}

func NewLoadMinisterLobbyingByPortfolio(
	ministers MinisterRepository,
	lobbying MinisterLobbyingRepository,
	mandates MandateLetterRepository,
	topics OCLTopicMapper,
	logger PortfolioBoundaryGapLogger,
) LoadMinisterLobbyingByPortfolio {
	if logger == nil {
		logger = NoopPortfolioBoundaryGapLogger{}
	}
	return LoadMinisterLobbyingByPortfolio{
		ministers: ministers,
		lobbying:  lobbying,
		mandates:  mandates,
		topics:    topics,
		logger:    logger,
	}
}

func (u LoadMinisterLobbyingByPortfolio) Execute(ctx context.Context, memberID string) (MinisterLobbyingByPortfolioResult, error) {
	memberID = strings.TrimSpace(memberID)
	if memberID == "" {
		return MinisterLobbyingByPortfolioResult{}, ErrMinisterNotFound
	}

	profile, err := u.ministers.LoadMinisterProfile(ctx, memberID)
	if err != nil {
		return MinisterLobbyingByPortfolioResult{}, err
	}
	periods := displayPeriodsForProfile(ctx, profile, u.logger)

	communications, err := u.lobbying.ListMinisterCommunications(ctx, MinisterCommunicationsFilter{
		MemberID:  profile.MemberID,
		FirstName: profile.FirstName,
		LastName:  profile.LastName,
		StartDate: profile.TenureStartDate,
		EndDate:   profile.TenureEndDate,
	})
	if err != nil {
		return MinisterLobbyingByPortfolioResult{}, err
	}
	normalizeCommunications(communications)
	u.applyMandateMatches(ctx, profile.MemberID, communications)

	grouped, ok := groupCommunicationsByPeriods(periods, communications)
	if !ok {
		u.logger.WarnPortfolioBoundaryGap(ctx, PortfolioBoundaryGap{
			MemberID:     profile.MemberID,
			MinisterName: profile.MinisterName,
			Reason:       "communication_outside_portfolio_periods",
		})
		grouped, _ = groupCommunicationsByPeriods([]MinisterPortfolioPeriod{fallbackPeriod(profile)}, communications)
	}

	return MinisterLobbyingByPortfolioResult{
		MemberID:            profile.MemberID,
		MinisterName:        profile.MinisterName,
		TotalCommunications: len(communications),
		Citation:            Citation,
		SourceURL:           SourceURL,
		Portfolios:          grouped,
	}, nil
}

func (u LoadMinisterLobbyingByPortfolio) applyMandateMatches(ctx context.Context, memberID string, communications []MinisterLobbyingCommunication) {
	if u.mandates == nil || u.topics == nil {
		return
	}
	areas, err := u.mandates.ListMandatePolicyAreas(ctx, memberID)
	if err != nil {
		return
	}
	mandateSlugs := make(map[string]struct{})
	for _, area := range areas {
		if area.Confidence < LowConfidenceThreshold {
			continue
		}
		slug := NormalizeTopicSlug(area.EpacTopicSlug)
		if slug != "" {
			mandateSlugs[slug] = struct{}{}
		}
	}
	if len(mandateSlugs) == 0 {
		return
	}
	for i := range communications {
		communications[i].MandateMatch = communicationMatchesMandate(communications[i], mandateSlugs, u.topics)
	}
}

type LoadCabinetLobbyingOverview struct {
	ministers MinisterRepository
	lobbying  MinisterLobbyingRepository
	logger    PortfolioBoundaryGapLogger
}

func NewLoadCabinetLobbyingOverview(
	ministers MinisterRepository,
	lobbying MinisterLobbyingRepository,
	logger PortfolioBoundaryGapLogger,
) LoadCabinetLobbyingOverview {
	if logger == nil {
		logger = NoopPortfolioBoundaryGapLogger{}
	}
	return LoadCabinetLobbyingOverview{ministers: ministers, lobbying: lobbying, logger: logger}
}

func (u LoadCabinetLobbyingOverview) Execute(ctx context.Context, input CabinetLobbyingOverviewInput) (CabinetLobbyingOverviewResult, error) {
	profiles, err := u.ministers.ListCabinetMinisters(ctx, CabinetMinisterFilter{
		Parliament: input.Parliament,
		Portfolio:  input.Portfolio,
	})
	if err != nil {
		return CabinetLobbyingOverviewResult{}, err
	}

	summaries := make([]CabinetLobbyingSummary, 0, len(profiles))
	for _, profile := range profiles {
		communications, err := u.lobbying.ListMinisterCommunications(ctx, MinisterCommunicationsFilter{
			MemberID:  profile.MemberID,
			FirstName: profile.FirstName,
			LastName:  profile.LastName,
			StartDate: profile.TenureStartDate,
			EndDate:   profile.TenureEndDate,
		})
		if err != nil {
			return CabinetLobbyingOverviewResult{}, err
		}
		normalizeCommunications(communications)
		summaries = append(summaries, CabinetLobbyingSummary{
			MemberID:            profile.MemberID,
			MinisterName:        profile.MinisterName,
			Portfolios:          displayPeriodsForProfile(ctx, profile, u.logger),
			TotalCommunications: len(communications),
			TopOrganizations:    topOrganizations(communications, 3),
		})
	}
	sort.SliceStable(summaries, func(i, j int) bool {
		if summaries[i].TotalCommunications != summaries[j].TotalCommunications {
			return summaries[i].TotalCommunications > summaries[j].TotalCommunications
		}
		return strings.ToLower(summaries[i].MinisterName) < strings.ToLower(summaries[j].MinisterName)
	})

	return CabinetLobbyingOverviewResult{
		Parliament:      input.Parliament,
		PortfolioFilter: strings.TrimSpace(input.Portfolio),
		Citation:        Citation,
		SourceURL:       SourceURL,
		Ministers:       summaries,
	}, nil
}

func displayPeriodsForProfile(ctx context.Context, profile MinisterProfile, logger PortfolioBoundaryGapLogger) []MinisterPortfolioPeriod {
	periods := sortedPeriods(profile.PortfolioPeriods)
	if reason := portfolioBoundaryGapReason(periods); reason != "" {
		logger.WarnPortfolioBoundaryGap(ctx, PortfolioBoundaryGap{
			MemberID:     profile.MemberID,
			MinisterName: profile.MinisterName,
			Reason:       reason,
		})
		return []MinisterPortfolioPeriod{fallbackPeriod(profile)}
	}
	return periods
}

func portfolioBoundaryGapReason(periods []MinisterPortfolioPeriod) string {
	if len(periods) == 0 {
		return "missing_portfolio_periods"
	}
	for i, period := range periods {
		if strings.TrimSpace(period.PortfolioName) == "" {
			return "missing_portfolio_name"
		}
		if strings.TrimSpace(period.StartDate) == "" {
			return "missing_portfolio_start_date"
		}
		if i > 0 && strings.TrimSpace(periods[i-1].EndDate) == "" {
			return "open_ended_period_before_next_portfolio"
		}
		if i > 0 {
			previousEnd, okPrev := parseISODate(periods[i-1].EndDate)
			currentStart, okCurrent := parseISODate(period.StartDate)
			if okPrev && okCurrent {
				if previousEnd.After(currentStart) {
					return "overlapping_portfolio_periods"
				}
				if previousEnd.AddDate(0, 0, 1).Before(currentStart) {
					return "gap_between_portfolio_periods"
				}
			}
		}
	}
	return ""
}

func fallbackPeriod(profile MinisterProfile) MinisterPortfolioPeriod {
	return MinisterPortfolioPeriod{
		PortfolioName: fallbackPortfolioName,
		StartDate:     profile.TenureStartDate,
		EndDate:       profile.TenureEndDate,
	}
}

func groupCommunicationsByPeriods(
	periods []MinisterPortfolioPeriod,
	communications []MinisterLobbyingCommunication,
) ([]MinisterPortfolioLobbyingPeriod, bool) {
	if len(periods) == 1 && periods[0].PortfolioName == fallbackPortfolioName {
		rows := []MinisterPortfolioLobbyingPeriod{{
			PortfolioName:    periods[0].PortfolioName,
			StartDate:        periods[0].StartDate,
			EndDate:          periods[0].EndDate,
			TopOrganizations: topOrganizations(communications, 3),
			Communications:   append([]MinisterLobbyingCommunication(nil), communications...),
		}}
		sortCommunications(rows[0].Communications)
		return rows, true
	}

	grouped := make([]MinisterPortfolioLobbyingPeriod, 0, len(periods))
	for _, period := range periods {
		grouped = append(grouped, MinisterPortfolioLobbyingPeriod{
			PortfolioName:    period.PortfolioName,
			StartDate:        period.StartDate,
			EndDate:          period.EndDate,
			TopOrganizations: []PortfolioTopOrganization{},
			Communications:   []MinisterLobbyingCommunication{},
		})
	}

	for _, communication := range communications {
		assigned := false
		for i, period := range periods {
			if dateInRange(communication.CommunicationDate, period.StartDate, period.EndDate) {
				grouped[i].Communications = append(grouped[i].Communications, communication)
				assigned = true
				break
			}
		}
		if !assigned {
			return nil, false
		}
	}
	for i := range grouped {
		sortCommunications(grouped[i].Communications)
		grouped[i].TopOrganizations = topOrganizations(grouped[i].Communications, 3)
	}
	return grouped, true
}

func communicationMatchesMandate(communication MinisterLobbyingCommunication, mandateSlugs map[string]struct{}, topics OCLTopicMapper) bool {
	for _, code := range communication.OCLCodes {
		for _, mapping := range topics.TopicMappingsForOCLCode(code) {
			if mapping.Confidence < LowConfidenceThreshold {
				continue
			}
			if _, ok := mandateSlugs[NormalizeTopicSlug(mapping.EpacTopicSlug)]; ok {
				return true
			}
		}
	}
	return false
}

func normalizeCommunications(communications []MinisterLobbyingCommunication) {
	for i := range communications {
		if communications[i].SubjectMatters == nil {
			communications[i].SubjectMatters = []string{}
		}
		if communications[i].OCLCodes == nil {
			communications[i].OCLCodes = []string{}
		}
		for j := range communications[i].OCLCodes {
			communications[i].OCLCodes[j] = NormalizeOCLCode(communications[i].OCLCodes[j])
		}
		if communications[i].Citation == "" {
			communications[i].Citation = Citation
		}
		if communications[i].SourceURL == "" {
			communications[i].SourceURL = SourceURL
		}
	}
}

func NormalizeOCLCode(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" || strings.HasPrefix(code, "SMT-") {
		return code
	}
	allDigits := true
	for _, r := range code {
		if r < '0' || r > '9' {
			allDigits = false
			break
		}
	}
	if allDigits {
		return "SMT-" + code
	}
	return code
}

func sortedPeriods(periods []MinisterPortfolioPeriod) []MinisterPortfolioPeriod {
	out := append([]MinisterPortfolioPeriod(nil), periods...)
	sort.SliceStable(out, func(i, j int) bool {
		left, leftOK := parseISODate(out[i].StartDate)
		right, rightOK := parseISODate(out[j].StartDate)
		switch {
		case leftOK && rightOK:
			if !left.Equal(right) {
				return left.Before(right)
			}
		case leftOK:
			return true
		case rightOK:
			return false
		}
		return strings.ToLower(out[i].PortfolioName) < strings.ToLower(out[j].PortfolioName)
	})
	return out
}

func topOrganizations(communications []MinisterLobbyingCommunication, limit int) []PortfolioTopOrganization {
	if limit <= 0 {
		return []PortfolioTopOrganization{}
	}
	counts := make(map[string]int)
	display := make(map[string]string)
	for _, communication := range communications {
		name := strings.TrimSpace(communication.OrganizationName)
		if name == "" {
			continue
		}
		key := strings.ToLower(name)
		counts[key]++
		if display[key] == "" {
			display[key] = name
		}
	}
	top := make([]PortfolioTopOrganization, 0, len(counts))
	for key, count := range counts {
		top = append(top, PortfolioTopOrganization{OrganizationName: display[key], Count: count})
	}
	sort.SliceStable(top, func(i, j int) bool {
		if top[i].Count != top[j].Count {
			return top[i].Count > top[j].Count
		}
		return strings.ToLower(top[i].OrganizationName) < strings.ToLower(top[j].OrganizationName)
	})
	if len(top) > limit {
		top = top[:limit]
	}
	return top
}

func sortCommunications(communications []MinisterLobbyingCommunication) {
	sort.SliceStable(communications, func(i, j int) bool {
		left, leftOK := parseISODate(communications[i].CommunicationDate)
		right, rightOK := parseISODate(communications[j].CommunicationDate)
		switch {
		case leftOK && rightOK:
			if !left.Equal(right) {
				return left.After(right)
			}
		case leftOK:
			return true
		case rightOK:
			return false
		}
		return communications[i].ID < communications[j].ID
	})
}

func dateInRange(date, start, end string) bool {
	if strings.TrimSpace(date) == "" && strings.TrimSpace(start) == "" && strings.TrimSpace(end) == "" {
		return true
	}
	parsed, ok := parseISODate(date)
	if !ok {
		return false
	}
	if startDate, ok := parseISODate(start); ok && parsed.Before(startDate) {
		return false
	}
	if endDate, ok := parseISODate(end); ok && parsed.After(endDate) {
		return false
	}
	return true
}

func parseISODate(raw string) (time.Time, bool) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, false
	}
	parsed, err := time.Parse("2006-01-02", raw)
	if err != nil {
		return time.Time{}, false
	}
	return parsed, true
}
