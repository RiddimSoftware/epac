// Package usecase implements the ViewMemberSpeechFeed application policy.
//
// It depends only on a HansardRepository port and standard library types.
package usecase

import (
	"context"
	"errors"
	"math"
	"sort"
	"strconv"
	"strings"
)

const (
	DefaultPerPage = 20
	MaxPerPage     = 100
)

var ErrNotFound = errors.New("member speeches not found")

type SpeechRecord struct {
	InterventionID  string  `json:"id"`
	SittingDate     *string `json:"sitting_date,omitempty"`
	ParliamentNum   *int    `json:"parliament_num,omitempty"`
	SessionNum      *int    `json:"session_num,omitempty"`
	SubjectTitle    *string `json:"subject_title,omitempty"`
	Preview         string  `json:"preview"`
	WordCount       *int    `json:"word_count,omitempty"`
	Filename        string  `json:"filename"`
	InterventionSeq *int    `json:"intervention_seq,omitempty"`
}

type SpeechEntry struct {
	InterventionID string  `json:"id"`
	SittingDate    *string `json:"sitting_date,omitempty"`
	ParliamentNum  *int    `json:"parliament_num,omitempty"`
	SessionNum     *int    `json:"session_num,omitempty"`
	SubjectTitle   *string `json:"subject_title,omitempty"`
	Preview        string  `json:"preview"`
	WordCount      *int    `json:"word_count,omitempty"`
	Filename       string  `json:"filename"`
}

type MemberStats struct {
	TotalSpeeches int    `json:"total_speeches"`
	AvgWordCount  int    `json:"avg_word_count"`
	TopTopic      string `json:"top_topic"`
}

type MemberSpeechesArtifact struct {
	MemberID string
	Stats    MemberStats
	Speeches []SpeechRecord
}

type MemberSpeechesResponse struct {
	MemberID string        `json:"member_id"`
	Page     int           `json:"page"`
	PerPage  int           `json:"per_page"`
	Total    int           `json:"total"`
	Pages    int           `json:"pages"`
	Stats    MemberStats   `json:"stats"`
	Speeches []SpeechEntry `json:"speeches"`
}

// MemberContentRepository is the outbound port for loading member speech artifacts
// derived from ingested Hansard records. Matches the catalog's
// `MemberContentRepository` port.
type MemberContentRepository interface {
	LoadMemberSpeeches(ctx context.Context, memberID string) (MemberSpeechesArtifact, error)
}

type ViewMemberSpeechFeed struct {
	repo MemberContentRepository
}

func New(repo MemberContentRepository) *ViewMemberSpeechFeed {
	return &ViewMemberSpeechFeed{repo: repo}
}

func (u *ViewMemberSpeechFeed) Execute(ctx context.Context, memberID string, page, perPage int, topic string) (MemberSpeechesResponse, error) {
	page, perPage = ClampPagination(page, perPage)
	artifact, err := u.repo.LoadMemberSpeeches(ctx, memberID)
	if errors.Is(err, ErrNotFound) {
		return emptySpeechesResponse(memberID, page, perPage), nil
	}
	if err != nil {
		return MemberSpeechesResponse{}, err
	}

	stats := artifact.Stats
	if stats.TotalSpeeches == 0 && len(artifact.Speeches) > 0 {
		stats = ComputeSpeechStats(artifact.Speeches)
	}

	filtered := filterSpeechesByTopic(artifact.Speeches, topic)
	sort.SliceStable(filtered, func(i, j int) bool {
		return speechAfter(filtered[i], filtered[j])
	})

	total := len(filtered)
	start, end := pageWindow(page, perPage, total)
	entries := make([]SpeechEntry, 0, end-start)
	for _, speech := range filtered[start:end] {
		entries = append(entries, speech.Entry())
	}

	return MemberSpeechesResponse{
		MemberID: memberID,
		Page:     page,
		PerPage:  perPage,
		Total:    total,
		Pages:    pageCount(total, perPage),
		Stats:    stats,
		Speeches: entries,
	}, nil
}

func (r SpeechRecord) Entry() SpeechEntry {
	return SpeechEntry{
		InterventionID: r.InterventionID,
		SittingDate:    r.SittingDate,
		ParliamentNum:  r.ParliamentNum,
		SessionNum:     r.SessionNum,
		SubjectTitle:   r.SubjectTitle,
		Preview:        r.Preview,
		WordCount:      r.WordCount,
		Filename:       r.Filename,
	}
}

func ClampPagination(page, perPage int) (int, int) {
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

func ComputeSpeechStats(speeches []SpeechRecord) MemberStats {
	stats := MemberStats{TotalSpeeches: len(speeches)}
	var wordCountTotal int
	var wordCountRows int
	topics := map[string]int{}

	for _, speech := range speeches {
		if speech.WordCount != nil {
			wordCountTotal += *speech.WordCount
			wordCountRows++
		}
		if speech.SubjectTitle != nil {
			topic := strings.TrimSpace(*speech.SubjectTitle)
			if topic != "" {
				topics[topic]++
			}
		}
	}
	if wordCountRows > 0 {
		stats.AvgWordCount = int(math.Round(float64(wordCountTotal) / float64(wordCountRows)))
	}
	var topCount int
	for topic, count := range topics {
		if count > topCount || (count == topCount && topic < stats.TopTopic) {
			stats.TopTopic = topic
			topCount = count
		}
	}
	return stats
}

func filterSpeechesByTopic(speeches []SpeechRecord, topic string) []SpeechRecord {
	topic = strings.ToLower(strings.TrimSpace(topic))
	if topic == "" {
		return append([]SpeechRecord(nil), speeches...)
	}
	filtered := make([]SpeechRecord, 0)
	for _, speech := range speeches {
		if speech.SubjectTitle == nil {
			continue
		}
		if strings.Contains(strings.ToLower(*speech.SubjectTitle), topic) {
			filtered = append(filtered, speech)
		}
	}
	return filtered
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

func emptySpeechesResponse(memberID string, page, perPage int) MemberSpeechesResponse {
	return MemberSpeechesResponse{
		MemberID: memberID,
		Page:     page,
		PerPage:  perPage,
		Stats:    MemberStats{},
		Speeches: []SpeechEntry{},
	}
}

func speechAfter(a, b SpeechRecord) bool {
	ad, bd := dateValue(a.SittingDate), dateValue(b.SittingDate)
	if ad != bd {
		if ad == "" {
			return false
		}
		if bd == "" {
			return true
		}
		return ad > bd
	}
	return intValue(a.InterventionSeq) < intValue(b.InterventionSeq)
}

func intValue(value *int) int {
	if value == nil {
		return 0
	}
	return *value
}

func dateValue(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}
