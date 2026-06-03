package domain

const LobbyingIndexManifestVersion = "v1"

type LobbyingIndexManifest struct {
	Version         string         `json:"version"`
	BuiltAt         string         `json:"built_at"`
	SQLiteKey       string         `json:"sqlite_key"`
	SQLiteSizeBytes int64          `json:"sqlite_size_bytes"`
	SQLiteSHA256    string         `json:"sqlite_sha256"`
	TableCounts     map[string]int `json:"table_counts"`
}
