// Package domain holds value objects shared across the hansard-search boundary.
package domain

// Manifest describes the SQLite search index artifact produced by the
// hansard-search-index Lambda (EPAC-2062).
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
