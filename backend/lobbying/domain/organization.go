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
	ID                   string               `json:"id"`
	OCLOrganizationID    string               `json:"ocl_organization_id,omitempty"`
	Name                 string               `json:"name"`
	Type                 OrganizationType     `json:"type"`
	Sector               string               `json:"sector,omitempty"`
	RegisteredLobbyists  []RegisteredLobbyist `json:"registered_lobbyists"`
	ActiveSubjectMatters []string             `json:"active_subject_matters"`
	CommunicationVolume  CommunicationCount   `json:"communication_volume"`
	TopDPOHsContacted    []DPOHContact        `json:"top_dpohs_contacted"`
	UpdatedAt            time.Time            `json:"updated_at"`
}

func dateOnly(t time.Time) time.Time {
	y, m, d := t.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
