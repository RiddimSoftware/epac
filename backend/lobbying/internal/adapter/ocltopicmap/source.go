// Package ocltopicmap adapts the checked-in OCL-to-epac JSON mapping file to
// the LoadLobbyingByTopic use case's OCLSubjectsSource port.
package ocltopicmap

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"epac/lobbying/internal/usecase"
)

type jsonMapping struct {
	OCLCode       string  `json:"ocl_code"`
	EpacTopicSlug string  `json:"epac_topic_slug"`
	Confidence    float64 `json:"confidence"`
}

type Source struct {
	bySlug map[string][]usecase.OCLTopicMapping
}

func NewSource(data []byte) (*Source, error) {
	var raw []jsonMapping
	if err := json.Unmarshal(data, &raw); err != nil {
		return nil, fmt.Errorf("decode OCL topic map: %w", err)
	}
	bySlug := make(map[string][]usecase.OCLTopicMapping)
	seen := make(map[string]bool, len(raw))
	for i, item := range raw {
		mapping, err := normalizeMapping(item)
		if err != nil {
			return nil, fmt.Errorf("mapping %d: %w", i, err)
		}
		key := mapping.OCLCode + "\x00" + mapping.EpacTopicSlug
		if seen[key] {
			return nil, fmt.Errorf("duplicate mapping for %s to %s", mapping.OCLCode, mapping.EpacTopicSlug)
		}
		seen[key] = true
		bySlug[mapping.EpacTopicSlug] = append(bySlug[mapping.EpacTopicSlug], mapping)
	}
	for slug := range bySlug {
		sort.Slice(bySlug[slug], func(i, j int) bool {
			return compareOCLCodes(bySlug[slug][i].OCLCode, bySlug[slug][j].OCLCode) < 0
		})
	}
	return &Source{bySlug: bySlug}, nil
}

func (s *Source) CodesForTopic(slug string) ([]usecase.OCLTopicMapping, bool) {
	if s == nil {
		return nil, false
	}
	normalized := usecase.NormalizeTopicSlug(slug)
	mappings, ok := s.bySlug[normalized]
	if !ok {
		return nil, false
	}
	out := append([]usecase.OCLTopicMapping(nil), mappings...)
	return out, true
}

func normalizeMapping(item jsonMapping) (usecase.OCLTopicMapping, error) {
	code := strings.ToUpper(strings.TrimSpace(item.OCLCode))
	slug := usecase.NormalizeTopicSlug(item.EpacTopicSlug)
	if code == "" {
		return usecase.OCLTopicMapping{}, fmt.Errorf("ocl_code is required")
	}
	if slug == "" {
		return usecase.OCLTopicMapping{}, fmt.Errorf("epac_topic_slug is required")
	}
	if item.Confidence <= 0 || item.Confidence > 1 {
		return usecase.OCLTopicMapping{}, fmt.Errorf("confidence must be greater than 0 and at most 1")
	}
	return usecase.OCLTopicMapping{
		OCLCode:       code,
		EpacTopicSlug: slug,
		Confidence:    item.Confidence,
	}, nil
}

func compareOCLCodes(left, right string) int {
	leftNum := oclCodeNumber(left)
	rightNum := oclCodeNumber(right)
	if leftNum != rightNum {
		if leftNum < rightNum {
			return -1
		}
		return 1
	}
	return strings.Compare(left, right)
}

func oclCodeNumber(code string) int {
	_, suffix, ok := strings.Cut(code, "-")
	if !ok {
		return 0
	}
	n, err := strconv.Atoi(suffix)
	if err != nil {
		return 0
	}
	return n
}
