package domain

import "time"

const (
	OCLCitation  = "Source: Office of the Commissioner of Lobbying (OCL)"
	OCLSourceURL = "https://lobbycanada.gc.ca/en/open-data/"
)

type LobbyingExposureWindow string

const (
	LobbyingExposureWindow30D LobbyingExposureWindow = "30d"
	LobbyingExposureWindow3M  LobbyingExposureWindow = "3m"
	LobbyingExposureWindow12M LobbyingExposureWindow = "12m"
	LobbyingExposureWindowAll LobbyingExposureWindow = "all"
)

type TopLobbyingOrganization struct {
	Name               string `json:"name"`
	Sector             string `json:"sector,omitempty"`
	CommunicationCount int    `json:"communication_count"`
}

type MPLobbyingTrend struct {
	CurrentParliament  int `json:"current_parliament"`
	PreviousParliament int `json:"previous_parliament"`
	Delta              int `json:"delta"`
}

type MPLobbyingSummary struct {
	MemberID                      string                    `json:"member_id"`
	Parliament                    int                       `json:"parliament"`
	QuarterStart                  time.Time                 `json:"quarter_start"`
	Window                        LobbyingExposureWindow    `json:"window"`
	TotalCommunicationCount       int                       `json:"total_communication_count"`
	UniqueOrganizationsCount      int                       `json:"unique_organizations_count"`
	MostFrequentSubjectMatter     string                    `json:"most_frequent_subject_matter,omitempty"`
	TopOrganizations              []TopLobbyingOrganization `json:"top_organizations"`
	TrendVsPreviousParliament     MPLobbyingTrend           `json:"trend_vs_previous_parliament"`
	PartyAverageCommunications    float64                   `json:"party_average_communications"`
	NationalAverageCommunications float64                   `json:"national_average_communications"`
	Citation                      string                    `json:"citation"`
	UpdatedAt                     time.Time                 `json:"updated_at"`
}

type LobbyingSubjectDistribution struct {
	SubjectMatter      string `json:"subject_matter"`
	CommunicationCount int    `json:"communication_count"`
}

type BillCrossReference struct {
	BillNumber string  `json:"bill_number"`
	BillTitle  string  `json:"bill_title,omitempty"`
	URL        string  `json:"url"`
	Confidence float64 `json:"mapping_confidence"`
}

type LobbyingTimelineEntry struct {
	CommunicationID    string              `json:"communication_id"`
	Date               string              `json:"date"`
	OrganizationName   string              `json:"organization_name"`
	OrganizationSector string              `json:"organization_sector,omitempty"`
	SubjectMatter      string              `json:"subject_matter"`
	CommunicationType  string              `json:"communication_type"`
	Bill               *BillCrossReference `json:"bill_cross_reference,omitempty"`
	Citation           string              `json:"citation"`
	SourceURL          string              `json:"source_url"`
}

type LobbyingTimelinePage struct {
	Total int
	Rows  []LobbyingTimelineEntry
}
