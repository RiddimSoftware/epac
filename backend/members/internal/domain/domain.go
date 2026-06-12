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

type Biography struct {
	Summary                string              `json:"summary,omitempty"`
	PreferredLanguage      string              `json:"preferred_language,omitempty"`
	PhotoURL               string              `json:"photo_url,omitempty"`
	SourceURL              string              `json:"source_url,omitempty"`
	YearsServed            []ServicePeriod     `json:"years_served,omitempty"`
	PreviousRoles          []ParliamentaryRole `json:"previous_roles,omitempty"`
	Education              []string            `json:"education,omitempty"`
	ProfessionalBackground []string            `json:"professional_background,omitempty"`
}

type ServicePeriod struct {
	Label    string `json:"label,omitempty"`
	FromDate string `json:"from_date,omitempty"`
	ToDate   string `json:"to_date,omitempty"`
}

type ParliamentaryRole struct {
	Title        string `json:"title,omitempty"`
	Organization string `json:"organization,omitempty"`
	StartDate    string `json:"start_date,omitempty"`
	EndDate      string `json:"end_date,omitempty"`
}

type PMBSponsorship struct {
	ID           string `json:"id,omitempty"`
	BillNumber   string `json:"bill_number,omitempty"`
	Title        string `json:"title,omitempty"`
	Relationship string `json:"relationship,omitempty"`
	LegisInfoURL string `json:"legis_info_url,omitempty"`
}

type Member struct {
	ID              string             `json:"id"`
	Name            string             `json:"name"`
	Riding          string             `json:"riding,omitempty"`
	Province        string             `json:"province,omitempty"`
	Party           string             `json:"party,omitempty"`
	SourceURL       string             `json:"source_url,omitempty"`
	ProfileURL      string             `json:"profile_url,omitempty"`
	FromDate        string             `json:"from_date,omitempty"`
	ToDate          string             `json:"to_date,omitempty"`
	Biography       *Biography         `json:"biography,omitempty"`
	Attendance      []AttendanceRecord `json:"attendance,omitempty"`
	PMBSponsorships []PMBSponsorship   `json:"pmb_sponsorships,omitempty"`
}
