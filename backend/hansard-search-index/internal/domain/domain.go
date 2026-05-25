package domain

import "time"

const ManifestVersion = "v1"

type Session struct {
	ParliamentNumber int
	SessionNumber    int
}

type Message struct {
	MessageID string
	Position  int
	Text      string
}

type Intervention struct {
	ParliamentNumber  int
	SessionNumber     int
	SittingDate       time.Time
	InterventionID    string
	SpeakerFirstName  string
	SpeakerLastName   string
	PartyAbbreviation string
	RidingName        string
	Topic             string
	Messages          []Message
}

type Stats struct {
	BuiltAt           time.Time
	ParliamentNumber  int
	SessionNumber     int
	SittingCount      int
	InterventionCount int
	MessageCount      int
}

type Manifest struct {
	Version           string `json:"version"`
	BuiltAt           string `json:"built_at"`
	ParliamentNumber  int    `json:"parliament_number"`
	SessionNumber     int    `json:"session_number"`
	SittingCount      int    `json:"sitting_count"`
	InterventionCount int    `json:"intervention_count"`
	MessageCount      int    `json:"message_count"`
	SQLiteKey         string `json:"sqlite_key"`
	SQLiteSizeBytes   int64  `json:"sqlite_size_bytes"`
	SQLiteSHA256      string `json:"sqlite_sha256"`
}
