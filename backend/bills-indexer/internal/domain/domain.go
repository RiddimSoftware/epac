package domain

import "time"

const ManifestVersion = "v1"

type Session struct {
	ParliamentNumber int
	SessionNumber    int
}

type Batch struct {
	Bills []Bill
}

type Bill struct {
	ID              string
	Number          string
	Title           string
	ShortTitle      string
	SponsorID       string
	SponsorName     string
	Status          string
	CurrentStage    string
	IntroducedOn    string
	SourceURL       string
	BillType        string
	Parliament      int
	Session         int
	LegisInfoURL    string
	Stages          []BillStage
	Events          []BillEvent
	Versions        []BillVersion
	Diffs           []BillDiff
	Amendments      []Amendment
	PBOCostings     []PBOCosting
	RelatedLinks    []RelatedLink
	CommitteeStages []BillCommitteeStage
	RawJSON         string
}

type BillStage struct {
	ID            string
	Name          string
	Chamber       string
	State         string
	CompletedDate string
	SortOrder     int
	IsCompleted   bool
}

type BillEvent struct {
	ID              string
	StageID         string
	StageName       string
	Name            string
	Chamber         string
	EventDate       string
	MeetingNumber   string
	AmendmentCount  int
	AmendmentNoteID string
}

type BillCommitteeStage struct {
	ID               string
	StageID          string
	StageName        string
	Chamber          string
	State            string
	CommitteeID      string
	CommitteeAcronym string
	CommitteeName    string
	CommitteeChamber string
	CommitteeURL     string
	StudiedSince     string
	StudyCompletedAt string
	Meetings         []BillCommitteeMeeting
	SortOrder        int
}

type BillCommitteeMeeting struct {
	ID            string
	MeetingNumber int
	Date          string
	EvidenceURL   string
	WitnessCount  *int
	SortOrder     int
}

type BillVersion struct {
	ID            string
	PublicationID string
	Stage         string
	StageSlug     string
	HTMLURL       string
	XMLURL        string
	PDFURL        string
	PublishedDate string
	Source        string
	SortOrder     int
}

type BillDiff struct {
	ID            string
	FromVersionID string
	ToVersionID   string
	SourceURL     string
}

type Amendment struct {
	ID              string
	EventID         string
	StageName       string
	AmendmentNoteID string
	AmendmentCount  int
	SourceURL       string
}

type PBOCosting struct {
	ID        string
	Title     string
	URL       string
	Source    string
	Published string
}

type RelatedLink struct {
	ID     string
	Title  string
	URL    string
	Type   string
	Source string
}

type Stats struct {
	BuiltAt               time.Time
	Parliament            int
	Session               int
	BillCount             int
	StageCount            int
	EventCount            int
	VersionCount          int
	DiffCount             int
	AmendmentCount        int
	PBOCostingCount       int
	RelatedLinkCount      int
	CommitteeStageCount   int
	CommitteeMeetingCount int
	TableCounts           map[string]int
}

type Manifest struct {
	Version          string         `json:"version"`
	BuiltAt          string         `json:"built_at"`
	ParliamentNumber int            `json:"parliament_number"`
	SessionNumber    int            `json:"session_number"`
	SQLiteKey        string         `json:"sqlite_key"`
	SQLiteSizeBytes  int64          `json:"sqlite_size_bytes"`
	SQLiteSHA256     string         `json:"sqlite_sha256"`
	TableCounts      map[string]int `json:"table_counts"`
}
