package usecase

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"
)

const DefaultBillLobbyingWindowMonths = 12

var ErrBillLobbyingContextMissingBillID = errors.New("missing bill id")

type BillSubjectContext struct {
	LegisInfoID           string
	SubjectTags           []string
	TopicSlugs            []string
	MostRecentReadingDate string
}

type BillLobbyingContextInput struct {
	LegisInfoID  string
	WindowMonths int
}

type DateWindow struct {
	StartDate string
	EndDate   string
}

type BillLobbyingCommunication struct {
	ID                string
	OrganizationName  string
	SubjectMatter     string
	OCLCode           string
	CommunicationDate string
}

type OrganizationCommunicationCount struct {
	OrganizationName string `json:"organization_name"`
	Count            int    `json:"count"`
}

type SubjectMatterCommunicationCount struct {
	OCLCode       string `json:"ocl_code"`
	SubjectMatter string `json:"subject_matter"`
	Count         int    `json:"count"`
}

type BillLobbyingContext struct {
	LegisInfoID          string                            `json:"legisinfo_id"`
	WindowMonths         int                               `json:"window_months"`
	WindowStartDate      string                            `json:"window_start_date"`
	WindowEndDate        string                            `json:"window_end_date"`
	SubjectTags          []string                          `json:"subject_tags"`
	TotalCommunications  int                               `json:"total_communications"`
	CountByOrganization  []OrganizationCommunicationCount  `json:"count_by_organization"`
	CountBySubjectMatter []SubjectMatterCommunicationCount `json:"count_by_subject_matter"`
	TopOrganizations     []OrganizationCommunicationCount  `json:"top_organizations"`
	Citation             string                            `json:"citation"`
	SourceURL            string                            `json:"source_url"`
}

type BillSubjectsRepository interface {
	LoadBillSubjectContext(ctx context.Context, legisInfoID string) (BillSubjectContext, error)
}

type BillLobbyingCommunicationsRepository interface {
	ListBillLobbyingCommunications(ctx context.Context, mappings []OCLTopicMapping, window DateWindow) ([]BillLobbyingCommunication, error)
}

type BillSubjectMapper interface {
	CodesForTopic(slug string) ([]OCLTopicMapping, bool)
}

type Clock interface {
	Now() time.Time
}

type SystemClock struct{}

func (SystemClock) Now() time.Time {
	return time.Now().UTC()
}

type LoadBillLobbyingContext struct {
	bills    BillSubjectsRepository
	lobbying BillLobbyingCommunicationsRepository
	mapper   BillSubjectMapper
	clock    Clock
}

func NewLoadBillLobbyingContext(
	bills BillSubjectsRepository,
	lobbying BillLobbyingCommunicationsRepository,
	mapper BillSubjectMapper,
	clock Clock,
) LoadBillLobbyingContext {
	if clock == nil {
		clock = SystemClock{}
	}
	return LoadBillLobbyingContext{
		bills:    bills,
		lobbying: lobbying,
		mapper:   mapper,
		clock:    clock,
	}
}

func (u LoadBillLobbyingContext) Execute(ctx context.Context, input BillLobbyingContextInput) (BillLobbyingContext, error) {
	legisInfoID := strings.TrimSpace(input.LegisInfoID)
	if legisInfoID == "" {
		return BillLobbyingContext{}, ErrBillLobbyingContextMissingBillID
	}

	windowMonths := input.WindowMonths
	if windowMonths <= 0 {
		windowMonths = DefaultBillLobbyingWindowMonths
	}

	subjectContext, err := u.bills.LoadBillSubjectContext(ctx, legisInfoID)
	if err != nil {
		return BillLobbyingContext{}, err
	}

	subjectTags := normalizedSubjectTags(subjectContext.SubjectTags)
	window := billLobbyingWindow(subjectContext.MostRecentReadingDate, windowMonths, u.clock)
	result := emptyBillLobbyingContext(legisInfoID, windowMonths, window, subjectTags)
	if len(subjectTags) == 0 {
		return result, nil
	}

	mappingTags := normalizedSubjectTags(subjectContext.TopicSlugs)
	if len(mappingTags) == 0 {
		mappingTags = subjectTags
	}
	mappings := highConfidenceMappingsForSubjectTags(u.mapper, mappingTags)
	if len(mappings) == 0 {
		return result, nil
	}

	communications, err := u.lobbying.ListBillLobbyingCommunications(ctx, mappings, window)
	if err != nil {
		return BillLobbyingContext{}, err
	}
	applyBillLobbyingCounts(&result, communications)
	return result, nil
}

func normalizedSubjectTags(tags []string) []string {
	seen := make(map[string]struct{}, len(tags))
	out := []string{}
	for _, tag := range tags {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		key := strings.ToLower(tag)
		if _, ok := seen[key]; ok {
			continue
		}
		seen[key] = struct{}{}
		out = append(out, tag)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return strings.ToLower(out[i]) < strings.ToLower(out[j])
	})
	return out
}

func highConfidenceMappingsForSubjectTags(mapper BillSubjectMapper, subjectTags []string) []OCLTopicMapping {
	if mapper == nil {
		return []OCLTopicMapping{}
	}
	byCode := make(map[string]OCLTopicMapping)
	for _, tag := range subjectTags {
		mappings, ok := mapper.CodesForTopic(NormalizeSubjectTagSlug(tag))
		if !ok {
			continue
		}
		for _, mapping := range mappings {
			mapping.OCLCode = NormalizeOCLCode(mapping.OCLCode)
			mapping.EpacTopicSlug = NormalizeTopicSlug(mapping.EpacTopicSlug)
			if mapping.OCLCode == "" || mapping.Confidence < LowConfidenceThreshold {
				continue
			}
			existing, exists := byCode[mapping.OCLCode]
			if !exists || mapping.Confidence > existing.Confidence {
				byCode[mapping.OCLCode] = mapping
			}
		}
	}

	out := make([]OCLTopicMapping, 0, len(byCode))
	for _, mapping := range byCode {
		out = append(out, mapping)
	}
	sort.SliceStable(out, func(i, j int) bool {
		return compareMappingCodes(out[i].OCLCode, out[j].OCLCode) < 0
	})
	return out
}

func NormalizeSubjectTagSlug(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))
	var b strings.Builder
	for _, r := range tag {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func billLobbyingWindow(anchorDate string, months int, clock Clock) DateWindow {
	end := clock.Now().UTC()
	if parsed, err := time.Parse("2006-01-02", strings.TrimSpace(anchorDate)); err == nil {
		end = parsed
	}
	start := end.AddDate(0, -months, 0)
	return DateWindow{
		StartDate: start.Format("2006-01-02"),
		EndDate:   end.Format("2006-01-02"),
	}
}

func emptyBillLobbyingContext(legisInfoID string, windowMonths int, window DateWindow, subjectTags []string) BillLobbyingContext {
	return BillLobbyingContext{
		LegisInfoID:          legisInfoID,
		WindowMonths:         windowMonths,
		WindowStartDate:      window.StartDate,
		WindowEndDate:        window.EndDate,
		SubjectTags:          append([]string(nil), subjectTags...),
		TotalCommunications:  0,
		CountByOrganization:  []OrganizationCommunicationCount{},
		CountBySubjectMatter: []SubjectMatterCommunicationCount{},
		TopOrganizations:     []OrganizationCommunicationCount{},
		Citation:             Citation,
		SourceURL:            SourceURL,
	}
}

func applyBillLobbyingCounts(result *BillLobbyingContext, communications []BillLobbyingCommunication) {
	seenCommunications := map[string]BillLobbyingCommunication{}
	seenSubjectRows := map[string]struct{}{}
	subjectCounts := map[string]SubjectMatterCommunicationCount{}

	for _, communication := range communications {
		id := strings.TrimSpace(communication.ID)
		if id == "" {
			continue
		}
		communication.ID = id
		communication.OrganizationName = cleanOrganizationName(communication.OrganizationName)
		communication.SubjectMatter = strings.TrimSpace(communication.SubjectMatter)
		communication.OCLCode = NormalizeOCLCode(communication.OCLCode)
		if _, ok := seenCommunications[id]; !ok {
			seenCommunications[id] = communication
		}

		subjectKey := id + "\x00" + communication.OCLCode + "\x00" + strings.ToLower(communication.SubjectMatter)
		if _, ok := seenSubjectRows[subjectKey]; ok {
			continue
		}
		seenSubjectRows[subjectKey] = struct{}{}

		countKey := communication.OCLCode + "\x00" + strings.ToLower(communication.SubjectMatter)
		count := subjectCounts[countKey]
		if count.OCLCode == "" {
			count.OCLCode = communication.OCLCode
			count.SubjectMatter = communication.SubjectMatter
		}
		count.Count++
		subjectCounts[countKey] = count
	}

	orgCounts := map[string]int{}
	for _, communication := range seenCommunications {
		orgCounts[communication.OrganizationName]++
	}

	result.TotalCommunications = len(seenCommunications)
	result.CountByOrganization = sortedOrganizationCounts(orgCounts)
	result.TopOrganizations = topBillOrganizations(result.CountByOrganization, 3)
	result.CountBySubjectMatter = sortedSubjectMatterCounts(subjectCounts)
}

func cleanOrganizationName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "Unknown organization"
	}
	return name
}

func sortedOrganizationCounts(counts map[string]int) []OrganizationCommunicationCount {
	out := make([]OrganizationCommunicationCount, 0, len(counts))
	for name, count := range counts {
		out = append(out, OrganizationCommunicationCount{OrganizationName: name, Count: count})
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		return strings.ToLower(out[i].OrganizationName) < strings.ToLower(out[j].OrganizationName)
	})
	return out
}

func topBillOrganizations(counts []OrganizationCommunicationCount, limit int) []OrganizationCommunicationCount {
	if len(counts) <= limit {
		return append([]OrganizationCommunicationCount(nil), counts...)
	}
	return append([]OrganizationCommunicationCount(nil), counts[:limit]...)
}

func sortedSubjectMatterCounts(counts map[string]SubjectMatterCommunicationCount) []SubjectMatterCommunicationCount {
	out := make([]SubjectMatterCommunicationCount, 0, len(counts))
	for _, count := range counts {
		out = append(out, count)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Count != out[j].Count {
			return out[i].Count > out[j].Count
		}
		if strings.ToLower(out[i].SubjectMatter) != strings.ToLower(out[j].SubjectMatter) {
			return strings.ToLower(out[i].SubjectMatter) < strings.ToLower(out[j].SubjectMatter)
		}
		return out[i].OCLCode < out[j].OCLCode
	})
	return out
}

func compareMappingCodes(left, right string) int {
	if left == right {
		return 0
	}
	if left < right {
		return -1
	}
	return 1
}
