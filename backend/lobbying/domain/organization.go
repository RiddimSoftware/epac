package domain

import "time"

type OrganizationType string

const (
	OrganizationTypeCorporation            OrganizationType = "corporation"
	OrganizationTypeNonProfit              OrganizationType = "non_profit"
	OrganizationTypeAssociation            OrganizationType = "association"
	OrganizationTypeIndigenousOrganization OrganizationType = "indigenous_organization"
)

type LobbyistKind string

const (
	LobbyistKindConsultant LobbyistKind = "consultant"
	LobbyistKindInHouse    LobbyistKind = "in_house"
)

type RegistrationStatus string

const (
	RegistrationStatusActive  RegistrationStatus = "active"
	RegistrationStatusExpired RegistrationStatus = "expired"
)

type RegisteredLobbyist struct {
	Name string       `json:"name"`
	Kind LobbyistKind `json:"kind"`
}

type CommunicationCount struct {
	CurrentParliament int `json:"current_parliament"`
	PriorParliament   int `json:"prior_parliament"`
}

type DPOHContact struct {
	MemberID    string `json:"member_id,omitempty"`
	Name        string `json:"name"`
	Institution string `json:"institution"`
	Count       int    `json:"count"`
}

type LobbyistRegistration struct {
	ID                   string             `json:"id"`
	Status               RegistrationStatus `json:"status"`
	Kind                 LobbyistKind       `json:"kind"`
	SubjectMatters       []string           `json:"subject_matters"`
	TargetedInstitutions []string           `json:"targeted_institutions"`
	SourceURL            string             `json:"source_url"`
}

type LobbyistOrganizationCommunication struct {
	ID             string   `json:"id"`
	Date           string   `json:"date,omitempty"`
	DPOHMemberID   string   `json:"dpoh_member_id,omitempty"`
	DPOHName       string   `json:"dpoh_name"`
	Institution    string   `json:"institution"`
	SubjectMatters []string `json:"subject_matters"`
	SourceURL      string   `json:"source_url"`
}

type LobbyistOrganizationSubjectMatter struct {
	SubjectMatter      string `json:"subject_matter"`
	CommunicationCount int    `json:"communication_count"`
	TopicSlug          string `json:"topic_slug,omitempty"`
}

type ParliamentSession struct {
	ParliamentNumber int
	SessionNumber    int
	From             time.Time
	To               time.Time
}

func (s ParliamentSession) Contains(t time.Time) bool {
	if t.IsZero() {
		return false
	}
	date := dateOnly(t)
	from := dateOnly(s.From)
	to := dateOnly(s.To)
	return !date.Before(from) && !date.After(to)
}

type LobbyistOrganization struct {
	ID                   string                              `json:"id"`
	OCLOrganizationID    string                              `json:"ocl_organization_id,omitempty"`
	Name                 string                              `json:"name"`
	Type                 OrganizationType                    `json:"type"`
	Sector               string                              `json:"sector,omitempty"`
	RegisteredLobbyists  []RegisteredLobbyist                `json:"registered_lobbyists"`
	ActiveSubjectMatters []string                            `json:"active_subject_matters"`
	CommunicationVolume  CommunicationCount                  `json:"communication_volume"`
	TopDPOHsContacted    []DPOHContact                       `json:"top_dpohs_contacted"`
	RegistrationStatus   RegistrationStatus                  `json:"registration_status"`
	Registrations        []LobbyistRegistration              `json:"registrations"`
	RecentCommunications []LobbyistOrganizationCommunication `json:"recent_communications"`
	SubjectMatters       []LobbyistOrganizationSubjectMatter `json:"subject_matters"`
	UpdatedAt            time.Time                           `json:"updated_at"`
}

func dateOnly(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
