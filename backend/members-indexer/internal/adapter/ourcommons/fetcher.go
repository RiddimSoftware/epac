package ourcommons

import (
	"context"
	"encoding/xml"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"

	"epac/members-indexer/internal/domain"
)

const (
	defaultBaseURL   = "https://www.ourcommons.ca"
	defaultUserAgent = "epac-members-indexer/1.0 (+https://riddimsoftware.com; contact: sunny@riddimsoftware.com)"
)

type Fetcher struct {
	client         *http.Client
	baseURL        string
	userAgent      string
	maxMembers     int
	fetchFullVotes bool
}

type Option func(*Fetcher)

func WithHTTPClient(client *http.Client) Option {
	return func(f *Fetcher) {
		if client != nil {
			f.client = client
		}
	}
}

func WithBaseURL(baseURL string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(baseURL) != "" {
			f.baseURL = strings.TrimRight(strings.TrimSpace(baseURL), "/")
		}
	}
}

func WithUserAgent(userAgent string) Option {
	return func(f *Fetcher) {
		if strings.TrimSpace(userAgent) != "" {
			f.userAgent = strings.TrimSpace(userAgent)
		}
	}
}

func WithMaxMembers(max int) Option {
	return func(f *Fetcher) {
		if max > 0 {
			f.maxMembers = max
		}
	}
}

func WithFullVotes(enabled bool) Option {
	return func(f *Fetcher) {
		f.fetchFullVotes = enabled
	}
}

func NewFetcher(opts ...Option) *Fetcher {
	f := &Fetcher{
		client:    &http.Client{Timeout: 45 * time.Second},
		baseURL:   defaultBaseURL,
		userAgent: defaultUserAgent,
	}
	for _, opt := range opts {
		opt(f)
	}
	return f
}

func (f *Fetcher) FetchMembers(ctx context.Context) (domain.Batch, error) {
	body, err := f.getBytes(ctx, f.baseURL+"/Members/en/search/XML", "application/xml")
	if err != nil {
		return domain.Batch{}, err
	}
	var list memberListXML
	if err := xml.Unmarshal(body, &list); err != nil {
		return domain.Batch{}, fmt.Errorf("parse members XML: %w", err)
	}
	xmlMembers := list.Members
	if f.maxMembers > 0 && len(xmlMembers) > f.maxMembers {
		xmlMembers = xmlMembers[:f.maxMembers]
	}
	members := make([]domain.Member, 0, len(xmlMembers))
	for _, raw := range xmlMembers {
		member := raw.toDomain(f.baseURL)
		if member.ID == "" {
			continue
		}
		if err := f.enrichProfile(ctx, &member); err != nil {
			return domain.Batch{}, fmt.Errorf("fetch member %s profile: %w", member.ID, err)
		}
		members = append(members, member)
	}
	return domain.Batch{Members: members}, nil
}

func (f *Fetcher) enrichProfile(ctx context.Context, member *domain.Member) error {
	body, err := f.getBytes(ctx, member.ProfileURL, "text/html")
	if err != nil {
		return err
	}
	base, _ := url.Parse(member.ProfileURL)
	member.Biography = domain.Biography{
		MemberID:          member.ID,
		Summary:           metaDescription(body),
		PreferredLanguage: definitionValue(body, "Preferred Language:"),
		PhotoURL:          resolveURL(base, firstMatch(body, photoPattern)),
		SourceURL:         member.ProfileURL,
	}
	member.PMBSponsorships = append(member.PMBSponsorships, parseBillTable(body, base, member.ID, "ce-mip-bill-sponsored-table", "sponsored")...)
	member.PMBSponsorships = append(member.PMBSponsorships, parseBillTable(body, base, member.ID, "ce-mip-bill-seconded-table", "jointly_seconded")...)
	member.Attendance = parseVoteTable(body, base, member.ID)
	if f.fetchFullVotes {
		if votesURL := firstMatch(body, allVotesPattern); votesURL != "" {
			fullBase := resolveURL(base, votesURL)
			votesBody, err := f.getBytes(ctx, fullBase, "text/html")
			if err == nil {
				votesBase, _ := url.Parse(fullBase)
				member.Attendance = parseVoteTable(votesBody, votesBase, member.ID)
			}
		}
	}
	return nil
}

func (f *Fetcher) getBytes(ctx context.Context, target, accept string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, fmt.Errorf("build request %s: %w", target, err)
	}
	req.Header.Set("Accept", accept)
	req.Header.Set("User-Agent", f.userAgent)
	resp, err := f.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fetch %s: %w", target, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s returned HTTP %d", target, resp.StatusCode)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", target, err)
	}
	return data, nil
}

type memberListXML struct {
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

func (m memberXML) toDomain(baseURL string) domain.Member {
	first := cleanText(m.FirstName)
	last := cleanText(m.LastName)
	id := cleanText(m.PersonID)
	name := strings.TrimSpace(strings.Join([]string{first, last}, " "))
	profileURL := fmt.Sprintf("%s/Members/en/%s", baseURL, id)
	return domain.Member{
		ID:         id,
		Name:       name,
		Honorific:  cleanText(m.Honorific),
		FirstName:  first,
		LastName:   last,
		Riding:     cleanText(m.Constituency),
		Province:   cleanText(m.Province),
		Party:      cleanText(m.Caucus),
		FromDate:   dateOnly(m.FromDate),
		ToDate:     dateOnly(m.ToDate),
		SourceURL:  baseURL + "/Members/en/search/XML",
		ProfileURL: profileURL,
	}
}

func parseBillTable(body []byte, base *url.URL, memberID, tableID, relationship string) []domain.PMBSponsorship {
	table := tableByID(body, tableID)
	rows := rows(table)
	out := make([]domain.PMBSponsorship, 0, len(rows))
	for i, row := range rows {
		cells := cells(row)
		if len(cells) < 2 || strings.Contains(strings.ToLower(cells[0]), "bill") {
			continue
		}
		href := firstMatch([]byte(row), hrefPattern)
		number := cleanText(cells[0])
		title := cleanText(cells[1])
		out = append(out, domain.PMBSponsorship{
			ID:           stableID(memberID, relationship, number, fmt.Sprintf("%d", i)),
			MemberID:     memberID,
			BillNumber:   number,
			Title:        title,
			Relationship: relationship,
			LegisInfoURL: resolveURL(base, href),
		})
	}
	return out
}

func parseVoteTable(body []byte, base *url.URL, memberID string) []domain.AttendanceRecord {
	table := tableByID(body, "ce-mip-vote-table")
	rows := rows(table)
	out := make([]domain.AttendanceRecord, 0, len(rows))
	for _, row := range rows {
		cells := cells(row)
		if len(cells) < 5 || strings.Contains(strings.ToLower(cells[0]), "vote") {
			continue
		}
		href := firstMatch([]byte(row), hrefPattern)
		voteNumber := cleanVoteNumber(cells[0])
		out = append(out, domain.AttendanceRecord{
			ID:         stableID(memberID, "vote", voteNumber),
			MemberID:   memberID,
			VoteNumber: voteNumber,
			Subject:    cleanText(cells[1]),
			Ballot:     cleanText(cells[2]),
			Result:     cleanText(cells[3]),
			VoteDate:   cleanText(cells[4]),
			SourceURL:  resolveURL(base, href),
		})
	}
	return out
}

func tableByID(body []byte, id string) string {
	pattern := regexp.MustCompile(`(?is)<table[^>]*\bid=["']` + regexp.QuoteMeta(id) + `["'][^>]*>(.*?)</table>`)
	return firstMatch(body, pattern)
}

func rows(table string) []string {
	matches := rowPattern.FindAllStringSubmatch(table, -1)
	out := make([]string, 0, len(matches))
	for _, match := range matches {
		out = append(out, match[1])
	}
	return out
}

func cells(row string) []string {
	matches := cellPattern.FindAllStringSubmatch(row, -1)
	out := make([]string, 0, len(matches))
	for _, match := range matches {
		out = append(out, cleanText(stripTags(match[1])))
	}
	return out
}

func metaDescription(body []byte) string {
	return cleanText(firstMatch(body, metaDescriptionPattern))
}

func definitionValue(body []byte, label string) string {
	pattern := regexp.MustCompile(`(?is)<dt>\s*` + regexp.QuoteMeta(label) + `\s*</dt>\s*<dd[^>]*>(.*?)</dd>`)
	return cleanText(stripTags(firstMatch(body, pattern)))
}

func firstMatch(body []byte, pattern *regexp.Regexp) string {
	match := pattern.FindSubmatch(body)
	if len(match) < 2 {
		return ""
	}
	return html.UnescapeString(strings.TrimSpace(string(match[1])))
}

func cleanVoteNumber(value string) string {
	value = strings.TrimSpace(strings.TrimPrefix(cleanText(value), "No."))
	return strings.TrimSpace(value)
}

func stripTags(value string) string {
	return tagPattern.ReplaceAllString(value, " ")
}

func cleanText(value string) string {
	value = html.UnescapeString(value)
	value = whitespacePattern.ReplaceAllString(value, " ")
	value = strings.TrimSpace(value)
	if strings.EqualFold(value, "null") {
		return ""
	}
	return value
}

func dateOnly(raw string) string {
	raw = cleanText(raw)
	if raw == "" {
		return ""
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05", "2006-01-02"} {
		if parsed, err := time.Parse(layout, raw); err == nil {
			return parsed.Format("2006-01-02")
		}
	}
	if len(raw) >= 10 {
		return raw[:10]
	}
	return raw
}

func resolveURL(base *url.URL, href string) string {
	href = strings.TrimSpace(href)
	if href == "" {
		return ""
	}
	parsed, err := url.Parse(href)
	if err != nil {
		return href
	}
	return base.ResolveReference(parsed).String()
}

func stableID(parts ...string) string {
	filtered := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			filtered = append(filtered, part)
		}
	}
	id := strings.ToLower(strings.Join(filtered, "-"))
	id = nonSlugPattern.ReplaceAllString(id, "-")
	id = strings.Trim(id, "-")
	if id == "" {
		return "unknown"
	}
	return id
}

var (
	metaDescriptionPattern = regexp.MustCompile(`(?is)<meta[^>]*name=["']description["'][^>]*content=["']([^"']*)["'][^>]*>`)
	photoPattern           = regexp.MustCompile(`(?is)<img[^>]*class=["'][^"']*ce-mip-mp-picture[^"']*["'][^>]*src=["']([^"']+)["']`)
	allVotesPattern        = regexp.MustCompile(`(?is)<a[^>]*href=["']([^"']*/votes)["'][^>]*>\s*All votes by`)
	hrefPattern            = regexp.MustCompile(`(?is)href=["']([^"']+)["']`)
	rowPattern             = regexp.MustCompile(`(?is)<tr[^>]*>(.*?)</tr>`)
	cellPattern            = regexp.MustCompile(`(?is)<t[dh][^>]*>(.*?)</t[dh]>`)
	tagPattern             = regexp.MustCompile(`(?is)<[^>]+>`)
	whitespacePattern      = regexp.MustCompile(`\s+`)
	nonSlugPattern         = regexp.MustCompile(`[^a-z0-9]+`)
)
