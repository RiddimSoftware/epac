package membercontent

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/smithy-go"
)

const (
	DefaultPerPage       = 20
	MaxPerPage           = 100
	MaxGzipArtifactBytes = 5 * 1024 * 1024
)

var ErrArtifactNotFound = errors.New("artifact not found")

type Store interface {
	Get(ctx context.Context, key string) ([]byte, error)
	Put(ctx context.Context, key string, body []byte) error
	Delete(ctx context.Context, key string) error
}

type FileStore struct {
	Root string
}

func (s FileStore) Get(_ context.Context, key string) ([]byte, error) {
	body, err := os.ReadFile(s.path(key))
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrArtifactNotFound
	}
	return body, err
}

func (s FileStore) Put(_ context.Context, key string, body []byte) error {
	path := s.path(key)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, body, 0o644)
}

func (s FileStore) Delete(_ context.Context, key string) error {
	err := os.Remove(s.path(key))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

func (s FileStore) path(key string) string {
	clean := filepath.Clean(strings.TrimPrefix(key, "/"))
	if clean == "." {
		clean = ""
	}
	return filepath.Join(s.Root, clean)
}

type S3Store struct {
	Client *s3.Client
	Bucket string
	Prefix string
}

func (s S3Store) Get(ctx context.Context, key string) ([]byte, error) {
	out, err := s.Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.Bucket),
		Key:    aws.String(s.key(key)),
	})
	if isS3NotFound(err) {
		return nil, ErrArtifactNotFound
	}
	if err != nil {
		return nil, err
	}
	defer out.Body.Close()
	return io.ReadAll(out.Body)
}

func (s S3Store) Put(ctx context.Context, key string, body []byte) error {
	_, err := s.Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.Bucket),
		Key:         aws.String(s.key(key)),
		Body:        bytes.NewReader(body),
		ContentType: aws.String("application/json"),
	})
	return err
}

func (s S3Store) Delete(ctx context.Context, key string) error {
	_, err := s.Client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.Bucket),
		Key:    aws.String(s.key(key)),
	})
	return err
}

func (s S3Store) key(key string) string {
	key = strings.TrimPrefix(key, "/")
	prefix := strings.Trim(s.Prefix, "/")
	if prefix == "" {
		return key
	}
	return prefix + "/" + key
}

func isS3NotFound(err error) bool {
	if err == nil {
		return false
	}
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) {
		switch apiErr.ErrorCode() {
		case "NoSuchKey", "NotFound", "404":
			return true
		}
	}
	return false
}

func NewStoreFromEnv(ctx context.Context) (Store, error) {
	if dir := firstEnv("EPAC_ARTIFACTS_DIR", "ARTIFACTS_DIR"); dir != "" {
		return FileStore{Root: dir}, nil
	}

	bucket := firstEnv("EPAC_ARTIFACT_BUCKET", "ARTIFACT_BUCKET", "MEMBER_CONTENT_ARTIFACT_BUCKET")
	if bucket == "" {
		return nil, errors.New("EPAC_ARTIFACT_BUCKET or ARTIFACT_BUCKET not set")
	}

	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}
	return S3Store{
		Client: s3.NewFromConfig(cfg),
		Bucket: bucket,
		Prefix: firstEnv("EPAC_ARTIFACT_PREFIX", "ARTIFACT_PREFIX", "MEMBER_CONTENT_ARTIFACT_PREFIX"),
	}, nil
}

func firstEnv(names ...string) string {
	for _, name := range names {
		if value := strings.TrimSpace(os.Getenv(name)); value != "" {
			return value
		}
	}
	return ""
}

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

type MemberStats struct {
	TotalSpeeches int    `json:"total_speeches"`
	AvgWordCount  int    `json:"avg_word_count"`
	TopTopic      string `json:"top_topic"`
}

type MemberSpeechesArtifact struct {
	MemberID string         `json:"member_id"`
	Stats    MemberStats    `json:"stats"`
	Speeches []SpeechRecord `json:"speeches"`
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

type VoteEntry struct {
	VoteID     string  `json:"vote_id"`
	Date       *string `json:"date,omitempty"`
	BillNumber string  `json:"bill_number,omitempty"`
	Summary    string  `json:"summary,omitempty"`
	Vote       string  `json:"vote"`
	SourceURL  string  `json:"source_url,omitempty"`
}

type MemberVotesArtifact struct {
	MemberID string      `json:"member_id"`
	Votes    []VoteEntry `json:"votes"`
}

type MemberVotesResponse struct {
	MemberID string      `json:"member_id"`
	Page     int         `json:"page"`
	PerPage  int         `json:"per_page"`
	Total    int         `json:"total"`
	Pages    int         `json:"pages"`
	Votes    []VoteEntry `json:"votes"`
}

type ArtifactIndex struct {
	MemberID string         `json:"member_id"`
	Pages    []ArtifactPage `json:"pages"`
}

type ArtifactPage struct {
	Key      string `json:"key"`
	FromDate string `json:"from_date,omitempty"`
	ToDate   string `json:"to_date,omitempty"`
	Count    int    `json:"count"`
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

func ListMemberSpeeches(ctx context.Context, store Store, memberID string, page, perPage int, topic string) (MemberSpeechesResponse, error) {
	page, perPage = ClampPagination(page, perPage)
	artifact, err := LoadMemberSpeechesArtifact(ctx, store, memberID)
	if errors.Is(err, ErrArtifactNotFound) {
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

func LoadMemberSpeechesArtifact(ctx context.Context, store Store, memberID string) (MemberSpeechesArtifact, error) {
	index, err := loadIndex(ctx, store, speechIndexKey(memberID))
	if err == nil {
		all := MemberSpeechesArtifact{MemberID: memberID}
		for _, page := range index.Pages {
			part, err := loadSpeechArtifact(ctx, store, page.Key)
			if err != nil {
				return MemberSpeechesArtifact{}, err
			}
			all.Speeches = append(all.Speeches, part.Speeches...)
		}
		all.Stats = ComputeSpeechStats(all.Speeches)
		return all, nil
	}
	if !errors.Is(err, ErrArtifactNotFound) {
		return MemberSpeechesArtifact{}, err
	}
	return loadSpeechArtifact(ctx, store, speechJSONKey(memberID))
}

func WriteMemberSpeechesArtifacts(ctx context.Context, store Store, artifact MemberSpeechesArtifact) ([]string, error) {
	sort.SliceStable(artifact.Speeches, func(i, j int) bool {
		return speechBefore(artifact.Speeches[i], artifact.Speeches[j])
	})
	artifact.Stats = ComputeSpeechStats(artifact.Speeches)

	key := speechJSONKey(artifact.MemberID)
	body, err := json.Marshal(artifact)
	if err != nil {
		return nil, err
	}
	if gzipSize(body) <= MaxGzipArtifactBytes {
		if err := store.Put(ctx, key, body); err != nil {
			return nil, err
		}
		if err := store.Delete(ctx, speechIndexKey(artifact.MemberID)); err != nil {
			return nil, err
		}
		return []string{key}, nil
	}

	pages, err := writeSpeechPages(ctx, store, artifact)
	if err != nil {
		return nil, err
	}
	if err := store.Delete(ctx, key); err != nil {
		return nil, err
	}
	return pages, nil
}

func ListMemberVotes(ctx context.Context, store Store, memberID string, page, perPage int) (MemberVotesResponse, error) {
	page, perPage = ClampPagination(page, perPage)
	artifact, err := LoadMemberVotesArtifact(ctx, store, memberID)
	if errors.Is(err, ErrArtifactNotFound) {
		return emptyVotesResponse(memberID, page, perPage), nil
	}
	if err != nil {
		return MemberVotesResponse{}, err
	}

	votes := append([]VoteEntry(nil), artifact.Votes...)
	sort.SliceStable(votes, func(i, j int) bool {
		return voteAfter(votes[i], votes[j])
	})

	total := len(votes)
	start, end := pageWindow(page, perPage, total)
	return MemberVotesResponse{
		MemberID: memberID,
		Page:     page,
		PerPage:  perPage,
		Total:    total,
		Pages:    pageCount(total, perPage),
		Votes:    votes[start:end],
	}, nil
}

func LoadMemberVotesArtifact(ctx context.Context, store Store, memberID string) (MemberVotesArtifact, error) {
	index, err := loadIndex(ctx, store, voteIndexKey(memberID))
	if err == nil {
		all := MemberVotesArtifact{MemberID: memberID}
		for _, page := range index.Pages {
			part, err := loadVoteArtifact(ctx, store, page.Key)
			if err != nil {
				return MemberVotesArtifact{}, err
			}
			all.Votes = append(all.Votes, part.Votes...)
		}
		return all, nil
	}
	if !errors.Is(err, ErrArtifactNotFound) {
		return MemberVotesArtifact{}, err
	}
	return loadVoteArtifact(ctx, store, voteJSONKey(memberID))
}

func WriteMemberVotesArtifacts(ctx context.Context, store Store, artifact MemberVotesArtifact) ([]string, error) {
	sort.SliceStable(artifact.Votes, func(i, j int) bool {
		return voteBefore(artifact.Votes[i], artifact.Votes[j])
	})

	key := voteJSONKey(artifact.MemberID)
	body, err := json.Marshal(artifact)
	if err != nil {
		return nil, err
	}
	if gzipSize(body) <= MaxGzipArtifactBytes {
		if err := store.Put(ctx, key, body); err != nil {
			return nil, err
		}
		if err := store.Delete(ctx, voteIndexKey(artifact.MemberID)); err != nil {
			return nil, err
		}
		return []string{key}, nil
	}

	pages, err := writeVotePages(ctx, store, artifact)
	if err != nil {
		return nil, err
	}
	if err := store.Delete(ctx, key); err != nil {
		return nil, err
	}
	return pages, nil
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

func Preview(content string, maxRunes int) string {
	runes := []rune(content)
	if len(runes) > maxRunes {
		return string(runes[:maxRunes])
	}
	return content
}

func loadSpeechArtifact(ctx context.Context, store Store, key string) (MemberSpeechesArtifact, error) {
	body, err := store.Get(ctx, key)
	if err != nil {
		return MemberSpeechesArtifact{}, err
	}
	var artifact MemberSpeechesArtifact
	if err := json.Unmarshal(body, &artifact); err != nil {
		return MemberSpeechesArtifact{}, fmt.Errorf("decode %s: %w", key, err)
	}
	return artifact, nil
}

func loadVoteArtifact(ctx context.Context, store Store, key string) (MemberVotesArtifact, error) {
	body, err := store.Get(ctx, key)
	if err != nil {
		return MemberVotesArtifact{}, err
	}
	var artifact MemberVotesArtifact
	if err := json.Unmarshal(body, &artifact); err != nil {
		return MemberVotesArtifact{}, fmt.Errorf("decode %s: %w", key, err)
	}
	return artifact, nil
}

func loadIndex(ctx context.Context, store Store, key string) (ArtifactIndex, error) {
	body, err := store.Get(ctx, key)
	if err != nil {
		return ArtifactIndex{}, err
	}
	var index ArtifactIndex
	if err := json.Unmarshal(body, &index); err != nil {
		return ArtifactIndex{}, fmt.Errorf("decode %s: %w", key, err)
	}
	return index, nil
}

func writeSpeechPages(ctx context.Context, store Store, artifact MemberSpeechesArtifact) ([]string, error) {
	pageGroups := splitSpeechPages(artifact)
	index := ArtifactIndex{MemberID: artifact.MemberID}
	keys := make([]string, 0, len(pageGroups)+1)
	for _, group := range pageGroups {
		key := speechPageKey(artifact.MemberID, group.suffix)
		part := MemberSpeechesArtifact{
			MemberID: artifact.MemberID,
			Stats:    artifact.Stats,
			Speeches: group.records,
		}
		body, err := json.Marshal(part)
		if err != nil {
			return nil, err
		}
		if err := store.Put(ctx, key, body); err != nil {
			return nil, err
		}
		index.Pages = append(index.Pages, ArtifactPage{
			Key:      key,
			FromDate: group.fromDate,
			ToDate:   group.toDate,
			Count:    len(group.records),
		})
		keys = append(keys, key)
	}
	indexBody, err := json.Marshal(index)
	if err != nil {
		return nil, err
	}
	indexKey := speechIndexKey(artifact.MemberID)
	if err := store.Put(ctx, indexKey, indexBody); err != nil {
		return nil, err
	}
	return append(keys, indexKey), nil
}

func writeVotePages(ctx context.Context, store Store, artifact MemberVotesArtifact) ([]string, error) {
	pageGroups := splitVotePages(artifact)
	index := ArtifactIndex{MemberID: artifact.MemberID}
	keys := make([]string, 0, len(pageGroups)+1)
	for _, group := range pageGroups {
		key := votePageKey(artifact.MemberID, group.suffix)
		part := MemberVotesArtifact{
			MemberID: artifact.MemberID,
			Votes:    group.records,
		}
		body, err := json.Marshal(part)
		if err != nil {
			return nil, err
		}
		if err := store.Put(ctx, key, body); err != nil {
			return nil, err
		}
		index.Pages = append(index.Pages, ArtifactPage{
			Key:      key,
			FromDate: group.fromDate,
			ToDate:   group.toDate,
			Count:    len(group.records),
		})
		keys = append(keys, key)
	}
	indexBody, err := json.Marshal(index)
	if err != nil {
		return nil, err
	}
	indexKey := voteIndexKey(artifact.MemberID)
	if err := store.Put(ctx, indexKey, indexBody); err != nil {
		return nil, err
	}
	return append(keys, indexKey), nil
}

type speechPageGroup struct {
	suffix   string
	fromDate string
	toDate   string
	records  []SpeechRecord
}

type votePageGroup struct {
	suffix   string
	fromDate string
	toDate   string
	records  []VoteEntry
}

func splitSpeechPages(artifact MemberSpeechesArtifact) []speechPageGroup {
	var groups []speechPageGroup
	for _, yearGroup := range groupSpeechByYear(artifact.Speeches) {
		chunks := chunkSpeechGroup(artifact.MemberID, artifact.Stats, yearGroup.records)
		for i, chunk := range chunks {
			suffix := yearGroup.suffix
			if len(chunks) > 1 {
				suffix = fmt.Sprintf("%s-%02d", suffix, i+1)
			}
			groups = append(groups, speechPageGroup{
				suffix:   suffix,
				fromDate: firstSpeechDate(chunk),
				toDate:   lastSpeechDate(chunk),
				records:  chunk,
			})
		}
	}
	return groups
}

func splitVotePages(artifact MemberVotesArtifact) []votePageGroup {
	var groups []votePageGroup
	for _, yearGroup := range groupVotesByYear(artifact.Votes) {
		chunks := chunkVoteGroup(artifact.MemberID, yearGroup.records)
		for i, chunk := range chunks {
			suffix := yearGroup.suffix
			if len(chunks) > 1 {
				suffix = fmt.Sprintf("%s-%02d", suffix, i+1)
			}
			groups = append(groups, votePageGroup{
				suffix:   suffix,
				fromDate: firstVoteDate(chunk),
				toDate:   lastVoteDate(chunk),
				records:  chunk,
			})
		}
	}
	return groups
}

func groupSpeechByYear(records []SpeechRecord) []speechPageGroup {
	var groups []speechPageGroup
	for _, record := range records {
		suffix := yearSuffix(record.SittingDate)
		if len(groups) == 0 || groups[len(groups)-1].suffix != suffix {
			groups = append(groups, speechPageGroup{suffix: suffix})
		}
		groups[len(groups)-1].records = append(groups[len(groups)-1].records, record)
	}
	return groups
}

func groupVotesByYear(records []VoteEntry) []votePageGroup {
	var groups []votePageGroup
	for _, record := range records {
		suffix := yearSuffix(record.Date)
		if len(groups) == 0 || groups[len(groups)-1].suffix != suffix {
			groups = append(groups, votePageGroup{suffix: suffix})
		}
		groups[len(groups)-1].records = append(groups[len(groups)-1].records, record)
	}
	return groups
}

func chunkSpeechGroup(memberID string, stats MemberStats, records []SpeechRecord) [][]SpeechRecord {
	var chunks [][]SpeechRecord
	var current []SpeechRecord
	for _, record := range records {
		candidate := append(append([]SpeechRecord(nil), current...), record)
		body, _ := json.Marshal(MemberSpeechesArtifact{MemberID: memberID, Stats: stats, Speeches: candidate})
		if len(current) > 0 && gzipSize(body) > MaxGzipArtifactBytes {
			chunks = append(chunks, current)
			current = []SpeechRecord{record}
			continue
		}
		current = candidate
	}
	if len(current) > 0 || len(records) == 0 {
		chunks = append(chunks, current)
	}
	return chunks
}

func chunkVoteGroup(memberID string, records []VoteEntry) [][]VoteEntry {
	var chunks [][]VoteEntry
	var current []VoteEntry
	for _, record := range records {
		candidate := append(append([]VoteEntry(nil), current...), record)
		body, _ := json.Marshal(MemberVotesArtifact{MemberID: memberID, Votes: candidate})
		if len(current) > 0 && gzipSize(body) > MaxGzipArtifactBytes {
			chunks = append(chunks, current)
			current = []VoteEntry{record}
			continue
		}
		current = candidate
	}
	if len(current) > 0 || len(records) == 0 {
		chunks = append(chunks, current)
	}
	return chunks
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

func emptyVotesResponse(memberID string, page, perPage int) MemberVotesResponse {
	return MemberVotesResponse{
		MemberID: memberID,
		Page:     page,
		PerPage:  perPage,
		Votes:    []VoteEntry{},
	}
}

func speechBefore(a, b SpeechRecord) bool {
	ad, bd := dateValue(a.SittingDate), dateValue(b.SittingDate)
	if ad != bd {
		if ad == "" {
			return false
		}
		if bd == "" {
			return true
		}
		return ad < bd
	}
	return intValue(a.InterventionSeq) < intValue(b.InterventionSeq)
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

func voteBefore(a, b VoteEntry) bool {
	ad, bd := dateValue(a.Date), dateValue(b.Date)
	if ad != bd {
		if ad == "" {
			return false
		}
		if bd == "" {
			return true
		}
		return ad < bd
	}
	return a.VoteID < b.VoteID
}

func voteAfter(a, b VoteEntry) bool {
	ad, bd := dateValue(a.Date), dateValue(b.Date)
	if ad != bd {
		if ad == "" {
			return false
		}
		if bd == "" {
			return true
		}
		return ad > bd
	}
	return a.VoteID > b.VoteID
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

func yearSuffix(value *string) string {
	date := dateValue(value)
	if len(date) >= 4 {
		return date[:4]
	}
	return "unknown"
}

func firstSpeechDate(records []SpeechRecord) string {
	for _, record := range records {
		if record.SittingDate != nil {
			return *record.SittingDate
		}
	}
	return ""
}

func lastSpeechDate(records []SpeechRecord) string {
	for i := len(records) - 1; i >= 0; i-- {
		if records[i].SittingDate != nil {
			return *records[i].SittingDate
		}
	}
	return ""
}

func firstVoteDate(records []VoteEntry) string {
	for _, record := range records {
		if record.Date != nil {
			return *record.Date
		}
	}
	return ""
}

func lastVoteDate(records []VoteEntry) string {
	for i := len(records) - 1; i >= 0; i-- {
		if records[i].Date != nil {
			return *records[i].Date
		}
	}
	return ""
}

func speechJSONKey(memberID string) string {
	return fmt.Sprintf("members/v1/by-id/%s/speeches.json", memberID)
}

func speechIndexKey(memberID string) string {
	return fmt.Sprintf("members/v1/by-id/%s/speeches-index.json", memberID)
}

func speechPageKey(memberID, suffix string) string {
	return fmt.Sprintf("members/v1/by-id/%s/speeches-%s.json", memberID, suffix)
}

func voteJSONKey(memberID string) string {
	return fmt.Sprintf("members/v1/by-id/%s/votes.json", memberID)
}

func voteIndexKey(memberID string) string {
	return fmt.Sprintf("members/v1/by-id/%s/votes-index.json", memberID)
}

func votePageKey(memberID, suffix string) string {
	return fmt.Sprintf("members/v1/by-id/%s/votes-%s.json", memberID, suffix)
}

func gzipSize(body []byte) int {
	var buf bytes.Buffer
	w := gzip.NewWriter(&buf)
	_, _ = w.Write(body)
	_ = w.Close()
	return buf.Len()
}
