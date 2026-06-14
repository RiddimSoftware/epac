package domain

const ManifestVersion = "v1"

type Manifest struct {
	Version         string         `json:"version"`
	BuiltAt         string         `json:"built_at"`
	SQLiteKey       string         `json:"sqlite_key"`
	SQLiteSizeBytes int64          `json:"sqlite_size_bytes"`
	SQLiteSHA256    string         `json:"sqlite_sha256"`
	TableCounts     map[string]int `json:"table_counts,omitempty"`
}

type BillStage struct {
	ID            string  `json:"id,omitempty"`
	Name          string  `json:"name,omitempty"`
	CompletedDate *string `json:"completed_date,omitempty"`
	IsCompleted   bool    `json:"is_completed"`
}

type BillVersion struct {
	ID          string  `json:"id,omitempty"`
	Label       string  `json:"label,omitempty"`
	Title       string  `json:"title,omitempty"`
	Stage       string  `json:"stage,omitempty"`
	Chamber     string  `json:"chamber,omitempty"`
	PublishedOn *string `json:"published_on,omitempty"`
	SourceURL   string  `json:"source_url,omitempty"`
}

type BillAmendment struct {
	ID          string  `json:"id,omitempty"`
	Number      string  `json:"number,omitempty"`
	Title       string  `json:"title,omitempty"`
	Status      string  `json:"status,omitempty"`
	Stage       string  `json:"stage,omitempty"`
	SponsorName string  `json:"sponsor_name,omitempty"`
	ProposedOn  *string `json:"proposed_on,omitempty"`
	Text        string  `json:"text,omitempty"`
	SourceURL   string  `json:"source_url,omitempty"`
}

type BillClauseDiff struct {
	ID               string  `json:"id,omitempty"`
	Label            string  `json:"label,omitempty"`
	ChangeType       string  `json:"change_type"`
	FromText         string  `json:"from_text"`
	ToText           string  `json:"to_text"`
	HansardAnchorURL *string `json:"hansard_anchor_url,omitempty"`
}

type BillVersionDiff struct {
	From    BillVersion      `json:"from"`
	To      BillVersion      `json:"to"`
	Clauses []BillClauseDiff `json:"clauses"`
}

type ParliamentaryCommittee struct {
	Code    string `json:"code"`
	Name    string `json:"name"`
	Chamber string `json:"chamber,omitempty"`
	URL     string `json:"url"`
}

type BillCommitteeMeeting struct {
	ID            string  `json:"id"`
	MeetingNumber int     `json:"meeting_number"`
	Date          *string `json:"date,omitempty"`
	WitnessCount  *int    `json:"witness_count,omitempty"`
	EvidenceURL   *string `json:"evidence_url,omitempty"`
}

type BillCommitteeStage struct {
	Committee        ParliamentaryCommittee `json:"committee"`
	StudiedSince     *string                `json:"studied_since,omitempty"`
	StudyCompletedAt *string                `json:"study_completed_at,omitempty"`
	UpcomingMeetings []BillCommitteeMeeting `json:"upcoming_meetings"`
	PastMeetings     []BillCommitteeMeeting `json:"past_meetings"`
}

type Bill struct {
	ID           string          `json:"id"`
	Number       string          `json:"number"`
	Title        string          `json:"title"`
	SponsorName  string          `json:"sponsor_name,omitempty"`
	Status       string          `json:"status,omitempty"`
	CurrentStage string          `json:"current_stage,omitempty"`
	IntroducedOn *string         `json:"introduced_on,omitempty"`
	Stages       []BillStage     `json:"stages,omitempty"`
	SourceURL    string          `json:"source_url,omitempty"`
	BillType     string          `json:"bill_type,omitempty"`
	Parliament   *int            `json:"parliament,omitempty"`
	Session      *int            `json:"session,omitempty"`
	LegisInfoURL string          `json:"legis_info_url,omitempty"`
	Versions     []BillVersion   `json:"versions,omitempty"`
	Amendments   []BillAmendment `json:"amendments,omitempty"`
}
