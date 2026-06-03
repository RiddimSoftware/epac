package ourcommons

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"epac/lobbying-index/internal/domain"
)

const (
	defaultMembersURL = "https://www.ourcommons.ca/Members/en/search/XML"
	defaultUserAgent  = "epac-lobbying-index/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

type Fetcher struct {
	client    *http.Client
	url       string
	userAgent string
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(fetcher *Fetcher) {
		if client != nil {
			fetcher.client = client
		}
	}
}

func WithURL(url string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(url) != "" {
			fetcher.url = strings.TrimSpace(url)
		}
	}
}

func WithUserAgent(userAgent string) Option {
	return func(fetcher *Fetcher) {
		if strings.TrimSpace(userAgent) != "" {
			fetcher.userAgent = strings.TrimSpace(userAgent)
		}
	}
}

func NewFetcher(opts ...Option) *Fetcher {
	fetcher := &Fetcher{
		client:    &http.Client{Timeout: 45 * time.Second},
		url:       defaultMembersURL,
		userAgent: defaultUserAgent,
	}
	for _, opt := range opts {
		opt(fetcher)
	}
	return fetcher
}

func (f *Fetcher) FetchMembers(ctx context.Context) ([]domain.Member, error) {
	resp, err := f.fetch(ctx)
	if err != nil {
		return nil, err
	}

	var payload memberList
	if err := xml.Unmarshal(resp, &payload); err != nil {
		return nil, fmt.Errorf("parse member XML: %w", err)
	}

	members := make([]domain.Member, 0, len(payload.Members))
	for _, member := range payload.Members {
		members = append(members, domain.Member{
			PersonID:     member.PersonID,
			Honorific:    pointerString(member.Honorific),
			FirstName:    pointerString(member.FirstName),
			LastName:     pointerString(member.LastName),
			Constituency: pointerString(member.Constituency),
			Province:     pointerString(member.Province),
			Caucus:       pointerString(member.Caucus),
			FromDate:     parseNullableDate(member.FromDate),
			ToDate:       parseNullableDate(member.ToDate),
		})
	}
	return members, nil
}

func (f *Fetcher) fetch(ctx context.Context) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, f.url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", f.userAgent)
	req.Header.Set("Accept", "application/xml")

	resp, err := f.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("expected HTTP 200 from members endpoint, got %d", resp.StatusCode)
	}
	payload, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	return payload, nil
}

type memberList struct {
	Members []memberXML `xml:"MemberOfParliament"`
}

type memberXML struct {
	PersonID     string `xml:"PersonId"`
	Honorific    string `xml:"PersonShortHonorific"`
	FirstName    string `xml:"PersonOfficialFirstName"`
	LastName     string `xml:"PersonOfficialLastName"`
	Constituency string `xml:"ConstituencyName"`
	Province     string `xml:"ConstituencyProvinceTerritoryName"`
	Caucus       string `xml:"CaucusShortName"`
	FromDate     string `xml:"FromDateTime"`
	ToDate       string `xml:"ToDateTime"`
}

func parseNullableDate(raw string) *time.Time {
	value := strings.TrimSpace(raw)
	if value == "" {
		return nil
	}
	for _, layout := range []string{time.RFC3339, "2006-01-02T15:04:05", "2006-01-02"} {
		if parsed, err := time.Parse(layout, value); err == nil {
			return &parsed
		}
	}
	return nil
}

func pointerString(raw string) *string {
	value := strings.TrimSpace(raw)
	if value == "" || strings.EqualFold(value, "null") {
		return nil
	}
	return &value
}
