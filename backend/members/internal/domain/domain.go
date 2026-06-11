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

type AttendanceRecord struct {
	SittingDate string `json:"sitting_date,omitempty"`
	Status      string `json:"status,omitempty"`
	Present     *bool  `json:"present,omitempty"`
	SourceURL   string `json:"source_url,omitempty"`
	Parliament  *int   `json:"parliament,omitempty"`
	Session     *int   `json:"session,omitempty"`
}

type Member struct {
	ID         string             `json:"id"`
	Name       string             `json:"name"`
	Riding     string             `json:"riding,omitempty"`
	Province   string             `json:"province,omitempty"`
	Party      string             `json:"party,omitempty"`
	SourceURL  string             `json:"source_url,omitempty"`
	Attendance []AttendanceRecord `json:"attendance,omitempty"`
}
