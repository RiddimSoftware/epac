package domain

import "time"

const ManifestVersion = "v1"

type Batch struct {
	Members []Member
}

type Member struct {
	ID              string
	Name            string
	Honorific       string
	FirstName       string
	LastName        string
	Riding          string
	Province        string
	Party           string
	FromDate        string
	ToDate          string
	SourceURL       string
	ProfileURL      string
	Biography       Biography
	Attendance      []AttendanceRecord
	PMBSponsorships []PMBSponsorship
}

type Biography struct {
	MemberID          string
	Summary           string
	PreferredLanguage string
	PhotoURL          string
	SourceURL         string
}

type AttendanceRecord struct {
	ID         string
	MemberID   string
	VoteNumber string
	Subject    string
	Ballot     string
	Result     string
	VoteDate   string
	SourceURL  string
}

type PMBSponsorship struct {
	ID           string
	MemberID     string
	BillNumber   string
	Title        string
	Relationship string
	LegisInfoURL string
}

type Stats struct {
	BuiltAt          time.Time
	MemberCount      int
	BiographyCount   int
	AttendanceCount  int
	SponsorshipCount int
	TableCounts      map[string]int
}

type Manifest struct {
	Version         string         `json:"version"`
	BuiltAt         string         `json:"built_at"`
	SQLiteKey       string         `json:"sqlite_key"`
	SQLiteSizeBytes int64          `json:"sqlite_size_bytes"`
	SQLiteSHA256    string         `json:"sqlite_sha256"`
	TableCounts     map[string]int `json:"table_counts"`
}
